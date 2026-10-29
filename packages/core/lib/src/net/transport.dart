import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:core/src/coordinator/coordinator_client.dart';
import 'package:core/src/crypto/crypto_provider.dart';
import 'package:core/src/errors.dart';
import 'package:core/src/net/byte_connection.dart';
import 'package:core/src/net/peer_handshake.dart';
import 'package:core/src/net/peer_identity.dart';
import 'package:core/src/net/relay/relay_client.dart';
import 'package:core/src/net/secure_channel.dart';
import 'package:core/src/net/traffic_meter.dart';
import 'package:core/src/net/udp/udp_connector.dart';
import 'package:core/src/net/udp/udp_endpoint.dart';
import 'package:core/src/util/bytes.dart';
import 'package:protocol/protocol.dart' as pb;

/// Как найти узел: `NodeAddress` из ответа координатора.
final class NodeContact {
  const new({required this.nodeId, this.endpoints = const []});

  new fromProto(pb.NodeAddress address)
    : nodeId = Uint8List.fromList(address.nodeId),
      endpoints = List.unmodifiable(address.endpoints);

  final Uint8List nodeId;

  /// Адреса `хост:порт` для прямого TCP; пусто — узел за NAT
  /// (`needs_relay`).
  final List<String> endpoints;
}

/// Канал Noise к узлу, проверенному по `node_id`, и способ, которым он
/// получен.
final class PeerConnection {
  const new({required this.channel, required this.method, this.endpoint});

  final SecureChannel channel;
  final pb.ConnectionMethod method;

  /// Адрес прямого TCP; у UDP и relay — `null`.
  final String? endpoint;
}

/// Подключение к узлу — граница сетевого модуля (готовность к Rust,
/// `Planning/Dart Flutter для всего проекта.md`): как установлен поток,
/// решает реализация, наружу выходит проверенный канал Noise.
abstract interface class Transport {
  /// Канал к узлу [node]. Ни один способ не удался —
  /// [PeerUnreachableException].
  Future<PeerConnection> connect(NodeContact node);

  /// Освобождает сокеты; начатые каналы не закрывает.
  Future<void> close();
}

/// Поток к узлу по прямому адресу `хост:порт`.
typedef DirectDialer = Future<ByteConnection> Function(String endpoint);

/// Поток к узлу [nodeId] без прямого адреса: UDP после сведения, relay.
typedef NodeDialer = Future<ByteConnection> Function(Uint8List nodeId);

/// Прямое соединение TCP с [endpoint] (`хост:порт`, IPv6 в скобках).
Future<ByteConnection> connectTcp(
  String endpoint, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final address = splitHostPort(endpoint);
  if (address == null) {
    throw SocketException('неверный адрес $endpoint');
  }
  final socket = await Socket.connect(address.$1, address.$2, timeout: timeout);
  socket.setOption(SocketOption.tcpNoDelay, true);
  return SocketConnection(socket);
}

/// [Transport] со стратегией подключения (задача 3.9.1; protocol.md,
/// раздел 7, «Соединение с узлом за NAT»): прямой TCP по адресам узла →
/// поток UDP после сведения → relay.
///
/// **Параллельные попытки.** Способы начинаются по очереди с задержкой,
/// не дожидаясь неудачи предыдущих (как «Happy Eyeballs», RFC 8305):
/// следующий адрес TCP — через [directStagger], UDP — через
/// [fallbackDelay] после последнего TCP, relay — через [relayDelay] после
/// UDP (сведение длится до 15 секунд). Если все начатые попытки уже не
/// удались, следующая начинается сразу. Побеждает первая, прошедшая
/// рукопожатие Noise с проверкой `node_id`: адрес, принявший TCP, но
/// предъявивший чужой ключ, — неудача. Остальные попытки закрываются.
///
/// **Кеш.** Удачный способ (и адрес TCP) запоминается для узла на
/// [cacheTtl]: следующее подключение начинает с него, остальные идут за
/// ним с обычными задержками. Неудача способа из кеша стирает запись.
///
/// **Метрики.** Каждое соединение оборачивается [meter] под своим
/// способом: байты всех попыток (рукопожатие) учитываются, соединение —
/// только у победившей. [connected] — подключения по способам с запуска.
final class ConnectionStrategy implements Transport {
  new({
    required this.crypto,
    required this.local,
    this.direct = connectTcp,
    this.udp,
    this.relay,
    this.meter,
    this.directStagger = const Duration(milliseconds: 250),
    this.fallbackDelay = const Duration(seconds: 1),
    this.relayDelay = const Duration(seconds: 3),
    this.handshakeTimeout = PeerHandshake.defaultTimeout,
    this.connectTimeout = const Duration(seconds: 60),
    this.cacheTtl = const Duration(minutes: 30),
    this.cacheSize = 4096,
    this._onClose,
  });

