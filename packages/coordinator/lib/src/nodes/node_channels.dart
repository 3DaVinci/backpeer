import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:coordinator/src/auth/key_directory.dart';
import 'package:coordinator/src/auth/request_verifier.dart';
import 'package:coordinator/src/limits/rate_limiter.dart';
import 'package:coordinator/src/log.dart';
import 'package:coordinator/src/rpc/call_context.dart';
import 'package:coordinator/src/rpc/errors.dart';
import 'package:coordinator/src/rpc/service.dart';
import 'package:core/core.dart';
import 'package:fixnum/fixnum.dart';
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart' show ServerException;
import 'package:protocol/protocol.dart' as pb;

/// Настройки канала команд.
final class ChannelPolicy {
  const new({
    this.maxConnections = 10000,
    this.pingInterval = const Duration(seconds: 30),
    this.commandTimeout = const Duration(seconds: 10),
  });

  /// Открытых каналов на координатор; сверх — `UNAVAILABLE`.
  final int maxConnections;

  /// Ping WebSocket: держит отображение NAT и находит оборванные
  /// соединения (нет pong до следующего ping — канал закрывается).
  final Duration pingInterval;

  /// Сколько ждать ответа узла на команду.
  final Duration commandTimeout;
}

/// Канал команд координатора к узлам (задача 3.6.1; protocol.md,
/// раздел 4.10).
///
/// Узел открывает WebSocket `GET /api/v1/NodeChannel` с подписью `FS-Auth`
/// ключом узла над путём и пустым телом; проверки — как у запроса API
/// (частота по IP, подпись, окно времени, повтор, частота по ключу). Отказ
/// до открытия — обычный ответ `Error` со статусом по коду.
///
/// По каналу узел шлёт heartbeat (тот же обработчик, что у `Heartbeat`,
/// перед каждым — повторная проверка ключа: удалённый узел или
/// заблокированный владелец теряет канал), координатор — команды
/// ([send], [broadcast]). Новый канал того же узла заменяет прежний.
///
/// Каналы живут в памяти процесса: команда доходит до узлов, подключённых
/// к этому экземпляру координатора.
final class NodeChannels {
  new({
    required this.service,
    required this.verifier,
    required this.keys,
    required this.ipLimiter,
    required this.keyLimiter,
    this.policy = const ChannelPolicy(),
    this.trustForwardedFor = false,
  });

  final CoordinatorService service;
  final RequestVerifier verifier;
  final KeyDirectory keys;
  final RateLimiter ipLimiter;
  final RateLimiter keyLimiter;
  final ChannelPolicy policy;
  final bool trustForwardedFor;

  /// Наибольшее сообщение в канале, как тело запроса API.
  static const int maxMessageBytes = 64 * 1024;

  /// Коды закрытия WebSocket (RFC 6455, раздел 7.4).
  static const closeNormal = 1000;
  static const closeGoingAway = 1001;
  static const closeProtocolError = 1002;
  static const closeUnsupportedData = 1003;
  static const closePolicyViolation = 1008;
  static const closeTooBig = 1009;

  /// Свой код: открыт новый канал того же узла.
  static const closeReplaced = 4000;

  static final _log = Logger('coordinator.channel');

  final _channels = <String, _NodeChannel>{};
  final Random _random = Random.secure();
  bool _closed = false;

  /// Открытых каналов.
  int get count => _channels.length;

  bool isConnected(List<int> nodeId) =>
      _channels.containsKey(bytesToHex(nodeId));

  /// Запрос к пути канала.
  bool handles(HttpRequest request) =>
      request.uri.path == CoordinatorClient.nodeChannelPath;

  /// Отправляет команду [command] узлу [nodeId] и ждёт ответа. `null` —
  /// канала нет или он закрылся до ответа; нет ответа за
  /// [ChannelPolicy.commandTimeout] — [TimeoutException].
  Future<pb.NodeChannelMessage?> send(
    List<int> nodeId,
    pb.CoordinatorChannelMessage command,
  ) async {
    final channel = _channels[bytesToHex(nodeId)];
    if (channel == null) return null;
    return await channel.command(command).timeout(policy.commandTimeout);
  }

