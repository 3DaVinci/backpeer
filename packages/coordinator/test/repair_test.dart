// Ремонт (группа 4.3; protocol.md, раздел 4.14): учёт живых фрагментов
// (4.3.1), очередь (4.3.2), задания: выбор исполнителя и новых узлов,
// талоны, отчёт, сроки (4.3.4). Исполнителя изображает тест поверх
// FakeNodes; сквозной ремонт с демонами — repair_network_test.dart. Нужен
// FS_TEST_POSTGRES.

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
    test('ремонт', () {}, skip: skipWithoutPostgres);
    return;
  }

  late DbHarness h;
  late AccountKeys account;
  late Ed25519KeyPair device;
  late FakeNodes channels;

  /// Узлы-хранители: у каждого свой владелец и своя подсеть.
  final nodes = <Ed25519KeyPair>[];
  final byId = <String, int>{};

  Future<void> start({
    CoordinatorConfig config = DbHarness.testConfig,
    int nodeCount = 24,
  }) async {
    h = await DbHarness.create(config: config);
    channels = FakeNodes(h.crypto);
    account = await h.newAccount();
    device = await h.newKey();
    await h.register(account, device, login: 'client');
    nodes.clear();
    byId.clear();
    for (var i = 0; i < nodeCount; i++) {
      final owner = await h.newAccount();
      await h.register(owner, await h.newKey(), login: 'keeper$i');
      final node = await h.newKey();
      await h.registerNode(
        owner,
        node,
        ip: '198.51.$i.10',
        endpoints: ['198.51.$i.10:7000'],
      );
      nodes.add(node);
      byId[bytesToHex(node.publicKey)] = i;
      channels.online.add(bytesToHex(node.publicKey));
    }
  }

  tearDown(() => h.close());

  /// Heartbeat всех узлов, кроме [except], — с их подсетей.
  Future<void> beatAll({Set<int> except = const {}}) async {
    for (var i = 0; i < nodes.length; i++) {
      if (except.contains(i)) continue;
      await h.heartbeat(nodes[i], ip: '198.51.$i.10');
    }
  }

  /// Сегмент 10 из 20 с порогом 16 из настоящих фрагментов: размещён,
  /// фрагменты [stored] (по умолчанию все) лежат на узлах в [channels] и
  /// подтверждены. Возвращает фрагменты и номера узлов по номерам
  /// фрагментов.
  Future<({Uint8List id, List<Fragment> fragments, List<int> holders})>
  storeSegment(int seed, {Iterable<int>? stored}) async {
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
    final indexes = (stored ?? List.generate(20, (i) => i)).toList();
    for (final i in indexes) {
      channels.add(nodes[holders[i]].publicKey, fragments[i]);
    }
    await h.call(
      'CommitSegment',
      pb.CommitSegmentRequest(segmentId: segmentId, storedIndexes: indexes),
      pb.CommitSegmentResponse.fromBuffer,
      key: device,
    );
    return (id: segmentId, fragments: fragments, holders: holders);
  }

  Future<({int live, int state, DateTime? since})> segment(
    Uint8List segmentId,
  ) async {
    final [live as int, state as int, since as DateTime?] = (await h.db.run(
      (s) => s.execute(
        Sql.named('''
          SELECT live, state, repair_since FROM segments
            WHERE segment_id = @g:bytea'''),
        parameters: {'g': segmentId},
      ),
    )).single;
    return (live: live, state: state, since: since);
  }

  RepairService repairService({
    RepairPolicy policy = const RepairPolicy(),
    int seed = 1,
  }) => RepairService(
    h.db,
    crypto: h.crypto,
    nodes: NodeService(
      h.db,
      CertificateChecks(h.crypto, clock: h.clock.call),
      policy: DbHarness.testConfig.nodes,
      clock: h.clock.call,
    ),
    signer: h.signer,
    policy: policy,
    placementPolicy: DbHarness.testConfig.placement,
    clock: h.clock.call,
    random: Random(seed),
  );

  group('живые фрагменты (4.3.1)', () {
    setUp(start);

    test('подтверждение: все фрагменты живые; не больше t — очередь '
        'ремонта', () async {
      final full = await storeSegment(1);
      expect(await segment(full.id), (live: 20, state: 1, since: null));
      final partial = await storeSegment(
        2,
        stored: List.generate(15, (i) => i),
      );
      final p = await segment(partial.id);
      expect(p.live, 15);
      expect(p.state, 2);
      expect(p.since, isNotNull);
      // Догрузка до 17 выводит сегмент из очереди.
      await h.call(
        'CommitSegment',
        pb.CommitSegmentRequest(segmentId: partial.id, storedIndexes: [15, 16]),
        pb.CommitSegmentResponse.fromBuffer,
        key: device,
      );
      expect(await segment(partial.id), (live: 17, state: 1, since: null));
    });

    test('отчёт узла о повреждении уменьшает число живых', () async {
      final a = await storeSegment(3);
      final b = await storeSegment(4);
      final damaged = a.fragments[3];
      await h.call(
        'ReportDamagedFragments',
        pb.ReportDamagedFragmentsRequest(
          fragmentIds: [damaged.header.fragmentId(h.crypto)],
        ),
        pb.ReportDamagedFragmentsResponse.fromBuffer,
        key: nodes[a.holders[3]],
        ip: '198.51.${a.holders[3]}.10',
      );
      expect((await segment(a.id)).live, 19);
      expect((await segment(b.id)).live, 20, reason: 'другой сегмент');
    });

    test('второй провал аудита — фрагмент потерян, живых меньше', () async {
      final s = await storeSegment(5);
      final victim = nodes[s.holders[7]].publicKey;
      channels.remove(victim, s.fragments[7]);
      final audits = AuditService(
        h.db,
        crypto: h.crypto,
        clock: h.clock.call,
        random: Random(1),
      )..channels = channels;
      await audits.runOnce();
      expect((await segment(s.id)).live, 20, reason: 'первый провал — повтор');
      h.clock.advance(const AuditPolicy().recheckDelay);
      await audits.runOnce();
      expect((await segment(s.id)).live, 19);
    });

    test('узел не в сети дольше 72 ч потерян; вернулся — фрагменты снова '
        'живые', () async {
      final s = await storeSegment(6);
      final gone = {s.holders[0], s.holders[1], s.holders[2], s.holders[3]};
      final repair = repairService();
      h.clock.advance(const Duration(hours: 71));
      await beatAll(except: gone);
      expect(await repair.markLost(), 0, reason: '71 ч — ещё не потерян');
      h.clock.advance(const Duration(hours: 2));
      await beatAll(except: gone);
      expect(await repair.markLost(), 4);
      final lost = await segment(s.id);
      expect(lost.live, 16);
      expect(lost.state, 2, reason: '16 = t: в очереди ремонта');
      expect(lost.since, isNotNull);
      expect(await repair.markLost(), 0, reason: 'повторно не отмечаются');

      final back = s.holders[0];
      await h.heartbeat(nodes[back], ip: '198.51.$back.10');
      expect(await segment(s.id), (live: 17, state: 1, since: null));
    });
  });

  group('очередь ремонта (4.3.2)', () {
    setUp(start);

    /// Действующее задание для сегмента [segmentId] с оценкой [bytes].
    Future<void> activeJob(Uint8List segmentId, int bytes) => h.db.run(
      (s) => s.execute(
        Sql.named('''
          INSERT INTO repair_jobs (job_id, account_id, segment_id, executor,
                                   live, planned_bytes, state, created_at,
                                   deadline)
            VALUES (@j:bytea, @a:bytea, @g:bytea, @e:bytea, 0, @b:int8, 0,
                    @t:timestamptz, @t:timestamptz)'''),
        parameters: {
          'j': h.crypto.randomBytes(16),
          'a': account.accountId,
          'g': segmentId,
          'e': nodes[0].publicKey,
          'b': bytes,
          't': h.clock.now,
        },
      ),
    );

    test('меньше живых — раньше; с запасом — после ленивой паузы', () async {
      final at16 = await storeSegment(10, stored: List.generate(16, (i) => i));
      final at11 = await storeSegment(11, stored: List.generate(11, (i) => i));
      await storeSegment(12);
      final at13 = await storeSegment(13, stored: List.generate(13, (i) => i));
      List<int> lives(List<RepairCandidate> q) => [for (final c in q) c.live];

      final eager = repairService(
        policy: const RepairPolicy(lazyDelay: Duration.zero),
      );
      final q = await eager.queue();
      expect(lives(q), [11, 13, 16]);
      expect(q.first.segmentId, at11.id);
      expect(q.last.segmentId, at16.id);

      final lazy = repairService();
      expect(lives(await lazy.queue()), [11, 13], reason: '16 = t ждёт');
      h.clock.advance(const RepairPolicy().lazyDelay);
      expect(lives(await lazy.queue()), [11, 13, 16]);
      final wider = repairService(policy: const RepairPolicy(lazyMargin: 3));
      h.clock.advance(const Duration(hours: -1));
      expect(lives(await wider.queue()), [11]);

      // Сегмент с действующим заданием не стоит в очереди.
      await activeJob(at13.id, 1000);
      expect(lives(await eager.queue()), [11, 16]);
      expect(lives(await eager.queue(limit: 1)), [11]);
    });

    test('предел заданий и трафика за час', () async {
      final a = await storeSegment(14, stored: List.generate(12, (i) => i));
      final b = await storeSegment(15, stored: List.generate(12, (i) => i));
      final repair = repairService(
        policy: const RepairPolicy(maxJobs: 3, maxBytesPerHour: 1 << 30),
      );
      expect(await repair.budget(), (jobs: 3, bytes: 1 << 30));
      await activeJob(a.id, 400 << 20);
      await activeJob(b.id, 400 << 20);
      expect(await repair.budget(), (jobs: 1, bytes: 224 << 20));
      h.clock.advance(const Duration(minutes: 61));
      expect(
        (await repair.budget()).bytes,
        1 << 30,
        reason: 'трафик считается за последний час',
      );
      expect(RepairService.plannedBytes(10, 5, 1000), 15000);
    });
  });

  group('задания ремонта (4.3.4)', () {
    // 20 узлов держат фрагменты сегмента; новым фрагментам и исполнителю
    // нужны другие.
    setUp(() => start(nodeCount: 30));

    /// Все узлы — старые и почти всегда в сети: проходят пороги
    /// доступности и репутации исполнителя.
    Future<void> healthy() => h.db.run(
      (s) => s.execute(
        Sql.named('''
          UPDATE nodes SET availability = 0.99,
                           registered_at = @t:timestamptz'''),
        parameters: {'t': h.clock.now.subtract(const Duration(days: 60))},
      ),
    );

    /// Узлы [gone] не в сети 73 часа и отмечены потерянными.
    Future<void> lose(Set<int> gone) async {
      h.clock.advance(const Duration(hours: 73));
      await beatAll(except: gone);
      await healthy();
      await repairService().markLost();
    }

    int nodeOf(pb.Placement p) => byId[bytesToHex(p.node.nodeId)]!;

    pb.FragmentTicket ticketOf(pb.Placement p) =>
        FragmentTickets.parse(Uint8List.fromList(p.ticket.body));

    Future<int> assignedTotal() async =>
        (await h.db.run(
              (x) => x.execute(
                'SELECT coalesce(sum(assigned_bytes), 0)::int8 FROM nodes',
              ),
            )).single.single!
            as int;

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

    /// Выполняет задание, как исполнитель: k источников из FakeNodes,
    /// пересоздание, загрузка на новые узлы (кроме [skip]) и отчёт.
    Future<void> execute(
      (String, pb.RepairCommand) job, {
      Set<int> skip = const {},
    }) async {
      final (executor, c) = job;
      final sources = [
        for (final p in c.sources.take(c.k))
          channels.fragments[bytesToHex(p.node.nodeId)]![bytesToHex(
            ticketOf(p).fragmentId,
          )]!,
      ];
      final indexes = [for (final p in c.targets) p.index];
      final rebuilt = rebuildFragments(h.crypto, sources, indexes);
      final stored = <int>[];
      for (var i = 0; i < c.targets.length; i++) {
        final p = c.targets[i];
        expect(rebuilt[i].header.fragmentId(h.crypto), ticketOf(p).fragmentId);
        if (skip.contains(p.index)) continue;
        channels.add(Uint8List.fromList(p.node.nodeId), rebuilt[i]);
        stored.add(p.index);
      }
      await h.call(
        'ReportRepair',
        pb.ReportRepairRequest(
          jobId: c.jobId,
          storedIndexes: stored,
          failures: [
            for (final i in skip.take(1))
              pb.RepairFailure(index: i, reason: 'test'),
          ],
          bytesDownloaded: Int64(c.k * c.fragmentSize),
          bytesUploaded: Int64(stored.length * c.fragmentSize),
        ),
        pb.ReportRepairResponse.fromBuffer,
        key: nodes[byId[executor]!],
        ip: '198.51.${byId[executor]}.10',
      );
    }

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

    test('сегмент, потерявший 5 фрагментов, возвращается к 20 живым без '
        'клиента', () async {
      final s = await storeSegment(20);
      final gone = {
        for (final i in [1, 4, 9, 12, 17]) s.holders[i],
      };
      await lose(gone);
      expect((await segment(s.id)).live, 15);
      final size = s.fragments.first.bytes.length;
      final before = await assigned(s.holders[4]);

      final repair = repairService()..channels = channels;
      expect(await repair.runOnce(), 1);
      final (executor, c) = channels.repairs.single;
      final e = byId[executor]!;
      expect(
        s.holders,
        isNot(contains(e)),
        reason: 'исполнитель без фрагментов',
      );
      expect((c.k, c.n, c.fragmentSize), (10, 20, size));
      expect([for (final p in c.targets) p.index], [1, 4, 9, 12, 17]);
      expect(c.sources, hasLength(15));
      for (final p in c.sources) {
        final t = ticketOf(p);
        expect(t.operation, pb.TicketOperation.TICKET_OPERATION_GET);
        expect(t.deviceSign, nodes[e].publicKey);
        expect(t.ownerAccount, isEmpty);
        expect(gone, isNot(contains(nodeOf(p))));
      }
      expect({for (final p in c.targets) nodeOf(p)}, hasLength(5));
      for (final p in c.targets) {
        final t = ticketOf(p);
        expect(t.operation, pb.TicketOperation.TICKET_OPERATION_PUT);
        expect(t.deviceSign, nodes[e].publicKey);
        expect(t.ownerAccount, account.accountId);
        expect(t.fragmentId, s.fragments[p.index].header.fragmentId(h.crypto));
        expect(s.holders, isNot(contains(nodeOf(p))));
        expect(nodeOf(p), isNot(e));
        expect(await assigned(nodeOf(p)), size, reason: 'место занято');
      }
      // Пока задание идёт, второе для сегмента не начинается.
      expect(await repair.runOnce(), 0);

      await execute(channels.repairs.single);
      await repair.runOnce();
      expect(await segment(s.id), (live: 20, state: 1, since: null));
      final now = await holdersNow(s.id);
      for (final p in c.targets) {
        expect(now[p.index], nodeOf(p));
      }
      expect(await assigned(s.holders[4]), before - size);
      final [state as int, down as int, up as int] = (await h.db.run(
        (x) => x.execute(
          'SELECT state, bytes_downloaded, bytes_uploaded FROM repair_jobs',
        ),
      )).single;
      expect(state, RepairJobState.done.index);
      expect((down, up), (10 * size, 5 * size));
      // Вернувшийся узел уже не держит номер сегмента.
      await h.heartbeat(nodes[s.holders[4]], ip: '198.51.${s.holders[4]}.10');
      expect((await segment(s.id)).live, 20);
    });

    test('меньше живых — раньше в работу', () async {
      final at16 = await storeSegment(21, stored: List.generate(16, (i) => i));
      final at11 = await storeSegment(22, stored: List.generate(11, (i) => i));
      await healthy();
      final repair = repairService(
        policy: const RepairPolicy(maxJobs: 1, lazyDelay: Duration.zero),
      )..channels = channels;
      expect(await repair.runOnce(), 1);
      expect(channels.repairs.single.$2.targets, hasLength(9));
      await execute(channels.repairs.single);
      await repair.runOnce();
      expect((await segment(at11.id)).live, 20);
      expect((await segment(at16.id)).live, 16);
      expect(
        channels.repairs,
        hasLength(2),
        reason: 'следующий — сегмент с 16',
      );
      expect(channels.repairs.last.$2.targets, hasLength(4));
    });

    test('отказ исполнителя и молчание до срока — задание провалено, '
        'другой исполнитель', () async {
      final s = await storeSegment(23, stored: List.generate(14, (i) => i));
      await healthy();
      final size = s.fragments.first.bytes.length;
      final repair = repairService()..channels = channels;
      final free = [
        for (var i = 0; i < nodes.length; i++)
          if (!s.holders.contains(i)) i,
      ];
      // Все, кроме одного свободного узла, отказываются.
      for (final n in nodes) {
        channels.refusing.add(bytesToHex(n.publicKey));
      }
      channels.refusing.remove(bytesToHex(nodes[free.last].publicKey));
      var started = 0;
      for (var i = 0; i < free.length && started == 0; i++) {
        started = await repair.runOnce();
      }
      expect(started, 1);
      expect(byId[channels.repairs.single.$1], free.last);
      expect(
        await assignedTotal(),
        20 * size,
        reason: 'место отказов свободно',
      );

      // Исполнитель молчит: после срока задание провалено, место
      // освобождено, после паузы — новый исполнитель.
      h.clock.advance(
        const RepairPolicy().jobTimeout + const Duration(seconds: 1),
      );
      await beatAll();
      await healthy();
      channels.refusing.clear();
      expect(await repair.expire(), 1);
      expect(await assignedTotal(), 14 * size);
      expect(await repair.runOnce(), 0, reason: 'пауза повтора');
      h.clock.advance(const RepairPolicy().retryDelay);
      await beatAll();
      await healthy();
      expect(await repair.runOnce(), 1);
      expect(channels.repairs.last.$1, isNot(channels.repairs.first.$1));
    });

    test('ReportRepair: чужое задание, неверные номера, частичный '
        'отчёт', () async {
      final s = await storeSegment(24, stored: List.generate(15, (i) => i));
      await healthy();
      final repair = repairService()..channels = channels;
      await repair.runOnce();
      final (executor, c) = channels.repairs.single;
      final e = nodes[byId[executor]!];
      final other = nodes.firstWhere((n) => !identical(n, e));
      Future<void> send(pb.ReportRepairRequest r, Ed25519KeyPair key) => h.call(
        'ReportRepair',
        r,
        pb.ReportRepairResponse.fromBuffer,
        key: key,
      );
      await expectLater(
        send(pb.ReportRepairRequest(jobId: c.jobId), other),
        failsWith(pb.ErrorCode.ERROR_CODE_NOT_FOUND),
      );
      await expectLater(
        send(pb.ReportRepairRequest(jobId: c.jobId, storedIndexes: [0]), e),
        failsWith(pb.ErrorCode.ERROR_CODE_BAD_REQUEST),
      );
      await expectLater(
        send(
          pb.ReportRepairRequest(
            jobId: c.jobId,
            storedIndexes: [15],
            failures: [pb.RepairFailure(index: 15)],
          ),
          e,
        ),
        failsWith(pb.ErrorCode.ERROR_CODE_BAD_REQUEST),
      );
      // Два номера загружены, один не удался, два не упомянуты.
      await execute(channels.repairs.single, skip: {17, 18, 19});
      await repair.runOnce();
      expect((await segment(s.id)).live, 17);
      final targets = await h.db.run(
        (x) => x.execute('SELECT idx, state FROM repair_targets ORDER BY idx'),
      );
      expect(
        [for (final [i, st] in targets) (i, st)],
        [(15, 2), (16, 2), (17, 3), (18, 3), (19, 3)],
      );
      // Повторный отчёт ничего не меняет.
      await send(
        pb.ReportRepairRequest(jobId: c.jobId, storedIndexes: [17]),
        e,
      );
      expect((await segment(s.id)).live, 17);
    });

    test('удаление сегмента во время ремонта освобождает место', () async {
      final s = await storeSegment(25, stored: List.generate(15, (i) => i));
      await healthy();
      final repair = repairService()..channels = channels;
      await repair.runOnce();
      expect(channels.repairs, hasLength(1));
      await h.call(
        'DeleteSegment',
        pb.DeleteSegmentRequest(segmentId: s.id),
        pb.DeleteSegmentResponse.fromBuffer,
        key: device,
      );
      expect(await assignedTotal(), 0);
      final jobs = await h.db.run(
        (x) => x.execute('SELECT count(*) FROM repair_jobs'),
      );
      expect(jobs.single.single, 0);
    });
  });
}
