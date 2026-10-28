import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:coordinator/src/db/database.dart';
import 'package:coordinator/src/log.dart';
import 'package:coordinator/src/repair/live_fragments.dart';
import 'package:core/core.dart';
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';

/// Настройки ремонта (`repair.*`, `docs/ops/coordinator.md`).
final class RepairPolicy {
  const new({
    this.enabled = true,
    this.offline = const Duration(hours: 72),
    this.lazyMargin = 0,
    this.lazyDelay = const Duration(hours: 12),
    this.maxJobs = 16,
    this.maxBytesPerHour = 50 * 1000 * 1000 * 1000,
    this.retryDelay = const Duration(minutes: 10),
    this.tick = const Duration(seconds: 30),
  });

  final bool enabled;

  /// Узел не в сети дольше — потерян, его фрагменты не живые
  /// (durability.md, раздел 2: 72 ч ожидания и сутки на ремонт — окно
  /// ремонта модели в 4 суток).
  final Duration offline;

  /// Ленивый ремонт (durability.md, раздел 5): сегмент, у которого живых
  /// не меньше `t − lazyMargin` (по умолчанию ровно t — запас t − k
  /// фрагментов), ремонтируется не раньше [lazyDelay] после попадания в
  /// очередь: потерянный узел может вернуться, и ремонт не понадобится.
  /// [lazyDelay] = 0 — без ленивого ремонта.
  final int lazyMargin;
  final Duration lazyDelay;

  /// Заданий одновременно на координатор.
  final int maxJobs;

  /// Предел трафика ремонта по сети: сумма оценок новых заданий за
  /// последний час (`planned_bytes`: k фрагментов скачать и новые
  /// разослать). Защищает исходящие каналы хранителей при массовом уходе
  /// узлов: ремонты встают в очередь по приоритету.
  final int maxBytesPerHour;

  /// Через сколько снова пробовать сегмент, задание для которого не
  /// удалось создать или провалилось.
  final Duration retryDelay;

  /// Как часто планировщик ищет работу.
  final Duration tick;
}

/// Сегмент в очереди ремонта.
final class RepairCandidate {
  const new({
    required this.accountId,
    required this.segmentId,
    required this.k,
    required this.n,
    required this.threshold,
    required this.fragmentSize,
    required this.live,
    required this.since,
  });

  final Uint8List accountId;
  final Uint8List segmentId;
  final int k;
  final int n;
  final int threshold;
  final int fragmentSize;

  /// Живых фрагментов.
  final int live;

  /// С какого времени в очереди.
  final DateTime since;
}

