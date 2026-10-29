import 'package:coordinator/src/db/database.dart';
import 'package:coordinator/src/nodes/node_policy.dart';
import 'package:coordinator/src/repair/live_fragments.dart';
import 'package:coordinator/src/rpc/call_context.dart';
import 'package:coordinator/src/rpc/errors.dart';
import 'package:core/core.dart';
import 'package:fixnum/fixnum.dart';
import 'package:postgres/postgres.dart';
import 'package:protocol/protocol.dart' as pb;

/// Здоровье бэкапа для клиента (задачи 4.5.1, 4.5.2; protocol.md,
/// раздел 4.16): `GetBackupHealth`.
///
/// Ответ — только о сегментах учётной записи запроса и только числа:
/// сколько живых фрагментов (`segments.live`, `LiveFragments`), сколько из
/// них на узлах в сети и сколько прошли аудит с границы
/// (`fragments.audited_at`), идёт ли ремонт. Узлы, их адреса и чужие
/// учётные записи в ответ не попадают.
final class BackupHealthService {
  new(
    this._db, {
    NodePolicy nodes = const NodePolicy(),
    DateTime Function()? clock,
  }) : _onlineWindow = nodes.onlineWindow,
       _clock = clock ?? DateTime.now;

  final Database _db;
  final Duration _onlineWindow;
  final DateTime Function() _clock;

  /// Наибольшее число сегментов в запросе.
  static const maxSegments = 1000;

  /// Граница проверки по умолчанию: аудит за последние 30 суток.
  static const defaultAuditWindow = Duration(days: 30);

  Future<pb.GetBackupHealthResponse> health(
    CallContext context,
    pb.GetBackupHealthRequest request,
  ) async {
    final ids = request.segmentIds;
    if (ids.length > maxSegments) {
      throw _bad('segment_ids — не больше $maxSegments');
    }
    final seen = <String>{};
    for (final id in ids) {
      if (id.length != 32) throw _bad('segment_ids — по 32 байта');
      if (!seen.add(bytesToHex(id))) throw _bad('segment_ids с повторами');
    }
    if (request.auditedSinceUnixMs < 0) {
      throw _bad('audited_since_unix_ms не может быть отрицательным');
    }
    final now = _clock();
    final sinceMs = request.auditedSinceUnixMs;
    // Граница позже запроса — время запроса: проверенных фрагментов нет,
    // а DateTime не переполняется (находка фаззинга).
    final since = sinceMs == 0
        ? now.subtract(defaultAuditWindow)
        : sinceMs >= now.millisecondsSinceEpoch
        ? now
        : DateTime.fromMillisecondsSinceEpoch(sinceMs.toInt(), isUtc: true);
    final accountId = context.caller!.info!.accountId;
    final parameters = {
      'a': accountId,
      'since': since,
      'online': now.subtract(_onlineWindow),
    };
    return await _db.run((s) async {
      final summary = await s.execute(
        Sql.named('''
          WITH h AS (${_segmentsQuery(selected: false)})
          SELECT count(*),
                 count(*) FILTER (WHERE live >= n),
                 count(*) FILTER (WHERE live > repair_threshold AND live < n),
                 count(*) FILTER (WHERE live <= repair_threshold
                                    AND live >= k),
                 count(*) FILTER (WHERE live < k),
                 count(*) FILTER (WHERE repairing),
                 count(*) FILTER (WHERE online >= k),
                 coalesce(sum(live), 0)::int8,
                 coalesce(sum(audited), 0)::int8,
                 max(last_audit),
                 (SELECT fragment_bytes FROM accounts
                    WHERE account_id = @a:bytea)
            FROM h'''),
        parameters: parameters,
      );
      final [
        segments as int,
        healthy as int,
        reduced as int,
        atRisk as int,
        lost as int,
        repairing as int,
        readable as int,
        live as int,
        audited as int,
        last as DateTime?,
        bytes as int?,
      ] = summary.single;
      final response = pb.GetBackupHealthResponse(
        summary: pb.BackupHealthSummary(
          segments: Int64(segments),
          healthy: Int64(healthy),
          reduced: Int64(reduced),
          atRisk: Int64(atRisk),
          lost: Int64(lost),
          repairing: Int64(repairing),
          readableNow: Int64(readable),
          liveFragments: Int64(live),
          auditedFragments: Int64(audited),
          lastAuditUnixMs: _ms(last),
          fragmentBytes: Int64(bytes ?? 0),
        ),
        auditedSinceUnixMs: _ms(since),
      );
      if (ids.isEmpty) return response;
      final rows = await s.execute(
        Sql.named(_segmentsQuery(selected: true)),
        parameters: {...parameters, 'ids': ids},
      );
      final byId = {
        for (final row in rows) bytesToHex(row[0]! as List<int>): row,
      };
      for (final id in ids) {
        final row = byId[bytesToHex(id)];
        if (row == null) continue;
        final [
          _,
          k as int,
          n as int,
          t as int,
          live as int,
          online as int,
          audited as int,
          last as DateTime?,
          repairing as bool,
        ] = row;
        response.segments.add(
          pb.SegmentHealth(
            segmentId: id,
            k: k,
            n: n,
            repairThreshold: t,
            live: live,
            online: online,
            audited: audited,
            lastAuditUnixMs: _ms(last),
            repairing: repairing,
          ),
        );
      }
      return response;
    });
  }

  /// Сохранённые сегменты учётной записи `@a` ([selected] — только из
  /// `@ids`): число живых, живых на узлах в сети, живых с аудитом после
  /// `@since`, последний аудит и идёт ли ремонт.
  static String _segmentsQuery({required bool selected}) {
    String only(String table) =>
        selected ? 'AND $table.segment_id = ANY(@ids:_bytea)' : '';
    return '''
      SELECT g.segment_id, g.k, g.n, g.repair_threshold, g.live,
             coalesce(f.online, 0)::int4 AS online,
             coalesce(f.audited, 0)::int4 AS audited,
             f.last_audit,
             EXISTS (SELECT 1 FROM repair_jobs j
                       WHERE j.account_id = g.account_id
                         AND j.segment_id = g.segment_id
                         AND j.kind = 0 AND j.state IN (0, 1)) AS repairing
        FROM segments g
          LEFT JOIN (
            SELECT f.segment_id,
                   count(*) FILTER (WHERE ${LiveFragments.condition}
                     AND n.last_heartbeat_at >= @online:timestamptz) AS online,
                   count(*) FILTER (WHERE ${LiveFragments.condition}
                     AND f.audited_at >= @since:timestamptz) AS audited,
                   max(f.audited_at) AS last_audit
              FROM fragments f JOIN nodes n USING (node_id)
              WHERE f.account_id = @a:bytea ${only('f')}
              GROUP BY f.segment_id) f USING (segment_id)
        WHERE g.account_id = @a:bytea AND g.state <> 0
          ${only('g')}''';
  }

  static Int64 _ms(DateTime? t) =>
      t == null ? Int64.ZERO : Int64(t.millisecondsSinceEpoch);

  static RpcException _bad(String message) =>
      RpcException(pb.ErrorCode.ERROR_CODE_BAD_REQUEST, message);
}
