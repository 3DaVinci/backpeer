// Канал команд координатора (задача 3.6.1): WebSocket от узла с подписью
// при подключении, heartbeat и команды по каналу, замена канала, удаление
// узла при открытом канале, переподключение после обрыва и после «тихой»
// потери сети (нет pong). Узел — настоящий CommandChannel и CoordinatorLink
// из пакета node, координатор — NodeChannels без базы.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:coordinator/coordinator.dart';
import 'package:core/core.dart';
import 'package:fixnum/fixnum.dart';
import 'package:node/node.dart';
import 'package:protocol/protocol.dart' as pb;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';

/// Heartbeat, регистрация и отзывы без базы.
final class _Service extends CoordinatorService {
  final beats = <pb.HeartbeatRequest>[];

  @override
  Future<pb.HeartbeatResponse> heartbeat(
    CallContext context,
    pb.HeartbeatRequest request,
  ) async {
    beats.add(request);
    return pb.HeartbeatResponse(nextHeartbeatMs: 60000);
  }

  @override
  Future<pb.RegisterNodeResponse> registerNode(
    CallContext context,
    pb.RegisterNodeRequest request,
  ) async => pb.RegisterNodeResponse();
}

/// Координатор на loopback: API и канал на одном порту, как
/// CoordinatorServer.
final class _Coordinator {
  new _(this.http, this.channels, this.service, this.keys) {
    final handler = ApiHandler(
      methods: coordinatorMethods(service),
      verifier: channels.verifier,
      ipLimiter: RateLimiter(perSecond: 1000, burst: 1000),
      keyLimiter: RateLimiter(perSecond: 1000, burst: 1000),
      healthCheck: () async => true,
    );
    shelf_io.serveRequests(
      http.where((request) {
        if (!channels.handles(request)) {
          httpCalls.add(request.uri.pathSegments.last);
          return true;
        }
        unawaited(channels.handle(request));
        return false;
      }),
      handler.call,
    );
  }

  static Future<_Coordinator> start(
    CryptoProvider crypto, {
    ChannelPolicy policy = const ChannelPolicy(),
  }) async {
    final keys = InMemoryKeyDirectory();
    final service = _Service();
    final verifier = RequestVerifier(crypto: crypto, keys: keys);
    return _Coordinator._(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
      NodeChannels(
        service: service,
        verifier: verifier,
        keys: keys,
        ipLimiter: RateLimiter(perSecond: 1000, burst: 1000),
        keyLimiter: RateLimiter(perSecond: 1000, burst: 1000),
        policy: policy,
      ),
      service,
      keys,
    );
  }

  final HttpServer http;
  final NodeChannels channels;
  final _Service service;
  final InMemoryKeyDirectory keys;
  final httpCalls = <String>[];

  int get port => http.port;

  Future<void> close() async {
    await channels.close();
    await http.close(force: true);
  }
}

/// TCP-прокси между узлом и координатором: [drop] рвёт соединения,
/// [frozen] молча теряет данные (сеть пропала без RST).
final class _Proxy {
  new _(this._server, this._target) {
    _server.listen(_accept);
  }

  static Future<_Proxy> start(int target) async => _Proxy._(
    await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
    target,
  );

  final ServerSocket _server;
  final int _target;
  final _sockets = <Socket>[];
  bool frozen = false;

  int get port => _server.port;

  Future<void> _accept(Socket inbound) async {
    final Socket outbound;
    try {
      outbound = await Socket.connect(InternetAddress.loopbackIPv4, _target);
    } on SocketException {
      inbound.destroy();
      return;
    }
    _sockets.addAll([inbound, outbound]);
    void pipe(Socket from, Socket to) => from.listen(
      (data) {
        if (!frozen) to.add(data);
      },
      onDone: to.destroy,
      onError: (Object _) => to.destroy(),
    );
    pipe(inbound, outbound);
    pipe(outbound, inbound);
  }

  void drop() {
    for (final s in _sockets) {
      s.destroy();
    }
    _sockets.clear();
  }

  Future<void> close() async {
    drop();
    await _server.close();
  }
}

