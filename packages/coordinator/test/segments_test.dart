// Размещение сегментов, талоны, подтверждение, поиск и удаление (задачи
// 2.7.1–2.7.4; protocol.md, разделы 5, 5.2). Нужен FS_TEST_POSTGRES.

import 'dart:typed_data';

import 'package:coordinator/coordinator.dart';
import 'package:core/core.dart';
import 'package:postgres/postgres.dart';
import 'package:protocol/protocol.dart' as pb;
import 'package:test/test.dart';

import 'support/db_harness.dart';
import 'support/postgres.dart';

const pb.ErrorCode _badRequest = pb.ErrorCode.ERROR_CODE_BAD_REQUEST;
const pb.ErrorCode _notFound = pb.ErrorCode.ERROR_CODE_NOT_FOUND;
const pb.ErrorCode _unavailable = pb.ErrorCode.ERROR_CODE_UNAVAILABLE;

const _size = 100000;

void main() {
  if (testPostgresUrl == null) {
    test('сегменты', () {}, skip: skipWithoutPostgres);
    return;
  }
  late DbHarness h;
  late AccountKeys account;
  late Ed25519KeyPair device;

  /// Узлы-хранители: у каждого свой владелец и своя подсеть.
  final nodes = <Ed25519KeyPair>[];

  Future<void> start({
    CoordinatorConfig config = DbHarness.testConfig,
    bool withSigner = true,
    int nodeCount = 24,
    int capacity = 1 << 40,
  }) async {
    h = await DbHarness.create(config: config, withSigner: withSigner);
    account = await h.newAccount();
    device = await h.newKey();
    await h.register(account, device, login: 'client');
    nodes.clear();
    for (var i = 0; i < nodeCount; i++) {
      final owner = await h.newAccount();
      await h.register(owner, await h.newKey(), login: 'keeper$i');
      final node = await h.newKey();
      await h.registerNode(
        owner,
        node,
        ip: '198.51.$i.10',
        capacity: capacity,
        endpoints: ['198.51.$i.10:7000'],
      );
      nodes.add(node);
    }
  }

  tearDown(() => h.close());

  Uint8List id(int tag, [int i = 0]) => Uint8List(32)
    ..[0] = tag
    ..[1] = i;

  pb.AllocateSegmentRequest allocation(
    Uint8List segmentId, {
    int k = 10,
    int n = 20,
    int t = 16,
    int size = _size,
  }) => pb.AllocateSegmentRequest(
    segmentId: segmentId,
    k: k,
    n: n,
    repairThreshold: t,
    fragmentSize: size,
    fragmentIds: [for (var i = 0; i < n; i++) id(0xF0, i)],
    bodyRoots: [for (var i = 0; i < n; i++) id(0xB0, i)],
  );

  Future<pb.AllocateSegmentResponse> allocate(
    pb.AllocateSegmentRequest r, {
    Ed25519KeyPair? key,
  }) => h.call(
    'AllocateSegment',
    r,
    pb.AllocateSegmentResponse.fromBuffer,
    key: key ?? device,
  );

  Future<void> commit(Uint8List segmentId, Iterable<int> indexes) => h.call(
    'CommitSegment',
    pb.CommitSegmentRequest(
      segmentId: segmentId,
      storedIndexes: indexes.toList(),
    ),
    pb.CommitSegmentResponse.fromBuffer,
    key: device,
  );

  Future<pb.LocateSegmentResponse> locate(Uint8List segmentId) => h.call(
    'LocateSegment',
    pb.LocateSegmentRequest(segmentId: segmentId),
    pb.LocateSegmentResponse.fromBuffer,
    key: device,
  );

  Future<pb.DeleteSegmentResponse> delete(Uint8List segmentId) => h.call(
    'DeleteSegment',
    pb.DeleteSegmentRequest(segmentId: segmentId),
    pb.DeleteSegmentResponse.fromBuffer,
    key: device,
  );

  Future<int> accountBytes() async {
    final rows = await h.db.run(
      (s) => s.execute(
        Sql.named(
          'SELECT fragment_bytes FROM accounts WHERE account_id = @a:bytea',
        ),
        parameters: {'a': account.accountId},
      ),
    );
    return rows.single.single! as int;
  }

  Future<int> assignedTotal() async {
    final rows = await h.db.run(
      (s) =>
          s.execute('SELECT coalesce(sum(assigned_bytes), 0)::int8 FROM nodes'),
    );
    return rows.single.single! as int;
  }

  Future<int> segmentState(Uint8List segmentId) async {
    final rows = await h.db.run(
      (s) => s.execute(
        Sql.named('SELECT state FROM segments WHERE segment_id = @g:bytea'),
        parameters: {'g': segmentId},
      ),
    );
    return rows.single.single! as int;
  }

  /// Узел-заглушка: проверяет талон так, как это сделает узел (protocol.md,
  /// раздел 5) — по ключу подписанта, своему node_id и устройству.
  Future<pb.FragmentTicket> nodeAccepts(
    pb.Placement p,
    pb.TicketOperation op, {
    required List<int> fragmentId,
  }) => FragmentTickets.authorize(
    h.crypto,
    p.ticket,
    CoordinatorKeySet([h.signerKey.publicKey]),
    now: h.clock.now,
    operation: op,
    nodeId: p.node.nodeId,
    deviceSign: device.publicKey,
    fragmentId: fragmentId,
    fragmentSize: _size,
  );

  group('AllocateSegment', () {
    setUp(start);

    test('n узлов с разными владельцами и подсетями, талоны PUT', () async {
      final response = await allocate(allocation(id(1)));
      expect(response.placements, hasLength(20));
      expect(response.placements.map((p) => p.index), [
        for (var i = 0; i < 20; i++) i,
      ]);
      final nodeIds = {
        for (final p in response.placements) bytesToHex(p.node.nodeId),
      };
      expect(nodeIds, hasLength(20));
      final ticketIds = <String>{};
      for (final p in response.placements) {
        expect(p.node.endpoints.single, endsWith(':7000'));
        expect(p.node.needsRelay, isFalse);
        final ticket = await nodeAccepts(
          p,
          pb.TicketOperation.TICKET_OPERATION_PUT,
          fragmentId: id(0xF0, p.index),
        );
        ticketIds.add(bytesToHex(ticket.ticketId));
        expect(
          ticket.expiresAtUnixMs.toInt(),
          h.clock.now
              .add(const PlacementPolicy().ticketLifetime)
              .millisecondsSinceEpoch,
        );
      }
      expect(ticketIds, hasLength(20), reason: 'ticket_id уникальны');
      // Чужой узел или устройство талон не примут.
      await expectLater(
        FragmentTickets.authorize(
          h.crypto,
          response.placements[0].ticket,
          CoordinatorKeySet([h.signerKey.publicKey]),
          now: h.clock.now,
          operation: pb.TicketOperation.TICKET_OPERATION_PUT,
          nodeId: response.placements[1].node.nodeId,
          deviceSign: device.publicKey,
          fragmentId: id(0xF0),
        ),
        throwsA(isA<TicketRejectedException>()),
      );
      expect(await accountBytes(), 20 * _size);
      expect(await assignedTotal(), 20 * _size);
      expect(await segmentState(id(1)), SegmentState.allocated.index);
    });

    test('узлы клиента не получают его фрагменты', () async {
      final own = await h.newKey();
      await h.registerNode(account, own, ip: '192.0.2.77');
      for (var s = 0; s < 10; s++) {
        final response = await allocate(allocation(id(2, s)));
        expect(
          response.placements.map((p) => bytesToHex(p.node.nodeId)),
          isNot(contains(bytesToHex(own.publicKey))),
        );
      }
    });

    test('подходящих узлов меньше n — UNAVAILABLE', () async {
      await expectLater(
        () => allocate(allocation(id(3), k: 20, n: 25, t: 22)),
        failsWith(_unavailable),
      );
    });

    test('поля запроса', () async {
      for (final bad in [
        allocation(id(4), k: 0),
        allocation(id(4), k: 20),
        allocation(id(4), t: 9),
        allocation(id(4), t: 20),
        allocation(id(4), size: FragmentTickets.minFragmentSize - 1),
        allocation(id(4), size: FragmentTickets.maxFragmentSize + 1),
        allocation(id(4))..fragmentIds.removeLast(),
        allocation(id(4))..bodyRoots[3] = [1, 2],
        allocation(Uint8List(31)),
      ]) {
        await expectLater(() => allocate(bad), failsWith(_badRequest));
      }
    });

    test('повторное размещение неподтверждённого сегмента', () async {
      await allocate(allocation(id(5)));
      await allocate(allocation(id(5)));
      expect(await accountBytes(), 20 * _size, reason: 'прежнее освобождено');
      expect(await assignedTotal(), 20 * _size);
      await commit(id(5), [for (var i = 0; i < 20; i++) i]);
      await expectLater(
        () => allocate(allocation(id(5))),
        failsWith(pb.ErrorCode.ERROR_CODE_ALREADY_EXISTS),
      );
    });

    test('выданное место уменьшает свободное место узла', () async {
      await h.close();
      // 21 узел на 3 фрагмента каждый: седьмой сегмент уже не помещается.
      await start(nodeCount: 21, capacity: 3 * _size);
      for (var s = 0; s < 3; s++) {
        await allocate(allocation(id(6, s)));
      }
      await expectLater(() async {
        for (var s = 3; s < 10; s++) {
          await allocate(allocation(id(6, s)));
        }
      }, failsWith(_unavailable));
    });
  });

  group('испытательный срок (С-6)', () {
    test('узлов на испытательном сроке не больше доли сегмента', () async {
      await start(
        // Испытательный срок по умолчанию: 72 часа, доля 0,25. Без кэша
        // кандидатов: тест меняет узлы в базе и сразу размещает.
        config: const CoordinatorConfig(
          nodes: NodePolicy(minCapacityBytes: 0),
          placement: PlacementPolicy(candidatesCache: Duration.zero),
        ),
      );
      // Все узлы только что зарегистрированы.
      await expectLater(
        () => allocate(allocation(id(7))),
        failsWith(_unavailable),
      );
      // 15 узлов «старые», 9 — на испытательном сроке.
      for (final node in nodes.take(15)) {
        await h.db.run(
          (s) => s.execute(
            Sql.named('''
              UPDATE nodes SET registered_at = registered_at - interval '4 days'
                WHERE node_id = @n:bytea'''),
            parameters: {'n': node.publicKey},
          ),
        );
      }
      final old = {for (final n in nodes.take(15)) bytesToHex(n.publicKey)};
      for (var s = 0; s < 5; s++) {
        final response = await allocate(allocation(id(7, s)));
        final fresh = response.placements.where(
          (p) => !old.contains(bytesToHex(p.node.nodeId)),
        );
        expect(fresh.length, 5, reason: 'не больше 20 × 0,25 по умолчанию');
      }
    });
  });

  group('CommitSegment и LocateSegment', () {
    setUp(start);

    test('все фрагменты — сохранён, талоны GET на все', () async {
      await allocate(allocation(id(8)));
      await expectLater(() => locate(id(8)), failsWith(_notFound));
      await commit(id(8), [for (var i = 0; i < 20; i++) i]);
      expect(await segmentState(id(8)), SegmentState.stored.index);
      final located = await locate(id(8));
      expect(located.placements, hasLength(20));
      for (final p in located.placements) {
        await nodeAccepts(
          p,
          pb.TicketOperation.TICKET_OPERATION_GET,
          fragmentId: id(0xF0, p.index),
        );
      }
    });

    test(
      't + 1 фрагментов — сохранён, место незагруженных освобождено',
      () async {
        await allocate(allocation(id(9)));
        await commit(id(9), [for (var i = 0; i < 17; i++) i]);
        expect(await segmentState(id(9)), SegmentState.stored.index);
        expect(await accountBytes(), 17 * _size);
        expect(await assignedTotal(), 17 * _size);
        final located = await locate(id(9));
        expect(located.placements.map((p) => p.index).toSet(), {
          for (var i = 0; i < 17; i++) i,
        });
        // Догруженный позже фрагмент снова занимает место.
        await commit(id(9), [17]);
        expect(await accountBytes(), 18 * _size);
        expect((await locate(id(9))).placements, hasLength(18));
      },
    );

    test('не больше t фрагментов — помечен для ремонта', () async {
      await allocate(allocation(id(10)));
      await commit(id(10), [for (var i = 0; i < 12; i++) i]);
      expect(await segmentState(id(10)), SegmentState.needsRepair.index);
      expect((await locate(id(10))).placements, hasLength(12));
    });

    test('меньше k фрагментов, неверные номера, чужой сегмент', () async {
      await allocate(allocation(id(11)));
      await expectLater(
        () => commit(id(11), [for (var i = 0; i < 9; i++) i]),
        failsWith(_badRequest),
      );
      await expectLater(() => commit(id(11), [20]), failsWith(_badRequest));
      await expectLater(() => commit(id(11), [1, 1]), failsWith(_badRequest));
      await expectLater(() => commit(id(12), [1]), failsWith(_notFound));
      expect(await segmentState(id(11)), SegmentState.allocated.index);

      final other = await h.newAccount();
      final otherDevice = await h.newKey();
      await h.register(other, otherDevice, login: 'other');
      await commit(id(11), [for (var i = 0; i < 20; i++) i]);
      await expectLater(
        () => h.call(
          'LocateSegment',
          pb.LocateSegmentRequest(segmentId: id(11)),
          pb.LocateSegmentResponse.fromBuffer,
          key: otherDevice,
        ),
        failsWith(_notFound),
      );
    });

    test('удалённый узел не попадает в LocateSegment', () async {
      final response = await allocate(allocation(id(13)));
      await commit(id(13), [for (var i = 0; i < 20; i++) i]);
      await h.db.run(
        (s) => s.execute(
          Sql.named(
            'UPDATE nodes SET removed_at = now() WHERE node_id = @n:bytea',
          ),
          parameters: {'n': response.placements[4].node.nodeId},
        ),
      );
      final located = await locate(id(13));
      expect(located.placements.map((p) => p.index), isNot(contains(4)));
      expect(located.placements, hasLength(19));
    });

    test('ReportDamagedFragments: повреждённый фрагмент не выдаётся в '
        'LocateSegment', () async {
      final response = await allocate(allocation(id(18)));
      await commit(id(18), [for (var i = 0; i < 20; i++) i]);
      final node = nodes.firstWhere(
        (n) =>
            constantTimeEquals(n.publicKey, response.placements[3].node.nodeId),
      );
      Future<pb.ReportDamagedFragmentsResponse> report(
        List<List<int>> ids, {
        Ed25519KeyPair? key,
      }) => h.call(
        'ReportDamagedFragments',
        pb.ReportDamagedFragmentsRequest(fragmentIds: ids),
        pb.ReportDamagedFragmentsResponse.fromBuffer,
        key: key ?? node,
      );

      // Свой фрагмент, чужой фрагмент (другого узла) и неизвестный.
      final result = await report([id(0xF0, 3), id(0xF0, 5), id(0xEE)]);
      expect(result.known, 1, reason: 'только фрагмент этого узла');
      expect((await report([id(0xF0, 3)])).known, 1, reason: 'повтор');
      final located = await locate(id(18));
      expect(located.placements.map((p) => p.index), isNot(contains(3)));
      expect(located.placements, hasLength(19));

      await expectLater(() => report([]), failsWith(_badRequest));
      await expectLater(() => report([Uint8List(31)]), failsWith(_badRequest));
      await expectLater(
        () => report([for (var i = 0; i < 1001; i++) id(0xEE)]),
        failsWith(_badRequest),
      );
      // Подписан не узлом.
      await expectLater(
        () => report([id(0xF0, 3)], key: device),
        failsWith(pb.ErrorCode.ERROR_CODE_PERMISSION_DENIED),
      );
    });
  });

  group('DeleteSegment (сборка мусора)', () {
    setUp(start);

    test('талоны DELETE и освобождение места', () async {
      await allocate(allocation(id(14)));
      await commit(id(14), [for (var i = 0; i < 20; i++) i]);
      await allocate(allocation(id(15)));
      await commit(id(15), [for (var i = 0; i < 18; i++) i]);
      expect(await accountBytes(), 38 * _size);

      final deleted = await delete(id(14));
      expect(deleted.placements, hasLength(20));
      for (final p in deleted.placements) {
        await nodeAccepts(
          p,
          pb.TicketOperation.TICKET_OPERATION_DELETE,
          fragmentId: id(0xF0, p.index),
        );
      }
      expect(await accountBytes(), 18 * _size, reason: 'место уменьшилось');
      expect(await assignedTotal(), 18 * _size);
      await expectLater(() => locate(id(14)), failsWith(_notFound));
      await expectLater(() => delete(id(14)), failsWith(_notFound));

      // Талоны DELETE — и на незагруженные фрагменты.
      expect((await delete(id(15))).placements, hasLength(20));
      expect(await accountBytes(), 0);
      expect(await assignedTotal(), 0);
    });

    test('неподтверждённый сегмент тоже удаляется', () async {
      await allocate(allocation(id(16)));
      await delete(id(16));
      expect(await accountBytes(), 0);
      expect(await assignedTotal(), 0);
    });
  });

  group('подписант', () {
    test('ключ подписанта — в RegisterNodeResponse', () async {
      await start(nodeCount: 0);
      final owner = await h.newAccount();
      await h.register(owner, await h.newKey(), login: 'keeper');
      final response = await h.registerNode(owner, await h.newKey());
      expect(response.coordinatorKeys.single, h.signerKey.publicKey);
    });

    test('без подписанта — UNAVAILABLE', () async {
      await start(withSigner: false);
      await expectLater(
        () => allocate(allocation(id(17))),
        failsWith(_unavailable),
      );
      final owner = await h.newAccount();
      await h.register(owner, await h.newKey(), login: 'keeper');
      expect(
        (await h.registerNode(owner, await h.newKey())).coordinatorKeys,
        isEmpty,
      );
    });
  });
}
