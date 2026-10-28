// Ремонт (группа 4.3; protocol.md, раздел 4.14): учёт живых фрагментов
// (4.3.1). Нужен FS_TEST_POSTGRES.

import 'dart:math';
import 'dart:typed_data';

import 'package:coordinator/coordinator.dart';
import 'package:core/core.dart';
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

  RepairService repairService({RepairPolicy policy = const RepairPolicy()}) =>
      RepairService(h.db, policy: policy, clock: h.clock.call);

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
}
