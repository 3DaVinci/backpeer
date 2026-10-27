import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:fixnum/fixnum.dart';
import 'package:logging/logging.dart';
import 'package:protocol/protocol.dart' as pb;
import 'package:relay/src/config.dart';
import 'package:relay/src/log.dart';

/// Relay (задачи 3.8.1, 3.8.2; protocol.md, раздел 4.12): узел без
/// входящих соединений держит к нему управляющее соединение по пропуску
/// LISTEN, клиент подключается по пропуску CONNECT, relay просит узел
/// открыть соединение приёма и склеивает два соединения. Noise идёт
/// насквозь: relay видит только шифротекст, объём и время.
///
/// Каждое соединение начинается с вызова (`RelayChallenge`): relay
/// принимает `RelayOpen` с пропуском, подписанным ключом пропусков
/// координатора ([passKeys]), для этого relay ([name]) и в сроке, и с
/// доказательством владения ключом пропуска — подписью над вызовом. Без
/// действующего пропуска соединение не устанавливается.
///
/// Учёт: байты сеансов в обе стороны — на учётную запись из пропуска
/// CONNECT ([usage], отчёт координатору — `RelayReporter`); предел
/// `max_bytes` пропуска действует на все его сеансы вместе.
final class RelayServer {
  new _(
    this._crypto,
    this._server,
    this.name,
    this.passKeys,
    this.limits,
    this._clock,
  ) : _ipLimiter = RateLimiter(
        perSecond: limits.opensPerIpPerSecond,
        burst: limits.opensPerIpBurst,
      ) {
    _subscription = _server.listen(
      (socket) => unawaited(_handle(socket)),
      onError: (Object e) =>
          _log.warning(LogEvent('accept_failed', {'error': e.runtimeType})),
    );
    _ticker = Timer.periodic(limits.pingInterval, (_) => _tick());
  }

  /// Слушает [port] на [host] (`null` — все адреса IPv6 и IPv4; 0 —
  /// любой свободный порт).
  static Future<RelayServer> bind({
    required CryptoProvider crypto,
    required String name,
    required CoordinatorKeySet passKeys,
    String? host,
    int port = 0,
    RelayLimits limits = const RelayLimits(),
    DateTime Function()? clock,
  }) async {
    final ServerSocket server;
    if (host != null) {
      server = await ServerSocket.bind(host, port);
    } else {
      try {
        server = await ServerSocket.bind(InternetAddress.anyIPv6, port);
      } on SocketException {
        return RelayServer._(
          crypto,
          await ServerSocket.bind(InternetAddress.anyIPv4, port),
          name,
          passKeys,
          limits,
          clock ?? DateTime.now,
        );
      }
    }
    final relay = RelayServer._(
      crypto,
      server,
      name,
      passKeys,
      limits,
      clock ?? DateTime.now,
    );
    _log.info(LogEvent('listening', {'name': name, 'port': server.port}));
    return relay;
  }

  static final _log = Logger('relay');

  final CryptoProvider _crypto;
  final ServerSocket _server;
  final String name;
  final CoordinatorKeySet passKeys;
  final RelayLimits limits;
  final DateTime Function() _clock;
  final RateLimiter _ipLimiter;
  late final StreamSubscription<Socket> _subscription;
  late final Timer _ticker;

  /// Прирост трафика для отчёта координатору.
  final RelayUsage usage = RelayUsage();

  final _listeners = <String, _Listener>{};
  final _pending = <String, _Pending>{};
  final _passes = <String, _PassState>{};
  final _sessions = <_Session>{};
  int _connections = 0;
  bool _closed = false;

  /// С запуска.
  int sessionsOpened = 0;
  int bytesRelayed = 0;
  int refused = 0;

  int get port => _server.port;

  /// Узлов с управляющим соединением.
  int get listeners => _listeners.length;

  /// Сеансов ретрансляции сейчас.
  int get sessions => _sessions.length;

  /// Открытых TCP-соединений.
  int get connections => _connections;

  /// Узел [nodeId] держит управляющее соединение.
  bool isListening(Uint8List nodeId) =>
      _listeners.containsKey(bytesToHex(nodeId));

  Map<String, Object?> toJson() => {
    'name': name,
    'port': port,
    'connections': _connections,
    'listeners': listeners,
    'sessions': sessions,
    'sessionsOpened': sessionsOpened,
    'bytesRelayed': bytesRelayed,
    'refused': refused,
  };

  /// Отчёт `ReportRelayUsage` с прироста; счётчики [usage] обнуляются.
  pb.ReportRelayUsageRequest takeReport() =>
      usage.take(name, listeners: listeners, sessions: sessions);

