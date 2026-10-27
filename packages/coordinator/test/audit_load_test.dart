// Нагрузка планировщика аудитов на базу (задача 4.1.3): 1000 узлов и
// 1 млн фрагментов, каждый узел проверяется один раз. Нужен
// FS_TEST_POSTGRES; размер — FS_AUDIT_LOAD_NODES и
// FS_AUDIT_LOAD_FRAGMENTS_PER_NODE (по умолчанию 1000 и 1000). Итоги —
// docs/benchmarks.md, раздел 4.1.3.

import 'dart:io';
import 'dart:typed_data';

import 'package:coordinator/coordinator.dart';
import 'package:core/core.dart';
import 'package:postgres/postgres.dart';
import 'package:protocol/protocol.dart' as pb;
import 'package:test/test.dart';

import 'support/db_harness.dart';
import 'support/postgres.dart';

/// Все фрагменты — с одним телом из одного блока: узел отвечает им же.
final class _Echo implements NodeCommands {
  new(this.block);

  final Uint8List block;
  int sent = 0;

  @override
  bool isConnected(List<int> nodeId) => true;

  @override
  Future<pb.NodeChannelMessage?> send(
    List<int> nodeId,
    pb.CoordinatorChannelMessage command,
  ) async {
    sent++;
    return pb.NodeChannelMessage(audit: pb.AuditReply(block: block));
  }
}

void main() {
  if (testPostgresUrl == null) {
    test('нагрузка аудитов', () {}, skip: skipWithoutPostgres);
    return;
  }
  final env = Platform.environment;
  final nodeCount = int.parse(env['FS_AUDIT_LOAD_NODES'] ?? '1000');
  final perNode = int.parse(env['FS_AUDIT_LOAD_FRAGMENTS_PER_NODE'] ?? '1000');

  test('$nodeCount узлов, ${nodeCount * perNode} фрагментов: проход по всем '
      'узлам, выбор фрагмента по индексу', () async {
    final h = await DbHarness.create();
    addTearDown(h.close);
    final crypto = h.crypto;
    final block = Uint8List.fromList(List.generate(64, (i) => i));
    final root = merkleLeafHash(crypto, block);
    final fill = Stopwatch()..start();
    // n = 20 фрагментов на сегмент, фрагменты сегмента — на соседних
    // узлах; fragment_id — псевдослучайные 32 байта.
    final segments = nodeCount * perNode ~/ 20;
    await h.db.transaction((tx) async {
      await tx.execute(
        Sql.named('INSERT INTO accounts (account_id) VALUES (@a:bytea)'),
        parameters: {'a': Uint8List(32)..fillRange(0, 32, 0xA0)},
      );
      await tx.execute(
        Sql.named(r'''
          INSERT INTO nodes (node_id, account_id, certificate, registered_at)
            SELECT decode(lpad(to_hex(i), 64, '0'), 'hex'),
                   decode(repeat('a0', 32), 'hex'), '\x00',
                   @t:timestamptz - interval '30 days'
              FROM generate_series(0, @nodes:int4 - 1) i'''),
        parameters: {'nodes': nodeCount, 't': h.clock.now},
      );
    });
    // Пачками по 100 000 фрагментов: запрос на миллион строк не
    // укладывается в срок запроса пула.
    const step = 5000;
    for (var from = 0; from < segments; from += step) {
      final to = from + step < segments ? from + step : segments;
      await h.db.transaction((tx) async {
        await tx.execute(
          Sql.named('''
            INSERT INTO segments (account_id, segment_id, k, n,
                                  repair_threshold, fragment_size, state,
                                  allocated_at, committed_at)
              SELECT decode(repeat('a0', 32), 'hex'),
                     decode(md5('g' || s) || md5('h' || s), 'hex'),
                     10, 20, 16, 160, 1, @t:timestamptz, @t:timestamptz
                FROM generate_series(@from:int4, @to:int4 - 1) s'''),
          parameters: {'from': from, 'to': to, 't': h.clock.now},
        );
        await tx.execute(
          Sql.named('''
            INSERT INTO fragments (account_id, segment_id, idx, fragment_id,
                                   body_root, node_id, stored)
              SELECT decode(repeat('a0', 32), 'hex'),
                     decode(md5('g' || s) || md5('h' || s), 'hex'), i,
                     decode(md5('f' || s || '.' || i)
                            || md5('e' || s || '.' || i), 'hex'),
                     @root:bytea,
                     decode(lpad(to_hex((s * 20 + i) % @nodes:int4), 64,
                                 '0'), 'hex'),
                     true
                FROM generate_series(@from:int4, @to:int4 - 1) s,
                     generate_series(0, 19) i'''),
          parameters: {
            'from': from,
            'to': to,
            'nodes': nodeCount,
            'root': root,
          },
        );
      });
    }
    await h.db.run((s) => s.execute('ANALYZE'));
    fill.stop();

    final plan = await h.db.run(
      (s) => s.execute(
        Sql.named('''
            EXPLAIN SELECT f.fragment_id, f.body_root, g.fragment_size
              FROM fragments f JOIN segments g USING (account_id, segment_id)
              WHERE f.node_id = @n:bytea AND f.stored
                AND f.damaged_at IS NULL AND f.fragment_id >= @r:bytea
              ORDER BY f.fragment_id LIMIT 1'''),
        parameters: {'n': Uint8List(32), 'r': crypto.randomBytes(32)},
      ),
    );
    final planText = plan.map((r) => r.single).join('\n');
    expect(planText, contains('fragments_audit'), reason: planText);

    final echo = _Echo(block);
    final audits = AuditService(
      h.db,
      crypto: crypto,
      policy: AuditPolicy(
        maxPerSecond: nodeCount,
        tick: const Duration(seconds: 1),
      ),
      clock: h.clock.call,
    )..channels = echo;
    final run = Stopwatch()..start();
    final done = await audits.runOnce();
    run.stop();
    expect(done, nodeCount);
    final stats = await h.db.run(
      (s) => s.execute(
        'SELECT count(*) FILTER (WHERE passed), count(*) FROM audits',
      ),
    );
    expect(stats.single[0], nodeCount, reason: 'все аудиты пройдены');

    // Время соединения с базой на аудит — не больше времени прохода,
    // умноженного на размер пула, делённого на число аудитов (каналы в
    // тесте отвечают сразу). Нагрузка при настройках по умолчанию: узел
    // старше недели — раз в 6 часов в среднем.
    const policy = AuditPolicy();
    final pool = h.testDb.config.maxConnections;
    final dbMs = run.elapsedMilliseconds * pool / done;
    final perSecond = nodeCount / policy.interval.inSeconds;
    final load = perSecond * dbMs / 1000;
    // ignore: avoid_print — итог замера для docs/benchmarks.md.
    print(
      'заполнение ${fill.elapsed.inSeconds} с; $done аудитов за '
      '${run.elapsedMilliseconds} мс, пул $pool соединений: не больше '
      '${dbMs.toStringAsFixed(1)} мс соединения на аудит; при настройках по '
      'умолчанию ${perSecond.toStringAsFixed(3)} аудита/с — '
      '${(load * 100).toStringAsFixed(2)} % одного соединения с базой',
    );
    // Проход по всей сети укладывается в минуту, а при настройках по
    // умолчанию аудиты занимают меньше 1 % одного соединения с базой.
    expect(run.elapsed, lessThan(const Duration(minutes: 1)));
    expect(load, lessThan(0.01));
  }, timeout: const Timeout(Duration(minutes: 10)));
}
