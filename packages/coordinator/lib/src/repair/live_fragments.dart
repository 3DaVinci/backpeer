import 'package:postgres/postgres.dart';

/// Учёт живых фрагментов сегментов (задача 4.3.1; protocol.md,
/// раздел 4.14).
///
/// Фрагмент живой, если он сохранён, не отмечен повреждённым (отчёт узла
/// `ReportDamagedFragments` или второй провал аудита) и лежит на
/// неудалённом узле, который не потерян — был в сети не позже
/// `repair.offline_hours` назад (`nodes.lost_at`, durability.md,
/// раздел 2). Число живых — `segments.live`; сегмент, у которого их не
/// больше порога ремонта t, стоит в очереди ремонта: состояние 2 и
/// `repair_since` — с какого времени.
///
/// Число пересчитывается по событиям, каждый раз только для затронутых
/// сегментов: подтверждение сегмента, повреждение фрагмента, потеря и
/// возвращение узла, завершённый ремонт. Полного обхода базы нет: сегменты
/// узла находятся по индексу `fragments_node`, фрагменты сегмента — по
/// первичному ключу.
abstract final class LiveFragments {
  /// Условие «фрагмент `f` на узле `n` живой» для SQL.
  static const condition =
      'f.stored AND f.damaged_at IS NULL AND n.removed_at IS NULL '
      'AND n.lost_at IS NULL';

  /// Пересчитывает сегменты, которые возвращает [scope] — подзапрос с
  /// `account_id, segment_id` и параметрами [parameters] (имена — без
  /// `now`). Неподтверждённые сегменты не меняются. Возвращает число
  /// живых и порог каждого пересчитанного сегмента.
  static Future<List<({int live, int threshold})>> recount(
    TxSession tx, {
    required String scope,
    required Map<String, Object?> parameters,
    required DateTime now,
  }) async {
    final rows = await tx.execute(
      Sql.named('''
        WITH scope AS ($scope),
        c AS (
          SELECT f.account_id, f.segment_id,
                 count(*) FILTER (WHERE $condition) AS live
            FROM fragments f JOIN nodes n USING (node_id)
            WHERE (f.account_id, f.segment_id) IN
              (SELECT account_id, segment_id FROM scope)
            GROUP BY f.account_id, f.segment_id)
        UPDATE segments g
          SET live = c.live,
              state = CASE WHEN c.live <= g.repair_threshold THEN 2 ELSE 1 END,
              repair_since = CASE WHEN c.live <= g.repair_threshold
                                  THEN coalesce(g.repair_since,
                                                @now:timestamptz) END
          FROM c
          WHERE g.account_id = c.account_id AND g.segment_id = c.segment_id
            AND g.state <> 0
          RETURNING g.live, g.repair_threshold'''),
      parameters: {...parameters, 'now': now},
    );
    return [
      for (final [live as int, threshold as int] in rows)
        (live: live, threshold: threshold),
    ];
  }

  /// Пересчитывает сегмент [segmentId] учётной записи [accountId].
  static Future<({int live, int threshold})?> recountSegment(
    TxSession tx,
    List<int> accountId,
    List<int> segmentId,
    DateTime now,
  ) async {
    final rows = await recount(
      tx,
      scope: 'SELECT @a:bytea AS account_id, @g:bytea AS segment_id',
      parameters: {'a': accountId, 'g': segmentId},
      now: now,
    );
    return rows.isEmpty ? null : rows.single;
  }

  /// Пересчитывает сегменты, у которых есть фрагменты на узле [nodeId].
  static Future<int> recountNode(
    TxSession tx,
    List<int> nodeId,
    DateTime now,
  ) async => (await recount(
    tx,
    scope:
        'SELECT DISTINCT account_id, segment_id FROM fragments '
        'WHERE node_id = @node:bytea',
    parameters: {'node': nodeId},
    now: now,
  )).length;
}
