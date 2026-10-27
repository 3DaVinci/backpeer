// Стратегия подключения к узлу (задача 3.9.1): прямой TCP → UDP после
// сведения → relay, параллельные попытки с задержкой, проверка node_id в
// рукопожатии, кеш удачного способа, учёт в метриках. Способы подменены
// парами соединений в памяти; на другой стороне — рукопожатие узла.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:protocol/protocol.dart' as pb;
import 'package:test/test.dart';

const pb.ConnectionMethod _direct =
    pb.ConnectionMethod.CONNECTION_METHOD_DIRECT;
const pb.ConnectionMethod _udp = pb.ConnectionMethod.CONNECTION_METHOD_UDP;
const pb.ConnectionMethod _relay = pb.ConnectionMethod.CONNECTION_METHOD_RELAY;

/// Узел на другом конце пары в памяти.
final class _Node {
  new(this.nodeId, this.local);

  final Uint8List nodeId;
  final LocalPeer local;
}

void main() {
  late CryptoProvider crypto;
  late LocalPeer client;
  late _Node node;
  late _Node impostor;

  Future<_Node> makeNode(AccountKeys owner) async {
    final sign = await crypto.ed25519FromSeed(
      SecretBytes(crypto.randomBytes(32)),
    );
    final dh = await crypto.x25519FromSecret(
      SecretBytes(crypto.randomBytes(32)),
    );
    return _Node(
      sign.publicKey,
      LocalPeer(
        role: pb.PeerRole.PEER_ROLE_NODE,
        staticKey: dh,
        certificate: await NodeCertificates.issue(
          crypto,
          owner,
          nodeId: sign.publicKey,
          nodeDh: dh.publicKey,
          issuedAt: DateTime.now(),
        ),
        software: 'node test',
      ),
    );
  }

  setUpAll(() async {
    crypto = await SodiumCryptoProvider.load();
    final alice = await AccountKeys.fromMasterKey(
      SecretBytes(crypto.randomBytes(32)),
      crypto,
    );
    final bob = await AccountKeys.fromMasterKey(
      SecretBytes(crypto.randomBytes(32)),
      crypto,
    );
    final device = await DeviceKeys.generate(crypto);
    client = LocalPeer(
      role: pb.PeerRole.PEER_ROLE_CLIENT,
      staticKey: device.dh,
      certificate: await DeviceCertificates.issue(
        crypto,
        alice,
        device,
        issuedAt: DateTime.now(),
      ),
      software: 'cli test',
    );
    node = await makeNode(bob);
    impostor = await makeNode(bob);
  });

  final channels = <SecureChannel>[];
  tearDown(() {
    for (final c in channels) {
      c.destroy();
    }
    channels.clear();
  });

  /// Соединение с узлом [to]: на той стороне — рукопожатие узла.
  ByteConnection serve(_Node to) {
    final (mine, theirs) = memoryConnectionPair();
    unawaited(
      PeerHandshake.respond(
        crypto,
        theirs,
        local: to.local,
        policy: PeerPolicy.anyone(),
      ).then(channels.add, onError: (Object _) {}),
    );
    return mine;
  }

  /// Способ, который отвечает [answer] после [delay] и считает вызовы.
  final calls = <String>[];
  setUp(calls.clear);

  DirectDialer direct(
    Map<String, FutureOr<ByteConnection> Function()> endpoints,
  ) => (endpoint) async {
    calls.add('direct $endpoint');
    final answer = endpoints[endpoint];
    if (answer == null) throw const SocketException('отказ в соединении');
    return await answer();
  };

  NodeDialer way(String name, FutureOr<ByteConnection> Function() answer) =>
      (nodeId) async {
        calls.add(name);
        return await answer();
      };

  Never refuse() => throw const SocketException('недоступно');

  Future<ByteConnection> never() => Completer<ByteConnection>().future;

  ConnectionStrategy strategy({
    DirectDialer? directDialer,
    NodeDialer? udp,
    NodeDialer? relay,
    TrafficMeter? meter,
    Duration fallbackDelay = const Duration(milliseconds: 100),
    Duration relayDelay = const Duration(milliseconds: 200),
    Duration connectTimeout = const Duration(seconds: 10),
  }) => ConnectionStrategy(
    crypto: crypto,
    local: client,
    direct: directDialer ?? direct(const {}),
    udp: udp,
    relay: relay,
    meter: meter,
    directStagger: const Duration(milliseconds: 50),
    fallbackDelay: fallbackDelay,
    relayDelay: relayDelay,
    connectTimeout: connectTimeout,
  );

  NodeContact contact([List<String> endpoints = const ['192.0.2.1:7000']]) =>
      NodeContact(nodeId: node.nodeId, endpoints: endpoints);

  test('прямой TCP: узел проверен, способ в метриках и кеше', () async {
    final meter = TrafficMeter();
    final s = strategy(
      directDialer: direct({'192.0.2.1:7000': () => serve(node)}),
      udp: way('udp', () => serve(node)),
      relay: way('relay', () => serve(node)),
      meter: meter,
    );
    final c = await s.connect(contact());
    expect(c.method, _direct);
    expect(c.endpoint, '192.0.2.1:7000');
    expect(c.channel.peer.signKey, node.nodeId);
    expect(c.channel.peer.certificate, node.local.certificate);
    expect(calls, ['direct 192.0.2.1:7000']);
    expect(s.connected, {_direct: 1});
    expect(s.cachedMethod(node.nodeId), _direct);
    final report = meter.takeReport()!.traffic.single;
    expect(report.method, _direct);
    expect(report.connections, 1);
    expect(report.bytes.toInt(), greaterThan(0), reason: 'рукопожатие');
    c.channel.destroy();
  });

  test('TCP не прошёл — UDP; relay не начинается, если UDP успел', () async {
    final meter = TrafficMeter();
    final s = strategy(
      udp: way('udp', () => serve(node)),
      relay: way('relay', () => serve(node)),
      meter: meter,
      relayDelay: const Duration(seconds: 5),
    );
    final c = await s.connect(contact(['192.0.2.1:7000', '192.0.2.2:7000']));
    expect(c.method, _udp);
    expect(c.endpoint, isNull);
    expect(calls, ['direct 192.0.2.1:7000', 'direct 192.0.2.2:7000', 'udp']);
    expect(meter.takeReport()!.traffic.single.method, _udp);
    c.channel.destroy();
  });

  test('без адресов: сразу UDP, при отказе сведения — relay', () async {
    final s = strategy(
      udp: way('udp', () => throw const UdpRendezvousException('симметричный')),
      relay: way('relay', () => serve(node)),
    );
    final watch = Stopwatch()..start();
    final c = await s.connect(contact(const []));
    expect(c.method, _relay);
    expect(calls, ['udp', 'relay']);
    expect(
      watch.elapsed,
      lessThan(const Duration(milliseconds: 150)),
      reason: 'отказ UDP начинает relay, не дожидаясь задержки',
    );
    c.channel.destroy();
  });

  test('долгое сведение: relay начинается параллельно и побеждает', () async {
    final punch = Completer<ByteConnection>();
    final s = strategy(
      udp: way('udp', () => punch.future),
      relay: way('relay', () => serve(node)),
    );
    final c = await s.connect(contact(const []));
    expect(c.method, _relay);
    expect(calls, ['udp', 'relay']);
    // Сведение закончилось позже: его поток закрывается без рукопожатия.
    final (late, other) = memoryConnectionPair();
    punch.complete(late);
    final ended = Completer<void>();
    other.input.listen(null, onDone: ended.complete);
    await ended.future.timeout(const Duration(seconds: 5));
    expect(s.connected, {_relay: 1});
    c.channel.destroy();
  });

  test('зависший адрес TCP не держит следующий', () async {
    final s = strategy(
      directDialer: direct({
        '192.0.2.1:7000': never,
        '192.0.2.2:7000': () => serve(node),
      }),
    );
    final c = await s.connect(contact(['192.0.2.1:7000', '192.0.2.2:7000']));
    expect(c.endpoint, '192.0.2.2:7000');
    c.channel.destroy();
  });

  test('адрес с чужим ключом — неудача, побеждает следующий способ', () async {
    final s = strategy(
      directDialer: direct({'192.0.2.1:7000': () => serve(impostor)}),
      relay: way('relay', () => serve(node)),
    );
    final c = await s.connect(contact());
    expect(c.method, _relay);
    expect(c.channel.peer.signKey, node.nodeId);
    c.channel.destroy();
  });

  test('кеш: следующее подключение начинается с удачного способа', () async {
    var relayUp = true;
    final s = strategy(
      directDialer: direct({'192.0.2.1:7000': never}),
      relay: way('relay', () => relayUp ? serve(node) : refuse()),
    );
    final first = await s.connect(contact());
    expect(first.method, _relay);
    expect(s.cachedMethod(node.nodeId), _relay);
    first.channel.destroy();

    calls.clear();
    final second = await s.connect(contact());
    expect(second.method, _relay);
    expect(calls.first, 'relay', reason: 'способ из кеша — первым');
    expect(s.cacheHits, 1);
    second.channel.destroy();

    // Способ из кеша не удался — запись стёрта.
    relayUp = false;
    calls.clear();
    await expectLater(
      s.connect(contact()).timeout(const Duration(milliseconds: 400)),
      throwsA(isA<TimeoutException>()),
    );
    expect(s.cachedMethod(node.nodeId), isNull);
  });

  test('ни один способ не удался — PeerUnreachableException', () async {
    final s = strategy(
      udp: way('udp', refuse),
      relay: way(
        'relay',
        () => throw const RelayException(
          pb.ErrorCode.ERROR_CODE_NOT_FOUND,
          'узла нет на relay',
        ),
      ),
    );
    final error = await s
        .connect(contact())
        .then<Object>((c) => c, onError: (Object e) => e);
    expect(error, isA<PeerUnreachableException>());
    final e = error as PeerUnreachableException;
    expect(e.attempts.map((a) => a.method), ['direct', 'udp', 'relay']);
    expect(e.attempts.first.endpoint, '192.0.2.1:7000');
    expect(e.message, contains('узла нет на relay'));
    expect(s.connected, isEmpty);
  });

  test('нет ни адресов, ни других способов — отказ сразу', () async {
    await expectLater(
      strategy().connect(contact(const [])),
      throwsA(
        isA<PeerUnreachableException>().having(
          (e) => e.attempts,
          'attempts',
          isEmpty,
        ),
      ),
    );
  });

  test('общий предел времени', () async {
    final s = strategy(
      directDialer: direct({'192.0.2.1:7000': never}),
      connectTimeout: const Duration(milliseconds: 200),
    );
    await expectLater(
      s.connect(contact()),
      throwsA(
        isA<PeerUnreachableException>().having(
          (e) => e.attempts.single.method,
          'method',
          'all',
        ),
      ),
    );
  });

  test('настоящий TCP на loopback', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((socket) {
      unawaited(
        PeerHandshake.respond(
          crypto,
          SocketConnection(socket),
          local: node.local,
          policy: PeerPolicy.anyone(),
        ).then(channels.add, onError: (Object _) {}),
      );
    });
    final s = ConnectionStrategy(crypto: crypto, local: client);
    final c = await s.connect(
      NodeContact(nodeId: node.nodeId, endpoints: ['127.0.0.1:${server.port}']),
    );
    expect(c.method, _direct);
    c.channel.destroy();
    await expectLater(connectTcp('нет-порта'), throwsA(isA<SocketException>()));
  });
}