  Future<void> close() async {
    _closed = true;
    _ticker.cancel();
    await _subscription.cancel();
    await _server.close();
    for (final l in _listeners.values.toList()) {
      l.socket.destroy();
    }
    for (final p in _pending.values) {
      if (!p.accepted.isCompleted) {
        p.accepted.completeError(StateError('relay остановлен'));
      }
    }
    _pending.clear();
    for (final s in _sessions.toList()) {
      s.end();
    }
  }

  Future<void> _handle(Socket raw) async {
    final String ip;
    try {
      ip = raw.remoteAddress.address;
    } on SocketException {
      raw.destroy();
      return;
    }
    if (_closed ||
        _connections >= limits.maxConnections ||
        _ipLimiter.take(ip) != null) {
      refused++;
      raw.destroy();
      return;
    }
    _connections++;
    unawaited(
      raw.done.then((_) {}, onError: (_) {}).whenComplete(() => _connections--),
    );
    try {
      raw.setOption(SocketOption.tcpNoDelay, true);
    } on SocketException {
      // Уже закрыто: увидим при чтении.
    }
    final socket = RelaySocket(raw);
    final nonce = _crypto.randomBytes(RelayWire.nonceLength);
    socket.send(
      pb.RelayChallenge(version: RelayWire.version, nonce: nonce, relay: name),
    );
    final pb.RelayOpen open;
    try {
      final frame = await socket.next(timeout: limits.handshakeTimeout);
      if (frame == null) {
        socket.destroy();
        return;
      }
      open = pb.RelayOpen.fromBuffer(frame);
    } on Object {
      // Таймаут, кадр не по формату, не RelayOpen.
      refused++;
      socket.destroy();
      return;
    }
    final pb.RelayPass pass;
    try {
      pass = await RelayPasses.verify(
        _crypto,
        open.pass,
        passKeys,
        relay: name,
        now: _clock(),
      );
    } on RelayPassRejectedException catch (e) {
      _refuse(
        socket,
        pb.ErrorCode.ERROR_CODE_UNAUTHENTICATED,
        'пропуск: ${e.reason.name}',
      );
      return;
    }
    final proofValid =
        open.proof.length == CryptoProvider.ed25519SignatureLength &&
        await _crypto.ed25519Verify(
          publicKey: Uint8List.fromList(pass.holder),
          message: RelayWire.proofInput(
            _crypto,
            nonce,
            open.pass.body,
            open.accept,
          ),
          signature: Uint8List.fromList(open.proof),
        );
    if (!proofValid) {
      _refuse(
        socket,
        pb.ErrorCode.ERROR_CODE_UNAUTHENTICATED,
        'нет доказательства владения ключом пропуска',
      );
      return;
    }
    if (_closed) {
      socket.destroy();
      return;
    }
    final listen = pass.role == pb.RelayRole.RELAY_ROLE_LISTEN;
    if (listen && open.accept.isEmpty) {
      _listen(socket, pass);
    } else if (listen && open.accept.length == RelayWire.sessionIdLength) {
      _accept(socket, pass, Uint8List.fromList(open.accept));
    } else if (!listen && open.accept.isEmpty) {
      await _connect(socket, pass);
    } else {
      _refuse(socket, pb.ErrorCode.ERROR_CODE_BAD_REQUEST, 'accept');
    }
  }

  /// Отказ: `RelayOpened` с ошибкой и закрытие после отправки.
  void _refuse(
    RelaySocket socket,
    pb.ErrorCode code,
    String message, {
    Duration? retryAfter,
  }) {
    refused++;
    _log.fine(LogEvent('refused', {'code': code.name, 'reason': message}));
    socket.send(
      pb.RelayOpened(
        error: pb.Error(
          code: code,
          message: message,
          retryAfterMs: retryAfter?.inMilliseconds,
        ),
      ),
    );
    unawaited(
      socket.socket.flush().then(
        (_) => socket.destroy(),
        onError: (_) => socket.destroy(),
      ),
    );
  }

  void _listen(RelaySocket socket, pb.RelayPass pass) {
    final node = bytesToHex(pass.nodeId);
    final expires = DateTime.fromMillisecondsSinceEpoch(
      pass.expiresAtUnixMs.toInt(),
    );
    socket.send(pb.RelayOpened());
    final previous = _listeners[node];
    final listener = _Listener(node, socket, _clock());
    _listeners[node] = listener;
    // Новое управляющее соединение заменяет прежнее: узел продлил пропуск
    // или переподключился после обрыва, которого relay ещё не заметил.
    previous?.socket.destroy();
    var left = expires.add(RelayPasses.clockSkew).difference(_clock());
    if (left.isNegative) left = Duration.zero;
    listener.expiry = Timer(left, socket.destroy);
    socket.listen((frame) => _onControl(listener, frame), () {
      listener.expiry?.cancel();
      if (identical(_listeners[node], listener)) {
        _listeners.remove(node);
        _log.fine(LogEvent('listener_closed', {'node_id': node}));
      }
    });
    _log.fine(LogEvent('listener', {'node_id': node}));
  }

