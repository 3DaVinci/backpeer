import 'dart:typed_data';

import 'package:coordinator/src/repair/live_fragments.dart';
import 'package:core/core.dart';
import 'package:postgres/postgres.dart';

/// Состояние задания ремонта (`repair_jobs.state`).
enum RepairJobState {
  /// Отправлено исполнителю, ждёт отчёта.
  running,

  /// Исполнитель отчитался; новые фрагменты проверяются.
  verifying,

  /// Завершено: хотя бы один новый фрагмент стал живым.
  done,

  /// Провалено (`reason`).
  failed,
}

/// Состояние нового фрагмента задания (`repair_targets.state`).
enum RepairTargetState {
  /// Ждёт отчёта исполнителя.
  pending,

  /// Загружен по отчёту, ждёт проверки аудитом.
  reported,

  /// Проверен и стал живым.
  verified,

  /// Не загружен или не прошёл проверку (`reason`).
  failed,
}

/// Записи заданий ремонта в базе (задачи 4.3.4, 4.3.5): место на узлах,
/// провал заданий и новых фрагментов, замена фрагмента сегмента.
///
/// Место на новых узлах занимается при создании задания (как при
/// `AllocateSegment`) и освобождается, если фрагмент не загружен или не
/// прошёл проверку. Когда новый фрагмент стал живым, место освобождается
/// на прежнем узле номера, если тот фрагмент был сохранён, а иначе
/// фрагмент впервые занимает место учётной записи.
abstract final class RepairJobs {
  /// Меняет выданное узлам [nodes] место на [delta] за каждый фрагмент.
  /// Узлы блокируются по возрастанию идентификатора `FOR NO KEY UPDATE`,
  /// как в `SegmentService`: без взаимоблокировок с размещением.
  static Future<void> addNodeBytes(
    TxSession tx,
    Iterable<List<int>> nodes,
    int delta,
  ) async {
    final hex = [for (final n in nodes) bytesToHex(n)]..sort();
    if (hex.isEmpty) return;
    await tx.execute(
      Sql.named('''
        SELECT 1 FROM nodes
          WHERE node_id IN (SELECT decode(h, 'hex') FROM unnest(@ids:_text) h)
          ORDER BY node_id FOR NO KEY UPDATE'''),
      parameters: {'ids': hex},
    );
    await tx.execute(
      Sql.named('''
        UPDATE nodes n SET assigned_bytes = greatest(n.assigned_bytes +
                                                     @d:int8 * c.cnt, 0)
          FROM (SELECT decode(h, 'hex') AS id, count(*) AS cnt
                  FROM unnest(@ids:_text) h GROUP BY h) c
          WHERE n.node_id = c.id'''),
      parameters: {'ids': hex, 'd': delta},
    );
  }

  /// Проваливает новые фрагменты задания [jobId] в состояниях `pending`
  /// и `reported` (или только номера [indexes]) с причиной [reason] и
  /// освобождает их место. Возвращает число проваленных.
  static Future<int> failTargets(
    TxSession tx,
    Uint8List jobId,
    String reason, {
    List<int>? indexes,
  }) async {
    final rows = await tx.execute(
      Sql.named('''
        UPDATE repair_targets t SET state = 3, reason = @r:text
          FROM repair_jobs j JOIN segments g USING (account_id, segment_id)
          WHERE t.job_id = @j:bytea AND j.job_id = t.job_id
            AND t.state IN (0, 1)
            AND (@all:boolean OR t.idx = ANY(@idx:_int4))
          RETURNING t.node_id, g.fragment_size'''),
      parameters: {
        'j': jobId,
        'r': reason,
        'all': indexes == null,
        'idx': indexes ?? const <int>[],
      },
    );
    if (rows.isEmpty) return 0;
    await addNodeBytes(tx, [
      for (final [node as List<int>, _] in rows) node,
    ], -(rows.first[1]! as int));
    return rows.length;
  }

  /// Проваливает задание [jobId] с причиной [reason]: новые фрагменты,
  /// ещё не ставшие живыми, — тоже; сегмент ждёт повтора до [retryAt].
  /// Уже завершённое задание не меняется. `false` — не было действующего.
  static Future<bool> failJob(
    TxSession tx,
    Uint8List jobId,
    String reason, {
    required DateTime now,
    required DateTime retryAt,
  }) async {
    final rows = await tx.execute(
      Sql.named('''
        UPDATE repair_jobs SET state = 3, reason = @r:text,
                               finished_at = @t:timestamptz
          WHERE job_id = @j:bytea AND state IN (0, 1)
          RETURNING account_id, segment_id'''),
      parameters: {'j': jobId, 'r': reason, 't': now},
    );
    if (rows.isEmpty) return false;
    await failTargets(tx, jobId, reason);
    final [account as List<int>, segment as List<int>] = rows.single;
    await tx.execute(
      Sql.named('''
        UPDATE segments SET repair_retry_at = @t:timestamptz
          WHERE account_id = @a:bytea AND segment_id = @g:bytea'''),
      parameters: {'a': account, 'g': segment, 't': retryAt},
    );
    return true;
  }