Future<void> _until(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 10),
  String? reason,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('не дождались${reason == null ? '' : ': $reason'}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  late CryptoProvider crypto;
  setUpAll(() async => crypto = await SodiumCryptoProvider.load());

  late _Coordinator coordinator;
  late Ed25519KeyPair nodeKey;
  late CoordinatorClient client;
  final cleanup = <Future<void> Function()>[];

  setUp(() async {
    coordinator = await _Coordinator.start(crypto);
    nodeKey = await crypto.ed25519FromSeed(SecretBytes(crypto.randomBytes(32)));
    coordinator.keys.put(
      nodeKey.publicKey,
      KeyInfo(kind: KeyKind.node, accountId: Uint8List(32)),
    );
    client = CoordinatorClient(
      baseUri: Uri.parse('http://127.0.0.1:${coordinator.port}'),
      crypto: crypto,
      requestTimeout: const Duration(seconds: 2),
    );
  });
  tearDown(() async {
    for (final f in cleanup.reversed) {
      await f();
    }
    cleanup.clear();
    client.close(force: true);
    await coordinator.close();
  });

  CommandChannel channel({
    CoordinatorClient? via,
    Future<pb.NodeChannelMessage?> Function(pb.CoordinatorChannelMessage)?
    onCommand,
    Duration pingInterval = const Duration(seconds: 30),
  }) {
    final c = CommandChannel(
      client: via ?? client,
      nodeKey: nodeKey,
      onCommand: onCommand ?? (_) async => null,
      pingInterval: pingInterval,
      replyTimeout: const Duration(seconds: 2),
      random: Random(1),
    )..start();
    cleanup.add(c.stop);
    return c;
  }

  /// Запрос открытия канала с подписью [key] (или без неё) — ответ HTTP.
  Future<(int, pb.Error?)> upgrade({
    Ed25519KeyPair? key,
    bool websocket = true,
    String path = CoordinatorClient.nodeChannelPath,
  }) async {
    final http = HttpClient();
    try {
      final request = await http.getUrl(
        Uri.parse('http://127.0.0.1:${coordinator.port}$path'),
      );
      if (websocket) {
        request.headers
          ..set('connection', 'Upgrade')
          ..set('upgrade', 'websocket')
          ..set('sec-websocket-version', '13')
          ..set('sec-websocket-key', base64.encode(crypto.randomBytes(16)));
      }
      if (key != null) {
        final auth = await RequestAuth.sign(
          crypto,
          key,
          path: CoordinatorClient.nodeChannelPath,
          body: const [],
        );
        request.headers.set('FS-Auth', auth.toHeader());
      }
      final response = await request.close();
      final body = await response.fold<List<int>>([], (a, b) => a..addAll(b));
      final error = response.statusCode == 101 || body.isEmpty
          ? null
          : pb.Error.fromBuffer(body);
      return (response.statusCode, error);
    } finally {
      http.close(force: true);
    }
  }

  test('без подписи, с чужим ключом, без WebSocket — отказ до '
      'открытия', () async {
    var (status, error) = await upgrade();
    expect(status, 401);
    expect(error!.code, pb.ErrorCode.ERROR_CODE_UNAUTHENTICATED);

    final stranger = await crypto.ed25519FromSeed(
      SecretBytes(crypto.randomBytes(32)),
    );
    (status, error) = await upgrade(key: stranger);
    expect(status, 401);

    final device = await crypto.ed25519FromSeed(
      SecretBytes(crypto.randomBytes(32)),
    );
    coordinator.keys.put(
      device.publicKey,
      KeyInfo(kind: KeyKind.device, accountId: Uint8List(32)),
    );
    (status, error) = await upgrade(key: device);
    expect(status, 403);
    expect(error!.code, pb.ErrorCode.ERROR_CODE_PERMISSION_DENIED);

    (status, error) = await upgrade(key: nodeKey, websocket: false);
    expect(status, 426);
    expect(error!.code, pb.ErrorCode.ERROR_CODE_BAD_REQUEST);

    final socket = await client.openNodeChannel(nodeKey: nodeKey);
    cleanup.add(socket.close);
    await _until(() => coordinator.channels.isConnected(nodeKey.publicKey));
  });

  test('heartbeat по каналу и команды координатора', () async {
    final received = <pb.CoordinatorChannelMessage>[];
    final c = channel(
      onCommand: (command) async {
        received.add(command);
        if (command.hasSyncRevocations() &&
            command.syncRevocations.sequence == Int64(13)) {
          throw const CoordinatorException(
            pb.ErrorCode.ERROR_CODE_BAD_REQUEST,
            'неизвестная команда',
          );
        }
        return null;
      },
    );
    await _until(() => c.connected);
    final beat = await c.heartbeat(
      pb.HeartbeatRequest(usedBytes: Int64(7), capacityBytes: Int64(100)),
    );
    expect(beat.nextHeartbeatMs, 60000);
    expect(coordinator.service.beats.single.usedBytes, Int64(7));
    expect(coordinator.httpCalls, isEmpty, reason: 'heartbeat не по HTTP');

    final started = DateTime.now();
    final pong = await coordinator.channels.send(
      nodeKey.publicKey,
      pb.CoordinatorChannelMessage(ping: pb.PingCommand()),
    );
    expect(pong!.hasDone(), isTrue);
    expect(
      DateTime.now().difference(started),
      lessThan(const Duration(seconds: 1)),
    );
    final rejected = await coordinator.channels.send(
      nodeKey.publicKey,
      pb.CoordinatorChannelMessage(
        syncRevocations: pb.SyncRevocationsCommand(sequence: Int64(13)),
      ),
    );
    expect(rejected!.error.code, pb.ErrorCode.ERROR_CODE_BAD_REQUEST);
    expect(
      coordinator.channels.broadcast(
        pb.CoordinatorChannelMessage(
          syncRevocations: pb.SyncRevocationsCommand(sequence: Int64(14)),
        ),
      ),
      1,
    );
    await _until(() => received.length == 3);
    expect(received.map((m) => m.whichBody()), [
      pb.CoordinatorChannelMessage_Body.ping,
      pb.CoordinatorChannelMessage_Body.syncRevocations,
      pb.CoordinatorChannelMessage_Body.syncRevocations,
    ]);
    await _until(() => c.commands == 2);
    expect(c.toJson(), containsPair('connected', true));
    // Узла без канала нет — команда не доставлена.
    expect(
      await coordinator.channels.send(
        Uint8List(32),
        pb.CoordinatorChannelMessage(ping: pb.PingCommand()),
      ),
      isNull,
    );
  });

  test('новый канал того же узла заменяет прежний', () async {
    final first = await client.openNodeChannel(nodeKey: nodeKey);
    final firstDone = first.drain<void>();
    await _until(() => coordinator.channels.count == 1);
    final second = await client.openNodeChannel(nodeKey: nodeKey);
    cleanup.add(second.close);
    await firstDone.timeout(const Duration(seconds: 5));
    expect(first.closeCode, NodeChannels.closeReplaced);
    expect(coordinator.channels.count, 1);
  });

  test('сообщение не Protobuf и текстовый кадр закрывают канал', () async {
    final binary = await client.openNodeChannel(nodeKey: nodeKey);
    binary.add(Uint8List.fromList([0xFF, 0xFF, 0xFF]));
    await binary.drain<void>().timeout(const Duration(seconds: 5));
    expect(binary.closeCode, NodeChannels.closeProtocolError);

    final text = await client.openNodeChannel(nodeKey: nodeKey);
    text.add('heartbeat');
    await text.drain<void>().timeout(const Duration(seconds: 5));
    expect(text.closeCode, NodeChannels.closeUnsupportedData);

    final tooBig = await client.openNodeChannel(nodeKey: nodeKey);
    tooBig.add(Uint8List(NodeChannels.maxMessageBytes + 1));
    await tooBig.drain<void>().timeout(const Duration(seconds: 5));
    expect(tooBig.closeCode, NodeChannels.closeTooBig);
  });

  test('узел удалён при открытом канале: heartbeat UNAUTHENTICATED, '
      'канал закрыт и больше не открывается', () async {
    final c = channel();
    await _until(() => c.connected);
    coordinator.keys.put(
      nodeKey.publicKey,
      KeyInfo(kind: KeyKind.node, accountId: Uint8List(32), revoked: true),
    );
    await expectLater(
      c.heartbeat(pb.HeartbeatRequest()),
      throwsA(
        isA<CoordinatorException>().having(
          (e) => e.code,
          'code',
          pb.ErrorCode.ERROR_CODE_UNAUTHENTICATED,
        ),
      ),
    );
    await _until(() => !c.connected);
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    expect(c.connected, isFalse);
    expect(c.opened, 1);
    expect(coordinator.channels.count, 0);
    expect(c.toJson()['lastError'], isNotNull);
  });

  test('обрыв соединения: канал открывается снова, команда доходит', () async {
    final proxy = await _Proxy.start(coordinator.port);
    cleanup.add(proxy.close);
    final viaProxy = CoordinatorClient(
      baseUri: Uri.parse('http://127.0.0.1:${proxy.port}'),
      crypto: crypto,
      requestTimeout: const Duration(seconds: 2),
    );
    cleanup.add(() async => viaProxy.close(force: true));
    var pings = 0;
    final c = channel(
      via: viaProxy,
      onCommand: (_) async {
        pings++;
        return null;
      },
    );
    await _until(() => c.connected);
    proxy.drop();
    await _until(() => c.opened == 2, reason: 'переподключение');
    await _until(() => coordinator.channels.isConnected(nodeKey.publicKey));
    final reply = await coordinator.channels.send(
      nodeKey.publicKey,
      pb.CoordinatorChannelMessage(ping: pb.PingCommand()),
    );
    expect(reply!.hasDone(), isTrue);
    expect(pings, 1);
  });

  test('сеть пропала без разрыва: нет pong — канал закрыт и открыт '
      'заново', () async {
    final proxy = await _Proxy.start(coordinator.port);
    cleanup.add(proxy.close);
    final viaProxy = CoordinatorClient(
      baseUri: Uri.parse('http://127.0.0.1:${proxy.port}'),
      crypto: crypto,
      requestTimeout: const Duration(seconds: 1),
    );
    cleanup.add(() async => viaProxy.close(force: true));
    final c = channel(
      via: viaProxy,
      pingInterval: const Duration(milliseconds: 200),
    );
    await _until(() => c.connected);
    proxy.frozen = true;
    await _until(() => !c.connected, reason: 'обрыв по ping');
    await Future<void>.delayed(const Duration(milliseconds: 300));
    proxy
      ..drop()
      ..frozen = false;
    await _until(() => c.connected && c.opened == 2, reason: 'переподключение');
    expect((await c.heartbeat(pb.HeartbeatRequest())).nextHeartbeatMs, 60000);
  });

  test('предел каналов: сверх — UNAVAILABLE', () async {
    await coordinator.close();
    coordinator = await _Coordinator.start(
      crypto,
      policy: const ChannelPolicy(maxConnections: 0),
    );
    coordinator.keys.put(
      nodeKey.publicKey,
      KeyInfo(kind: KeyKind.node, accountId: Uint8List(32)),
    );
    final (status, error) = await upgrade(key: nodeKey);
    expect(status, 503);
    expect(error!.code, pb.ErrorCode.ERROR_CODE_UNAVAILABLE);
    expect(error.retryAfterMs, greaterThan(0));
  });

  test('CoordinatorLink: после регистрации heartbeat идёт по каналу, '
      'без канала — по HTTP', () async {
    final dir = Directory.systemTemp.createTempSync('fs-channel-link-');
    cleanup.add(() async => dir.deleteSync(recursive: true));
    await NodeIdentity.ensureKeys(dir, crypto);
    final owner = await AccountKeys.fromMasterKey(
      SecretBytes(crypto.randomBytes(32)),
      crypto,
    );
    var identity = await NodeIdentity.load(dir, crypto);
    await NodeIdentity.importCertificate(
      dir,
      crypto,
      (await NodeCertificates.issue(
        crypto,
        owner,
        nodeId: identity.nodeId,
        nodeDh: identity.nodeDh,
        issuedAt: DateTime.now(),
      )).writeToBuffer(),
    );
    identity.dispose();
    owner.dispose();
    identity = await NodeIdentity.load(dir, crypto);
    cleanup.add(() async => identity.dispose());
    coordinator.keys.put(
      identity.nodeId,
      KeyInfo(kind: KeyKind.node, accountId: Uint8List(32)),
    );
    final link = CoordinatorLink(
      client: client,
      identity: identity,
      capacityBytes: 1000,
      usedBytes: () => 1,
      trustedKeys: CoordinatorKeySet.builtIn,
      commandChannel: true,
    )..start();
    cleanup.add(link.stop);
    // Открылся канал — heartbeat сразу, по каналу.
    await _until(() => coordinator.service.beats.isNotEmpty);
    expect(coordinator.httpCalls, ['RegisterNode']);
    expect(link.channel!.connected, isTrue);
    expect(link.toJson()['channel'], containsPair('connected', true));
    // Ping по каналу — ответ узла.
    final reply = await coordinator.channels.send(
      identity.nodeId,
      pb.CoordinatorChannelMessage(ping: pb.PingCommand()),
    );
    expect(reply!.hasDone(), isTrue);
    // Канал закрыт координатором — следующий heartbeat по HTTP.
    await coordinator.channels.close();
    await _until(() => !link.channel!.connected);
    await link.heartbeat();
    expect(coordinator.httpCalls, ['RegisterNode', 'Heartbeat']);
  });
}