  void _onControl(_Listener listener, Uint8List frame) {
    listener.lastSeen = _clock();
    final pb.RelayControl message;
    try {
      message = pb.RelayControl.fromBuffer(frame);
    } on Object {
      listener.socket.destroy();
      return;
    }
    if (message.hasPing()) {
      listener.socket.send(pb.RelayControl(pong: message.ping));
    }
  }

  void _accept(RelaySocket socket, pb.RelayPass pass, Uint8List sessionId) {
    final key = bytesToHex(sessionId);
    final pending = _pending[key];
    // Сеанс принимает только узел, к которому подключаются.
    if (pending == null || pending.node != bytesToHex(pass.nodeId)) {
      _refuse(socket, pb.ErrorCode.ERROR_CODE_NOT_FOUND, 'нет такого сеанса');
      return;
    }
    _pending.remove(key);
    pending.accepted.complete(socket);
  }

  Future<void> _connect(RelaySocket client, pb.RelayPass pass) async {
    final node = bytesToHex(pass.nodeId);
    final listener = _listeners[node];
    if (listener == null) {
      _refuse(client, pb.ErrorCode.ERROR_CODE_NOT_FOUND, 'узла нет на relay');
      return;
    }
    final passKey = bytesToHex(pass.passId);
    final state = _passes.putIfAbsent(
      passKey,
      () => _PassState(pass.expiresAtUnixMs.toInt(), pass.maxBytes.toInt()),
    );
    if (state.maxBytes > 0 && state.bytes >= state.maxBytes) {
      _refuse(
        client,
        pb.ErrorCode.ERROR_CODE_QUOTA_EXCEEDED,
        'исчерпан объём пропуска',
      );
      return;
    }
    if (state.sessions >= limits.maxSessionsPerPass) {
      _refuse(
        client,
        pb.ErrorCode.ERROR_CODE_RATE_LIMITED,
        'много сеансов по пропуску',
        retryAfter: const Duration(seconds: 1),
      );
      return;
    }
    final waiting = _pending.values.where((p) => p.node == node).length;
    if (waiting >= limits.maxPendingPerNode) {
      _refuse(
        client,
        pb.ErrorCode.ERROR_CODE_UNAVAILABLE,
        'узел не успевает принимать',
        retryAfter: const Duration(seconds: 1),
      );
      return;
    }
    state.sessions++;
    final sessionId = _crypto.randomBytes(RelayWire.sessionIdLength);
    final key = bytesToHex(sessionId);
    final pending = _pending[key] = _Pending(node, Completer<RelaySocket>());
    listener.socket.send(
      pb.RelayControl(incoming: pb.RelayIncoming(sessionId: sessionId)),
    );
    final RelaySocket nodeSide;
    try {
      nodeSide = await pending.accepted.future.timeout(limits.acceptTimeout);
    } on Object {
      _pending.remove(key);
      state.sessions--;
      if (!_closed) {
        _refuse(
          client,
          pb.ErrorCode.ERROR_CODE_UNAVAILABLE,
          'узел не принял соединение',
          retryAfter: const Duration(seconds: 1),
        );
      }
      return;
    }
    if (client.isClosed) {
      state.sessions--;
      nodeSide.destroy();
      return;
    }
    // Узел узнаёт об открытии раньше клиента: байты клиента приходят к
    // нему уже после RelayOpened.
    nodeSide.send(pb.RelayOpened());
    client.send(pb.RelayOpened());
    sessionsOpened++;
    usage.opened(pass.accountId);
    final session = _Session(
      this,
      state,
      Uint8List.fromList(pass.accountId),
      _clock(),
    );
    _sessions.add(session);
    session.start(client, nodeSide);
    _log.fine(LogEvent('session', {'node_id': node}));
  }

  void _count(_Session session, int bytes) {
    bytesRelayed += bytes;
    usage.add(session.accountId, bytes);
  }

  void _ended(_Session session) {
    if (_sessions.remove(session)) session.state.sessions--;
  }

  void _tick() {
    final now = _clock();
    for (final l in _listeners.values.toList()) {
      if (now.difference(l.lastSeen) > limits.pingInterval * 3) {
        l.socket.destroy();
      } else {
        l.socket.send(pb.RelayControl(ping: Int64(++l.pings)));
      }
    }
    for (final s in _sessions.toList()) {
      if (now.difference(s.lastActivity) > limits.idleTimeout) s.end();
    }
    final nowMs = now.millisecondsSinceEpoch;
    _passes.removeWhere(
      (_, p) =>
          p.sessions <= 0 &&
          p.expiresMs + RelayPasses.clockSkew.inMilliseconds < nowMs,
    );
  }
}