  /// Отправляет команду всем открытым каналам, не дожидаясь ответов;
  /// возвращает число каналов.
  int broadcast(pb.CoordinatorChannelMessage command) {
    for (final channel in _channels.values.toList()) {
      unawaited(
        channel
            .command(command.deepCopy())
            .timeout(policy.commandTimeout, onTimeout: () => null)
            .then((reply) {
              if (reply != null && reply.hasError()) {
                _log.fine(
                  LogEvent('command_rejected', {
                    'code': errorCodeName(reply.error.code),
                  }),
                );
              }
            }),
      );
    }
    return _channels.length;
  }

  /// Принимает запрос к [CoordinatorClient.nodeChannelPath].
  Future<void> handle(HttpRequest request) async {
    final requestId = _newRequestId();
    final address = _clientAddress(request);
    final Caller caller;
    try {
      if (request.method != 'GET') {
        throw const RpcException(
          pb.ErrorCode.ERROR_CODE_BAD_REQUEST,
          'нужен метод GET',
          httpStatus: 405,
        );
      }
      if (request.uri.hasQuery) {
        throw const RpcException(
          pb.ErrorCode.ERROR_CODE_BAD_REQUEST,
          'строка запроса не поддерживается',
        );
      }
      _limit(ipLimiter, address, 'IP');
      if (!WebSocketTransformer.isUpgradeRequest(request)) {
        throw const RpcException(
          pb.ErrorCode.ERROR_CODE_BAD_REQUEST,
          'нужен WebSocket',
          httpStatus: 426,
        );
      }
      if (_closed) {
        throw const RpcException(
          pb.ErrorCode.ERROR_CODE_UNAVAILABLE,
          'координатор останавливается',
          retryAfter: Duration(seconds: 5),
        );
      }
      caller = (await verifier.verify(
        requirement: AuthRequirement.node,
        path: request.uri.path,
        header: request.headers.value(RequestAuth.headerName),
        body: const [],
      ))!;
      _limit(keyLimiter, String.fromCharCodes(caller.publicKey), 'ключ');
      final hex = bytesToHex(caller.publicKey);
      if (!_channels.containsKey(hex) &&
          _channels.length >= policy.maxConnections) {
        throw const RpcException(
          pb.ErrorCode.ERROR_CODE_UNAVAILABLE,
          'слишком много каналов',
          retryAfter: Duration(seconds: 30),
        );
      }
    } on RpcException catch (e) {
      _log.info(
        LogEvent('channel_refused', {
          'rid': requestId,
          'code': errorCodeName(e.code),
        }),
      );
      await _refuse(request, e, requestId);
      return;
    }

    final WebSocket socket;
    try {
      socket = await WebSocketTransformer.upgrade(
        request,
        compression: CompressionOptions.compressionOff,
      );
    } on Object catch (e) {
      _log.warning(LogEvent('channel_upgrade_failed', {'rid': requestId}), e);
      return;
    }
    socket.pingInterval = policy.pingInterval;
    final hex = bytesToHex(caller.publicKey);
    final channel = _NodeChannel(this, socket, caller, address, requestId);
    final previous = _channels[hex];
    _channels[hex] = channel;
    if (previous != null) {
      unawaited(previous.close(closeReplaced, 'новый канал'));
    }
    _log.info(
      LogEvent('channel_opened', {'rid': requestId, 'open': _channels.length}),
    );
    await channel.run();
    if (identical(_channels[hex], channel)) _channels.remove(hex);
    _log.info(
      LogEvent('channel_closed', {
        'rid': requestId,
        'code': socket.closeCode,
        'open': _channels.length,
      }),
    );
  }

  /// Закрывает все каналы (остановка координатора): узлы переподключатся
  /// к другому экземпляру или после перезапуска.
  Future<void> close() async {
    _closed = true;
    final all = _channels.values.toList();
    _channels.clear();
    await Future.wait([
      for (final c in all) c.close(closeGoingAway, 'координатор остановлен'),
    ]);
  }