  /// Стратегия клиента координатора [client]: TCP, UDP через сводник
  /// координатора (сокет открывается при первом сведении) и relay по
  /// пропускам `GetRelayPass`. [udp] и [relay] — включить способ.
  /// [key] — ключ, которым подписаны `Rendezvous` и `GetRelayPass`: ключ
  /// узла-исполнителя ремонта; `null` — ключ устройства клиента.
  factory forCoordinator({
    required CryptoProvider crypto,
    required LocalPeer local,
    required CoordinatorClient client,
    Ed25519KeyPair? key,
    TrafficMeter? meter,
    bool udp = true,
    bool relay = true,
  }) {
    Future<UdpConnector>? connector;
    Future<UdpConnector> udpConnector() => connector ??= UdpEndpoint.bind()
        .then((e) => UdpConnector(client: client, endpoint: e, key: key));
    final relayConnector = RelayConnector(client: client, key: key);
    return ConnectionStrategy(
      crypto: crypto,
      local: local,
      meter: meter,
      udp: udp
          ? (nodeId) async => await (await udpConnector()).connect(nodeId)
          : null,
      relay: relay ? relayConnector.connect : null,
      onClose: () async {
        final c = connector;
        connector = null;
        if (c != null) await (await c).endpoint.close();
      },
    );
  }

  final CryptoProvider crypto;

  /// Своя сторона: устройство клиента или узел при ремонте.
  final LocalPeer local;

  final DirectDialer direct;

  /// `null` — способ выключен.
  final NodeDialer? udp;
  final NodeDialer? relay;

  final TrafficMeter? meter;
  final Duration directStagger;
  final Duration fallbackDelay;
  final Duration relayDelay;
  final Duration handshakeTimeout;

  /// Предел на подключение целиком.
  final Duration connectTimeout;
  final Duration cacheTtl;
  final int cacheSize;
  final Future<void> Function()? _onClose;

  final _cache = <String, _Success>{};

  /// Подключений по способам с запуска.
  final Map<pb.ConnectionMethod, int> connected = {};

  /// Подключений, начатых со способа из кеша.
  int cacheHits = 0;

  /// Способ из кеша для узла [nodeId]: для журнала и тестов.
  pb.ConnectionMethod? cachedMethod(Uint8List nodeId) =>
      _cached(bytesToHex(nodeId))?.method;

  @override
  Future<PeerConnection> connect(NodeContact node) {
    final key = bytesToHex(node.nodeId);
    final cached = _cached(key);
    final plan = _plan(node, cached);
    if (plan.isEmpty) {
      return Future.error(PeerUnreachableException(node.nodeId, const []));
    }
    if (cached != null && plan.first.matches(cached)) cacheHits++;
    return _Race(this, node, plan).run();
  }

  @override
  Future<void> close() async => await _onClose?.call();

  _Success? _cached(String key) {
    final s = _cache[key];
    if (s == null) return null;
    if (DateTime.now().difference(s.at) > cacheTtl) {
      _cache.remove(key);
      return null;
    }
    return s;
  }

  /// Попытки по порядку с задержками перед каждой.
  List<_Attempt> _plan(NodeContact node, _Success? cached) {
    final attempts = <_Attempt>[
      for (final e in {...node.endpoints})
        _Attempt(pb.ConnectionMethod.CONNECTION_METHOD_DIRECT, e),
      if (udp != null)
        const _Attempt(pb.ConnectionMethod.CONNECTION_METHOD_UDP),
      if (relay != null)
        const _Attempt(pb.ConnectionMethod.CONNECTION_METHOD_RELAY),
    ];
    if (cached != null) {
      final i = attempts.indexWhere((a) => a.matches(cached));
      if (i > 0) attempts.insert(0, attempts.removeAt(i));
    }
    for (var i = 1; i < attempts.length; i++) {
      final previous = attempts[i - 1].method;
      attempts[i] = attempts[i].after(switch (attempts[i].method) {
        pb.ConnectionMethod.CONNECTION_METHOD_DIRECT
            when previous == pb.ConnectionMethod.CONNECTION_METHOD_DIRECT =>
          directStagger,
        pb.ConnectionMethod.CONNECTION_METHOD_RELAY
            when previous == pb.ConnectionMethod.CONNECTION_METHOD_UDP =>
          relayDelay,
        _ => fallbackDelay,
      });
    }
    return attempts;
  }

  void _remember(String key, _Attempt attempt) {
    _cache
      ..remove(key)
      ..[key] = _Success(attempt.method, attempt.endpoint, DateTime.now());
    while (_cache.length > cacheSize) {
      _cache.remove(_cache.keys.first);
    }
  }

