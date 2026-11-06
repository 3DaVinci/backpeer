import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:daemon_kit/daemon_kit.dart';
import 'package:fixnum/fixnum.dart';
import 'package:logging/logging.dart';
import 'package:protocol/protocol.dart' as pb;

/// Канал закрыт или не открыт: heartbeat уходит по HTTP.
final class ChannelUnavailableException implements Exception {
  const new(this.reason);

  final String reason;

  @override
  String toString() => 'ChannelUnavailableException: $reason';
}

/// Канал команд координатора на стороне узла (задача 3.6.1; protocol.md,
/// раздел 4.10): исходящее соединение WebSocket, через которое координатор
/// достаёт узел за NAT за секунды.
///
/// - Открывается [CoordinatorClient.openNodeChannel] с подписью ключом
///   узла; не открылся или оборвался — повтор с растущей паузой со
///   случайной долей до [maxBackoff]. Соединение, прожившее
///   [stableAfter], обнуляет счёт неудач: после обрыва сети первая попытка
///   — через секунду.
/// - Ping WebSocket каждые [pingInterval] держит отображение NAT; нет pong
///   до следующего ping — соединение считается оборванным.
/// - [heartbeat] — по каналу, пока он открыт; ответ ошибкой координатора
///   — [CoordinatorException], как по HTTP; канала нет или ответа нет за
///   [replyTimeout] — [ChannelUnavailableException].
/// - Команды координатора выполняет [onCommand]: вернул `null` — ответ
///   `CommandDone`, вернул сообщение — ответ с его телом (например,
///   `RendezvousReply`), бросил [CoordinatorException] — ответ `Error` с
///   его кодом.
final class CommandChannel {
  new({
    required this.client,
    required this.nodeKey,
    required this.onCommand,
    this.onConnected,
    this.maxBackoff = const Duration(minutes: 5),
    this.pingInterval = const Duration(seconds: 30),
    this.replyTimeout = const Duration(seconds: 30),
    this.stableAfter = const Duration(seconds: 30),
    math.Random? random,
    DateTime Function()? clock,
  }) : _random = random ?? math.Random(),
       _clock = clock ?? DateTime.now;

  final CoordinatorClient client;
  final Ed25519KeyPair nodeKey;

  /// Выполняет команду и возвращает тело ответа (`null` —
  /// `CommandDone`); бросает [CoordinatorException], чтобы отклонить.
  final Future<pb.NodeChannelMessage?> Function(
    pb.CoordinatorChannelMessage command,
  )
  onCommand;

  /// Вызывается после каждого открытия канала.
  final void Function()? onConnected;

  final Duration maxBackoff;
  final Duration pingInterval;
  final Duration replyTimeout;
  final Duration stableAfter;
  final math.Random _random;
  final DateTime Function() _clock;

  /// Наибольшее сообщение координатора в канале (protocol.md, раздел 4.10);
  /// свои сообщения узел шлёт до 128 КиБ (ответ на аудит).
  static const int maxMessageBytes = 64 * 1024;

  static final Logger _log = Logger('coordinator.channel');

  WebSocket? _socket;
  bool _stopped = false;
  Future<void>? _loop;
  Completer<void>? _wake;
  int _nextId = 1;
  int _lastCommandId = 0;
  final Map<int, Completer<pb.CoordinatorChannelMessage>> _pending = {};

  DateTime? _connectedAt;
  int _opened = 0;
  int _commands = 0;
  String? _lastError;

  bool get connected => _socket != null;

  /// Сколько раз канал открывался.
  int get opened => _opened;

  /// Выполнено команд.
  int get commands => _commands;

  /// Состояние для `cli node status`.
  Map<String, Object?> toJson() => {
    'connected': connected,
    'connectedAt': connected ? _connectedAt?.toUtc().toIso8601String() : null,
    'opened': _opened,
    'commands': _commands,
    'lastError': _lastError,
  };

  /// Запускает цикл подключения; повторный вызов ничего не делает.
  void start() => _loop ??= _run();

  /// Закрывает канал и останавливает цикл.
  Future<void> stop() async {
    _stopped = true;
    if (_wake case final w? when !w.isCompleted) w.complete();
    final socket = _socket;
    if (socket != null) {
      try {
        await socket
            .close(WebSocketStatus.normalClosure)
            .timeout(const Duration(seconds: 2));
      } on Object {
        // Соединение уже оборвано.
      }
    }
    await _loop;
  }

  /// Heartbeat по каналу.
  Future<pb.HeartbeatResponse> heartbeat(pb.HeartbeatRequest request) async {
    final reply = await _request(pb.NodeChannelMessage(heartbeat: request));
    if (reply.hasHeartbeat()) return reply.heartbeat;
    throw _errorOf(reply);
  }

  Future<pb.CoordinatorChannelMessage> _request(
    pb.NodeChannelMessage message,
  ) async {
    final socket = _socket;
    if (socket == null) {
      throw const ChannelUnavailableException('канал не открыт');
    }
    final id = _nextId++;
    final reply = _pending[id] = Completer<pb.CoordinatorChannelMessage>();
    message.id = Int64(id);
    try {
      _send(socket, message.writeToBuffer());
      return await reply.future.timeout(replyTimeout);
    } on TimeoutException {
      // Соединение зависло: закрыть, цикл откроет новое.
      unawaited(_abort(socket));
      throw const ChannelUnavailableException('нет ответа по каналу');
    } finally {
      _pending.remove(id);
    }
  }