  void _limit(RateLimiter limiter, String key, String what) {
    final wait = limiter.take(key);
    if (wait != null) {
      throw RpcException(
        pb.ErrorCode.ERROR_CODE_RATE_LIMITED,
        'превышена частота запросов ($what)',
        retryAfter: wait,
      );
    }
  }

  String _clientAddress(HttpRequest request) {
    if (trustForwardedFor) {
      final forwarded = request.headers.value('x-forwarded-for');
      if (forwarded != null && forwarded.isNotEmpty) {
        return forwarded.split(',').last.trim();
      }
    }
    return request.connectionInfo?.remoteAddress.address ?? '';
  }

  static Future<void> _refuse(
    HttpRequest request,
    RpcException e,
    String requestId,
  ) async {
    final body = e.toProto().writeToBuffer();
    final response = request.response
      ..statusCode = e.status
      ..headers.contentType = ContentType('application', 'x-protobuf')
      ..headers.set(HttpHeaders.cacheControlHeader, 'no-store')
      ..headers.set('fs-request-id', requestId)
      ..contentLength = body.length;
    if (e.retryAfter case final retry?) {
      response.headers.set(
        HttpHeaders.retryAfterHeader,
        '${(retry.inMilliseconds / 1000).ceil()}',
      );
    }
    if (e.httpStatus == 405) response.headers.set('allow', 'GET');
    response.add(body);
    try {
      await response.close();
    } on IOException {
      // Узел уже отключился.
    }
  }

  String _newRequestId() =>
      bytesToHex(List<int>.generate(8, (_) => _random.nextInt(256)));
}

/// Один открытый канал узла.
final class _NodeChannel {
  new(this._hub, this._socket, this._caller, this._address, this._requestId);

  final NodeChannels _hub;
  final WebSocket _socket;
  final Caller _caller;
  final String _address;
  final String _requestId;

  final _pending = <int, Completer<pb.NodeChannelMessage?>>{};
  int _nextId = 1;
  int _lastNodeId = 0;
  int _heartbeats = 0;

  static final Logger _log = NodeChannels._log;

  Future<pb.NodeChannelMessage?> command(pb.CoordinatorChannelMessage message) {
    final id = _nextId++;
    final reply = Completer<pb.NodeChannelMessage?>();
    _pending[id] = reply;
    message
      ..id = Int64(id)
      ..clearReplyTo();
    if (!_add(message)) {
      _pending.remove(id);
      return Future.value();
    }
    return reply.future.whenComplete(() => _pending.remove(id));
  }

  Future<void> run() async {
    try {
      await for (final data in _socket) {
        if (data is! List<int>) {
          await close(
            NodeChannels.closeUnsupportedData,
            'нужны двоичные кадры',
          );
          break;
        }
        if (data.length > NodeChannels.maxMessageBytes) {
          await close(NodeChannels.closeTooBig, 'сообщение больше 64 КиБ');
          break;
        }
        final pb.NodeChannelMessage message;
        try {
          message = ManifestObjects.parseMessage(
            'NodeChannelMessage',
            () => pb.NodeChannelMessage.fromBuffer(data),
          );
        } on DataFormatException {
          await close(
            NodeChannels.closeProtocolError,
            'сообщение не разбирается',
          );
          break;
        }
        if (!await _dispatch(message)) break;
      }
    } on Object catch (e) {
      // Обрыв соединения: тот же итог, что закрытие.
      _log.fine(LogEvent('channel_error', {'rid': _requestId}), e);
    }
    for (final reply in _pending.values.toList()) {
      if (!reply.isCompleted) reply.complete();
    }
  }

