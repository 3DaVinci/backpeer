// Сведение узлов через координатор (задачи 3.7.2–3.7.4; protocol.md,
// раздел 4.11): подтверждения адресов сводника; клиент сводится с демоном
// узла через настоящий координатор, поверх потока UDP проходят
// рукопожатие Noise и операции с фрагментами; отказы `Rendezvous`.
// Сквозные тесты нужны FS_TEST_POSTGRES.

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:coordinator/coordinator.dart';
import 'package:core/core.dart';
import 'package:fixnum/fixnum.dart';
import 'package:node/node.dart';
import 'package:protocol/protocol.dart' as pb;
import 'package:test/test.dart';

import 'support/live.dart';
import 'support/postgres.dart';

void main() {
  group('подтверждения сводника', () {
    late CryptoProvider crypto;
    setUpAll(() async => crypto = await SodiumCryptoProvider.load());

    test('действует для своего адреса и порта, пока не истекло', () {
      var now = DateTime.utc(2026, 10, 27, 12);
      final tokens = RendezvousTokens(crypto, clock: () => now);
      final ip = InternetAddress('203.0.113.5');
      const life = Duration(minutes: 2);
      final t = tokens.issue(ip, 40000);
      expect(t, hasLength(20));
      expect(tokens.verify(t, ip, 40000, life), isTrue);
      expect(tokens.verify(t, ip, 40001, life), isFalse);
      expect(
        tokens.verify(t, InternetAddress('203.0.113.6'), 40000, life),
        isFalse,
      );
      expect(
        tokens.verify(Uint8List.fromList(t)..[10] ^= 1, ip, 40000, life),
        isFalse,
      );
      // Время выдачи тоже под MAC.
      expect(
        tokens.verify(Uint8List.fromList(t)..[3] ^= 1, ip, 40000, life),
        isFalse,
      );
      now = now.add(const Duration(minutes: 3));
      expect(tokens.verify(t, ip, 40000, life), isFalse);
      // Другой процесс координатора — другой ключ.
      expect(RendezvousTokens(crypto).verify(t, ip, 40000, life), isFalse);
    });
  });

  if (testPostgresUrl == null) {
    test('сведение через координатор', () {}, skip: skipWithoutPostgres);
    return;
  }

  group('сведение через координатор', () {
    late LiveCoordinator live;
    late Directory dir;
    late NodeDaemon daemon;
    late Uint8List nodeId;
    late DeviceKeys device;
    late pb.Signed deviceCertificate;
    late Ed25519KeyPair signerKey;
    late CryptoProvider crypto;

    setUp(() async {
      live = await LiveCoordinator.start();
      crypto = live.crypto;
      dir = Directory.systemTemp.createTempSync('fs-rendezvous-');
      final owner = await AccountKeys.fromMasterKey(
        SecretBytes(crypto.randomBytes(32)),
        crypto,
      );
      device = await DeviceKeys.generate(crypto);
      deviceCertificate = await DeviceCertificates.issue(
        crypto,
        owner,
        device,
        issuedAt: DateTime.now(),
      );
      final client = live.client();
      await client.registerAccount(
        pb.RegisterAccountRequest(
          deviceCertificate: deviceCertificate,
          login: 'udp-owner',
        ),
        accountKey: owner.accountSign,
      );
      client.close();
      await NodeIdentity.ensureKeys(dir, crypto);
      final identity = await NodeIdentity.load(dir, crypto);
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
      nodeId = identity.nodeId;
      identity.dispose();
      signerKey = await crypto.ed25519FromSeed(
        SecretBytes(Uint8List(32)..fillRange(0, 32, 0xC0)),
      );
      daemon = await NodeDaemon.start(
        NodeConfig.parse(
          '''
storage:
  quota_bytes: 200000000000
  free_reserve_bytes: 0
listen:
  port: 0
  port_mapping: off
coordinator:
  url: ${live.url}
  keys: [${bytesToHex(signerKey.publicKey)}]
log:
  file: "-"
  level: warning
''',
          const {},
          dataDir: dir.path,
        ),
        crypto: crypto,
        handleSignals: false,
      );
      final channels = live.server.channels;
      for (var i = 0; i < 200 && !channels.isConnected(nodeId); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(channels.isConnected(nodeId), isTrue);
    });

    tearDown(() async {
      await daemon.stop();
      await live.close();
      dir.deleteSync(recursive: true);
    });

    test('клиент сводится с узлом, по UDP — Noise и фрагменты', () async {
      final client = live.client(device: device);
      addTearDown(client.close);
      final info = await client.getRendezvousInfo();
      expect(info.servers, [
        for (final p in live.server.rendezvous!.ports) '127.0.0.1:$p',
      ]);
      final endpoint = await UdpEndpoint.bind();
      addTearDown(endpoint.close);
      final stream = await UdpConnector(
        client: client,
        endpoint: endpoint,
      ).connect(nodeId);
      final peer = PeerClient(
        await PeerHandshake.initiate(
          crypto,
          stream,
          local: LocalPeer(
            role: pb.PeerRole.PEER_ROLE_CLIENT,
            staticKey: device.dh,
            certificate: deviceCertificate,
            software: 'cli test',
          ),
          policy: PeerPolicy.node(nodeId),
        ),
      );
      await peer.ping();
      final random = Random(1);
      Uint8List bytes(int n) =>
          Uint8List.fromList(List<int>.generate(n, (_) => random.nextInt(256)));
      final fragment = encodeFragments(
        crypto,
        blob: bytes(2 << 20),
        segmentId: bytes(32),
        k: 1,
        n: 2,
      ).first;
      final id = fragment.header.fragmentId(crypto);
      Future<pb.Signed> ticket(pb.TicketOperation op, int n) =>
          SignedMessages.sign(
            crypto,
            signerKey,
            FragmentTickets.signingContext,
            pb.FragmentTicket(
              operation: op,
              nodeId: nodeId,
              deviceSign: device.sign.publicKey,
              fragmentId: id,
              fragmentSize: fragment.bytes.length,
              expiresAtUnixMs: Int64(
                DateTime.now()
                    .add(const Duration(minutes: 5))
                    .millisecondsSinceEpoch,
              ),
              ticketId: Uint8List(16)..[0] = n,
            ),
          );
      expect(
        await peer.putFragment(
          await ticket(pb.TicketOperation.TICKET_OPERATION_PUT, 1),
          fragment.bytes,
        ),
        id,
      );
      expect(
        await peer.readFragment(
          await ticket(pb.TicketOperation.TICKET_OPERATION_GET, 2),
        ),
        fragment.bytes,
      );
      await peer.close();
      final udp = daemon.status()['udp']! as Map<String, Object?>;
      expect(udp['rendezvous'], 1);
      expect(udp['punchesSucceeded'], 1);
      expect(udp['streamsAccepted'], 1);
      expect(udp['symmetricNat'], isFalse);
      expect(daemon.storage.fragmentCount, 1);
    });

    test('отказы Rendezvous', () async {
      final client = live.client(device: device);
      addTearDown(client.close);
      final servers = await resolveRendezvousServers(
        (await client.getRendezvousInfo()).servers,
      );
      final endpoint = await UdpEndpoint.bind();
      addTearDown(endpoint.close);
      final binding = await endpoint.discover(servers);
      final good = pb.UdpBinding(
        endpoint: binding.endpoint,
        token: binding.token,
      );
      Matcher fails(pb.ErrorCode code) => throwsA(
        isA<CoordinatorException>().having((e) => e.code, 'code', code),
      );
      // Чужой адрес с подтверждением своего — отказ.
      await expectLater(
        client.rendezvous(
          pb.RendezvousRequest(
            nodeId: nodeId,
            binding: pb.UdpBinding(
              endpoint: '127.0.0.1:${binding.port == 1 ? 2 : binding.port - 1}',
              token: binding.token,
            ),
          ),
        ),
        fails(pb.ErrorCode.ERROR_CODE_BAD_REQUEST),
      );
      await expectLater(
        client.rendezvous(
          pb.RendezvousRequest(nodeId: Uint8List(32), binding: good),
        ),
        fails(pb.ErrorCode.ERROR_CODE_NOT_FOUND),
      );
      await expectLater(
        client.rendezvous(
          pb.RendezvousRequest(nodeId: Uint8List(5), binding: good),
        ),
        fails(pb.ErrorCode.ERROR_CODE_BAD_REQUEST),
      );
      // Ключ учётной записи сведение не запрашивает.
      await expectLater(
        client.rendezvous(
          pb.RendezvousRequest(nodeId: nodeId, binding: good),
          key: await crypto.ed25519FromSeed(
            SecretBytes(crypto.randomBytes(32)),
          ),
        ),
        fails(pb.ErrorCode.ERROR_CODE_UNAUTHENTICATED),
      );
      // Узел без канала команд свести нельзя.
      await daemon.link!.channel!.stop();
      for (
        var i = 0;
        i < 100 && live.server.channels.isConnected(nodeId);
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      await expectLater(
        client.rendezvous(pb.RendezvousRequest(nodeId: nodeId, binding: good)),
        fails(pb.ErrorCode.ERROR_CODE_NOT_FOUND),
      );
    });
  });
}
