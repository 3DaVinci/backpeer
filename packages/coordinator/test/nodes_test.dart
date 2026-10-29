// Реестр узлов: RegisterNode, Heartbeat, доступность, кандидаты для
// размещения (задачи 2.6.1, 2.6.2, начало 2.7.1), проверка достижимости
// (3.5.1). Нужен FS_TEST_POSTGRES.

import 'dart:async';
import 'dart:io';

import 'package:coordinator/coordinator.dart';
import 'package:core/core.dart';
import 'package:fixnum/fixnum.dart';
import 'package:postgres/postgres.dart';
import 'package:protocol/protocol.dart' as pb;
import 'package:test/test.dart';

import 'support/db_harness.dart';
import 'support/postgres.dart';

const pb.ErrorCode _badRequest = pb.ErrorCode.ERROR_CODE_BAD_REQUEST;
const pb.ErrorCode _unauthenticated = pb.ErrorCode.ERROR_CODE_UNAUTHENTICATED;

void main() {
  if (testPostgresUrl == null) {
    test('реестр узлов', () {}, skip: skipWithoutPostgres);
    return;
  }
  late DbHarness h;
  late AccountKeys owner;
  setUp(() async {
    h = await DbHarness.create();
    owner = await h.newAccount();
    await h.register(owner, await h.newKey(), login: 'owner');
  });
  tearDown(() => h.close());

  Future<List<Object?>> nodeRow(Ed25519KeyPair node) async {
    final rows = await h.db.run(
      (s) => s.execute(
        Sql.named('''
          SELECT account_id, capacity_bytes, used_bytes, endpoints, versions,
                 software, subnet, last_heartbeat_at
            FROM nodes WHERE node_id = @n:bytea'''),
        parameters: {'n': node.publicKey},
      ),
    );
    return rows.single;
  }

  NodeService service() => NodeService(
    h.db,
    CertificateChecks(h.crypto, clock: h.clock.call),
    clock: h.clock.call,
  );

  group('RegisterNode', () {
    test('регистрирует узел и обновляет сведения при повторе', () async {
      final node = await h.newKey();
      final response = await h.registerNode(owner, node);
      expect(response.coordinatorKeys, [h.signerKey.publicKey]);
      var row = await nodeRow(node);
      expect(row[0], owner.accountId);
      expect(row[1], 1 << 40);
      expect(row[3], ['203.0.113.10:7000']);
      expect(row[4], [1]);
      expect(row[5], 'node 0.2.0');
      expect(row[6], '203.0.113.0/24', reason: 'подсеть — по адресу запроса');
      expect(row[7], isNotNull, reason: 'регистрация — признак «в сети»');

      await h.registerNode(
        owner,
        node,
        ip: '198.51.100.7',
        endpoints: ['node.example.org:7000'],
      );
      row = await nodeRow(node);
      expect(row[3], ['node.example.org:7000']);
      expect(row[6], '198.51.100.0/24');
    });

    test('узел без действующего сертификата не регистрируется', () async {
      final node = await h.newKey();
      final stranger = await h.newAccount();

      // Владелец не зарегистрирован.
      await expectLater(
        () => h.registerNode(stranger, node),
        failsWith(_unauthenticated),
      );

      // Подпись не сходится.
      final cert = await h.nodeCert(owner, node);
      final broken = cert.deepCopy()..signature[0] ^= 1;
      await expectLater(
        () => h.registerNode(owner, node, certificate: broken),
        failsWith(_unauthenticated),
      );

      // Сертификат подписан не учётной записью из него.
      final forged = await SignedMessages.sign(
        h.crypto,
        stranger.accountSign,
        'node-cert',
        pb.NodeCertificate.fromBuffer(cert.body),
      );
      await expectLater(
        () => h.registerNode(owner, node, certificate: forged),
        failsWith(_unauthenticated),
      );

      // Сертификат другого узла.
      final other = await h.nodeCert(owner, await h.newKey());
      await expectLater(
        () => h.registerNode(owner, node, certificate: other),
        failsWith(_badRequest),
      );

      // Выпущен в будущем.
      final future = await h.nodeCert(
        owner,
        node,
        issuedAt: h.clock.now.add(const Duration(minutes: 10)),
      );
      await expectLater(
        () => h.registerNode(owner, node, certificate: future),
        failsWith(_badRequest),
      );

      // Без сертификата.
      await expectLater(
        () => h.registerNode(owner, node, certificate: pb.Signed()),
        failsWith(_badRequest),
      );

      // Heartbeat незарегистрированного узла.
      await expectLater(() => h.heartbeat(node), failsWith(_unauthenticated));
    });

    test('чужой узел не перехватывается, ключ другого вида — отказ', () async {
      final node = await h.newKey();
      await h.registerNode(owner, node);
      final other = await h.newAccount();
      final device = await h.newKey();
      await h.register(other, device, login: 'other');
      await expectLater(
        () => h.registerNode(other, node),
        failsWith(pb.ErrorCode.ERROR_CODE_ALREADY_EXISTS),
      );
      await expectLater(
        () => h.registerNode(other, device),
        failsWith(pb.ErrorCode.ERROR_CODE_PERMISSION_DENIED),
        reason: 'ключ устройства',
      );
    });

    test('версии, ёмкость, адреса', () async {
      final node = await h.newKey();
      await expectLater(
        () => h.registerNode(owner, node, versions: [2]),
        failsWith(pb.ErrorCode.ERROR_CODE_VERSION_UNSUPPORTED),
      );
      await expectLater(
        () => h.registerNode(owner, node, endpoints: ['203.0.113.10']),
        failsWith(_badRequest),
      );
      await expectLater(
        () => h.registerNode(owner, node, capacity: -1),
        failsWith(_badRequest),
      );
      // Без адресов — можно: узел за NAT (relay — этап 3).
      await h.registerNode(owner, node, endpoints: []);
    });

    test('предел узлов на учётную запись и минимум места', () async {
      await h.close();
      h = await DbHarness.create(
        config: const CoordinatorConfig(
          nodes: NodePolicy(minCapacityBytes: 1000, maxPerAccount: 2),
        ),
      );
      owner = await h.newAccount();
      await h.register(owner, await h.newKey(), login: 'owner');
      await expectLater(
        () async =>
            await h.registerNode(owner, await h.newKey(), capacity: 999),
        failsWith(_badRequest),
      );
      final first = await h.newKey();
      await h.registerNode(owner, first);
      await h.registerNode(owner, await h.newKey());
      await expectLater(
        () async => await h.registerNode(owner, await h.newKey()),
        failsWith(pb.ErrorCode.ERROR_CODE_QUOTA_EXCEEDED),
      );
      // Повторная регистрация того же узла в предел не упирается.
      await h.registerNode(owner, first);
    });

    test('удалённый узел не регистрируется и не шлёт heartbeat', () async {
      final node = await h.newKey();
      await h.registerNode(owner, node);
      await h.db.run(
        (s) => s.execute(
          Sql.named(
            'UPDATE nodes SET removed_at = now() WHERE node_id = @n:bytea',
          ),
          parameters: {'n': node.publicKey},
        ),
      );
      await expectLater(
        () => h.registerNode(owner, node),
        failsWith(_unauthenticated),
      );
      await expectLater(() => h.heartbeat(node), failsWith(_unauthenticated));
    });
  });

  group('Heartbeat', () {
    test('обновляет место и адрес, сообщает период', () async {
      final node = await h.newKey();
      await h.registerNode(owner, node);
      final response = await h.heartbeat(
        node,
        used: 5000,
        capacity: 1 << 41,
        ip: '192.0.2.200',
      );
      expect(response.nextHeartbeatMs, 300000);
      final row = await nodeRow(node);
      expect(row[1], 1 << 41);
      expect(row[2], 5000);
      expect(row[6], '192.0.2.0/24');
      // Занятое больше ёмкости — квоту уменьшили: координатор перенесёт
      // лишнее (4.4.2).
      await h.heartbeat(node, used: 2, capacity: 1);
      expect((await nodeRow(node))[2], 2);
      await expectLater(
        () => h.heartbeat(node, free: 2, capacity: 1),
        failsWith(_badRequest),
      );
    });

    test('свободное место узла ограничивает размещение', () async {
      final other = await h.newAccount();
      await h.register(other, await h.newKey(), login: 'other');
      final node = await h.newKey();
      await h.registerNode(other, node);
      Future<int?> free() async {
        final found = await service().candidates(
          fragmentSize: 1000,
          minAvailability: 0,
        );
        return found.isEmpty ? null : found.single.freeBytes;
      }

      await h.heartbeat(node, used: 1000);
      expect(await free(), (1 << 40) - 1000, reason: 'без free_bytes');
      // Диск почти полон: принимает ещё 5000 байт.
      await h.heartbeat(node, used: 1000, free: 5000);
      expect(await free(), 5000);
      // Выданное координатором, но ещё не принятое узлом, вычитается.
      await h.db.run(
        (s) => s.execute(
          Sql.named(
            'UPDATE nodes SET assigned_bytes = 3000 WHERE node_id = @n:bytea',
          ),
          parameters: {'n': node.publicKey},
        ),
      );
      expect(await free(), 3000);
      await h.heartbeat(node, used: 1000, free: 1500);
      expect(await free(), isNull, reason: 'фрагмент в 1000 байт не влезет');
    });

    test('узел, бывший в сети половину времени, — доступность 0,5', () async {
      final node = await h.newKey();
      await h.registerNode(owner, node);
      final registered = h.clock.now;
      // Двое суток: 12 часов в сети (heartbeat каждые 5 минут), 12 — нет.
      final end = registered.add(const Duration(days: 2));
      while (h.clock.now.isBefore(end)) {
        if ((h.clock.now.difference(registered).inHours ~/ 12).isEven) {
          await h.heartbeat(node);
        }
        h.clock.advance(const Duration(minutes: 5));
      }
      final a = await service().availability(node.publicKey);
      expect(a, closeTo(0.5, 0.02));
    });

    test('история старше 30 дней удаляется', () async {
      final node = await h.newKey();
      await h.registerNode(owner, node);
      for (var day = 0; day < 40; day++) {
        await h.heartbeat(node);
        h.clock.advance(const Duration(days: 1));
      }
      await h.heartbeat(node);
      final rows = await h.db.run(
        (s) => s.execute(
          Sql.named(
            'SELECT count(*) FROM node_uptime WHERE node_id = @n:bytea',
          ),
          parameters: {'n': node.publicKey},
        ),
      );
      expect(rows.single.single, lessThanOrEqualTo(Uptime.windowDays + 1));
    });
  });

  group('кандидаты для размещения', () {
    test('в сети, с местом и доступностью, не владелец сегмента', () async {
      final online = await h.newKey();
      final silent = await h.newKey();
      final full = await h.newKey();
      final mine = await h.newKey();
      final other = await h.newAccount();
      await h.register(other, await h.newKey(), login: 'other');
      await h.registerNode(other, online);
      await h.registerNode(other, silent, ip: '198.51.100.1');
      await h.registerNode(other, full, ip: '198.51.100.2');
      await h.registerNode(owner, mine, ip: '198.51.100.3');
      await h.heartbeat(full, used: 1 << 40);

      h.clock.advance(const Duration(minutes: 14));
      await h.heartbeat(online);
      await h.heartbeat(full, used: (1 << 40) - 100);
      await h.heartbeat(mine);
      h.clock.advance(const Duration(minutes: 2));

      final found = await service().candidates(
        fragmentSize: 1000,
        minAvailability: 0.6,
        exceptOwner: owner.accountId,
      );
      expect(found.map((c) => bytesToHex(c.nodeId)), [
        bytesToHex(online.publicKey),
      ], reason: 'silent молчит 16 минут, у full мало места, mine — свой');
      expect(found.single.subnet, '203.0.113.0/24');
      expect(found.single.availability, 1);
      expect(found.single.ownerId, other.accountId);

      final all = await service().candidates(
        fragmentSize: 1000,
        minAvailability: 0.6,
      );
      expect(all, hasLength(2), reason: 'без исключения владельца');
      expect(
        await service().candidates(fragmentSize: 1000, minAvailability: 1.1),
        isEmpty,
      );

      // Кэш: новые сведения не видны, пока он жив; выданное место
      // вычитается сразу.
      final cached = service();
      const cache = Duration(minutes: 1);
      final before = await cached.candidates(
        fragmentSize: 1000,
        minAvailability: 0.6,
        cacheFor: cache,
      );
      expect(before, hasLength(2));
      await h.heartbeat(mine, used: 1 << 40); // места больше нет
      expect(
        await cached.candidates(
          fragmentSize: 1000,
          minAvailability: 0.6,
          cacheFor: cache,
        ),
        hasLength(2),
        reason: 'из кэша',
      );
      cached.noteAssigned([online.publicKey], (1 << 40) - 500);
      final after = await cached.candidates(
        fragmentSize: 1000,
        minAvailability: 0.6,
        cacheFor: cache,
      );
      expect(after.map((c) => bytesToHex(c.nodeId)), [
        bytesToHex(mine.publicKey),
      ], reason: 'online исчерпан выдачей, mine — по старым сведениям');
      final fresh = await cached.candidates(
        fragmentSize: 1000,
        minAvailability: 0.6,
      );
      expect(fresh.map((c) => bytesToHex(c.nodeId)), [
        bytesToHex(online.publicKey),
      ], reason: 'без кэша — свежая выборка: mine заполнен');
    });
  });

  test('ListRevocations доступен зарегистрированному узлу', () async {
    final node = await h.newKey();
    await h.registerNode(owner, node);
    final response = await h.call(
      'ListRevocations',
      pb.ListRevocationsRequest(afterSequence: Int64.ZERO),
      pb.ListRevocationsResponse.fromBuffer,
      key: node,
    );
    expect(response.revocations, isEmpty);
  });

  group('CheckReachability (3.5.1)', () {
    late Ed25519KeyPair node;
    late X25519KeyPair nodeDh;
    late pb.Signed certificate;

    setUp(() async {
      node = await h.newKey();
      nodeDh = await h.crypto.x25519FromSecret(
        SecretBytes(h.crypto.randomBytes(32)),
      );
      certificate = await NodeCertificates.issue(
        h.crypto,
        owner,
        nodeId: node.publicKey,
        nodeDh: nodeDh.publicKey,
        issuedAt: h.clock.now,
      );
    });

    Future<pb.CheckReachabilityResponse> check(
      DbHarness harness,
      List<int> ports, {
      String ip = '192.168.1.5',
      Ed25519KeyPair? key,
    }) => harness.call(
      'CheckReachability',
      pb.CheckReachabilityRequest(ports: ports),
      pb.CheckReachabilityResponse.fromBuffer,
      key: key ?? node,
      ip: ip,
    );

    test('частный адрес — без проверки; поля запроса; незарегистрированный '
        'узел', () async {
      await h.registerNode(owner, node, certificate: certificate);
      final r = await check(h, [7340, 41000]);
      expect(r.observedAddress, '192.168.1.5');
      expect(
        [for (final x in r.results) (x.port, x.status)],
        [
          (7340, pb.ReachabilityStatus.REACHABILITY_STATUS_NOT_CHECKED),
          (41000, pb.ReachabilityStatus.REACHABILITY_STATUS_NOT_CHECKED),
        ],
      );
      for (final ports in [
        <int>[],
        [1, 2, 3, 4, 5],
        [7340, 7340],
        [0],
        [65536],
      ]) {
        await expectLater(
          () => check(h, ports),
          failsWith(_badRequest),
          reason: '$ports',
        );
      }
      await expectLater(
        () => check(h, [7340], key: owner.accountSign),
        throwsA(isA<RpcFailure>()),
        reason: 'ключ не узла',
      );
    });

    test('с частными адресами по настройке: отвечает узел — reachable, '
        'порт закрыт — refused, чужой ключ — wrong_peer', () async {
      final local = await DbHarness.create(
        config: const CoordinatorConfig(
          nodes: NodePolicy(
            minCapacityBytes: 0,
            checkPrivateAddresses: true,
            reachabilityTimeout: Duration(seconds: 2),
          ),
        ),
      );
      addTearDown(local.close);
      final localOwner = await local.newAccount();
      await local.register(localOwner, await local.newKey(), login: 'owner2');
      final cert = await NodeCertificates.issue(
        local.crypto,
        localOwner,
        nodeId: node.publicKey,
        nodeDh: nodeDh.publicKey,
        issuedAt: local.clock.now,
      );
      await local.registerNode(localOwner, node, certificate: cert);

      Future<ServerSocket> responder(X25519KeyPair key) async {
        final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(server.close);
        server.listen(
          (socket) => unawaited(
            PeerHandshake.respond(
              local.crypto,
              SocketConnection(socket),
              local: LocalPeer(
                role: pb.PeerRole.PEER_ROLE_NODE,
                staticKey: key,
                certificate: cert,
                software: 'node test',
              ),
              policy: PeerPolicy.anyone(),
            ).then((_) {}, onError: (Object _) {}),
          ),
        );
        return server;
      }

      final good = await responder(nodeDh);
      final other = await responder(
        await local.crypto.x25519FromSecret(
          SecretBytes(local.crypto.randomBytes(32)),
        ),
      );
      final closed = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final closedPort = closed.port;
      await closed.close();

      final r = await check(local, [
        good.port,
        closedPort,
        other.port,
      ], ip: '::ffff:127.0.0.1');
      expect(r.observedAddress, '127.0.0.1');
      expect(
        [for (final x in r.results) (x.port, x.status)],
        [
          (good.port, pb.ReachabilityStatus.REACHABILITY_STATUS_REACHABLE),
          (closedPort, pb.ReachabilityStatus.REACHABILITY_STATUS_REFUSED),
          (other.port, pb.ReachabilityStatus.REACHABILITY_STATUS_WRONG_PEER),
        ],
      );
    });
  });
}