  /// Обрабатывает сообщение узла; `false` — канал закрыт.
  Future<bool> _dispatch(pb.NodeChannelMessage message) async {
    final replyTo = message.replyTo.toInt();
    if (replyTo != 0) {
      final pending = _pending[replyTo];
      if (pending != null && !pending.isCompleted) pending.complete(message);
      return true;
    }
    final id = message.id.toInt();
    if (id <= _lastNodeId) {
      await close(NodeChannels.closeProtocolError, 'номера запросов не растут');
      return false;
    }
    _lastNodeId = id;
    if (message.hasHeartbeat()) return await _heartbeat(id, message.heartbeat);
    // Запрос новой версии узла или без тела.
    _reply(
      id,
      error: const RpcException(
        pb.ErrorCode.ERROR_CODE_BAD_REQUEST,
        'неизвестный запрос',
      ),
    );
    return true;
  }

  Future<bool> _heartbeat(int id, pb.HeartbeatRequest request) async {
    final started = DateTime.now();
    final rid = '$_requestId-${++_heartbeats}';
    final nodeId = _caller.publicKey;
    var code = 'OK';
    try {
      final wait = _hub.keyLimiter.take(String.fromCharCodes(nodeId));
      if (wait != null) {
        throw RpcException(
          pb.ErrorCode.ERROR_CODE_RATE_LIMITED,
          'превышена частота запросов (ключ)',
          retryAfter: wait,
        );
      }
      // Узел могли удалить, а владельца заблокировать после открытия
      // канала.
      final info = await _hub.keys.lookup(nodeId);
      if (info == null || info.revoked || info.kind != KeyKind.node) {
        throw const RpcException(
          pb.ErrorCode.ERROR_CODE_UNAUTHENTICATED,
          'узел неизвестен или удалён',
        );
      }
      if (info.blocked) {
        throw const RpcException(
          pb.ErrorCode.ERROR_CODE_PERMISSION_DENIED,
          'учётная запись заблокирована',
        );
      }
      final response = await _hub.service.heartbeat(
        CallContext(
          method: 'Heartbeat',
          requestId: rid,
          caller: Caller(publicKey: nodeId, info: info),
          clientAddress: _address,
        ),
        request,
      );
      _reply(id, heartbeat: response);
      return true;
    } on RpcException catch (e) {
      code = errorCodeName(e.code);
      _reply(id, error: e);
      if (e.code == pb.ErrorCode.ERROR_CODE_UNAUTHENTICATED ||
          e.code == pb.ErrorCode.ERROR_CODE_PERMISSION_DENIED) {
        await close(NodeChannels.closePolicyViolation, code);
        return false;
      }
      return true;
    } on Object catch (e, stack) {
      final RpcException error;
      if (e is ServerException && (e.code == '40P01' || e.code == '40001')) {
        error = const RpcException(
          pb.ErrorCode.ERROR_CODE_UNAVAILABLE,
          'конфликт транзакций',
          retryAfter: Duration(milliseconds: 200),
        );
      } else {
        _log.severe(LogEvent('unhandled', {'rid': rid}), e, stack);
        error = const RpcException(
          pb.ErrorCode.ERROR_CODE_INTERNAL,
          'внутренняя ошибка',
        );
      }
      code = errorCodeName(error.code);
      _reply(id, error: error);
      return true;
    } finally {
      _log.info(
        LogEvent('request', {
          'rid': rid,
          'method': 'Heartbeat',
          'channel': true,
          'code': code,
          'ms': DateTime.now().difference(started).inMilliseconds,
        }),
      );
    }
  }

  void _reply(int id, {pb.HeartbeatResponse? heartbeat, RpcException? error}) {
    _add(
      pb.CoordinatorChannelMessage(
        replyTo: Int64(id),
        heartbeat: heartbeat,
        error: error?.toProto(),
      ),
    );
  }

  bool _add(pb.CoordinatorChannelMessage message) {
    if (_socket.readyState != WebSocket.open) return false;
    try {
      _socket.add(Uint8List.fromList(message.writeToBuffer()));
      return true;
    } on Object {
      return false;
    }
  }

  Future<void> close(int code, String reason) async {
    try {
      await _socket.close(code, reason).timeout(const Duration(seconds: 2));
    } on Object {
      // Соединение уже оборвано.
    }
  }
}
