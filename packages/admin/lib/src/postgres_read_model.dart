import 'dart:math';
import 'dart:typed_data';

import 'package:admin/src/read_model.dart';
import 'package:coordinator/coordinator.dart'
    show AdminService, Database, EconomyPolicy, Reputation, ReputationInput;
import 'package:core/core.dart' show bytesToHex, hexToBytes;
import 'package:postgres/postgres.dart';

/// Чтение метаданных координатора под ролью только для чтения.
///
/// Запросы не меняют базу: панель ничего не блокирует, не отзывает и не
/// исключает — это по-прежнему `coordinator admin` с причиной и журналом.
/// Секреты (KeyBundle, `auth_verifier`, сертификаты, блобы) не читаются:
/// у роли нет на них прав, а модель угроз К-2 остаётся в силе.
final class PostgresReadModel implements AdminReadModel {
  new(
    this._db, {
    required this.onlineWindow,
    required this.probation,
    this.economyPolicy = const EconomyPolicy(),
    this.readOnlyRole = '',
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Database _db;
  final Duration onlineWindow;
  final Duration probation;
  final EconomyPolicy economyPolicy;

  /// Роль только для чтения, членство в которой проверено при старте.
  final String readOnlyRole;

  final DateTime Function() _clock;

  AdminService get _admin => AdminService(
    _db,
    onlineWindow: onlineWindow,
    probation: probation,
    clock: _clock,
  );

  @override
  Future<bool> ping() => _db.ping();

  @override
  Future<Map<String, Object?>> overview() async {
    final service = _admin;
    final stats = _normaliseSegments(await service.stats());
    final revenue = await _db.run((s) async {
      final now = _clock().toUtc();
      final since = now.subtract(const Duration(hours: 24));
      final graceStart = now.subtract(Duration(days: economyPolicy.graceDays));
      final [
        balance as int,
        negative as int,
        blocked as int,
      ] = (await s.execute(
        Sql.named('''
          SELECT coalesce(sum(balance_mc), 0)::int8,
                 count(*) FILTER (WHERE balance_mc < 0),
                 count(*) FILTER (WHERE balance_mc < 0
                                    AND negative_since IS NOT NULL
                                    AND negative_since <= @g:timestamptz)
            FROM credit_accounts'''),
        parameters: {'g': graceStart},
      )).single;
      final [earned as int, spent as int] = (await s.execute('''
        SELECT coalesce(sum(amount_mc) FILTER (WHERE amount_mc > 0), 0)::int8,
               coalesce(sum(-amount_mc) FILTER (WHERE amount_mc < 0), 0)::int8
          FROM credit_ledger''')).single;
      final [
        nodesFree as int,
        nodesUsed as int,
        nodesAssigned as int,
      ] = (await s.execute('''
            SELECT coalesce(sum(greatest(0, capacity_bytes
                       - greatest(used_bytes, assigned_bytes))), 0)::int8,
                   coalesce(sum(used_bytes), 0)::int8,
                   coalesce(sum(assigned_bytes), 0)::int8
              FROM nodes WHERE removed_at IS NULL''')).single;
      final [dataBytes as int] = (await s.execute('''
        SELECT coalesce(sum(k::int8 * (fragment_size - 96))
                        FILTER (WHERE state <> 0), 0)::int8
          FROM segments''')).single;
      final [
        storedFragments as int,
        damagedFragments as int,
      ] = (await s.execute('''
        SELECT count(*) FILTER (WHERE stored),
               count(*) FILTER (WHERE damaged_at IS NOT NULL)
          FROM fragments''')).single;
      final [objectsCount as int] = (await s.execute(
        'SELECT count(object_id) FROM objects',
      )).single;
      final [
        auditPassed as int,
        auditFailed as int,
        auditLatency as double?,
        lastAudit as DateTime?,
      ] = (await s.execute(
        Sql.named('''
          SELECT count(*) FILTER (WHERE passed),
                 count(*) FILTER (WHERE NOT passed),
                 avg(latency_ms) FILTER (WHERE passed),
                 max(at)
            FROM audits WHERE at >= @t:timestamptz'''),
        parameters: {'t': since},
      )).single;
      final [repairRunning as int, repairQueue as int, minLive as int?] =
          (await s.execute('''
            SELECT (SELECT count(*) FROM repair_jobs WHERE state IN (0, 1)),
                   (SELECT count(*) FROM segments WHERE state = 2),
                   (SELECT min(live) FROM segments WHERE state <> 0)'''))
              .single;
      final traffic = await s.execute(
        Sql.named('''
          SELECT method, sum(bytes)::int8, sum(connections)::int8,
                 count(DISTINCT account_id)
            FROM traffic_daily WHERE day >= @d:date
            GROUP BY method ORDER BY method'''),
        parameters: {'d': _dateValue(now.subtract(const Duration(hours: 24)))},
      );
      final versions = await s.execute('''
        SELECT software, count(*) FROM nodes
          WHERE removed_at IS NULL AND software <> ''
          GROUP BY software ORDER BY count(*) DESC LIMIT 12''');
      final countries = await s.execute('''
        SELECT country, count(*) FROM nodes
          WHERE removed_at IS NULL AND country IS NOT NULL
          GROUP BY country ORDER BY count(*) DESC LIMIT 12''');
      final registrations = await s.execute(
        Sql.named('''
          SELECT to_char(created_at, 'YYYY-MM-DD'), count(*)
            FROM admin_accounts WHERE created_at >= @t:timestamptz
            GROUP BY 1 ORDER BY 1'''),
        parameters: {'t': now.subtract(const Duration(days: 14))},
      );
      final nodeRegistrations = await s.execute(
        Sql.named('''
          SELECT to_char(registered_at, 'YYYY-MM-DD'), count(*)
            FROM nodes WHERE registered_at >= @t:timestamptz
            GROUP BY 1 ORDER BY 1'''),
        parameters: {'t': now.subtract(const Duration(days: 14))},
      );
      final journal = await service.audit(limit: 6);
      return {
        'generatedAt': now.toIso8601String(),
        'stats': stats,
        'dataBytes': dataBytes,
        'objectsCount': objectsCount,
        'storedFragments': storedFragments,
        'damagedFragments': damagedFragments,
        'nodesFreeBytes': nodesFree,
        'nodesUsedBytes': nodesUsed,
        'nodesAssignedBytes': nodesAssigned,
        'economy': {
          'balanceMc': balance,
          'negativeAccounts': negative,
          'blockedAccounts': blocked,
          'earnedMc': earned,
          'spentMc': spent,
          'graceDays': economyPolicy.graceDays,
          'starterCredits': economyPolicy.starterCredits,
        },
        'audits': {
          'passed24h': auditPassed,
          'failed24h': auditFailed,
          'latencyMs': auditLatency?.round(),
          'lastAt': _iso(lastAudit),
        },
        'repair': {
          'running': repairRunning,
          'queue': repairQueue,
          'minLive': minLive,
        },
        'traffic': {
          for (final [
                method as int,
                bytes as int,
                connections as int,
                accounts as int,
              ]
              in traffic)
            _method(method): {
              'bytes': bytes,
              'connections': connections,
              'accounts': accounts,
            },
        },
        'versions': [
          for (final [name as String, count as int] in versions)
            {'name': name, 'count': count},
        ],
        'countries': [
          for (final [code as String, count as int] in countries)
            {'code': code, 'count': count},
        ],
        'activity': {
          'accounts': _series(registrations, now, 14),
          'nodes': _series(nodeRegistrations, now, 14),
        },
        'journal': journal,
      };
    });
    return revenue;
  }

  @override
  Future<Map<String, Object?>> users({
    String query = '',
    String filter = 'all',
    String sort = 'created_desc',
    int page = 1,
    int limit = 25,
  }) async {
    final q = query.trim();
    final offset = _offset(page, limit);
    final order = switch (sort) {
      'created_asc' => 'created_at ASC',
      'login' => 'login ASC NULLS LAST',
      'storage' => '(object_bytes + fragment_bytes) DESC',
      'balance' => 'balance_mc ASC',
      'balance_desc' => 'balance_mc DESC',
      'activity' => 'last_activity DESC',
      'nodes' => 'nodes_active DESC',
      _ => 'created_at DESC',
    };
    final where = switch (filter) {
      'blocked' => 'blocked_at IS NOT NULL',
      'debt' => 'balance_mc < 0',
      'keepers' => 'nodes_active > 0',
      'clients' => 'segments_active > 0',
      'inactive' => 'last_activity < @inactive',
      'active' => 'last_activity >= @inactive',
      _ => 'TRUE',
    };
    final sql =
        '''
      WITH base AS (
        SELECT a.account_id, a.login, a.created_at, a.blocked_at,
               a.blocked_reason, a.object_bytes, a.fragment_bytes,
               coalesce(c.balance_mc, 0) AS balance_mc,
               c.negative_since,
               (SELECT count(*) FROM devices d
                 WHERE d.account_id = a.account_id AND d.revoked_at IS NULL)
                 AS devices_active,
               (SELECT count(*) FROM nodes n
                 WHERE n.account_id = a.account_id AND n.removed_at IS NULL)
                 AS nodes_active,
               (SELECT count(*) FROM nodes n
                 WHERE n.account_id = a.account_id AND n.removed_at IS NULL
                   AND n.last_heartbeat_at >= @online)
                 AS nodes_online,
               (SELECT count(*) FROM segments s
                 WHERE s.account_id = a.account_id AND s.state <> 0)
                 AS segments_active,
               greatest(
                 a.created_at,
                 coalesce(a.key_bundle_updated_at, a.created_at),
                 coalesce((SELECT max(o.stored_at) FROM objects o
                            WHERE o.account_id = a.account_id), a.created_at),
                 coalesce((SELECT max(s.allocated_at) FROM segments s
                            WHERE s.account_id = a.account_id), a.created_at),
                 coalesce((SELECT max(n.last_heartbeat_at) FROM nodes n
                            WHERE n.account_id = a.account_id), a.created_at)
               ) AS last_activity
          FROM admin_accounts a
          LEFT JOIN credit_accounts c USING (account_id)
      )
      SELECT *, count(*) OVER() AS total
        FROM base
       WHERE (@q = '' OR login ILIKE @like
              OR encode(account_id, 'hex') LIKE @prefix)
         AND $where
       ORDER BY $order
       LIMIT @limit OFFSET @offset''';
    return await _db.run((s) async {
      final rows = await s.execute(
        Sql.named(sql),
        parameters: {
          'q': q,
          'like': '%$q%',
          'prefix': '${q.toLowerCase()}%',
          'online': _clock().toUtc().subtract(onlineWindow),
          if (filter == 'inactive' || filter == 'active')
            'inactive': _clock().toUtc().subtract(const Duration(days: 30)),
          'limit': limit,
          'offset': offset,
        },
      );
      final total = rows.isEmpty ? 0 : rows.first[14]! as int;
      return {
        'items': [
          for (final row in rows)
            {
              'accountId': bytesToHex(row[0]! as List<int>),
              'login': row[1],
              'createdAt': _iso(row[2]),
              'blockedAt': _iso(row[3]),
              'blockedReason': row[4],
              'objectBytes': row[5],
              'fragmentBytes': row[6],
              'balanceMc': row[7],
              'negativeSince': _iso(row[8]),
              'devicesActive': row[9],
              'nodesActive': row[10],
              'nodesOnline': row[11],
              'segmentsActive': row[12],
              'lastActivityAt': _iso(row[13]),
            },
        ],
        'total': total,
        'page': page,
        'limit': limit,
      };
    });
  }

  @override
  Future<Map<String, Object?>?> user(String accountId) async {
    final id = _bytes(accountId);
    if (id == null) return null;
    return await _db.run((s) async {
      final rows = await s.execute(
        Sql.named('''
          SELECT a.account_id, a.login, a.created_at, a.key_copy,
                 a.key_bundle_updated_at, a.object_bytes, a.fragment_bytes,
                 a.blocked_at, a.blocked_reason,
                 coalesce(c.balance_mc, 0), c.negative_since
            FROM admin_accounts a
            LEFT JOIN credit_accounts c USING (account_id)
           WHERE a.account_id = @a:bytea'''),
        parameters: {'a': id},
      );
      if (rows.isEmpty) return null;
      final row = rows.single;
      final devices = await s.execute(
        Sql.named('''
          SELECT device_sign, created_at, revoked_at,
                 revocation_seq IS NOT NULL
            FROM devices WHERE account_id = @a:bytea
           ORDER BY created_at'''),
        parameters: {'a': id},
      );
      final objects = await s.execute(
        Sql.named('''
          SELECT kind, count(*), coalesce(sum(size), 0)::int8, max(stored_at)
            FROM objects WHERE account_id = @a:bytea GROUP BY kind'''),
        parameters: {'a': id},
      );
      final segments = await s.execute(
        Sql.named('''
          SELECT state, count(*), coalesce(sum(k::int8 * fragment_size), 0)::int8,
                 max(allocated_at)
            FROM segments WHERE account_id = @a:bytea GROUP BY state'''),
        parameters: {'a': id},
      );
      final nodes = await s.execute(
        Sql.named('''
          SELECT n.node_id, n.country, n.city, n.capacity_bytes,
                 n.used_bytes, n.assigned_bytes, n.availability,
                 n.last_heartbeat_at, n.removed_at, n.excluded_at,
                 n.leaving_at, n.lost_at, n.software, n.registered_at,
                 n.relay, n.relay_until
            FROM nodes n WHERE n.account_id = @a:bytea
           ORDER BY n.registered_at'''),
        parameters: {'a': id},
      );
      final ledger = await s.execute(
        Sql.named('''
          SELECT amount_mc, kind, day, ref, note, created_at
            FROM credit_ledger WHERE account_id = @a:bytea
           ORDER BY id DESC LIMIT 50'''),
        parameters: {'a': id},
      );
      final traffic = await s.execute(
        Sql.named('''
          SELECT day, method, bytes, connections FROM traffic_daily
           WHERE account_id = @a:bytea
             AND day >= @d:date
           ORDER BY day'''),
        parameters: {
          'a': id,
          'd': _dateValue(_clock().subtract(const Duration(days: 14))),
        },
      );
      final relay = await s.execute(
        Sql.named('''
          SELECT day, bytes, sessions FROM relay_usage
           WHERE account_id = @a:bytea AND day >= @d:date
           ORDER BY day'''),
        parameters: {
          'a': id,
          'd': _dateValue(_clock().subtract(const Duration(days: 14))),
        },
      );
      final usage = await s.execute(
        Sql.named(
          '''
          SELECT
            coalesce((SELECT sum(s.k::bigint * s.fragment_size)
                        FROM segments s WHERE s.account_id = @a:bytea
                          AND s.state >= 1), 0)::int8,
            coalesce((SELECT sum(s.k::bigint * s.fragment_size)
                        FROM segments s WHERE s.account_id = @a:bytea), 0)::int8,
            coalesce((SELECT sum(n.capacity_bytes) FROM nodes n
                       WHERE n.account_id = @a:bytea
                         AND n.removed_at IS NULL), 0)::int8,
            coalesce((SELECT sum(l.amount_mc) FROM credit_ledger l
                       WHERE l.account_id = @a:bytea AND l.amount_mc > 0), 0)::int8,
            coalesce((SELECT sum(-l.amount_mc) FROM credit_ledger l
                       WHERE l.account_id = @a:bytea AND l.amount_mc < 0), 0)::int8''',
        ),
        parameters: {'a': id},
      );
      final [
        dataBytes as int,
        reservedBytes as int,
        capacityBytes as int,
        earned as int,
        spent as int,
      ] = usage.single;
      final objectBytes = row[5]! as int;
      final balance = row[9]! as int;
      final negativeSince = row[10] as DateTime?;
      final barter = economyPolicy.barterBytes(capacityBytes);
      final billable = max(0, dataBytes + objectBytes - barter);
      final monthly = economyPolicy.dataCostMicro(billable);
      final graceUntil = negativeSince?.toUtc().add(
        Duration(days: economyPolicy.graceDays),
      );
      final blocked =
          balance < 0 &&
          negativeSince != null &&
          !_clock().toUtc().isBefore(graceUntil!);
      return {
        'accountId': bytesToHex(id),
        'login': row[1],
        'createdAt': _iso(row[2]),
        'keyCopy': row[3],
        'keyCopyUpdatedAt': _iso(row[4]),
        'objectBytes': objectBytes,
        'fragmentBytes': row[6],
        'blockedAt': _iso(row[7]),
        'blockedReason': row[8],
        'balanceMc': balance,
        'negativeSince': _iso(negativeSince),
        'devices': [
          for (final [
                sign as List<int>,
                added as DateTime,
                revoked as DateTime?,
                signed as bool,
              ]
              in devices)
            {
              'deviceId': bytesToHex(sign),
              'addedAt': _iso(added),
              'revokedAt': _iso(revoked),
              'revokedBy': revoked == null
                  ? null
                  : signed
                  ? 'account'
                  : 'operator',
            },
        ],
        'objects': [
          for (final [
                kind as int,
                count as int,
                bytes as int,
                last as DateTime?,
              ]
              in objects)
            {
              'kind': kind == 1 ? 'snapshots' : 'indexes',
              'count': count,
              'bytes': bytes,
              'lastAt': _iso(last),
            },
        ],
        'segments': [
          for (final [
                state as int,
                count as int,
                bytes as int,
                last as DateTime?,
              ]
              in segments)
            {
              'state': _segmentState(state),
              'count': count,
              'bytes': bytes,
              'lastAt': _iso(last),
            },
        ],
        'nodes': [for (final row in nodes) _accountNode(row)],
        'ledger': [
          for (final [
                amount as int,
                kind as String,
                day as DateTime,
                ref as String,
                note as String,
                created as DateTime,
              ]
              in ledger)
            {
              'amountMc': amount,
              'kind': kind,
              'day': _dateText(day),
              'ref': ref,
              'note': note,
              'createdAt': _iso(created),
            },
        ],
        'traffic': [
          for (final [
                day as DateTime,
                method as int,
                bytes as int,
                connections as int,
              ]
              in traffic)
            {
              'day': _dateText(day),
              'method': _method(method),
              'bytes': bytes,
              'connections': connections,
            },
        ],
        'relay': [
          for (final [day as DateTime, bytes as int, sessions as int] in relay)
            {'day': _dateText(day), 'bytes': bytes, 'sessions': sessions},
        ],
        'quota': {
          'dataBytes': dataBytes + objectBytes,
          'reservedBytes': reservedBytes + objectBytes,
          'capacityBytes': capacityBytes,
          'barterBytes': barter,
          'maxBytes': barter + economyPolicy.bytesForMicro(max(0, balance)),
          'balanceMc': balance,
          'availableMc': max(0, balance),
          'billableBytes': billable,
          'monthlyCostMc': monthly,
          'dailyCostMc': monthly ~/ 30,
          'earnedMc': earned,
          'spentMc': spent,
          'negativeSince': _iso(negativeSince),
          'graceDays': economyPolicy.graceDays,
          'graceUntil': _iso(graceUntil),
          'blocked': blocked,
        },
      };
    });
  }

  @override
  Future<Map<String, Object?>> nodes({
    String query = '',
    String filter = 'active',
    String sort = 'last_seen',
    String version = '',
    String country = '',
    int page = 1,
    int limit = 25,
  }) async {
    final q = query.trim();
    final offset = _offset(page, limit);
    final order = switch (sort) {
      'registered_desc' => 'registered_at DESC',
      'capacity' => 'capacity_bytes DESC',
      'used' => 'used_bytes DESC',
      'availability' => 'availability ASC',
      'audits' => 'audits_failed DESC, audits_passed DESC',
      _ => 'last_heartbeat_at DESC NULLS LAST',
    };
    final where = switch (filter) {
      'all' => 'TRUE',
      'online' => 'online',
      'offline' => "status = 'offline'",
      'lost' => 'lost_at IS NOT NULL AND removed_at IS NULL',
      'excluded' => 'excluded_at IS NOT NULL AND removed_at IS NULL',
      'leaving' => 'leaving_at IS NOT NULL AND removed_at IS NULL',
      'probation' => 'on_probation AND removed_at IS NULL',
      _ => 'removed_at IS NULL',
    };
    return await _db.run((s) async {
      final rows = await s.execute(
        Sql.named('''
          WITH base AS (
            SELECT n.node_id, n.account_id, a.login, n.country, n.city,
                   n.registered_at, n.removed_at, n.excluded_at,
                   n.excluded_reason, n.leaving_at, n.lost_at,
                   n.last_heartbeat_at, n.capacity_bytes, n.used_bytes,
                   n.assigned_bytes, n.availability, n.software,
                   n.audits_passed, n.audits_failed,
                   n.audit_window_failures, n.audit_latency_ms,
                   n.last_audit_at, n.relay, n.relay_until,
                   n.registered_at > @probation AS on_probation,
                   coalesce(array_length(n.endpoints, 1), 0) AS endpoint_count,
                   (n.last_heartbeat_at IS NOT NULL
                    AND n.last_heartbeat_at >= @online) AS online,
                   CASE
                     WHEN n.removed_at IS NOT NULL THEN 'removed'
                     WHEN n.excluded_at IS NOT NULL THEN 'excluded'
                     WHEN n.leaving_at IS NOT NULL THEN 'leaving'
                     WHEN n.lost_at IS NOT NULL THEN 'lost'
                     WHEN n.last_heartbeat_at >= @online THEN 'online'
                     ELSE 'offline'
                   END AS status
              FROM nodes n JOIN admin_accounts a USING (account_id)
          )
          SELECT *, count(*) OVER() AS total
            FROM base
           WHERE (@q = '' OR login ILIKE @like
                  OR encode(node_id, 'hex') LIKE @prefix)
             AND (@version = '' OR software = @version)
             AND (@country = '' OR country = @country)
             AND $where
           ORDER BY $order
           LIMIT @limit OFFSET @offset'''),
        parameters: {
          'q': q,
          'like': '%$q%',
          'prefix': '${q.toLowerCase()}%',
          'online': _clock().toUtc().subtract(onlineWindow),
          'probation': _clock().toUtc().subtract(probation),
          'version': version,
          'country': country,
          'limit': limit,
          'offset': offset,
        },
      );
      final total = rows.isEmpty ? 0 : rows.first[28]! as int;
      return {
        'items': [for (final row in rows) _node(row)],
        'total': total,
        'page': page,
        'limit': limit,
      };
    });
  }

  @override
  Future<Map<String, Object?>?> node(String nodeId) async {
    final id = _bytes(nodeId);
    if (id == null) return null;
    return await _db.run((s) async {
      final rows = await s.execute(
        Sql.named('''
          SELECT n.node_id, n.account_id, a.login, n.country, n.city,
                 n.latitude, n.longitude, n.registered_at, n.removed_at,
                 n.excluded_at, n.excluded_reason, n.leaving_at, n.lost_at,
                 n.last_heartbeat_at, n.capacity_bytes, n.used_bytes,
                 n.assigned_bytes, n.free_bytes, n.availability, n.software,
                 n.audits_passed, n.audits_failed, n.audit_window_failures,
                 n.audit_latency_ms, n.last_audit_at, n.relay, n.relay_until,
                 n.endpoints, n.reconcile_at, n.repair_suspended_until,
                 CASE
                   WHEN n.removed_at IS NOT NULL THEN 'removed'
                   WHEN n.excluded_at IS NOT NULL THEN 'excluded'
                   WHEN n.leaving_at IS NOT NULL THEN 'leaving'
                   WHEN n.lost_at IS NOT NULL THEN 'lost'
                   WHEN n.last_heartbeat_at >= @online THEN 'online'
                   ELSE 'offline'
                 END AS status,
                 (n.last_heartbeat_at IS NOT NULL
                  AND n.last_heartbeat_at >= @online) AS online,
                 n.registered_at > @probation AS on_probation
            FROM nodes n JOIN admin_accounts a USING (account_id)
           WHERE n.node_id = @n:bytea'''),
        parameters: {
          'n': id,
          'online': _clock().toUtc().subtract(onlineWindow),
          'probation': _clock().toUtc().subtract(probation),
        },
      );
      if (rows.isEmpty) return null;
      final node = _node(rows.single, detail: true);
      final fragments = await s.execute(
        Sql.named('''
          SELECT count(*), count(*) FILTER (WHERE f.damaged_at IS NOT NULL),
                 count(DISTINCT (f.account_id, f.segment_id)),
                 coalesce(sum(g.fragment_size), 0)::int8
            FROM fragments f JOIN segments g USING (account_id, segment_id)
           WHERE f.node_id = @n:bytea AND f.stored'''),
        parameters: {'n': id},
      );
      final audits = await s.execute(
        Sql.named('''
          SELECT at, passed, recheck, reason, latency_ms
            FROM audits WHERE node_id = @n:bytea
           ORDER BY at DESC LIMIT 20'''),
        parameters: {'n': id},
      );
      final jobs = await s.execute(
        Sql.named('''
          SELECT job_id, kind, state, created_at, finished_at,
                 planned_bytes, bytes_downloaded, bytes_uploaded
            FROM repair_jobs WHERE executor = @n:bytea
           ORDER BY created_at DESC LIMIT 20'''),
        parameters: {'n': id},
      );
      final uptime = await s.execute(
        Sql.named('''
          SELECT day, slots FROM node_uptime
           WHERE node_id = @n:bytea
             AND day >= @d:int4
           ORDER BY day'''),
        parameters: {
          'n': id,
          'd': _dayNumber(_clock().subtract(const Duration(days: 30))),
        },
      );
      final [
        storedFragments as int,
        damagedFragments as int,
        segmentsCount as int,
        storedBytes as int,
      ] = fragments.single;
      return {
        ...node,
        'storedFragments': storedFragments,
        'damagedFragments': damagedFragments,
        'segmentsCount': segmentsCount,
        'storedBytes': storedBytes,
        'audits': [
          for (final [
                at as DateTime,
                passed as bool,
                recheck as bool,
                reason as String?,
                latency as int,
              ]
              in audits)
            {
              'at': _iso(at),
              'passed': passed,
              'recheck': recheck,
              'reason': reason,
              'latencyMs': latency,
            },
        ],
        'jobs': [
          for (final [
                job as List<int>,
                kind as int,
                state as int,
                created as DateTime,
                finished as DateTime?,
                planned as int,
                down as int,
                up as int,
              ]
              in jobs)
            {
              'jobId': bytesToHex(job),
              'kind': kind == 1 ? 'relocate' : 'repair',
              'state': _jobState(state),
              'createdAt': _iso(created),
              'finishedAt': _iso(finished),
              'plannedBytes': planned,
              'bytesDownloaded': down,
              'bytesUploaded': up,
            },
        ],
        'uptime': [
          for (final [day as int, slots as List<int>] in uptime)
            {'day': _dayNumberText(day), 'online': _slotFraction(slots)},
        ],
      };
    });
  }

  @override
  Future<Map<String, Object?>> segments({
    String query = '',
    String state = 'all',
    String sort = 'allocated_desc',
    int page = 1,
    int limit = 25,
  }) async {
    final q = query.trim();
    final offset = _offset(page, limit);
    final where = switch (state) {
      'pending' => 's.state = 0',
      'ok' => 's.state = 1',
      'repair' => 's.state = 2',
      'lost' => 's.state <> 0 AND s.live = 0',
      'stored' => 's.state <> 0',
      _ => 'TRUE',
    };
    final order = switch (sort) {
      'allocated_asc' => 's.allocated_at ASC',
      'live' => 's.live ASC, s.repair_since ASC NULLS LAST',
      'size' => '(s.k::int8 * s.fragment_size) DESC',
      _ => 's.allocated_at DESC',
    };
    return await _db.run((s) async {
      final rows = await s.execute(
        Sql.named('''
          SELECT s.account_id, a.login, s.segment_id, s.k, s.n,
                 s.repair_threshold, s.fragment_size, s.state, s.live,
                 s.allocated_at, s.committed_at, s.repair_since,
                 (SELECT count(*) FROM fragments f
                   WHERE f.account_id = s.account_id
                     AND f.segment_id = s.segment_id AND f.stored) AS stored,
                 (SELECT count(*) FROM fragments f
                   WHERE f.account_id = s.account_id
                     AND f.segment_id = s.segment_id
                     AND f.damaged_at IS NOT NULL) AS damaged,
                 count(*) OVER() AS total
            FROM segments s JOIN admin_accounts a USING (account_id)
           WHERE (@q = '' OR a.login ILIKE @like
                  OR encode(s.segment_id, 'hex') LIKE @prefix)
             AND $where
           ORDER BY $order
           LIMIT @limit OFFSET @offset'''),
        parameters: {
          'q': q,
          'like': '%$q%',
          'prefix': '${q.toLowerCase()}%',
          'limit': limit,
          'offset': offset,
        },
      );
      final total = rows.isEmpty ? 0 : rows.first[14]! as int;
      return {
        'items': [
          for (final row in rows)
            {
              'accountId': bytesToHex(row[0]! as List<int>),
              'login': row[1],
              'segmentId': bytesToHex(row[2]! as List<int>),
              'k': row[3],
              'n': row[4],
              'repairThreshold': row[5],
              'fragmentSize': row[6],
              'state': _segmentState(row[7]! as int),
              'live': row[8],
              'allocatedAt': _iso(row[9]),
              'committedAt': _iso(row[10]),
              'repairSince': _iso(row[11]),
              'storedFragments': row[12],
              'damagedFragments': row[13],
              'dataBytes': (row[3]! as int) * ((row[6]! as int) - 96),
            },
        ],
        'total': total,
        'page': page,
        'limit': limit,
      };
    });
  }

  @override
  Future<Map<String, Object?>?> segment(
    String accountId,
    String segmentId,
  ) async {
    final account = _bytes(accountId);
    final segment = _bytes(segmentId);
    if (account == null || segment == null) return null;
    return await _db.run((s) async {
      final rows = await s.execute(
        Sql.named('''
          SELECT s.account_id, a.login, s.segment_id, s.k, s.n,
                 s.repair_threshold, s.fragment_size, s.state, s.live,
                 s.allocated_at, s.committed_at, s.repair_since
            FROM segments s JOIN admin_accounts a USING (account_id)
           WHERE s.account_id = @a:bytea AND s.segment_id = @g:bytea'''),
        parameters: {'a': account, 'g': segment},
      );
      if (rows.isEmpty) return null;
      final fragments = await s.execute(
        Sql.named('''
          SELECT f.idx, f.node_id, n.country, n.city, f.stored,
                 f.damaged_at, f.audit_failed_at, f.audited_at, n.removed_at,
                 n.last_heartbeat_at, a.login
            FROM fragments f
            JOIN nodes n USING (node_id)
            JOIN admin_accounts a ON a.account_id = n.account_id
           WHERE f.account_id = @a:bytea AND f.segment_id = @g:bytea
           ORDER BY f.idx'''),
        parameters: {'a': account, 'g': segment},
      );
      final row = rows.single;
      return {
        'accountId': bytesToHex(account),
        'login': row[1],
        'segmentId': bytesToHex(segment),
        'k': row[3],
        'n': row[4],
        'repairThreshold': row[5],
        'fragmentSize': row[6],
        'state': _segmentState(row[7]! as int),
        'live': row[8],
        'allocatedAt': _iso(row[9]),
        'committedAt': _iso(row[10]),
        'repairSince': _iso(row[11]),
        'dataBytes': (row[3]! as int) * ((row[6]! as int) - 96),
        'fragments': [
          for (final [
                idx as int,
                nodeId as List<int>,
                country as String?,
                city as String?,
                stored as bool,
                damaged as DateTime?,
                failed as DateTime?,
                audited as DateTime?,
                removed as DateTime?,
                heartbeat as DateTime?,
                login as String?,
              ]
              in fragments)
            {
              'idx': idx,
              'nodeId': bytesToHex(nodeId),
              'ownerLogin': login,
              'country': country,
              'city': city,
              'stored': stored,
              'damagedAt': _iso(damaged),
              'auditFailedAt': _iso(failed),
              'auditedAt': _iso(audited),
              'nodeRemovedAt': _iso(removed),
              'nodeLastHeartbeatAt': _iso(heartbeat),
              'online':
                  removed == null &&
                  heartbeat != null &&
                  !heartbeat.isBefore(_clock().toUtc().subtract(onlineWindow)),
            },
        ],
      };
    });
  }

  @override
  Future<Map<String, Object?>> network({int hours = 24}) async {
    final service = _admin;
    final stats = _normaliseSegments(await service.stats());
    final relay = await service.relayStats(days: max(1, hours ~/ 24));
    final repair = await service.repairStats(hours: hours);
    final audits = await _db.run((s) async {
      final now = _clock().toUtc();
      final since = now.subtract(Duration(hours: hours));
      final [
        passed as int,
        failed as int,
        latency as double?,
      ] = (await s.execute(
        Sql.named('''
          SELECT count(*) FILTER (WHERE passed),
                 count(*) FILTER (WHERE NOT passed),
                 avg(latency_ms) FILTER (WHERE passed)
            FROM audits WHERE at >= @t:timestamptz'''),
        parameters: {'t': since},
      )).single;
      final reasons = await s.execute(
        Sql.named('''
          SELECT coalesce(reason, 'без причины'), count(*)
            FROM audits WHERE at >= @t:timestamptz AND NOT passed
            GROUP BY 1 ORDER BY count(*) DESC LIMIT 10'''),
        parameters: {'t': since},
      );
      final recent = await s.execute(
        Sql.named('''
          SELECT a.at, a.passed, a.recheck, a.reason, a.latency_ms,
                 encode(a.node_id, 'hex'), n.software, n.country, o.login
            FROM audits a
            JOIN nodes n USING (node_id)
            JOIN admin_accounts o ON o.account_id = n.account_id
           WHERE a.at >= @t:timestamptz
           ORDER BY a.at DESC LIMIT 40'''),
        parameters: {'t': since},
      );
      return {
        'passed': passed,
        'failed': failed,
        'latencyMs': latency?.round(),
        'reasons': [
          for (final [reason as String, count as int] in reasons)
            {'reason': reason, 'count': count},
        ],
        'recent': [
          for (final [
                at as DateTime,
                ok as bool,
                recheck as bool,
                reason as String?,
                latency as int,
                node as String,
                software as String,
                country as String?,
                login as String?,
              ]
              in recent)
            {
              'at': _iso(at),
              'passed': ok,
              'recheck': recheck,
              'reason': reason,
              'latencyMs': latency,
              'nodeId': node,
              'software': software,
              'country': country,
              'ownerLogin': login,
            },
        ],
      };
    });
    return {
      'hours': hours,
      'stats': stats,
      'relay': relay,
      'repair': repair,
      'audits': audits,
    };
  }

  @override
  Future<Map<String, Object?>> repairJobs({
    String state = 'open',
    String kind = 'all',
    int page = 1,
    int limit = 25,
  }) async {
    final offset = _offset(page, limit);
    final where = switch (state) {
      'done' => 'j.state = 2',
      'failed' => 'j.state = 3',
      'all' => 'TRUE',
      _ => 'j.state IN (0, 1)',
    };
    final kindWhere = switch (kind) {
      'repair' => 'j.kind = 0',
      'relocate' => 'j.kind = 1',
      _ => 'TRUE',
    };
    return await _db.run((s) async {
      final rows = await s.execute(
        Sql.named('''
          SELECT j.job_id, j.account_id, a.login, j.segment_id, j.executor,
                 o.login, j.kind, j.state, j.live, j.planned_bytes,
                 j.bytes_downloaded, j.bytes_uploaded, j.created_at,
                 j.deadline, j.reported_at, j.finished_at, j.reason,
                 (SELECT count(*) FROM repair_targets t
                   WHERE t.job_id = j.job_id AND t.state = 2) AS targets_done,
                 (SELECT count(*) FROM repair_targets t
                   WHERE t.job_id = j.job_id) AS targets_total,
                 count(*) OVER() AS total
            FROM repair_jobs j
            JOIN admin_accounts a ON a.account_id = j.account_id
            JOIN admin_accounts o ON o.account_id =
              (SELECT account_id FROM nodes WHERE node_id = j.executor)
           WHERE $where AND $kindWhere
           ORDER BY j.created_at DESC
           LIMIT @limit OFFSET @offset'''),
        parameters: {'limit': limit, 'offset': offset},
      );
      final total = rows.isEmpty ? 0 : rows.first[19]! as int;
      return {
        'items': [
          for (final [
                job as List<int>,
                account as List<int>,
                login as String?,
                segment as List<int>,
                executor as List<int>,
                executorLogin as String?,
                kind as int,
                state as int,
                live as int,
                planned as int,
                down as int,
                up as int,
                created as DateTime,
                deadline as DateTime,
                reported as DateTime?,
                finished as DateTime?,
                reason as String?,
                done as int,
                targets as int,
                _,
              ]
              in rows)
            {
              'jobId': bytesToHex(job),
              'accountId': bytesToHex(account),
              'login': login,
              'segmentId': bytesToHex(segment),
              'executorNodeId': bytesToHex(executor),
              'executorLogin': executorLogin,
              'kind': kind == 1 ? 'relocate' : 'repair',
              'state': _jobState(state),
              'live': live,
              'plannedBytes': planned,
              'bytesDownloaded': down,
              'bytesUploaded': up,
              'createdAt': _iso(created),
              'deadline': _iso(deadline),
              'reportedAt': _iso(reported),
              'finishedAt': _iso(finished),
              'reason': reason,
              'targetsDone': done,
              'targetsTotal': targets,
            },
        ],
        'total': total,
        'page': page,
        'limit': limit,
      };
    });
  }

  @override
  Future<Map<String, Object?>> audits({
    bool? passed,
    int page = 1,
    int limit = 25,
  }) async {
    final offset = _offset(page, limit);
    return await _db.run((s) async {
      final rows = await s.execute(
        Sql.named('''
          SELECT a.at, a.passed, a.recheck, a.reason, a.latency_ms,
                 encode(a.node_id, 'hex'), n.software, n.country, o.login,
                 a.id
            FROM audits a
            JOIN nodes n USING (node_id)
            JOIN admin_accounts o ON o.account_id = n.account_id
           WHERE (@passed:boolean IS NULL OR a.passed = @passed:boolean)
           ORDER BY a.at DESC, a.id DESC
           LIMIT @limit OFFSET @offset'''),
        parameters: {'passed': passed, 'limit': limit, 'offset': offset},
      );
      final totalRows = await s.execute(
        Sql.named('''
          SELECT count(*) FROM audits
           WHERE (@passed:boolean IS NULL OR passed = @passed:boolean)'''),
        parameters: {'passed': passed},
      );
      return {
        'items': [
          for (final [
                at as DateTime,
                ok as bool,
                recheck as bool,
                reason as String?,
                latency as int,
                node as String,
                software as String,
                country as String?,
                login as String?,
                id as int,
              ]
              in rows)
            {
              'id': id,
              'at': _iso(at),
              'passed': ok,
              'recheck': recheck,
              'reason': reason,
              'latencyMs': latency,
              'nodeId': node,
              'software': software,
              'country': country,
              'ownerLogin': login,
            },
        ],
        'total': totalRows.single[0]! as int,
        'page': page,
        'limit': limit,
      };
    });
  }

  @override
  Future<Map<String, Object?>> economy({int days = 30}) async {
    final since = _clock().toUtc().subtract(Duration(days: days));
    final graceStart = _clock().toUtc().subtract(
      Duration(days: economyPolicy.graceDays),
    );
    return await _db.run((s) async {
      final [
        accounts as int,
        total as int,
        positive as int,
        negative as int,
        positiveSum as int,
        negativeSum as int,
        blocked as int,
      ] = (await s.execute(
        Sql.named('''
          SELECT count(account_id), coalesce(sum(balance_mc), 0)::int8,
                 count(account_id) FILTER (WHERE balance_mc > 0),
                 count(account_id) FILTER (WHERE balance_mc < 0),
                 coalesce(sum(balance_mc) FILTER (WHERE balance_mc > 0), 0)::int8,
                 coalesce(sum(balance_mc) FILTER (WHERE balance_mc < 0), 0)::int8,
                 count(*) FILTER (WHERE balance_mc < 0
                                    AND negative_since IS NOT NULL
                                    AND negative_since <= @g:timestamptz)
            FROM credit_accounts'''),
        parameters: {'g': graceStart},
      )).single;
      final topPositive = await s.execute('''
        SELECT a.login, encode(a.account_id, 'hex'), c.balance_mc
          FROM credit_accounts c JOIN admin_accounts a USING (account_id)
         WHERE c.balance_mc > 0 ORDER BY c.balance_mc DESC LIMIT 10''');
      final topNegative = await s.execute('''
        SELECT a.login, encode(a.account_id, 'hex'), c.balance_mc,
               c.negative_since
          FROM credit_accounts c JOIN admin_accounts a USING (account_id)
         WHERE c.balance_mc < 0 ORDER BY c.balance_mc ASC LIMIT 10''');
      final ledger = await s.execute(
        Sql.named('''
          SELECT l.created_at, a.login, encode(l.account_id, 'hex'),
                 l.amount_mc, l.kind, l.day, l.ref, l.note
            FROM credit_ledger l JOIN admin_accounts a USING (account_id)
           WHERE l.created_at >= @t:timestamptz
           ORDER BY l.id DESC LIMIT 100'''),
        parameters: {'t': since},
      );
      final daily = await s.execute(
        Sql.named('''
          SELECT day, coalesce(sum(amount_mc) FILTER (WHERE amount_mc > 0), 0)::int8,
                 coalesce(sum(-amount_mc) FILTER (WHERE amount_mc < 0), 0)::int8,
                 count(*)
            FROM credit_ledger WHERE day >= @d:date
           GROUP BY day ORDER BY day'''),
        parameters: {'d': _dateValue(since)},
      );
      return {
        'days': days,
        'policy': {
          'dataCreditsPerTbMonth': economyPolicy.dataCreditsPerTbMonth,
          'storeCreditsPerTbMonth': economyPolicy.storeCreditsPerTbMonth,
          'barterRatio': economyPolicy.barterRatio,
          'starterCredits': economyPolicy.starterCredits,
          'graceDays': economyPolicy.graceDays,
        },
        'summary': {
          'accounts': accounts,
          'totalMc': total,
          'positiveAccounts': positive,
          'negativeAccounts': negative,
          'positiveMc': positiveSum,
          'negativeMc': negativeSum,
          'blockedAccounts': blocked,
        },
        'topPositive': [
          for (final [login as String?, id as String, balance as int]
              in topPositive)
            {'login': login, 'accountId': id, 'balanceMc': balance},
        ],
        'topNegative': [
          for (final [
                login as String?,
                id as String,
                balance as int,
                since as DateTime?,
              ]
              in topNegative)
            {
              'login': login,
              'accountId': id,
              'balanceMc': balance,
              'negativeSince': _iso(since),
            },
        ],
        'ledger': [
          for (final [
                at as DateTime,
                login as String?,
                id as String,
                amount as int,
                kind as String,
                day as DateTime,
                ref as String,
                note as String,
              ]
              in ledger)
            {
              'createdAt': _iso(at),
              'login': login,
              'accountId': id,
              'amountMc': amount,
              'kind': kind,
              'day': _dateText(day),
              'ref': ref,
              'note': note,
            },
        ],
        'daily': [
          for (final [
                day as DateTime,
                earned as int,
                spent as int,
                count as int,
              ]
              in daily)
            {
              'day': _dateText(day),
              'earnedMc': earned,
              'spentMc': spent,
              'entries': count,
            },
        ],
      };
    });
  }

  @override
  Future<Map<String, Object?>> journal({
    String query = '',
    int page = 1,
    int limit = 50,
  }) async {
    final q = query.trim();
    final offset = _offset(page, limit);
    return await _db.run((s) async {
      final rows = await s.execute(
        Sql.named('''
          SELECT id, at, os_user, db_user, command, arguments, reason, result,
                 count(*) OVER() AS total
            FROM admin_audit
           WHERE (@q = '' OR command ILIKE @like OR coalesce(reason, '') ILIKE @like
                  OR os_user ILIKE @like OR result ILIKE @like
                  OR arguments::text ILIKE @like)
           ORDER BY id DESC LIMIT @limit OFFSET @offset'''),
        parameters: {'q': q, 'like': '%$q%', 'limit': limit, 'offset': offset},
      );
      final total = rows.isEmpty ? 0 : rows.first[8]! as int;
      return {
        'items': [
          for (final [
                id as int,
                at as DateTime,
                osUser as String,
                dbUser as String,
                command as String,
                arguments,
                reason as String?,
                result as String,
                _,
              ]
              in rows)
            {
              'id': id,
              'at': _iso(at),
              'osUser': osUser,
              'dbUser': dbUser,
              'command': command,
              'arguments': _jsonValue(arguments),
              'reason': reason,
              'result': result,
            },
        ],
        'total': total,
        'page': page,
        'limit': limit,
      };
    });
  }

  @override
  Future<Map<String, Object?>> system() => _db.run((s) async {
    final info = (await s.execute(
      'SELECT current_user, current_database(), version()',
    )).single;
    final schema = (await s.execute(
      'SELECT coalesce(max(version), 0) FROM schema_migrations',
    )).single[0];
    final counts = (await s.execute('''
      SELECT (SELECT count(account_id) FROM admin_accounts),
             (SELECT count(device_sign) FROM devices WHERE revoked_at IS NULL),
             (SELECT count(node_id) FROM nodes WHERE removed_at IS NULL),
             (SELECT count(k) FROM segments),
             (SELECT count(stored) FROM fragments),
             (SELECT count(id) FROM audits),
             (SELECT count(job_id) FROM repair_jobs),
             (SELECT count(account_id) FROM credit_accounts),
             (SELECT count(id) FROM credit_ledger)''')).single;
    var isReadOnly = false;
    if (readOnlyRole.isNotEmpty) {
      final rows = await s.execute(
        Sql.named("SELECT pg_has_role(current_user, @r:text, 'MEMBER')"),
        parameters: {'r': readOnlyRole},
      );
      isReadOnly = rows.single[0]! as bool;
    }
    return {
      'database': {
        'user': info[0],
        'name': info[1],
        'version': info[2],
        'schema': schema,
        'readOnlyRole': readOnlyRole,
        'readOnly': isReadOnly,
      },
      'counts': {
        'accounts': counts[0],
        'devicesActive': counts[1],
        'nodesActive': counts[2],
        'segments': counts[3],
        'fragments': counts[4],
        'audits': counts[5],
        'repairJobs': counts[6],
        'creditAccounts': counts[7],
        'creditEntries': counts[8],
      },
    };
  });

  @override
  Future<List<Map<String, Object?>>> exportUsers({int limit = 10000}) async {
    final page = await users(limit: limit.clamp(1, 20000));
    return (page['items']! as List).cast<Map<String, Object?>>();
  }

  @override
  Future<List<Map<String, Object?>>> exportNodes({int limit = 10000}) async {
    final page = await nodes(filter: 'all', limit: limit.clamp(1, 20000));
    return (page['items']! as List).cast<Map<String, Object?>>();
  }

  /// `AdminService` называет состояния `allocated`/`stored`/`needsRepair`;
  /// панель и API используют `pending`/`ok`/`repair`.
  static Map<String, Object?> _normaliseSegments(Map<String, Object?> stats) {
    final raw = stats['segments'];
    if (raw is Map) {
      stats['segments'] = {
        'pending': raw['allocated'] ?? 0,
        'ok': raw['stored'] ?? 0,
        'repair': raw['needsRepair'] ?? 0,
      };
    }
    return stats;
  }

  // --- разбор строк ---------------------------------------------------------

  Map<String, Object?> _node(List<Object?> row, {bool detail = false}) {
    final now = _clock().toUtc();
    final registered = row[detail ? 7 : 5]! as DateTime;
    final availability = (row[detail ? 18 : 15]! as num).toDouble();
    final passed = row[detail ? 20 : 17]! as int;
    final failed = row[detail ? 21 : 18]! as int;
    final recentFailures = row[detail ? 22 : 19]! as int;
    final latency = row[detail ? 23 : 20] as double?;
    final reputation = Reputation.of(
      ReputationInput(
        availability: availability,
        age: now.difference(registered),
        auditsPassed: passed,
        auditsFailed: failed,
        recentFailures: recentFailures,
        auditLatency: latency == null
            ? null
            : Duration(microseconds: (latency * 1000).round()),
      ),
    );
    if (!detail) {
      return {
        'nodeId': bytesToHex(row[0]! as List<int>),
        'accountId': bytesToHex(row[1]! as List<int>),
        'ownerLogin': row[2],
        'country': row[3],
        'city': row[4],
        'registeredAt': _iso(row[5]),
        'removedAt': _iso(row[6]),
        'excludedAt': _iso(row[7]),
        'excludedReason': row[8],
        'leavingAt': _iso(row[9]),
        'lostAt': _iso(row[10]),
        'lastHeartbeatAt': _iso(row[11]),
        'capacityBytes': row[12],
        'usedBytes': row[13],
        'assignedBytes': row[14],
        'freeBytes': max(
          0,
          (row[12]! as int) - max(row[13]! as int, row[14]! as int),
        ),
        'availability': availability,
        'software': row[16],
        'auditsPassed': passed,
        'auditsFailed': failed,
        'auditWindowFailures': recentFailures,
        'auditLatencyMs': latency?.round(),
        'lastAuditAt': _iso(row[21]),
        'relay': row[22],
        'relayUntil': _iso(row[23]),
        'onProbation': row[24],
        'endpointCount': row[25],
        'online': row[26],
        'status': row[27],
        'reputation': reputation,
      };
    }
    final free = row[17] as int?;
    return {
      'nodeId': bytesToHex(row[0]! as List<int>),
      'accountId': bytesToHex(row[1]! as List<int>),
      'ownerLogin': row[2],
      'country': row[3],
      'city': row[4],
      'latitude': row[5],
      'longitude': row[6],
      'registeredAt': _iso(row[7]),
      'removedAt': _iso(row[8]),
      'excludedAt': _iso(row[9]),
      'excludedReason': row[10],
      'leavingAt': _iso(row[11]),
      'lostAt': _iso(row[12]),
      'lastHeartbeatAt': _iso(row[13]),
      'capacityBytes': row[14],
      'usedBytes': row[15],
      'assignedBytes': row[16],
      'freeBytes':
          free ??
          max(0, (row[14]! as int) - max(row[15]! as int, row[16]! as int)),
      'availability': availability,
      'software': row[19],
      'auditsPassed': passed,
      'auditsFailed': failed,
      'auditWindowFailures': recentFailures,
      'auditLatencyMs': latency?.round(),
      'lastAuditAt': _iso(row[24]),
      'relay': row[25],
      'relayUntil': _iso(row[26]),
      'endpoints': (row[27]! as List<Object?>).cast<String>(),
      'reconcileAt': _iso(row[28]),
      'repairSuspendedUntil': _iso(row[29]),
      'status': row[30],
      'online': row[31],
      'onProbation': row[32],
      'reputation': reputation,
    };
  }

  Map<String, Object?> _accountNode(List<Object?> row) {
    final heartbeat = row[7] as DateTime?;
    final removed = row[8] as DateTime?;
    return {
      'nodeId': bytesToHex(row[0]! as List<int>),
      'country': row[1],
      'city': row[2],
      'capacityBytes': row[3],
      'usedBytes': row[4],
      'assignedBytes': row[5],
      'availability': row[6],
      'online':
          removed == null &&
          heartbeat != null &&
          !heartbeat.isBefore(_clock().toUtc().subtract(onlineWindow)),
      'lastHeartbeatAt': _iso(heartbeat),
      'removedAt': _iso(removed),
      'excludedAt': _iso(row[9]),
      'leavingAt': _iso(row[10]),
      'lostAt': _iso(row[11]),
      'software': row[12],
      'registeredAt': _iso(row[13]),
      'relay': row[14],
      'relayUntil': _iso(row[15]),
    };
  }
}

double _slotFraction(List<int> slots) {
  var set = 0;
  for (final byte in slots) {
    var value = byte;
    while (value != 0) {
      set += value & 1;
      value >>= 1;
    }
  }
  return slots.isEmpty ? 0 : set / (slots.length * 8);
}

List<Map<String, Object?>> _series(Result rows, DateTime now, int days) {
  final values = <String, int>{
    for (final row in rows) row[0]! as String: row[1]! as int,
  };
  return [
    for (var i = days - 1; i >= 0; i--)
      {
        'day': _date(now.subtract(Duration(days: i))),
        'count': values[_date(now.subtract(Duration(days: i)))] ?? 0,
      },
  ];
}

String _date(DateTime time) {
  final utc = time.toUtc();
  return '${utc.year.toString().padLeft(4, '0')}-'
      '${utc.month.toString().padLeft(2, '0')}-'
      '${utc.day.toString().padLeft(2, '0')}';
}

String _dateText(DateTime time) => _date(time);

DateTime _dateValue(DateTime time) {
  final utc = time.toUtc();
  return DateTime.utc(utc.year, utc.month, utc.day);
}

int _dayNumber(DateTime time) {
  final d = DateTime.utc(time.year, time.month, time.day);
  return d.difference(DateTime.utc(1970)).inDays;
}

String _dayNumberText(int day) =>
    _date(DateTime.utc(1970).add(Duration(days: day)));

String _segmentState(int state) => switch (state) {
  0 => 'pending',
  1 => 'ok',
  2 => 'repair',
  _ => 'unknown',
};

String _jobState(int state) => switch (state) {
  0 => 'running',
  1 => 'verifying',
  2 => 'done',
  3 => 'failed',
  _ => 'unknown',
};

String _method(int method) => switch (method) {
  1 => 'direct',
  2 => 'udp',
  3 => 'relay',
  _ => '$method',
};

String? _iso(Object? value) =>
    value is DateTime ? value.toUtc().toIso8601String() : null;

Object? _jsonValue(Object? value) {
  if (value == null || value is String || value is num || value is bool) {
    return value;
  }
  if (value is Map) return Map<String, Object?>.from(value);
  if (value is List) return value;
  return '$value';
}

int _offset(int page, int limit) {
  final p = page < 1 ? 1 : page;
  return (p - 1) * limit;
}

Uint8List? _bytes(String hex) {
  final text = hex.trim().toLowerCase();
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(text)) return null;
  return hexToBytes(text);
}
