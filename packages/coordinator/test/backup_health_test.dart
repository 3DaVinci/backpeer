// Здоровье бэкапа для клиента (задачи 4.5.1, 4.5.2; protocol.md,
// раздел 4.16): GetBackupHealth — сводка по сегментам учётной записи и
// состояние запрошенных сегментов без узлов и чужих данных. Нужен
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
    test('здоровье бэкапа', () {}, skip: skipWithoutPostgres);
    return;
  }

  late DbHarness h;
  late AccountKeys account;
  late Ed25519KeyPair device;
  late FakeNodes channels;
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
    for (var i = 0; i < 22; i++) {
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
    await h.db.run(
      (s) => s.execute(
        Sql.named('''
          UPDATE nodes SET availability = 0.99,
                           registered_at = @r:timestamptz,
                           last_heartbeat_at = @t:timestamptz'''),
        parameters: {
          'r': h.clock.now.subtract(const Duration(days: 60)),
          't': h.clock.now,
        },
      ),
    );
  });

  tearDown(() => h.close());

  /// Сегмент 10 из 20 с порогом 16, все фрагменты подтверждены. Фрагменты
  /// по номерам — у [channels], чтобы узлы отвечали на аудит.
  Future<Uint8List> storeSegment(int seed, {Ed25519KeyPair? key}) async {
    final r = Random(seed);
    final segmentId = Uint8List.fromList(
      List.generate(32, (_) => r.nextInt(256)),
    );
    final fragments = encodeFragments(
      h.crypto,
      blob: Uint8List.fromList(List.generate(30000, (_) => r.nextInt(256))),
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
      key: key ?? device,
    );
    for (final p in response.placements) {
      channels.add(
        nodes[byId[bytesToHex(p.node.nodeId)]!].publicKey,
        fragments[p.index],
      );
    }
    await h.call(
      'CommitSegment',
      pb.CommitSegmentRequest(
        segmentId: segmentId,
        storedIndexes: List.generate(20, (i) => i),
      ),
      pb.CommitSegmentResponse.fromBuffer,
      key: key ?? device,
    );
    return segmentId;
  }

  Future<pb.GetBackupHealthResponse> health({
    List<Uint8List> segments = const [],
    DateTime? since,
    Ed25519KeyPair? key,
  }) => h.call(
    'GetBackupHealth',
    pb.GetBackupHealthRequest(
      segmentIds: segments,
      auditedSinceUnixMs: since == null
          ? null
          : Int64(since.millisecondsSinceEpoch),
    ),
    pb.GetBackupHealthResponse.fromBuffer,
    key: key ?? device,
  );

  /// Отмечает повреждёнными [count] фрагментов сегмента и пересчитывает
  /// живые, как это делает отчёт узла или провал аудита.
  Future<void> damage(Uint8List segmentId, int count) =>
      h.db.transaction((tx) async {
        await tx.execute(
          Sql.named('''
            UPDATE fragments SET damaged_at = @t:timestamptz
              WHERE segment_id = @g:bytea AND idx < @c:int4'''),
          parameters: {'g': segmentId, 'c': count, 't': h.clock.now},
        );
        await LiveFragments.recountSegment(
          tx,
          account.accountId,
          segmentId,
          h.clock.now,
        );
      });

  test('все сегменты здоровы и доступны', () async {
    final a = await storeSegment(1);
    await storeSegment(2);
    final r = await health(segments: [a, Uint8List(32)]);
    final s = r.summary;
    expect(s.segments.toInt(), 2);
    expect(s.healthy.toInt(), 2);
    expect(s.reduced.toInt() + s.atRisk.toInt() + s.lost.toInt(), 0);
    expect(s.readableNow.toInt(), 2);
    expect(s.liveFragments.toInt(), 40);
    expect(s.auditedFragments.toInt(), 0);
    expect(s.lastAuditUnixMs, Int64.ZERO);
    expect(s.fragmentBytes.toInt(), greaterThan(0));
    expect(
      r.auditedSinceUnixMs.toInt(),
      h.clock.now
          .subtract(BackupHealthService.defaultAuditWindow)
          .millisecondsSinceEpoch,
    );
    // Незнакомого сегмента в ответе нет.
    expect(r.segments, hasLength(1));
    final g = r.segments.single;
    expect(g.segmentId, a);
    expect((g.k, g.n, g.repairThreshold), (10, 20, 16));
    expect((g.live, g.online, g.audited), (20, 20, 0));
    expect(g.repairing, isFalse);
  });

  test('уменьшенные, в риске, потерянные и ремонт', () async {
    final reduced = await storeSegment(1);
    final atRisk = await storeSegment(2);
    final lost = await storeSegment(3);
    await damage(reduced, 2);
    await damage(atRisk, 5);
    await damage(lost, 11);
    // Сегмент в риске ремонтируется.
    await h.db.run(
      (s) => s.execute(
        Sql.named('''
          INSERT INTO repair_jobs (job_id, account_id, segment_id, executor,
                                   live, planned_bytes, state, created_at,
                                   deadline)
            VALUES (@j:bytea, @a:bytea, @g:bytea, @e:bytea, 15, 0, 0,
                    @t:timestamptz, @t:timestamptz)'''),
        parameters: {
          'j': Uint8List(16),
          'a': account.accountId,
          'g': atRisk,
          'e': nodes.first.publicKey,
          't': h.clock.now,
        },
      ),
    );
    // Узлы двух фрагментов сегмента reduced давно не в сети, но ещё не
    // потеряны: фрагменты живые, но сейчас не читаются.
    await h.db.run(
      (s) => s.execute(
        Sql.named('''
          UPDATE nodes SET last_heartbeat_at = @t:timestamptz
            WHERE node_id IN (SELECT node_id FROM fragments
                                WHERE segment_id = @g:bytea
                                  AND idx IN (2, 3))'''),
        parameters: {
          'g': reduced,
          't': h.clock.now.subtract(const Duration(hours: 2)),
        },
      ),
    );
    final r = await health(segments: [lost, atRisk, reduced]);
    final s = r.summary;
    expect(s.segments.toInt(), 3);
    expect(s.healthy.toInt(), 0);
    expect(s.reduced.toInt(), 1);
    expect(s.atRisk.toInt(), 1);
    expect(s.lost.toInt(), 1);
    expect(s.repairing.toInt(), 1);
    expect(s.readableNow.toInt(), 2);
    expect(s.liveFragments.toInt(), 18 + 15 + 9);
    expect([for (final g in r.segments) g.segmentId], [lost, atRisk, reduced]);
    expect([for (final g in r.segments) g.live], [9, 15, 18]);
    expect([for (final g in r.segments) g.repairing], [false, true, false]);
    expect(r.segments.last.online, lessThanOrEqualTo(16));
    expect(r.segments.last.online, greaterThanOrEqualTo(10));
  });

  test('проверенные аудитом фрагменты и граница', () async {
    final a = await storeSegment(1);
    final audits = AuditService(
      h.db,
      crypto: h.crypto,
      clock: h.clock.call,
      random: Random(1),
    )..channels = channels;
    expect(await audits.runOnce(), greaterThan(0));
    final auditedAt = Int64(h.clock.now.millisecondsSinceEpoch);
    final r = await health(segments: [a]);
    final audited = r.summary.auditedFragments.toInt();
    expect(audited, greaterThan(0));
    expect(audited, lessThanOrEqualTo(20));
    expect(r.segments.single.audited, audited);
    expect(r.summary.lastAuditUnixMs, auditedAt);
    expect(r.segments.single.lastAuditUnixMs, r.summary.lastAuditUnixMs);
    // Граница позже аудитов — проверенных нет, последний аудит остаётся.
    h.clock.advance(const Duration(days: 1));
    final later = await health(
      segments: [a],
      since: h.clock.now.subtract(const Duration(hours: 1)),
    );
    expect(later.summary.auditedFragments.toInt(), 0);
    expect(later.segments.single.audited, 0);
    expect(later.summary.lastAuditUnixMs, r.summary.lastAuditUnixMs);
  });

  test('чужие сегменты не видны', () async {
    final mine = await storeSegment(1);
    final other = await h.newAccount();
    final otherDevice = await h.newKey();
    await h.register(other, otherDevice, login: 'other');
    final r = await health(segments: [mine], key: otherDevice);
    expect(r.summary.segments.toInt(), 0);
    expect(r.summary.fragmentBytes.toInt(), 0);
    expect(r.segments, isEmpty);
  });

  test('неверный запрос', () async {
    Future<void> bad(pb.GetBackupHealthRequest request) => expectLater(
      h.call(
        'GetBackupHealth',
        request,
        pb.GetBackupHealthResponse.fromBuffer,
        key: device,
      ),
      failsWith(pb.ErrorCode.ERROR_CODE_BAD_REQUEST),
    );
    await bad(pb.GetBackupHealthRequest(segmentIds: [Uint8List(31)]));
    await bad(
      pb.GetBackupHealthRequest(segmentIds: [Uint8List(32), Uint8List(32)]),
    );
    await bad(
      pb.GetBackupHealthRequest(
        segmentIds: [
          for (var i = 0; i < 1001; i++)
            Uint8List(32)
              ..[0] = i
              ..[1] = i >> 8,
        ],
      ),
    );
    await bad(pb.GetBackupHealthRequest(auditedSinceUnixMs: Int64(-1)));
    // Граница позже запроса — время запроса, не ошибка.
    final future = await h.call(
      'GetBackupHealth',
      pb.GetBackupHealthRequest(auditedSinceUnixMs: Int64.MAX_VALUE),
      pb.GetBackupHealthResponse.fromBuffer,
      key: device,
    );
    expect(
      future.auditedSinceUnixMs,
      Int64(h.clock.now.millisecondsSinceEpoch),
    );
    // Ключ узла — не устройство.
    await expectLater(
      health(key: nodes.first),
      failsWith(pb.ErrorCode.ERROR_CODE_PERMISSION_DENIED),
    );
  });
}