/// Прирост трафика relay с прошлого отчёта: по учётным записям из
/// пропусков CONNECT и всего.
final class RelayUsage {
  final _accounts = <String, (int, int)>{};
  int _bytes = 0;
  int _sessionsOpened = 0;

  void add(List<int> accountId, int bytes) {
    _bytes += bytes;
    final key = bytesToHex(accountId);
    final (b, s) = _accounts[key] ?? (0, 0);
    _accounts[key] = (b + bytes, s);
  }

  void opened(List<int> accountId) {
    _sessionsOpened++;
    final key = bytesToHex(accountId);
    final (b, s) = _accounts[key] ?? (0, 0);
    _accounts[key] = (b, s + 1);
  }

  pb.ReportRelayUsageRequest take(
    String relay, {
    required int listeners,
    required int sessions,
  }) {
    final request = pb.ReportRelayUsageRequest(
      relay: relay,
      usage: [
        for (final MapEntry(:key, value: (bytes, opened)) in _accounts.entries)
          pb.RelayAccountUsage(
            accountId: hexToBytes(key),
            bytes: Int64(bytes),
            sessions: opened,
          ),
      ],
      listeners: listeners,
      sessions: sessions,
      sessionsOpened: Int64(_sessionsOpened),
      bytes: Int64(_bytes),
    );
    _accounts.clear();
    _bytes = 0;
    _sessionsOpened = 0;
    return request;
  }

  /// Возвращает прирост отчёта, который не дошёл до координатора.
  void restore(pb.ReportRelayUsageRequest request) {
    _bytes += request.bytes.toInt();
    _sessionsOpened += request.sessionsOpened.toInt();
    for (final u in request.usage) {
      final key = bytesToHex(u.accountId);
      final (b, s) = _accounts[key] ?? (0, 0);
      _accounts[key] = (b + u.bytes.toInt(), s + u.sessions);
    }
  }
}

final class _Listener {
  new(this.node, this.socket, this.lastSeen);

  final String node;
  final RelaySocket socket;
  DateTime lastSeen;
  Timer? expiry;
  int pings = 0;
}

final class _Pending {
  new(this.node, this.accepted);

  final String node;
  final Completer<RelaySocket> accepted;
}

/// Сеансы и байты одного пропуска CONNECT.
final class _PassState {
  new(this.expiresMs, this.maxBytes);

  final int expiresMs;

  /// 0 — без предела.
  final int maxBytes;
  int bytes = 0;
  int sessions = 0;
}

/// Две склеенные стороны: байты каждой уходят другой как есть. Закрытие
/// одной стороны на запись закрывает на запись другую (половинное
/// закрытие, как у TCP); сеанс заканчивается, когда закрыты обе, при
/// ошибке, сверх объёма пропуска или после простоя.
final class _Session {
  new(this._relay, this.state, this.accountId, this.lastActivity);

  final RelayServer _relay;
  final _PassState state;
  final Uint8List accountId;
  DateTime lastActivity;
  final _sockets = <Socket>[];
  final _subscriptions = <StreamSubscription<Uint8List>>[];
  int _halfClosed = 0;
  bool _ended = false;

  void start(RelaySocket a, RelaySocket b) {
    final (restA, subA) = a.detach();
    final (restB, subB) = b.detach();
    _sockets.addAll([a.socket, b.socket]);
    _subscriptions.addAll([subA, subB]);
    if (!_forward(restA, b.socket) || !_forward(restB, a.socket)) return;
    _pump(subA, b.socket);
    _pump(subB, a.socket);
  }

  /// `false` — сеанс закончен (сверх объёма).
  bool _forward(Uint8List chunk, Socket to) {
    if (chunk.isEmpty) return true;
    lastActivity = _relay._clock();
    state.bytes += chunk.length;
    _relay._count(this, chunk.length);
    if (state.maxBytes > 0 && state.bytes > state.maxBytes) {
      end();
      return false;
    }
    to.add(chunk);
    return true;
  }

  void _pump(StreamSubscription<Uint8List> from, Socket to) {
    from
      ..onData((chunk) {
        if (_ended || !_forward(chunk, to)) return;
        // Обратное давление: следующая часть — когда эта ушла в сеть.
        from.pause();
        unawaited(
          to.flush().then((_) {
            if (!_ended) from.resume();
          }, onError: (_) => end()),
        );
      })
      ..onError((_) => end())
      ..onDone(() {
        if (_ended) return;
        unawaited(to.close().then((_) {}, onError: (_) => end()));
        if (++_halfClosed == 2) end();
      })
      ..resume();
  }

  void end() {
    if (_ended) return;
    _ended = true;
    for (final s in _subscriptions) {
      unawaited(s.cancel());
    }
    for (final s in _sockets) {
      s.destroy();
    }
    _relay._ended(this);
  }
}