  void _forget(String key, _Attempt attempt) {
    final s = _cache[key];
    if (s != null && attempt.matches(s)) _cache.remove(key);
  }

  Future<PeerConnection> _attempt(
    NodeContact node,
    _Attempt attempt,
    void Function(ByteConnection) opened,
  ) async {
    final raw = await switch (attempt.method) {
      pb.ConnectionMethod.CONNECTION_METHOD_DIRECT => direct(attempt.endpoint!),
      pb.ConnectionMethod.CONNECTION_METHOD_UDP => udp!(node.nodeId),
      _ => relay!(node.nodeId),
    };
    final connection = meter?.wrap(raw, attempt.method, count: false) ?? raw;
    opened(connection);
    final channel = await PeerHandshake.initiate(
      crypto,
      connection,
      local: local,
      policy: PeerPolicy.node(node.nodeId),
      timeout: handshakeTimeout,
    );
    return PeerConnection(
      channel: channel,
      method: attempt.method,
      endpoint: attempt.endpoint,
    );
  }
}

/// Попытка подключения: способ, адрес TCP, задержка после начала
/// предыдущей.
final class _Attempt {
  const new(this.method, [this.endpoint, this.delay = Duration.zero]);

  final pb.ConnectionMethod method;
  final String? endpoint;
  final Duration delay;

  _Attempt after(Duration delay) => _Attempt(method, endpoint, delay);

  bool matches(_Success s) => s.method == method && s.endpoint == endpoint;

  String get methodName => TrafficMeter.methodName(method);
}

final class _Success {
  const new(this.method, this.endpoint, this.at);

  final pb.ConnectionMethod method;
  final String? endpoint;
  final DateTime at;
}

/// Одно подключение: попытки по плану, первая удачная побеждает.
final class _Race {
  new(this.strategy, this.node, this.plan) : key = bytesToHex(node.nodeId);

  final ConnectionStrategy strategy;
  final NodeContact node;
  final List<_Attempt> plan;
  final String key;
  final _result = Completer<PeerConnection>();
  final _failures = <({String method, String? endpoint, String error})>[];

  /// Потоки попыток, ещё не прошедших рукопожатие: закрываются, когда
  /// победила другая.
  final _opening = <ByteConnection>{};
  int _next = 0;
  int _running = 0;
  Timer? _timer;
  Timer? _deadline;

  Future<PeerConnection> run() {
    _deadline = Timer(strategy.connectTimeout, () {
      _failures.add((
        method: 'all',
        endpoint: null,
        error: 'не подключились за ${strategy.connectTimeout.inSeconds} с',
      ));
      _fail();
    });
    _start();
    return _result.future;
  }

  void _fail() {
    if (_result.isCompleted) return;
    _timer?.cancel();
    _deadline?.cancel();
    for (final c in _opening) {
      c.destroy();
    }
    _opening.clear();
    _result.completeError(PeerUnreachableException(node.nodeId, _failures));
  }

  void _start() {
    _timer?.cancel();
    if (_result.isCompleted || _next >= plan.length) return;
    final attempt = plan[_next++];
    _running++;
    ByteConnection? opened;
    unawaited(
      strategy
          ._attempt(node, attempt, (c) {
            opened = c;
            if (_result.isCompleted) {
              c.destroy();
            } else {
              _opening.add(c);
            }
          })
          .then(
            (connection) => _won(attempt, connection, opened),
            onError: (Object e) => _failed(attempt, e, opened),
          ),
    );
    if (_next < plan.length) _timer = Timer(plan[_next].delay, _start);
  }

  void _won(_Attempt attempt, PeerConnection connection, ByteConnection? raw) {
    _running--;
    _opening.remove(raw);
    if (_result.isCompleted) {
      connection.channel.destroy();
      return;
    }
    _timer?.cancel();
    _deadline?.cancel();
    for (final c in _opening) {
      c.destroy();
    }
    _opening.clear();
    strategy._remember(key, attempt);
    strategy.connected.update(attempt.method, (n) => n + 1, ifAbsent: () => 1);
    strategy.meter?.countConnection(attempt.method);
    _result.complete(connection);
  }

  void _failed(_Attempt attempt, Object error, ByteConnection? raw) {
    _running--;
    _opening.remove(raw);
    if (_result.isCompleted) return;
    strategy._forget(key, attempt);
    _failures.add((
      method: attempt.methodName,
      endpoint: attempt.endpoint,
      error: error is CoreException ? error.message : '$error',
    ));
    if (_running > 0) return;
    if (_next < plan.length) {
      // Начатые попытки не удались: ждать задержки следующей незачем.
      _start();
    } else {
      _fail();
    }
  }
}