  static CoordinatorException _errorOf(pb.CoordinatorChannelMessage reply) {
    if (!reply.hasError()) {
      return const CoordinatorException(
        pb.ErrorCode.ERROR_CODE_INTERNAL,
        'ответ канала без тела',
      );
    }
    final e = reply.error;
    return CoordinatorException(
      e.code == pb.ErrorCode.ERROR_CODE_UNSPECIFIED
          ? pb.ErrorCode.ERROR_CODE_INTERNAL
          : e.code,
      e.message,
      retryAfter: e.retryAfterMs == 0
          ? null
          : Duration(milliseconds: e.retryAfterMs),
    );
  }

  Future<void> _run() async {
    var failures = 0;
    while (!_stopped) {
      final WebSocket socket;
      try {
        socket = await client.openNodeChannel(nodeKey: nodeKey);
      } on CoordinatorException catch (e) {
        if (_stopped) break;
        failures++;
        _lastError = '${e.code.name}: ${e.detail}';
        final pause = _backoff(failures);
        _log.fine(
          LogEvent('channel_open_failed', {
            'code': e.code.name,
            'retry_in_ms': pause.inMilliseconds,
          }),
        );
        await _sleep(pause);
        continue;
      }
      if (_stopped) {
        await _abort(socket);
        break;
      }
      socket.pingInterval = pingInterval;
      // Координатор нумерует команды заново в каждом канале.
      _lastCommandId = 0;
      final openedAt = _connectedAt = _clock();
      _socket = socket;
      _opened++;
      _lastError = null;
      _log.info(LogEvent('channel_opened', {'opened': _opened}));
      onConnected?.call();
      await _serve(socket);
      _socket = null;
      for (final reply in _pending.values) {
        if (!reply.isCompleted) {
          reply.completeError(
            const ChannelUnavailableException('канал закрыт'),
          );
        }
      }
      _pending.clear();
      if (_stopped) break;
      _lastError = 'канал закрыт (${socket.closeCode})';
      failures = _clock().difference(openedAt) >= stableAfter
          ? 1
          : failures + 1;
      final pause = _backoff(failures);
      _log.info(
        LogEvent('channel_closed', {
          'code': socket.closeCode,
          'retry_in_ms': pause.inMilliseconds,
        }),
      );
      await _sleep(pause);
    }
  }

  Future<void> _serve(WebSocket socket) async {
    try {
      await for (final data in socket) {
        if (data is! List<int>) {
          await _abort(socket, WebSocketStatus.unsupportedData);
          break;
        }
        if (data.length > maxMessageBytes) {
          await _abort(socket, WebSocketStatus.messageTooBig);
          break;
        }
        final pb.CoordinatorChannelMessage message;
        try {
          message = ManifestObjects.parseMessage(
            'CoordinatorChannelMessage',
            () => pb.CoordinatorChannelMessage.fromBuffer(data),
          );
        } on DataFormatException {
          await _abort(socket, WebSocketStatus.protocolError);
          break;
        }
        final replyTo = message.replyTo.toInt();
        if (replyTo != 0) {
          final pending = _pending[replyTo];
          if (pending != null && !pending.isCompleted) {
            pending.complete(message);
          }
          continue;
        }
        final id = message.id.toInt();
        if (id <= _lastCommandId) {
          await _abort(socket, WebSocketStatus.protocolError);
          break;
        }
        _lastCommandId = id;
        unawaited(_command(socket, id, message));
      }
    } on Object catch (e) {
      _log.fine(const LogEvent('channel_error'), e);
    }
  }

  Future<void> _command(
    WebSocket socket,
    int id,
    pb.CoordinatorChannelMessage command,
  ) async {
    var reply = pb.NodeChannelMessage();
    try {
      reply = await onCommand(command) ?? (reply..done = pb.CommandDone());
      _commands++;
    } on CoordinatorException catch (e) {
      reply.error = pb.Error(code: e.code, message: e.detail);
    } on Object catch (e, stack) {
      _log.severe(const LogEvent('command_failed'), e, stack);
      reply.error = pb.Error(
        code: pb.ErrorCode.ERROR_CODE_INTERNAL,
        message: 'команда не выполнена',
      );
    }
    reply
      ..id = Int64.ZERO
      ..replyTo = Int64(id);
    _log.fine(
      LogEvent('command', {
        'command': command.whichBody().name,
        'ok': !reply.hasError(),
      }),
    );
    try {
      _send(socket, reply.writeToBuffer());
    } on ChannelUnavailableException {
      // Канал закрылся, пока команда выполнялась.
    }
  }

  static void _send(WebSocket socket, List<int> bytes) {
    if (socket.readyState != WebSocket.open) {
      throw const ChannelUnavailableException('канал закрыт');
    }
    try {
      socket.add(Uint8List.fromList(bytes));
      // dart:io бросает StateError, если соединение закрылось между
      // проверкой readyState и записью. Для вызывающего это тот же
      // закрытый канал, а не падение.
      // ignore: avoid_catching_errors
    } on StateError {
      throw const ChannelUnavailableException('канал закрыт');
    }
  }

  static Future<void> _abort(
    WebSocket socket, [
    int code = WebSocketStatus.goingAway,
  ]) async {
    try {
      await socket.close(code).timeout(const Duration(seconds: 2));
    } on Object {
      // Соединение уже оборвано.
    }
  }

  /// Пауза перед попыткой после [failures] неудач подряд (с 1):
  /// 2^(failures−1) секунд до [maxBackoff], из них случайная половина.
  Duration _backoff(int failures) {
    final capMs = math.min(
      1000 * (1 << math.min(failures - 1, 20)),
      maxBackoff.inMilliseconds,
    );
    return Duration(
      milliseconds: capMs ~/ 2 + _random.nextInt(math.max(1, capMs ~/ 2)),
    );
  }

  Future<void> _sleep(Duration d) async {
    final wake = _wake = Completer<void>();
    final timer = Timer(d, () {
      if (!wake.isCompleted) wake.complete();
    });
    await wake.future;
    timer.cancel();
  }
}
