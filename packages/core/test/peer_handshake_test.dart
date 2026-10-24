// Рукопожатие с Hello и проверка собеседника (задача 3.3.2, protocol.md,
// раздел 3.2): подмена ключа, чужой сертификат, не тот узел, отозванное
// устройство, нет общей версии, недопустимая роль.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:fixnum/fixnum.dart';
import 'package:protocol/protocol.dart' as pb;
import 'package:test/test.dart';

final class _Revoked implements RevokedDevices {
  new(this.keys);

  final List<Uint8List> keys;

  @override
  bool isRevoked(Uint8List deviceSign) =>
      keys.any((k) => constantTimeEquals(k, deviceSign));
}

void main() {
  late CryptoProvider crypto;
  late AccountKeys alice;
  late AccountKeys bob;
  late DeviceKeys device;
  late pb.Signed deviceCert;
  late Ed25519KeyPair nodeSign;
  late X25519KeyPair nodeDh;
  late pb.Signed nodeCert;
  final now = DateTime.utc(2026, 10, 24);

  Future<AccountKeys> account() =>
      AccountKeys.fromMasterKey(SecretBytes(crypto.randomBytes(32)), crypto);
  Future<X25519KeyPair> dhKey() =>
      crypto.x25519FromSecret(SecretBytes(crypto.randomBytes(32)));

  setUpAll(() async {
    crypto = await SodiumCryptoProvider.load();
    alice = await account();
    bob = await account();
    device = await DeviceKeys.generate(crypto);
    deviceCert = await DeviceCertificates.issue(
      crypto,
      alice,
      device,
      issuedAt: now,
    );
    nodeSign = await crypto.ed25519FromSeed(
      SecretBytes(crypto.randomBytes(32)),
    );
    nodeDh = await dhKey();
    nodeCert = await NodeCertificates.issue(
      crypto,
      bob,
      nodeId: nodeSign.publicKey,
      nodeDh: nodeDh.publicKey,
      issuedAt: now,
    );
  });

  LocalPeer client({List<int>? versions, pb.Signed? certificate}) => LocalPeer(
    role: pb.PeerRole.PEER_ROLE_CLIENT,
    staticKey: device.dh,
    certificate: certificate ?? deviceCert,
    software: 'cli test',
    versions: versions ?? supportedProtocolVersions,
  );

  LocalPeer node({
    List<int>? versions,
    pb.Signed? certificate,
    X25519KeyPair? key,
  }) => LocalPeer(
    role: pb.PeerRole.PEER_ROLE_NODE,
    staticKey: key ?? nodeDh,
    certificate: certificate ?? nodeCert,
    software: 'node test',
    versions: versions ?? supportedProtocolVersions,
  );

  /// Клиент подключается к узлу; результаты обеих сторон (канал или
  /// ошибка).
  Future<(Object, Object)> connect({
    LocalPeer? clientPeer,
    LocalPeer? nodePeer,
    PeerPolicy? clientPolicy,
    PeerPolicy? nodePolicy,
  }) async {
    final (a, b) = memoryConnectionPair();
    Future<Object> settle(Future<SecureChannel> f) =>
        f.then<Object>((c) => c, onError: (Object e) => e);
    final results = await Future.wait([
      settle(
        PeerHandshake.initiate(
          crypto,
          a,
          local: clientPeer ?? client(),
          policy: clientPolicy ?? PeerPolicy.node(nodeSign.publicKey),
        ),
      ),
      settle(
        PeerHandshake.respond(
          crypto,
          b,
          local: nodePeer ?? node(),
          policy: nodePolicy ?? PeerPolicy.anyone(),
        ),
      ),
    ]);
    return (results[0], results[1]);
  }

  Matcher rejected(PeerRejection reason) =>
      isA<PeerRejectedException>().having((e) => e.reason, 'reason', reason);

  /// Сторона, отказавшая собеседнику, закрывает соединение: у другой
  /// стороны рукопожатие обрывается или канал сразу закрывается.
  Future<void> expectClosed(Object result) async {
    if (result is SecureChannel) {
      expect(await result.messages.toList(), isEmpty);
    } else {
      expect(result, rejected(PeerRejection.handshake));
    }
  }

  test('клиент и узел узнают друг друга и обмениваются сообщениями', () async {
    final (c, n) = await connect();
    final clientChannel = c as SecureChannel;
    final nodeChannel = n as SecureChannel;
    expect(clientChannel.peer.isNode, isTrue);
    expect(clientChannel.peer.signKey, nodeSign.publicKey);
    expect(clientChannel.peer.accountId, bob.accountId);
    expect(clientChannel.peer.software, 'node test');
    expect(clientChannel.peer.version, 1);
    expect(nodeChannel.peer.isClient, isTrue);
    expect(nodeChannel.peer.signKey, device.sign.publicKey);
    expect(nodeChannel.peer.accountId, alice.accountId);
    expect(nodeChannel.peer.noiseKey, device.dh.publicKey);
    expect(clientChannel.sessionId, nodeChannel.sessionId);

    final nodeMessages = StreamIterator(nodeChannel.messages);
    final clientMessages = StreamIterator(clientChannel.messages);
    await clientChannel.send(
      pb.PeerMessage(
        requestId: Int64(1),
        ping: pb.Ping(nonce: Int64(42)),
      ),
    );
    // Большое сообщение — через много транспортных кадров.
    final big = Uint8List(NoiseFrames.maxAppMessage - 64);
    await clientChannel.send(
      pb.PeerMessage(
        requestId: Int64(2),
        fragmentData: pb.FragmentData(data: big, last: true),
      ),
    );
    expect(await nodeMessages.moveNext(), isTrue);
    expect(nodeMessages.current.ping.nonce, Int64(42));
    expect(await nodeMessages.moveNext(), isTrue);
    expect(nodeMessages.current.fragmentData.data, big);
    await nodeChannel.send(
      pb.PeerMessage(
        requestId: Int64(1),
        pong: pb.Pong(nonce: Int64(42)),
      ),
    );
    expect(await clientMessages.moveNext(), isTrue);
    expect(clientMessages.current.pong.nonce, Int64(42));

    await clientChannel.close();
    expect(await nodeMessages.moveNext(), isFalse);
    expect(nodeChannel.isClosed, isTrue);
  });

  test('по TCP: рукопожатие и передача с обратным давлением', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    final accepted = server.first.then(
      (socket) => PeerHandshake.respond(
        crypto,
        SocketConnection(socket),
        local: node(),
        policy: PeerPolicy.anyone(),
      ),
    );
    final socket = await Socket.connect(server.address, server.port);
    final clientChannel = await PeerHandshake.initiate(
      crypto,
      SocketConnection(socket),
      local: client(),
      policy: PeerPolicy.node(nodeSign.publicKey),
    );
    final nodeChannel = await accepted;
    final data = Uint8List(61440);
    const count = 400; // 24 МиБ — больше буферов сокета
    final sent = () async {
      for (var i = 0; i < count; i++) {
        await clientChannel.send(
          pb.PeerMessage(
            requestId: Int64(i),
            fragmentData: pb.FragmentData(data: data, last: i == count - 1),
          ),
        );
      }
      await clientChannel.close();
    }();
    var received = 0;
    await for (final m in nodeChannel.messages) {
      expect(m.requestId, Int64(received));
      expect(m.fragmentData.data.length, data.length);
      received++;
    }
    await sent;
    expect(received, count);
  });

  test('подмена ключа: ключ Noise узла не из его сертификата', () async {
    final (c, n) = await connect(nodePeer: node(key: await dhKey()));
    expect(c, rejected(PeerRejection.keyMismatch));
    await expectClosed(n);
  });

  test('подмена ключа: клиент с чужим ключом Noise', () async {
    final other = await DeviceKeys.generate(crypto);
    final (c, n) = await connect(
      clientPeer: LocalPeer(
        role: pb.PeerRole.PEER_ROLE_CLIENT,
        staticKey: other.dh,
        certificate: deviceCert,
      ),
    );
    expect(n, rejected(PeerRejection.keyMismatch));
    await expectClosed(c);
  });

  test('чужой сертификат: подписан не учётной записью из него', () async {
    final forged = await SignedMessages.sign(
      crypto,
      alice.accountSign,
      NodeCertificates.signingContext,
      pb.NodeCertificate(
        accountId: bob.accountId,
        nodeId: nodeSign.publicKey,
        nodeDh: nodeDh.publicKey,
        issuedAtUnixMs: Int64(now.millisecondsSinceEpoch),
      ),
    );
    final (c, _) = await connect(nodePeer: node(certificate: forged));
    expect(c, rejected(PeerRejection.certificate));
  });

  test('чужой сертификат: испорчена подпись или контекст', () async {
    final tampered = deviceCert.deepCopy()
      ..signature = (Uint8List.fromList(deviceCert.signature)..[0] ^= 1);
    final (_, n1) = await connect(clientPeer: client(certificate: tampered));
    expect(n1, rejected(PeerRejection.certificate));

    // Сертификат устройства, выданный как сертификат узла.
    final (c2, _) = await connect(nodePeer: node(certificate: deviceCert));
    expect(c2, rejected(PeerRejection.certificate));
  });

  test('сертификат другого узла', () async {
    final otherNode = await crypto.ed25519FromSeed(
      SecretBytes(crypto.randomBytes(32)),
    );
    final (c, n) = await connect(
      clientPolicy: PeerPolicy.node(otherNode.publicKey),
    );
    expect(c, rejected(PeerRejection.unexpectedNode));
    await expectClosed(n);
  });

  test('отозванное устройство', () async {
    final (c, n) = await connect(
      nodePolicy: PeerPolicy.anyone(
        revoked: _Revoked([Uint8List(32), device.sign.publicKey]),
      ),
    );
    expect(n, rejected(PeerRejection.revoked));
    await expectClosed(c);

    // Отзыв другого устройства не мешает.
    final (c2, n2) = await connect(
      nodePolicy: PeerPolicy.anyone(revoked: _Revoked([Uint8List(32)])),
    );
    expect(c2, isA<SecureChannel>());
    expect(n2, isA<SecureChannel>());
    (c2 as SecureChannel).destroy();
  });

  test('нет общей версии: отказ у обеих сторон', () async {
    final (c, n) = await connect(clientPeer: client(versions: [2, 3]));
    expect(c, rejected(PeerRejection.versionUnsupported));
    expect(n, rejected(PeerRejection.versionUnsupported));

    final (c2, n2) = await connect(
      clientPeer: client(versions: [1, 2]),
      nodePeer: node(versions: [1]),
    );
    expect((c2 as SecureChannel).peer.version, 1);
    expect((n2 as SecureChannel).peer.version, 1);
    c2.destroy();
  });

  test('выбирается наибольшая общая версия', () {
    expect(PeerVerifier.selectVersion([1, 2, 3], [5, 2, 1]), 2);
    expect(PeerVerifier.selectVersion([1], [2]), isNull);
    expect(PeerVerifier.selectVersion([1], []), isNull);
  });

  test('нет общей версии: узел отвечает VERSION_UNSUPPORTED', () async {
    final (a, b) = memoryConnectionPair();
    final nodeResult = PeerHandshake.respond(
      crypto,
      b,
      local: node(versions: [2]),
      policy: PeerPolicy.anyone(),
    );
    // Клиент вручную: рукопожатие Noise без своей проверки версий.
    final reader = NoiseFrameReader(a.input);
    final hs = await NoiseHandshake.start(
      crypto,
      initiator: true,
      staticKey: device.dh,
    );
    a.add(NoiseFrames.frame(await hs.writeMessage(Uint8List(0))));
    final hello = pb.Hello.fromBuffer(
      await hs.readMessage((await reader.next())!),
    );
    expect(hello.versions, [2]);
    a.add(
      NoiseFrames.frame(
        await hs.writeMessage(client().hello().writeToBuffer()),
      ),
    );
    final keys = hs.finish();
    await expectLater(
      nodeResult,
      throwsA(rejected(PeerRejection.versionUnsupported)),
    );
    final decoder = ChannelDecoder(keys.receive);
    final frame = await reader.next();
    final reply = pb.PeerMessage.fromBuffer(decoder.add(frame!).single);
    expect(reply.error.code, pb.ErrorCode.ERROR_CODE_VERSION_UNSUPPORTED);
    expect(await reader.next(), isNull);
  });

  test('недопустимая роль', () async {
    // Клиент ждёт узел, а отвечает клиент другого устройства.
    final other = await DeviceKeys.generate(crypto);
    final otherCert = await DeviceCertificates.issue(
      crypto,
      bob,
      other,
      issuedAt: now,
    );
    final (c, _) = await connect(
      nodePeer: LocalPeer(
        role: pb.PeerRole.PEER_ROLE_CLIENT,
        staticKey: other.dh,
        certificate: otherCert,
      ),
    );
    expect(c, rejected(PeerRejection.role));

    // Узел, принимающий только клиентов, не пускает другой узел.
    final (_, n) = await connect(
      clientPeer: node(),
      nodePolicy: PeerPolicy(roles: {pb.PeerRole.PEER_ROLE_CLIENT}),
    );
    expect(n, rejected(PeerRejection.role));
  });

  test('непустая нагрузка первого сообщения', () async {
    final (a, b) = memoryConnectionPair();
    final nodeResult = PeerHandshake.respond(
      crypto,
      b,
      local: node(),
      policy: PeerPolicy.anyone(),
    );
    final hs = await NoiseHandshake.start(
      crypto,
      initiator: true,
      staticKey: device.dh,
    );
    a.add(NoiseFrames.frame(await hs.writeMessage(Uint8List(1))));
    await expectLater(nodeResult, throwsA(rejected(PeerRejection.handshake)));
  });

  test('Hello не разбирается', () async {
    final (a, b) = memoryConnectionPair();
    final nodeResult = PeerHandshake.respond(
      crypto,
      b,
      local: node(),
      policy: PeerPolicy.anyone(),
    );
    final reader = NoiseFrameReader(a.input);
    final hs = await NoiseHandshake.start(
      crypto,
      initiator: true,
      staticKey: device.dh,
    );
    a.add(NoiseFrames.frame(await hs.writeMessage(Uint8List(0))));
    await hs.readMessage((await reader.next())!);
    a.add(NoiseFrames.frame(await hs.writeMessage(Uint8List.fromList([0xFF]))));
    await expectLater(nodeResult, throwsA(rejected(PeerRejection.hello)));
  });

  test('собеседник молчит: истекает время рукопожатия', () async {
    final (a, _) = memoryConnectionPair();
    await expectLater(
      PeerHandshake.initiate(
        crypto,
        a,
        local: client(),
        policy: PeerPolicy.node(nodeSign.publicKey),
        timeout: const Duration(milliseconds: 100),
      ),
      throwsA(rejected(PeerRejection.timeout)),
    );
  });

  test('соединение закрыто посреди рукопожатия', () async {
    final (a, b) = memoryConnectionPair();
    final result = PeerHandshake.respond(
      crypto,
      b,
      local: node(),
      policy: PeerPolicy.anyone(),
    );
    a.add(Uint8List.fromList([0, 32, 1, 2, 3]));
    await a.close();
    await expectLater(result, throwsA(rejected(PeerRejection.handshake)));
  });

  test('испорченный кадр после рукопожатия закрывает канал', () async {
    final (a, b) = memoryConnectionPair();
    final results = await Future.wait([
      PeerHandshake.initiate(
        crypto,
        a,
        local: client(),
        policy: PeerPolicy.node(nodeSign.publicKey),
      ),
      PeerHandshake.respond(
        crypto,
        b,
        local: node(),
        policy: PeerPolicy.anyone(),
      ),
    ]);
    final nodeChannel = results[1];
    // Мимо шифра: кадр с мусором вместо шифротекста.
    a.add(NoiseFrames.frame(Uint8List(40)));
    await expectLater(
      nodeChannel.messages.toList(),
      throwsA(isA<IntegrityException>()),
    );
    expect(nodeChannel.isClosed, isTrue);
    results[0].destroy();
  });
}
