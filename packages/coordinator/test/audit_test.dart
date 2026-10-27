// Аудиты хранения: проверка ответа узла (4.1.1), планировщик (4.1.3),
// реакция на провал (4.1.4); protocol.md, раздел 4.13. Тесты с базой
// нужен FS_TEST_POSTGRES.

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:coordinator/coordinator.dart';
import 'package:core/core.dart';
import 'package:postgres/postgres.dart';
import 'package:protocol/protocol.dart' as pb;
import 'package:test/test.dart';

import 'support/db_harness.dart';
import 'support/postgres.dart';

/// Узлы в памяти вместо каналов команд: отвечают на аудит по своим
/// фрагментам, как `answerAudit` узла.
final class FakeNodes implements NodeCommands {
  new(this.crypto);

  final CryptoProvider crypto;
  final online = <String>{};
  final fragments = <String, Map<String, Fragment>>{};

  /// Не отвечают вовремя.
  final silent = <String>{};

  /// Канал закрывается до ответа.
  final dropping = <String>{};

  /// Отвечают соседним блоком.
  final lying = <String>{};
  int sent = 0;

  void add(Uint8List nodeId, Fragment f) =>
      (fragments[bytesToHex(nodeId)] ??= {})[bytesToHex(
            f.header.fragmentId(crypto),
          )] =
          f;

  void remove(Uint8List nodeId, Fragment f) => fragments[bytesToHex(nodeId)]
      ?.remove(bytesToHex(f.header.fragmentId(crypto)));

  @override
  bool isConnected(List<int> nodeId) => online.contains(bytesToHex(nodeId));

  @override
  Future<pb.NodeChannelMessage?> send(
    List<int> nodeId,
    pb.CoordinatorChannelMessage command,
  ) async {
    sent++;
    final node = bytesToHex(nodeId);
    if (silent.contains(node)) throw TimeoutException('нет ответа');
    if (dropping.contains(node)) return null;
    final a = command.audit;
    final f = fragments[node]?[bytesToHex(a.fragmentId)];
    if (f == null) {
      return pb.NodeChannelMessage(
        error: pb.Error(code: pb.ErrorCode.ERROR_CODE_NOT_FOUND),
      );
    }
    return pb.NodeChannelMessage(
      audit: prove(crypto, f, a.blockIndex, lie: lying.contains(node)),
    );
  }
}

pb.AuditReply prove(
  CryptoProvider crypto,
  Fragment f,
  int index, {
  bool lie = false,
}) {
  final count = merkleLeafCount(f.body.length);
  Uint8List block(int i) => Uint8List.sublistView(
    f.body,
    i * merkleBlockSize,
    min(f.body.length, (i + 1) * merkleBlockSize),
  );
  final leaves = [
    for (var i = 0; i < count; i++) merkleLeafHash(crypto, block(i)),
  ];
  return pb.AuditReply(
    block: block(lie ? (index + 1) % count : index),
    path: merkleAuditPath(crypto, leaves, index),
  );
}

/// Сегменты блоба 600 000 байт, k = 2, n = 4: тело фрагмента — 5 блоков.
List<Fragment> segmentFragments(CryptoProvider crypto, int seed) {
  final r = Random(seed);
  return encodeFragments(
    crypto,
    blob: Uint8List.fromList(List.generate(600000, (_) => r.nextInt(256))),
    segmentId: Uint8List.fromList(List.generate(32, (_) => r.nextInt(256))),
    k: 2,
    n: 4,
  );
}