/// Ремонт сегментов (группа 4.3; protocol.md, раздел 4.14).
///
/// **Потерянные узлы.** Раз в [RepairPolicy.tick] узлы без heartbeat
/// дольше [RepairPolicy.offline] отмечаются потерянными (`lost_at`), и
/// число живых фрагментов их сегментов пересчитывается
/// ([LiveFragments]); heartbeat вернувшегося узла снимает отметку
/// (`NodeService`).
///
/// **Очередь** ([queue]) — сегменты с живыми не больше порога t, сначала
/// с меньшим числом живых, при равенстве — дольше ждущие. Сегменты с
/// запасом ждут [RepairPolicy.lazyDelay] (ленивый ремонт). Новые задания
/// не начинаются сверх [RepairPolicy.maxJobs] одновременно и сверх
/// [RepairPolicy.maxBytesPerHour] оценённого трафика за час ([budget]).
final class RepairService {
  new(
    this._db, {
    this.policy = const RepairPolicy(),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Database _db;
  final RepairPolicy policy;
  final DateTime Function() _clock;

  static final _log = Logger('repair');

  /// Узлов, отмечаемых потерянными за проход: каждый — своя транзакция.
  static const _lostBatch = 100;

  Timer? _timer;
  Future<void>? _round;
  bool _closed = false;

  /// Запускает планировщик, если ремонт включён.
  void start() {
    if (!policy.enabled || _timer != null || _closed) return;
    _timer = Timer.periodic(policy.tick, (_) {
      if (_round != null) return;
      _round = runOnce()
          .catchError((Object e, StackTrace stack) {
            _log.severe(const LogEvent('repair_round_failed'), e, stack);
          })
          .whenComplete(() => _round = null);
    });
  }

  Future<void> close() async {
    _closed = true;
    _timer?.cancel();
    _timer = null;
    await _round;
  }

  /// Один проход планировщика.
  Future<void> runOnce() async {
    await markLost();
  }

  /// Сегменты, которым пора в ремонт, по приоритету: живых не больше
  /// порога, нет действующего задания, не ждут повтора, ленивые — после
  /// [RepairPolicy.lazyDelay]. Порядок — по индексу `segments_live`.
  Future<List<RepairCandidate>> queue({int limit = 100}) async {
    final now = _clock();
    final rows = await _db.run(
      (s) => s.execute(
        Sql.named('''
          SELECT g.account_id, g.segment_id, g.k, g.n, g.repair_threshold,
                 g.fragment_size, g.live, g.repair_since
            FROM segments g
            WHERE g.state = 2
              AND (g.repair_retry_at IS NULL
                   OR g.repair_retry_at <= @now:timestamptz)
              AND (g.live < g.repair_threshold - @margin:int4
                   OR g.repair_since <= @lazy:timestamptz)
              AND NOT EXISTS (
                SELECT 1 FROM repair_jobs j
                  WHERE j.account_id = g.account_id
                    AND j.segment_id = g.segment_id AND j.state IN (0, 1))
            ORDER BY g.live, g.repair_since
            LIMIT @limit:int4'''),
        parameters: {
          'now': now,
          'margin': policy.lazyMargin,
          'lazy': now.subtract(policy.lazyDelay),
          'limit': limit,
        },
      ),
    );
    return [
      for (final [
            account as List<int>,
            segment as List<int>,
            k as int,
            n as int,
            t as int,
            size as int,
            live as int,
            since as DateTime,
          ]
          in rows)
        RepairCandidate(
          accountId: Uint8List.fromList(account),
          segmentId: Uint8List.fromList(segment),
          k: k,
          n: n,
          threshold: t,
          fragmentSize: size,
          live: live,
          since: since,
        ),
    ];
  }

  /// Сколько заданий и байт трафика можно начать сейчас: остаток
  /// [RepairPolicy.maxJobs] и [RepairPolicy.maxBytesPerHour].
  Future<({int jobs, int bytes})> budget() async {
    final now = _clock();
    final [active as int, recent as int] = (await _db.run(
      (s) => s.execute(
        Sql.named('''
          SELECT (SELECT count(*) FROM repair_jobs WHERE state IN (0, 1)),
                 (SELECT coalesce(sum(planned_bytes), 0)::int8
                    FROM repair_jobs
                    WHERE created_at > @h:timestamptz)'''),
        parameters: {'h': now.subtract(const Duration(hours: 1))},
      ),
    )).single;
    return (
      jobs: max(0, policy.maxJobs - active),
      bytes: max(0, policy.maxBytesPerHour - recent),
    );
  }

  /// Оценка трафика ремонта сегмента: скачать k фрагментов и разослать
  /// [targets] новых (durability.md, раздел 2).
  static int plannedBytes(int k, int targets, int fragmentSize) =>
      (k + targets) * fragmentSize;

  /// Отмечает потерянными узлы без heartbeat дольше
  /// [RepairPolicy.offline] и пересчитывает их сегменты. Возвращает число
  /// отмеченных узлов.
  Future<int> markLost() async {
    final now = _clock();
    final cutoff = now.subtract(policy.offline);
    final rows = await _db.run(
      (s) => s.execute(
        Sql.named('''
          SELECT node_id FROM nodes
            WHERE removed_at IS NULL AND lost_at IS NULL
              AND last_heartbeat_at < @c:timestamptz
            ORDER BY last_heartbeat_at
            LIMIT @l:int4'''),
        parameters: {'c': cutoff, 'l': _lostBatch},
      ),
    );
    var marked = 0;
    for (final [id as List<int>] in rows) {
      final nodeId = Uint8List.fromList(id);
      final segments = await _db.transaction((tx) async {
        // Условие повторяется: узел мог прислать heartbeat после выборки.
        final updated = await tx.execute(
          Sql.named('''
            UPDATE nodes SET lost_at = @t:timestamptz
              WHERE node_id = @n:bytea AND lost_at IS NULL
                AND last_heartbeat_at < @c:timestamptz
              RETURNING 1'''),
          parameters: {'n': nodeId, 't': now, 'c': cutoff},
        );
        if (updated.isEmpty) return null;
        return await LiveFragments.recountNode(tx, nodeId, now);
      });
      if (segments == null) continue;
      marked++;
      _log.warning(
        LogEvent('node_lost', {
          'node_id': bytesToHex(nodeId),
          'segments': segments,
        }),
      );
    }
    return marked;
  }
}
