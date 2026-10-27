import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:daemon_kit/daemon_kit.dart';
import 'package:logging/logging.dart';
import 'package:protocol/protocol.dart' as pb;

/// Когда узел держит соединение с relay (`listen.relay`).
enum RelayMode {
  off,

  /// Когда у узла нет адресов: проверка достижимости не нашла ни одного
  /// доступного порта, а `listen.endpoints` пуст.
  auto,

  /// Всегда, рядом с прямыми соединениями.
  on,
}

/// Приём соединений через relay (задачи 3.8.1, 3.8.2; protocol.md,
/// раздел 4.12): пропуск LISTEN у координатора (`GetRelayPass` на себя),
/// управляющее соединение с relay из ответа и приём каждого сеанса новым
/// соединением, которое уходит [serve] — тому же `PeerService.serve`, что
/// у TCP.
///
/// Пропуск продлевается заранее, на [renewShare] его срока: новое
/// управляющее соединение relay ставит вместо прежнего, начатые сеансы
/// не прерываются. Обрыв, отказ relay или координатора — повтор с
/// растущей паузой до [maxBackoff]. [wanted] опрашивается каждые
/// [pollInterval]: перестал быть нужен — соединение закрывается.
final class RelayPeers {
  new({
    required this.client,
    required this.nodeKey,
    required this.serve,
    required this.wanted,
    this.renewShare = 0.75,
    this.pollInterval = const Duration(seconds: 5),
    this.maxBackoff = const Duration(minutes: 5),
  });

  final CoordinatorClient client;
  final Ed25519KeyPair nodeKey;
  final Future<void> Function(ByteConnection connection) serve;
  final bool Function() wanted;
  final double renewShare;
  final Duration pollInterval;
  final Duration maxBackoff;

  static final _log = Logger('relay');

  RelayListener? _listener;
  StreamSubscription<Uint8List>? _incoming;
  final _active = <Future<void>>{};
  Future<void>? _loop;
  Completer<void>? _wake;
  bool _stopped = false;
  String? _endpoint;
  DateTime? _renewAt;
  String? lastError;

  /// Принятых через relay сеансов с запуска.
  int accepted = 0;

  /// Управляющее соединение открыто.
  bool get connected => _listener != null && !_listener!.isClosed;

  Map<String, Object?> toJson() => {
    'connected': connected,
    'relay': _endpoint,
    'passExpiresAt': _listener?.expiresAt.toUtc().toIso8601String(),
    'accepted': accepted,
    'lastError': lastError,
  };

  void start() => _loop ??= _run();

  /// Проверить [wanted] сейчас.
  void wake() {
    if (_wake case final w? when !w.isCompleted) w.complete();
  }

  Future<void> stop() async {
    _stopped = true;
    wake();
    await _loop;
    await _close();
    await Future.wait(_active.toList());
  }

  Future<void> _run() async {
    var failures = 0;
    while (!_stopped) {
      if (!wanted()) {
        if (_listener != null) {
          _log.info(const LogEvent('relay_not_needed'));
          await _close();
        }
        await _sleep(pollInterval);
        continue;
      }
      final listener = _listener;
      final renewAt = _renewAt;
      if (listener == null ||
          listener.isClosed ||
          renewAt == null ||
          !DateTime.now().isBefore(renewAt)) {
        try {
          await _open();
          failures = 0;
          lastError = null;
        } on CoordinatorException catch (e) {
          lastError = '${e.code.name}: ${e.detail}';
          failures++;
          _log.warning(
            LogEvent('relay_pass_failed', {
              'code': e.code.name,
              'http_status': e.httpStatus,
            }),
          );
          await _sleep(_backoff(failures, e.retryAfter));
          continue;
        } on RelayException catch (e) {
          lastError = '${e.code.name}: ${e.message}';
          failures++;
          _log.warning(LogEvent('relay_open_failed', {'code': e.code.name}));
          await _sleep(_backoff(failures, e.retryAfter));
          continue;
        }
      }
      final current = _listener!;
      final wait = _renewAt!.difference(DateTime.now());
      final opened = DateTime.now();
      await Future.any([
        current.done,
        _sleep(wait < pollInterval ? wait : pollInterval),
      ]);
      if (current.isClosed && !_stopped && identical(current, _listener)) {
        // Relay закрыл соединение: перезапуск, остановка relay, обрыв.
        _log.info(const LogEvent('relay_disconnected'));
        _renewAt = null;
        if (DateTime.now().difference(opened) < const Duration(seconds: 30)) {
          failures++;
          await _sleep(_backoff(failures, null));
        }
      }
    }
  }

  Future<void> _open() async {
    final response = await client.getRelayPass(
      pb.GetRelayPassRequest(nodeId: nodeKey.publicKey),
      key: nodeKey,
    );
    final endpoint = splitHostPort(response.relayEndpoint);
    if (endpoint == null) {
      throw const RelayException(
        pb.ErrorCode.ERROR_CODE_INTERNAL,
        'координатор вернул неверный адрес relay',
      );
    }
    final listener = await RelayListener.open(
      client.crypto,
      host: endpoint.$1,
      port: endpoint.$2,
      pass: response.pass,
      key: nodeKey,
    );
    final previous = _listener;
    final previousIncoming = _incoming;
    _listener = listener;
    _endpoint = response.relayEndpoint;
    final left = listener.expiresAt.difference(DateTime.now());
    _renewAt = DateTime.now().add(left * renewShare);
    _incoming = listener.incoming.listen((id) => _accept(listener, id));
    // Прежнее relay уже заменило новым; закрываем и со своей стороны.
    await previousIncoming?.cancel();
    previous?.close();
    _log.info(
      LogEvent('relay_listening', {
        'relay': response.relayEndpoint,
        'renew_in_s': left.inSeconds,
      }),
    );
  }

  void _accept(RelayListener listener, Uint8List sessionId) {
    final served = () async {
      final ByteConnection connection;
      try {
        connection = await listener.accept(sessionId);
      } on RelayException catch (e) {
        _log.fine(LogEvent('relay_accept_failed', {'code': e.code.name}));
        return;
      }
      accepted++;
      try {
        await serve(connection);
      } on Object catch (e) {
        _log.fine(const LogEvent('relay_peer_error'), e);
      }
    }();
    _active.add(served);
    unawaited(served.whenComplete(() => _active.remove(served)));
  }

  Future<void> _close() async {
    await _incoming?.cancel();
    _incoming = null;
    _listener?.close();
    _listener = null;
    _renewAt = null;
  }

  Duration _backoff(int failures, Duration? retryAfter) {
    final seconds = math.min(1 << math.min(failures, 20), maxBackoff.inSeconds);
    final pause = Duration(seconds: seconds);
    if (retryAfter != null && retryAfter > pause) return retryAfter;
    return pause;
  }

  Future<void> _sleep(Duration d) async {
    if (_stopped) return;
    final wake = _wake = Completer<void>();
    final timer = Timer(d.isNegative ? Duration.zero : d, () {
      if (!wake.isCompleted) wake.complete();
    });
    await wake.future;
    timer.cancel();
  }
}
