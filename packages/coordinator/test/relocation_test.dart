// Выход узла и уборка фрагментов (группа 4.4; protocol.md, раздел 4.15):
// перенос фрагментов уходящего узла (4.4.1), перенос лишнего при
// уменьшении ёмкости (4.4.2), сверка фрагментов узла (4.4.3). Узлы
// изображает FakeNodes, исполнителя переноса — тест; сквозной выход с
// демонами — relocation_network_test.dart. Нужен FS_TEST_POSTGRES.

import 'dart:math';
import 'dart:typed_data';

import 'package:coordinator/coordinator.dart';
import 'package:core/core.dart';
import 'package:fixnum/fixnum.dart';
import 'package:postgres/postgres.dart';
import 'package:protocol/protocol.dart' as pb;
import 'package:test/test.dart';

import 'support/db_harness.dart';
import 'support/fake_nodes.dart';
import 'support/postgres.dart';

void main() {
  if (testPostgresUrl == null) {
    test('выход узла', () {}, skip: skipWithoutPostgres);
    return;
  }

  late DbHarness h;
  late AccountKeys account;
  late Ed25519KeyPair device;
  late FakeNodes channels;

  /// Узлы-хранители: у каждого свой владелец и своя подсеть.
  final nodes = <Ed25519KeyPair>[];
  final byId = <String, int>{};

  String ipOf(int i) => '198.51.$i.10';

  setUp(() async {
    h = await DbHarness.create();
    channels = FakeNodes(h.crypto);
    account = await h.newAccount();
    device = await h.newKey();
    await h.register(account, device, login: 'client');
    nodes.clear();
    byId.clear();
    for (var i = 0; i < 26; i++) {
      final owner = await h.newAccount();
      await h.register(owner, await h.newKey(), login: 'keeper$i');
      final node = await h.newKey();
      await h.registerNode(
        owner,
        node,
        ip: ipOf(i),
        endpoints: ['${ipOf(i)}:7000'],
      );
      nodes.add(node);
      byId[bytesToHex(node.publicKey)] = i;
      channels.online.add(bytesToHex(node.publicKey));
    }
    // Старые и почти всегда в сети: проходят пороги размещения.
    await h.db.run(
      (s) => s.execute(
        Sql.named('''
          UPDATE nodes SET availability = 0.99,
                           registered_at = @t:timestamptz'''),
        parameters: {'t': h.clock.now.subtract(const Duration(days: 60))},
      ),
    );
  });

  tearDown(() => h.close());

  /// Сегмент 10 из 20 с порогом 16: все фрагменты на узлах в [channels] и
  /// подтверждены. Возвращает фрагменты и номера узлов по номерам.
  Future<({Uint8List id, List<Fragment> fragments, List<int> holders})>
  storeSegment(int seed) async {
    final r = Random(seed);
    final segmentId = Uint8List.fromList(
      List.generate(32, (_) => r.nextInt(256)),
    );
    final fragments = encodeFragments(
      h.crypto,
      blob: Uint8List.fromList(List.generate(50000, (_) => r.nextInt(256))),
      segmentId: segmentId,
      k: 10,
      n: 20,
    );
    final response = await h.call(
      'AllocateSegment',
      pb.AllocateSegmentRequest(
        segmentId: segmentId,
        k: 10,
        n: 20,
        repairThreshold: 16,
        fragmentSize: fragments.first.bytes.length,
        fragmentIds: [for (final f in fragments) f.header.fragmentId(h.crypto)],
        bodyRoots: [for (final f in fragments) f.header.bodyRoot],
      ),
      pb.AllocateSegmentResponse.fromBuffer,
      key: device,
    );
    final holders = [
      for (final p in response.placements) byId[bytesToHex(p.node.nodeId)]!,
    ];
    for (var i = 0; i < 20; i++) {
      channels.add(nodes[holders[i]].publicKey, fragments[i]);
    }
    await h.call(
      'CommitSegment',
      pb.CommitSegmentRequest(
        segmentId: segmentId,
        storedIndexes: List.generate(20, (i) => i),
      ),
      pb.CommitSegmentResponse.fromBuffer,
      key: device,
    );
    return (id: segmentId, fragments: fragments, holders: holders);
  }

  RepairService repairService() => RepairService(
    h.db,
    crypto: h.crypto,
    nodes: NodeService(
      h.db,
      CertificateChecks(h.crypto, clock: h.clock.call),
      policy: DbHarness.testConfig.nodes,
      clock: h.clock.call,
    ),
    signer: h.signer,
    placementPolicy: DbHarness.testConfig.placement,
    clock: h.clock.call,
    random: Random(1),
  )..channels = channels;

  Future<int> live(Uint8List segmentId) async =>
      (await h.db.run(
            (s) => s.execute(
              Sql.named(
                'SELECT live FROM segments WHERE segment_id = @g:bytea',
              ),
              parameters: {'g': segmentId},
            ),
          )).single.single!
          as int;

  Future<List<int>> holdersNow(Uint8List segmentId) async => [
    for (final [id as List<int>] in await h.db.run(
      (s) => s.execute(
        Sql.named('''
          SELECT node_id FROM fragments WHERE segment_id = @g:bytea
            ORDER BY idx'''),
        parameters: {'g': segmentId},
      ),
    ))
      byId[bytesToHex(id)]!,
  ];

  Future<int> assigned(int node) async =>
      (await h.db.run(
            (s) => s.execute(
              Sql.named(
                'SELECT assigned_bytes FROM nodes WHERE node_id = @n:bytea',
              ),
              parameters: {'n': nodes[node].publicKey},
            ),
          )).single.single!
          as int;

  Future<pb.LeaveNetworkResponse> leave(int node, {bool cancel = false}) =>
      h.call(
        'LeaveNetwork',
        pb.LeaveNetworkRequest(cancel: cancel),
        pb.LeaveNetworkResponse.fromBuffer,
        key: nodes[node],
        ip: ipOf(node),
      );

  Future<List<List<int>>> reconcile(
    int node,
    List<List<int>> ids, {
    bool first = false,
  }) async => (await h.call(
    'ReconcileFragments',
    pb.ReconcileFragmentsRequest(fragmentIds: ids, first: first),
    pb.ReconcileFragmentsResponse.fromBuffer,
    key: nodes[node],
    ip: ipOf(node),
  )).unknown;

  pb.FragmentTicket ticketOf(pb.Placement p) =>
      FragmentTickets.parse(Uint8List.fromList(p.ticket.body));

  int nodeOf(pb.Placement p) => byId[bytesToHex(p.node.nodeId)]!;

  /// Выполняет перенос, как узел-исполнитель: свой фрагмент — новому узлу,
  /// затем отчёт.
  Future<void> relocate((String, pb.RelocateCommand) job) async {
    final (executor, c) = job;
    final t = ticketOf(c.target);
    final fragment = channels.fragments[executor]![bytesToHex(t.fragmentId)]!;
    channels.add(Uint8List.fromList(c.target.node.nodeId), fragment);
    await h.call(
      'ReportRepair',
      pb.ReportRepairRequest(
        jobId: c.jobId,
        storedIndexes: [c.target.index],
        bytesUploaded: Int64(fragment.bytes.length),
      ),
      pb.ReportRepairResponse.fromBuffer,
      key: nodes[byId[executor]!],
      ip: ipOf(byId[executor]!),
    );
  }

  test('узел, объявивший выход, уходит без снижения числа живых ниже 20 '
      '(4.4.1)', () async {
    final segments = [for (var i = 0; i < 3; i++) await storeSegment(40 + i)];
    // Уходит узел с фрагментами больше чем одного сегмента.
    final counts = <int, int>{};
    for (final s in segments) {
      for (final n in s.holders) {
        counts[n] = (counts[n] ?? 0) + 1;
      }
    }
    final x = counts.entries.firstWhere((e) => e.value >= 2).key;
    final mine = [
      for (final s in segments)
        if (s.holders.contains(x)) (s, s.holders.indexOf(x)),
    ];
    final size = segments.first.fragments.first.bytes.length;

    final first = await leave(x);
    expect(first.done, isFalse);
    expect(first.remainingFragments.toInt(), mine.length);
    expect(first.remainingBytes.toInt(), mine.length * size);
    // Уходящий узел не получает новых фрагментов.
    final fresh = await storeSegment(50);
    expect(fresh.holders, isNot(contains(x)));

    final repair = repairService();
    expect(await repair.runOnce(), mine.length);
    expect(channels.repairs, isEmpty);
    expect(channels.relocations, hasLength(mine.length));
    for (final (executor, c) in channels.relocations) {
      expect(byId[executor], x, reason: 'переносит сам уходящий узел');
      final t = ticketOf(c.target);
      expect(t.operation, pb.TicketOperation.TICKET_OPERATION_PUT);
      expect(t.nodeId, c.target.node.nodeId);
      expect(t.deviceSign, nodes[x].publicKey);
      expect(t.ownerAccount, account.accountId);
      final (s, index) = mine.firstWhere(
        (m) => constantTimeEquals(
          m.$1.fragments[m.$2].header.fragmentId(h.crypto),
          t.fragmentId,
        ),
      );
      expect(c.target.index, index);
      expect(s.holders, isNot(contains(nodeOf(c.target))));
      expect(await assigned(nodeOf(c.target)), greaterThanOrEqualTo(size));
    }
    // Пока перенос идёт, фрагмент уходящего узла живой, второго задания
    // нет, а новый узел сверкой фрагмент не теряет.
    for (final (s, _) in mine) {
      expect(await live(s.id), 20);
    }
    expect(await repair.runOnce(), 0);
    final (_, c0) = channels.relocations.first;
    final target0 = nodeOf(c0.target);
    expect(await reconcile(target0, [ticketOf(c0.target).fragmentId]), isEmpty);

    for (final job in channels.relocations) {
      await relocate(job);
    }
    await repair.runOnce();
    for (final (s, index) in mine) {
      expect(await live(s.id), 20);
      final now = await holdersNow(s.id);
      expect(now[index], isNot(x));
    }
    final stats = await AdminService(
      h.db,
      onlineWindow: const Duration(minutes: 15),
      probation: Duration.zero,
      clock: h.clock.call,
    ).repairStats();
    expect(stats['relocations'], {
      'nodesLeaving': 1,
      'running': 0,
      'done': mine.length,
      'failed': 0,
      'uploadedBytes': mine.length * size,
    });
    expect((stats['jobs']! as Map)['done'], 0, reason: 'это не ремонт');

    // Прежний узел просят сверить фрагменты: перенесённые — неучтённые.
    expect((await h.heartbeat(nodes[x], ip: ipOf(x))).reconcile, isTrue);
    final moved = [
      for (final (s, index) in mine)
        s.fragments[index].header.fragmentId(h.crypto),
    ];
    expect(await reconcile(x, moved, first: true), unorderedEquals(moved));
    expect((await h.heartbeat(nodes[x], ip: ipOf(x))).reconcile, isFalse);

    final last = await leave(x);
    expect(last.done, isTrue);
    expect(last.remainingFragments.toInt(), 0);
    await expectLater(
      leave(x),
      throwsA(
        isA<RpcFailure>().having(
          (e) => e.code,
          'code',
          pb.ErrorCode.ERROR_CODE_UNAUTHENTICATED,
        ),
      ),
      reason: 'узел удалён',
    );
  });

  test('выход ждёт новых фрагментов, идущих на узел; отмена выхода', () async {
    final s = await storeSegment(60);
    final x = s.holders[7];
    await leave(x);
    // Отмена: узел снова получает фрагменты, переносов нет.
    final cancelled = await leave(x, cancel: true);
    expect(cancelled.done, isFalse);
    final repair = repairService();
    expect(await repair.runOnce(), 0);
    expect(channels.relocations, isEmpty);
    final [leaving as DateTime?] = (await h.db.run(
      (q) => q.execute(
        Sql.named('SELECT leaving_at FROM nodes WHERE node_id = @n:bytea'),
        parameters: {'n': nodes[x].publicKey},
      ),
    )).single;
    expect(leaving, isNull);
    // Узел без фрагментов, на который идёт перенос, не удаляется, пока
    // перенос не кончится.
    await leave(x);
    await repair.runOnce();
    final (_, c) = channels.relocations.single;
    final target = nodeOf(c.target);
    final idle = await leave(target);
    expect(idle.remainingFragments.toInt(), 0);
    expect(idle.done, isFalse, reason: 'на узел идёт новый фрагмент');
  });

  test(
    'уменьшение ёмкости: переносится только лишнее, потерь нет (4.4.2)',
    () async {
      final segments = [for (var i = 0; i < 3; i++) await storeSegment(70 + i)];
      final counts = <int, int>{};
      for (final s in segments) {
        for (final n in s.holders) {
          counts[n] = (counts[n] ?? 0) + 1;
        }
      }
      final x = counts.entries.firstWhere((e) => e.value >= 2).key;
      final size = segments.first.fragments.first.bytes.length;
      final held = await assigned(x);
      expect(held, counts[x]! * size);
      // Квоту уменьшили на один фрагмент: занятое больше ёмкости — не
      // ошибка.
      await h.heartbeat(nodes[x], ip: ipOf(x), used: held, capacity: held - 1);
      final repair = repairService();
      expect(await repair.runOnce(), 1);
      expect(await repair.runOnce(), 0, reason: 'идущий перенос учтён');
      await relocate(channels.relocations.single);
      await repair.runOnce();
      expect(await assigned(x), held - size);
      expect(await repair.runOnce(), 0, reason: 'лишнего больше нет');
      for (final s in segments) {
        expect(await live(s.id), 20);
      }
      final kept = [
        for (final s in segments)
          if ((await holdersNow(s.id)).contains(x)) s,
      ];
      expect(kept, hasLength(counts[x]! - 1));
    },
  );

  test('сверка: неучтённые фрагменты, удалённый сегмент, проверки запроса '
      '(4.4.3)', () async {
    final s = await storeSegment(80);
    final a = s.holders[0];
    final known = s.fragments[0].header.fragmentId(h.crypto);
    final stranger = Uint8List.fromList(List.filled(32, 7));
    expect(await reconcile(a, [known, stranger]), [stranger]);
    expect(await reconcile(s.holders[1], [known]), [
      known,
    ], reason: 'фрагмент другого узла');
    expect((await h.heartbeat(nodes[a], ip: ipOf(a))).reconcile, isFalse);

    // Удалённый сегмент: узлы просят сверить, его фрагменты неучтённые.
    await h.call(
      'DeleteSegment',
      pb.DeleteSegmentRequest(segmentId: s.id),
      pb.DeleteSegmentResponse.fromBuffer,
      key: device,
    );
    expect((await h.heartbeat(nodes[a], ip: ipOf(a))).reconcile, isTrue);
    expect(await reconcile(a, [known], first: true), [known]);

    for (final (ids, problem) in [
      (<List<int>>[], 'пусто'),
      (List.generate(1001, (i) => List.filled(32, i % 256)), 'много'),
      ([List.filled(31, 1)], 'длина'),
      ([known, known], 'повтор'),
    ]) {
      await expectLater(
        reconcile(a, ids),
        throwsA(
          isA<RpcFailure>().having(
            (e) => e.code,
            'code',
            pb.ErrorCode.ERROR_CODE_BAD_REQUEST,
          ),
        ),
        reason: problem,
      );
    }
  });
}