void main() {
  late CryptoProvider crypto;
  setUpAll(() async => crypto = await SodiumCryptoProvider.load());

  group('checkAuditReply', () {
    late Fragment f;
    late AuditTarget target;
    setUpAll(() {
      f = segmentFragments(crypto, 1).first;
      target = AuditTarget(
        nodeId: Uint8List(32),
        fragmentId: f.header.fragmentId(crypto),
        bodyRoot: f.header.bodyRoot,
        fragmentSize: f.bytes.length,
        recheck: false,
      );
    });

    AuditOutcome check(int index, pb.NodeChannelMessage reply) =>
        checkAuditReply(crypto, target, index, reply);

    test('верный блок и путь, в том числе последний короткий блок', () {
      final count = merkleLeafCount(f.body.length);
      expect(count, 5);
      for (var i = 0; i < count; i++) {
        final r = pb.NodeChannelMessage(audit: prove(crypto, f, i));
        expect(check(i, r).passed, isTrue, reason: 'блок $i');
      }
    });

    test('чужой блок, обрезанный блок, лишний и длинный путь, ошибка', () {
      String? reason(pb.NodeChannelMessage r, [int index = 2]) =>
          check(index, r).reason;
      final good = prove(crypto, f, 2);
      expect(
        reason(pb.NodeChannelMessage(audit: prove(crypto, f, 2, lie: true))),
        'proof',
      );
      expect(
        reason(
          pb.NodeChannelMessage(
            audit: good.deepCopy()..block = good.block.sublist(1),
          ),
        ),
        'proof',
      );
      expect(
        reason(
          pb.NodeChannelMessage(
            audit: good.deepCopy()..path.add(Uint8List(32)),
          ),
        ),
        'proof',
      );
      expect(
        reason(
          pb.NodeChannelMessage(
            audit: good.deepCopy()
              ..path.addAll(List.filled(maxAuditPathLength, Uint8List(32))),
          ),
        ),
        'proof',
      );
      expect(reason(pb.NodeChannelMessage(audit: good), 3), 'proof');
      expect(reason(pb.NodeChannelMessage(audit: good), 5), 'proof');
      expect(
        reason(
          pb.NodeChannelMessage(
            error: pb.Error(code: pb.ErrorCode.ERROR_CODE_NOT_FOUND),
          ),
        ),
        'error:NOT_FOUND',
      );
      expect(
        reason(pb.NodeChannelMessage(done: pb.CommandDone())),
        'bad_reply',
      );
    });
  });

  if (testPostgresUrl == null) {
    test('аудиты с базой', () {}, skip: skipWithoutPostgres);
    return;
  }

  late DbHarness h;
  late FakeNodes nodes;
  late Uint8List owner;
  var policy = const AuditPolicy();

  AuditService service({int seed = 1}) => AuditService(
    h.db,
    crypto: crypto,
    policy: policy,
    clock: h.clock.call,
    random: Random(seed),
  )..channels = nodes;

  Future<Uint8List> addNode(int i, {Duration age = Duration.zero}) async {
    final id = Uint8List(32)
      ..[0] = 0x4E
      ..[1] = i;
    await h.db.run(
      (s) => s.execute(
        Sql.named(r'''
          INSERT INTO nodes (node_id, account_id, certificate, registered_at)
            VALUES (@n:bytea, @a:bytea, '\x00', @t:timestamptz)'''),
        parameters: {'n': id, 'a': owner, 't': h.clock.now.subtract(age)},
      ),
    );
    nodes.online.add(bytesToHex(id));
    return id;
  }

  /// Сохранённый сегмент, все фрагменты которого — на [node].
  Future<List<Fragment>> storeSegment(Uint8List node, int seed) async {
    final fragments = segmentFragments(crypto, seed);
    final header = fragments.first.header;
    await h.db.transaction((tx) async {
      await tx.execute(
        Sql.named('''
          INSERT INTO segments (account_id, segment_id, k, n,
                                repair_threshold, fragment_size, state,
                                allocated_at, committed_at)
            VALUES (@a:bytea, @g:bytea, 2, 4, 3, @size:int4, 1,
                    @t:timestamptz, @t:timestamptz)'''),
        parameters: {
          'a': owner,
          'g': header.segmentId,
          'size': fragments.first.bytes.length,
          't': h.clock.now,
        },
      );
      for (final f in fragments) {
        await tx.execute(
          Sql.named('''
            INSERT INTO fragments (account_id, segment_id, idx, fragment_id,
                                   body_root, node_id, stored)
              VALUES (@a:bytea, @g:bytea, @i:int2, @f:bytea, @r:bytea,
                      @n:bytea, true)'''),
          parameters: {
            'a': owner,
            'g': header.segmentId,
            'i': f.header.index,
            'f': f.header.fragmentId(crypto),
            'r': f.header.bodyRoot,
            'n': node,
          },
        );
        nodes.add(node, f);
      }
    });
    return fragments;
  }

  Future<List<ResultRow>> audits(Uint8List node) => h.db.run(
    (s) => s.execute(
      Sql.named('''
        SELECT passed, recheck, reason, fragment_id FROM audits
          WHERE node_id = @n:bytea ORDER BY id'''),
      parameters: {'n': node},
    ),
  );

  Future<ResultRow> nodeRow(Uint8List node) async => (await h.db.run(
    (s) => s.execute(
      Sql.named('''
        SELECT audit_next_at, audits_passed, audits_failed, excluded_at,
               excluded_reason, audit_window_failures, audit_latency_ms
          FROM nodes WHERE node_id = @n:bytea'''),
      parameters: {'n': node},
    ),
  )).single;

  Future<ResultRow> fragmentRow(Fragment f) async => (await h.db.run(
    (s) => s.execute(
      Sql.named('''
        SELECT audit_failed_at, damaged_at FROM fragments
          WHERE fragment_id = @f:bytea'''),
      parameters: {'f': f.header.fragmentId(crypto)},
    ),
  )).single;

  setUp(() async {
    policy = const AuditPolicy();
    h = await DbHarness.create();
    nodes = FakeNodes(crypto);
    owner = Uint8List(32)..[0] = 0xA0;
    await h.db.run(
      (s) => s.execute(
        Sql.named('INSERT INTO accounts (account_id) VALUES (@a:bytea)'),
        parameters: {'a': owner},
      ),
    );
  });
  tearDown(() => h.close());

  test('честный узел проходит аудит; следующий — через паузу нового узла '
      'со случайной долей', () async {
    final node = await addNode(1);
    await storeSegment(node, 10);
    final a = service();
    expect(await a.runOnce(), 1);
    final [passed as bool, recheck as bool, reason, _] = (await audits(node))
        .single;
    expect(passed, isTrue);
    expect(recheck, isFalse);
    expect(reason, isNull);
    final row = await nodeRow(node);
    expect(row[1], 1);
    expect(row[2], 0);
    expect(row[5], 0);
    expect(row[6], isA<double>(), reason: 'время ответа для репутации');
    final next = (row[0]! as DateTime).difference(h.clock.now);
    expect(next, greaterThanOrEqualTo(policy.newNodeInterval * 0.5));
    expect(next, lessThan(policy.newNodeInterval * 1.5));
    // Пока пауза не прошла, узел не проверяется.
    expect(await a.runOnce(), 0);
    h.clock.advance(policy.newNodeInterval * 1.5);
    expect(await a.runOnce(), 1);
  });

  test('старый узел проверяется реже нового', () async {
    final node = await addNode(1, age: const Duration(days: 30));
    await storeSegment(node, 11);
    await service().runOnce();
    final next = ((await nodeRow(node))[0]! as DateTime).difference(
      h.clock.now,
    );
    expect(next, greaterThanOrEqualTo(policy.interval * 0.5));
  });

  test('узел без канала и без фрагментов не проверяется', () async {
    final offline = await addNode(1);
    await storeSegment(offline, 12);
    nodes.online.remove(bytesToHex(offline));
    final empty = await addNode(2);
    final dropping = await addNode(3);
    await storeSegment(dropping, 13);
    nodes.dropping.add(bytesToHex(dropping));
    final a = service();
    expect(await a.runOnce(), 0);
    expect(nodes.sent, 1);
    for (final n in [offline, empty, dropping]) {
      expect(await audits(n), isEmpty);
      expect((await nodeRow(n))[0], isNotNull);
    }
    expect(
      ((await nodeRow(offline))[0]! as DateTime).difference(h.clock.now),
      policy.offlineRetry,
    );
    expect(await a.runOnce(), 0, reason: 'всем назначен следующий раз');
  });

  test('потерянный фрагмент: провал, повторная проверка, фрагмент потерян '
      'и больше не проверяется', () async {
    final node = await addNode(1);
    // Узел потерял все фрагменты сегмента.
    final segment = await storeSegment(node, 14);
    for (final f in segment) {
      nodes.remove(node, f);
    }
    final a = service(seed: 3);
    await a.runOnce();
    final [passed as bool, _, reason, fid as List<int>] = (await audits(node))
        .single;
    expect(passed, isFalse);
    expect(reason, 'error:NOT_FOUND');
    final failed = segment.firstWhere(
      (f) => bytesToHex(f.header.fragmentId(crypto)) == bytesToHex(fid),
    );
    expect((await fragmentRow(failed))[0], isNotNull);
    expect(
      ((await nodeRow(node))[0]! as DateTime).difference(h.clock.now),
      policy.recheckDelay,
    );
    h.clock.advance(policy.recheckDelay);
    await a.runOnce();
    final second = (await audits(node)).last;
    expect(second[0], isFalse);
    expect(second[1], isTrue, reason: 'повторная проверка того же фрагмента');
    expect(bytesToHex(second[3]! as List<int>), bytesToHex(fid));
    final row = await fragmentRow(failed);
    expect(row[0], isNull);
    expect(row[1], isNotNull, reason: 'фрагмент потерян');
    expect((await nodeRow(node))[2], 2);
    expect((await nodeRow(node))[3], isNull, reason: 'два провала из окна 20');
    expect((await nodeRow(node))[5], 2, reason: 'провалы в окне — репутация');
    expect((await nodeRow(node))[6], isNull, reason: 'время — по пройденным');
    final before = (await audits(node)).length;
    for (var i = 0; i < 6; i++) {
      h.clock.advance(const Duration(hours: 2));
      await a.runOnce();
    }
    final later = (await audits(node)).skip(before).toList();
    expect(later, isNotEmpty);
    expect(
      later.map((r) => bytesToHex(r[3]! as List<int>)),
      isNot(contains(bytesToHex(fid))),
    );
  });

  test(
    'случайный сбой: повторная проверка проходит, отметка снимается',
    () async {
      final node = await addNode(1);
      final f = (await storeSegment(node, 16)).first;
      nodes.silent.add(bytesToHex(node));
      final a = service();
      await a.runOnce();
      expect((await audits(node)).single[2], 'timeout');
      nodes.silent.clear();
      h.clock.advance(policy.recheckDelay);
      await a.runOnce();
      final last = (await audits(node)).last;
      expect(last[0], isTrue);
      expect(last[1], isTrue);
      final failedId = bytesToHex((await audits(node)).first[3]! as List<int>);
      expect(bytesToHex(last[3]! as List<int>), failedId);
      for (final g in [f, ...nodes.fragments[bytesToHex(node)]!.values]) {
        final row = await fragmentRow(g);
        expect(row[0], isNull);
        expect(row[1], isNull);
      }
    },
  );

  test('неверный блок — провал proof', () async {
    final node = await addNode(1);
    await storeSegment(node, 17);
    nodes.lying.add(bytesToHex(node));
    await service().runOnce();
    expect((await audits(node)).single[2], 'proof');
  });

  test('потолок аудитов за проход', () async {
    policy = const AuditPolicy(maxPerSecond: 2, tick: Duration(seconds: 1));
    for (var i = 0; i < 5; i++) {
      await storeSegment(await addNode(i), 20 + i);
    }
    final a = service();
    expect(await a.runOnce(), 2);
    expect(await a.runOnce(), 2);
    expect(await a.runOnce(), 1);
    expect(await a.runOnce(), 0);
  });

  test('узел, удаливший половину фрагментов, исключается из размещения за '
      'двое суток; честный — нет, его фрагменты целы', () async {
    const age = Duration(days: 30);
    final cheat = await addNode(1, age: age);
    final honest = await addNode(2, age: age);
    final r = Random(5);
    for (var s = 0; s < 10; s++) {
      for (final f in await storeSegment(cheat, 100 + s)) {
        if (r.nextBool()) nodes.remove(cheat, f);
      }
      await storeSegment(honest, 200 + s);
    }
    final a = service(seed: 7);
    final start = h.clock.now;
    DateTime? excludedAt;
    while (h.clock.now.difference(start) < const Duration(days: 2)) {
      await a.runOnce();
      if ((await nodeRow(cheat))[3] case final DateTime t) {
        excludedAt = t;
        break;
      }
      h.clock.advance(const Duration(minutes: 5));
    }
    expect(excludedAt, isNotNull, reason: 'не исключён за двое суток');
    final row = await nodeRow(cheat);
    expect(row[4], startsWith('аудит: '));
    printOnFailure('исключён через ${excludedAt!.difference(start)}');
    final honestRow = await nodeRow(honest);
    expect(honestRow[3], isNull);
    expect(honestRow[2], 0);
    final damaged = await h.db.run(
      (s) => s.execute(
        Sql.named('''
          SELECT count(*) FROM fragments
            WHERE node_id = @n:bytea AND damaged_at IS NOT NULL'''),
        parameters: {'n': honest},
      ),
    );
    expect(damaged.single.single, 0);
  });

  test('журнал старше срока хранения удаляется', () async {
    policy = const AuditPolicy(retention: Duration(days: 1));
    final node = await addNode(1);
    await storeSegment(node, 30);
    final a = service();
    await a.runOnce();
    expect(await audits(node), hasLength(1));
    h.clock.advance(const Duration(days: 2));
    await a.runOnce();
    expect(await audits(node), hasLength(1), reason: 'старая запись удалена');
  });
}