  /// Новый фрагмент номера [index] на узле [nodeId] проверен: номер
  /// сегмента переходит на этот узел, фрагмент сохранён и без отметок
  /// повреждения, место на прежнем узле освобождается, число живых
  /// пересчитывается. `false` — сегмента или номера уже нет (сегмент
  /// удалён).
  static Future<bool> acceptTarget(
    TxSession tx, {
    required Uint8List jobId,
    required Uint8List accountId,
    required Uint8List segmentId,
    required int index,
    required Uint8List nodeId,
    required DateTime now,
  }) async {
    // Порядок блокировок — как у SegmentService: учётная запись, затем
    // строки сегмента и узлы.
    await tx.execute(
      Sql.named(
        'SELECT 1 FROM accounts WHERE account_id = @a:bytea FOR UPDATE',
      ),
      parameters: {'a': accountId},
    );
    final rows = await tx.execute(
      Sql.named('''
        SELECT f.node_id, f.stored, g.fragment_size
          FROM fragments f JOIN segments g USING (account_id, segment_id)
          WHERE f.account_id = @a:bytea AND f.segment_id = @g:bytea
            AND f.idx = @i:int2
          FOR UPDATE OF f'''),
      parameters: {'a': accountId, 'g': segmentId, 'i': index},
    );
    if (rows.isEmpty) return false;
    final [old as List<int>, stored as bool, size as int] = rows.single;
    await tx.execute(
      Sql.named('''
        UPDATE fragments
          SET node_id = @n:bytea, stored = true, damaged_at = NULL,
              audit_failed_at = NULL
          WHERE account_id = @a:bytea AND segment_id = @g:bytea
            AND idx = @i:int2'''),
      parameters: {'a': accountId, 'g': segmentId, 'i': index, 'n': nodeId},
    );
    if (stored) {
      await addNodeBytes(tx, [old], -size);
    } else {
      // Фрагмент номера не был загружен клиентом: место учётной записи
      // занимается впервые.
      await tx.execute(
        Sql.named('''
          UPDATE accounts SET fragment_bytes = fragment_bytes + @s:int8
            WHERE account_id = @a:bytea'''),
        parameters: {'a': accountId, 's': size},
      );
    }
    await tx.execute(
      Sql.named('''
        UPDATE repair_targets SET state = 2
          WHERE job_id = @j:bytea AND idx = @i:int2'''),
      parameters: {'j': jobId, 'i': index},
    );
    await LiveFragments.recountSegment(tx, accountId, segmentId, now);
    return true;
  }

  /// Завершает задание, если все его новые фрагменты проверены или
  /// провалены: `done`, если хоть один стал живым, иначе `failed`
  /// (сегмент тогда ждёт повтора до [retryAt]). Возвращает новое
  /// состояние или `null`, если задание ещё идёт.
  static Future<RepairJobState?> finishIfDone(
    TxSession tx,
    Uint8List jobId, {
    required DateTime now,
    required DateTime retryAt,
  }) async {
    final rows = await tx.execute(
      Sql.named('''
        UPDATE repair_jobs j
          SET state = CASE WHEN c.verified > 0 THEN 2 ELSE 3 END,
              reason = CASE WHEN c.verified > 0 THEN j.reason
                            ELSE coalesce(j.reason, 'нет проверенных') END,
              finished_at = @t:timestamptz
          FROM (SELECT count(*) FILTER (WHERE state = 2) AS verified,
                       count(*) FILTER (WHERE state IN (0, 1)) AS open
                  FROM repair_targets WHERE job_id = @j:bytea) c
          WHERE j.job_id = @j:bytea AND j.state IN (0, 1) AND c.open = 0
          RETURNING j.state, j.account_id, j.segment_id'''),
      parameters: {'j': jobId, 't': now},
    );
    if (rows.isEmpty) return null;
    final [state as int, account as List<int>, segment as List<int>] =
        rows.single;
    if (state == RepairJobState.failed.index) {
      await tx.execute(
        Sql.named('''
          UPDATE segments SET repair_retry_at = @t:timestamptz
            WHERE account_id = @a:bytea AND segment_id = @g:bytea'''),
        parameters: {'a': account, 'g': segment, 't': retryAt},
      );
    }
    return RepairJobState.values[state];
  }

  /// Сегмент удаляется: место новых фрагментов его действующих заданий
  /// освобождается (сами задания удалит каскад).
  static Future<void> releaseSegment(
    TxSession tx,
    Uint8List accountId,
    Uint8List segmentId,
  ) async {
    final rows = await tx.execute(
      Sql.named('''
        SELECT t.node_id, g.fragment_size
          FROM repair_targets t
            JOIN repair_jobs j USING (job_id)
            JOIN segments g USING (account_id, segment_id)
          WHERE j.account_id = @a:bytea AND j.segment_id = @g:bytea
            AND t.state IN (0, 1)'''),
      parameters: {'a': accountId, 'g': segmentId},
    );
    if (rows.isEmpty) return;
    await addNodeBytes(tx, [
      for (final [node as List<int>, _] in rows) node,
    ], -(rows.first[1]! as int));
  }
}
