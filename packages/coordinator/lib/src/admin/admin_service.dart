import 'dart:convert';
import 'dart:typed_data';

import 'package:coordinator/src/db/database.dart';
import 'package:core/core.dart';
import 'package:postgres/postgres.dart';

/// Ошибка команды администратора, понятная оператору.
final class AdminException implements Exception {
  const new(this.message);

  final String message;

  @override
  String toString() => 'AdminException: $message';
}

/// Кто и зачем выполняет изменяющую команду.
final class AdminActor {
  const new({required this.osUser, required this.reason});

  /// Пользователь ОС (`SUDO_USER`, `USER`).
  final String osUser;

  /// Причина (`--reason`), обязательна для изменяющих команд.
  final String reason;
}

/// Запись журнала администратора.
typedef AuditRecord = Map<String, Object?>;

/// Действия оператора координатора (задачи 2.10.2–2.10.4): поиск и сводки
/// — только чтение; блокировка, отзыв, исключение — с записью в журнал
/// `admin_audit` в той же транзакции. Неудачная попытка тоже пишется в
/// журнал, отдельной транзакцией.
///
/// Видны только метаданные, которые координатор и так знает (модель
/// угроз, К-2): ни KeyBundle, ни блобов роль администратора не читает.
final class AdminService {
  new(
    this._db, {
    required this.onlineWindow,
    required this.probation,
    DateTime Function()? clock,
    this.journal,
  }) : _clock = clock ?? DateTime.now;

  final Database _db;

  /// Узел без heartbeat дольше — вне сети (`NodePolicy.onlineWindow`).
  final Duration onlineWindow;

  /// Испытательный срок узлов (`PlacementPolicy.probation`).
  final Duration probation;

  final DateTime Function() _clock;

  /// Копия записи журнала вне базы (журнал systemd); сбой не мешает.
  final void Function(AuditRecord record)? journal;

  // --- учётные записи -------------------------------------------------------

  static final _hex64 = RegExp(r'^[0-9a-f]{64}$');

  /// Учётные записи по имени для входа, `account_id`, ключу устройства или
  /// ключу узла (64 hex-символа).
  Future<List<Map<String, Object?>>> findAccounts(String query) async {
    final q = query.trim().toLowerCase();
    final Sql sql;
    final Map<String, Object?> parameters;
    if (_hex64.hasMatch(q)) {
      sql = Sql.named('''
        SELECT a.account_id, a.login, a.created_at, a.blocked_at, m.how
          FROM admin_accounts a JOIN (
            SELECT account_id, 'account' AS how FROM accounts
              WHERE account_id = @k:bytea
            UNION ALL
            SELECT account_id, 'device' FROM devices
              WHERE device_sign = @k:bytea
            UNION ALL
            SELECT account_id, 'node' FROM nodes WHERE node_id = @k:bytea
          ) m USING (account_id)''');
      parameters = {'k': hexToBytes(q)};
    } else {
      final login = LoginName.normalize(q);
      if (login == null) {
        throw const AdminException(
          'ищите по имени для входа или по ключу (64 hex-символа)',
        );
      }
      sql = Sql.named('''
        SELECT account_id, login, created_at, blocked_at, 'login'
          FROM admin_accounts WHERE login = @l:text''');
      parameters = {'l': login};
    }
    final rows = await _db.run((s) => s.execute(sql, parameters: parameters));
    return [
      for (final [
            id as List<int>,
            login as String?,
            created as DateTime,
            blocked as DateTime?,
            how as String,
          ]
          in rows)
        {
          'accountId': bytesToHex(id),
          'login': login,
          'createdAt': _iso(created),
          'blockedAt': _iso(blocked),
          'matchedBy': how,
        },
    ];
  }

  /// Ровно одна учётная запись по запросу [findAccounts].
  Future<Uint8List> resolveAccount(String query) async {
    final found = await findAccounts(query);
    final ids = {for (final f in found) f['accountId']! as String};
    return switch (ids.length) {
      1 => hexToBytes(ids.single),
      0 => throw AdminException('учётная запись «$query» не найдена'),
      _ => throw AdminException('запросу «$query» подходят ${ids.length}'),
    };
  }

  /// Сводка по учётной записи: устройства, объём, сегменты, узлы, последняя
  /// активность.
  Future<Map<String, Object?>> showAccount(String query) async {
    final id = await resolveAccount(query);
    return await _db.run((s) async {
      final p = {'a': id};
      final [
        login as String?,
        created as DateTime,
        keyCopy as bool,
        keyCopyAt as DateTime?,
        objectBytes as int,
        fragmentBytes as int,
        blockedAt as DateTime?,
        blockedReason as String?,
      ] = (await s.execute(
        Sql.named('''
          SELECT login, created_at, key_copy, key_bundle_updated_at,
                 object_bytes, fragment_bytes, blocked_at, blocked_reason
            FROM admin_accounts WHERE account_id = @a:bytea'''),
        parameters: p,
      )).single;
      final devices = await s.execute(
        Sql.named('''
          SELECT device_sign, created_at, revoked_at,
                 revocation_seq IS NOT NULL
            FROM devices WHERE account_id = @a:bytea ORDER BY created_at'''),
        parameters: p,
      );
      final objects = await s.execute(
        Sql.named('''
          SELECT kind, count(*), coalesce(sum(size), 0)::int8, max(stored_at)
            FROM objects WHERE account_id = @a:bytea GROUP BY kind'''),
        parameters: p,
      );
      final segments = await s.execute(
        Sql.named('''
          SELECT state, count(*), max(allocated_at)
            FROM segments WHERE account_id = @a:bytea GROUP BY state'''),
        parameters: p,
      );
      final nodes = await _nodes(s, account: id);
      DateTime? last;
      void seen(DateTime? t) {
        if (t != null && (last == null || t.isAfter(last!))) last = t;
      }

      seen(keyCopyAt);
      for (final row in objects) {
        seen(row[3] as DateTime?);
      }
      for (final row in segments) {
        seen(row[2] as DateTime?);
      }
      return {
        'accountId': bytesToHex(id),
        'login': login,
        'createdAt': _iso(created),
        'keyCopy': keyCopy,
        'blockedAt': _iso(blockedAt),
        'blockedReason': blockedReason,
        'objectBytes': objectBytes,
        'fragmentBytes': fragmentBytes,
        'lastActivityAt': _iso(last),
        'devices': [
          for (final [
                d as List<int>,
                added as DateTime,
                revoked as DateTime?,
                signed as bool,
              ]
              in devices)
            {
              'deviceId': bytesToHex(d),
              'addedAt': _iso(added),
              'revokedAt': _iso(revoked),
              // Отзыв оператором — без подписи учётной записи.
              'revokedBy': revoked == null
                  ? null
                  : signed
                  ? 'account'
                  : 'operator',
            },
        ],
        'objects': {
          for (final [kind as int, n as int, bytes as int, _] in objects)
            kind == 1 ? 'snapshots' : 'indexes': {'count': n, 'bytes': bytes},
        },
        'segments': {
          for (final [state as int, n as int, _] in segments)
            _segmentState(state): n,
        },
        'nodes': nodes,
      };
    });
  }

  /// Блокирует или разблокирует учётную запись.
  Future<Map<String, Object?>> setBlocked(
    String query, {
    required bool blocked,
    required AdminActor actor,
  }) => _audited(
    blocked ? 'account block' : 'account unblock',
    {'account': query},
    actor,
    (tx) async {
      final id = await resolveAccount(query);
      final rows = await tx.execute(
        Sql.named(
          blocked
              ? '''
            UPDATE accounts
               SET blocked_at = @t:timestamptz, blocked_reason = @r:text
             WHERE account_id = @a:bytea AND blocked_at IS NULL
             RETURNING 1'''
              : '''
            UPDATE accounts SET blocked_at = NULL, blocked_reason = NULL
             WHERE account_id = @a:bytea AND blocked_at IS NOT NULL
             RETURNING 1''',
        ),
        parameters: {
          'a': id,
          if (blocked) ...{'t': _clock(), 'r': actor.reason},
        },
      );
      return {
        'accountId': bytesToHex(id),
        'blocked': blocked,
        'changed': rows.isNotEmpty,
      };
    },
  );

  /// Отзывает устройство без ключа учётной записи (злоупотребление).
  /// Подписанного отзыва нет, поэтому узлы о нём не узнают из
  /// `ListRevocations`; но талонов устройству больше не выдаётся, а
  /// выданные истекают за час.
  Future<Map<String, Object?>> revokeDevice(
    String device, {
    required AdminActor actor,
  }) => _audited('device revoke', {'device': device}, actor, (tx) async {
    final prefix = device.trim().toLowerCase();
    if (!RegExp(r'^[0-9a-f]{8,64}$').hasMatch(prefix)) {
      throw const AdminException('устройство — не меньше 8 hex-символов ключа');
    }
    final found = await tx.execute(
      Sql.named('''
        SELECT device_sign, account_id, revoked_at IS NOT NULL FROM devices
          WHERE encode(device_sign, 'hex') LIKE @p:text || '%'
          LIMIT 2'''),
      parameters: {'p': prefix},
    );
    if (found.isEmpty) throw AdminException('устройство $prefix не найдено');
    if (found.length > 1) {
      throw AdminException('префиксу $prefix подходят несколько устройств');
    }
    final [id as List<int>, account as List<int>, revoked as bool] =
        found.single;
    if (!revoked) {
      await tx.execute(
        Sql.named(
          'UPDATE devices SET revoked_at = @t:timestamptz '
          'WHERE device_sign = @d:bytea',
        ),
        parameters: {'d': id, 't': _clock()},
      );
    }
    return {
      'deviceId': bytesToHex(id),
      'accountId': bytesToHex(account),
      'changed': !revoked,
    };
  });

  // --- узлы -----------------------------------------------------------------

  Future<List<Map<String, Object?>>> listNodes({String? account}) async {
    final id = account == null ? null : await resolveAccount(account);
    return await _db.run((s) => _nodes(s, account: id));
  }

  Future<Map<String, Object?>> showNode(String node) async {
    final id = await _resolveNode(node);
    return await _db.run((s) async {
      final nodes = await _nodes(s, node: id);
      final [stored as int, bytes as int] = (await s.execute(
        Sql.named('''
          SELECT count(*), coalesce(sum(s.fragment_size), 0)::int8
            FROM fragments f JOIN segments s USING (account_id, segment_id)
            WHERE f.node_id = @n:bytea AND f.stored'''),
        parameters: {'n': id},
      )).single;
      return {...nodes.single, 'storedFragments': stored, 'storedBytes': bytes};
    });
  }

  /// Исключает узел из размещения или возвращает; его фрагменты остаются
  /// (перенос — этап 4).
  Future<Map<String, Object?>> setExcluded(
    String node, {
    required bool excluded,
    required AdminActor actor,
  }) => _audited(
    excluded ? 'node exclude' : 'node include',
    {'node': node},
    actor,
    (tx) async {
      final id = await _resolveNode(node);
      final rows = await tx.execute(
        Sql.named(
          excluded
              ? '''
            UPDATE nodes
               SET excluded_at = @t:timestamptz, excluded_reason = @r:text
             WHERE node_id = @n:bytea AND excluded_at IS NULL RETURNING 1'''
              : '''
            UPDATE nodes SET excluded_at = NULL, excluded_reason = NULL
             WHERE node_id = @n:bytea AND excluded_at IS NOT NULL
             RETURNING 1''',
        ),
        parameters: {
          'n': id,
          if (excluded) ...{'t': _clock(), 'r': actor.reason},
        },
      );
      return {
        'nodeId': bytesToHex(id),
        'excluded': excluded,
        'changed': rows.isNotEmpty,
      };
    },
  );

  Future<Uint8List> _resolveNode(String node) async {
    final prefix = node.trim().toLowerCase();
    if (!RegExp(r'^[0-9a-f]{8,64}$').hasMatch(prefix)) {
      throw const AdminException('узел — не меньше 8 hex-символов node_id');
    }
    final rows = await _db.run(
      (s) => s.execute(
        Sql.named('''
          SELECT node_id FROM nodes
            WHERE encode(node_id, 'hex') LIKE @p:text || '%' LIMIT 2'''),
        parameters: {'p': prefix},
      ),
    );
    if (rows.isEmpty) throw AdminException('узел $prefix не найден');
    if (rows.length > 1) {
      throw AdminException('префиксу $prefix подходят несколько узлов');
    }
    return Uint8List.fromList(rows.single.single! as List<int>);
  }

  Future<List<Map<String, Object?>>> _nodes(
    Session s, {
    Uint8List? account,
    Uint8List? node,
  }) async {
    final now = _clock();
    final rows = await s.execute(
      Sql.named('''
        SELECT n.node_id, n.account_id, a.login, n.subnet, n.availability,
               n.capacity_bytes, n.used_bytes, n.assigned_bytes,
               n.last_heartbeat_at, n.registered_at, n.removed_at,
               n.excluded_at, n.excluded_reason, n.endpoints, n.software,
               n.audits_passed, n.audits_failed, n.last_audit_at
          FROM nodes n JOIN admin_accounts a USING (account_id)
          WHERE (@a:bytea IS NULL OR n.account_id = @a:bytea)
            AND (@n:bytea IS NULL OR n.node_id = @n:bytea)
          ORDER BY n.registered_at'''),
      parameters: {'a': account, 'n': node},
    );
    return [
      for (final [
            id as List<int>,
            owner as List<int>,
            login as String?,
            subnet as String?,
            availability as double,
            capacity as int,
            used as int,
            assigned as int,
            heartbeat as DateTime?,
            registered as DateTime,
            removed as DateTime?,
            excludedAt as DateTime?,
            excludedReason as String?,
            endpoints as List<Object?>,
            software as String,
            auditsPassed as int,
            auditsFailed as int,
            lastAudit as DateTime?,
          ]
          in rows)
        {
          'nodeId': bytesToHex(id),
          'ownerId': bytesToHex(owner),
          'ownerLogin': login,
          'subnet': subnet,
          'availability': availability,
          'capacityBytes': capacity,
          'freeBytes': capacity - (used > assigned ? used : assigned),
          'online':
              removed == null &&
              heartbeat != null &&
              !heartbeat.isBefore(now.subtract(onlineWindow)),
          'onProbation': registered.isAfter(now.subtract(probation)),
          'lastHeartbeatAt': _iso(heartbeat),
          'registeredAt': _iso(registered),
          'removedAt': _iso(removed),
          'excludedAt': _iso(excludedAt),
          'excludedReason': excludedReason,
          'endpoints': endpoints.cast<String>(),
          'software': software,
          'auditsPassed': auditsPassed,
          'auditsFailed': auditsFailed,
          'lastAuditAt': _iso(lastAudit),
        },
    ];
  }

  // --- сводка и журнал ------------------------------------------------------

  Future<Map<String, Object?>> stats() => _db.run((s) async {
    final online = _clock().subtract(onlineWindow);
    final probationStart = _clock().subtract(probation);
    final [
      accounts as int,
      blocked as int,
      objectBytes as int,
      fragmentBytes as int,
    ] = (await s.execute('''
      SELECT count(*), count(blocked_at), coalesce(sum(object_bytes), 0)::int8,
             coalesce(sum(fragment_bytes), 0)::int8
        FROM admin_accounts''')).single;
    final [devices as int] = (await s.execute(
      'SELECT count(*) FROM devices WHERE revoked_at IS NULL',
    )).single;
    final [
      nodes as int,
      nodesOnline as int,
      excluded as int,
      onProbation as int,
      capacity as int,
    ] = (await s.execute(
      Sql.named('''
        SELECT count(*),
               count(*) FILTER (WHERE last_heartbeat_at >= @o:timestamptz),
               count(excluded_at),
               count(*) FILTER (WHERE registered_at > @p:timestamptz),
               coalesce(sum(capacity_bytes), 0)::int8
          FROM nodes WHERE removed_at IS NULL'''),
      parameters: {'o': online, 'p': probationStart},
    )).single;
    final states = await s.execute(
      'SELECT state, count(*) FROM segments GROUP BY state',
    );
    // Сохранённые сегменты по числу загруженных фрагментов.
    final histogram = await s.execute('''
      SELECT stored, count(*) FROM (
        SELECT count(*) FILTER (WHERE f.stored) AS stored
          FROM segments s JOIN fragments f USING (account_id, segment_id)
          WHERE s.state <> 0
          GROUP BY s.account_id, s.segment_id) t
        GROUP BY stored ORDER BY stored''');
    return {
      'accounts': accounts,
      'accountsBlocked': blocked,
      'devicesActive': devices,
      'nodes': nodes,
      'nodesOnline': nodesOnline,
      'nodesExcluded': excluded,
      'nodesOnProbation': onProbation,
      'capacityBytes': capacity,
      'objectBytes': objectBytes,
      'fragmentBytes': fragmentBytes,
      'segments': {
        for (final [state as int, n as int] in states) _segmentState(state): n,
      },
      'segmentsByStoredFragments': {
        for (final [stored as int, n as int] in histogram) '$stored': n,
      },
    };
  });

  /// Метрики relay за последние [days] суток (задача 3.8.3): по каждому
  /// relay — последний отчёт (узлы на связи, сеансы), сеансы и трафик за
  /// период; узлы с действующим пропуском LISTEN; трафик фрагментов по
  /// способам подключения по отчётам клиентов и узлов и доля relay в нём
  /// (контрольная точка 3.10.4).
  Future<Map<String, Object?>> relayStats({int days = 7}) => _db.run((s) async {
    final now = _clock();
    final since = now.subtract(Duration(days: days));
    final u = now.toUtc();
    final firstDay = DateTime.utc(u.year, u.month, u.day - days + 1);
    final relays = await s.execute(
      Sql.named('''
            SELECT r.relay, max(r.at), sum(r.bytes)::int8,
                   sum(r.sessions_opened)::int8,
                   (array_agg(r.listeners ORDER BY r.at DESC))[1],
                   (array_agg(r.sessions ORDER BY r.at DESC))[1]
              FROM relay_reports r
              WHERE r.at >= @t:timestamptz
              GROUP BY r.relay ORDER BY r.relay'''),
      parameters: {'t': since},
    );
    final assigned = await s.execute(
      Sql.named('''
            SELECT relay, count(*) FROM nodes
              WHERE removed_at IS NULL AND relay_until > @t:timestamptz
              GROUP BY relay'''),
      parameters: {'t': now},
    );
    final nodesByRelay = {
      for (final [relay as String, n as int] in assigned) relay: n,
    };
    final traffic = await s.execute(
      Sql.named('''
            SELECT method, sum(bytes)::int8, sum(connections)::int8,
                   count(DISTINCT account_id)
              FROM traffic_daily WHERE day >= @d:date
              GROUP BY method ORDER BY method'''),
      parameters: {'d': firstDay},
    );
    final byMethod = <String, Map<String, Object?>>{};
    var total = 0;
    var relayed = 0;
    for (final [
          method as int,
          bytes as int,
          connections as int,
          accounts as int,
        ]
        in traffic) {
      final name = switch (method) {
        1 => 'direct',
        2 => 'udp',
        3 => 'relay',
        _ => '$method',
      };
      byMethod[name] = {
        'bytes': bytes,
        'connections': connections,
        'accounts': accounts,
      };
      total += bytes;
      if (method == 3) relayed = bytes;
    }
    final [accountsUsingRelay as int] = (await s.execute(
      Sql.named('''
            SELECT count(DISTINCT account_id) FROM relay_usage
              WHERE day >= @d:date'''),
      parameters: {'d': firstDay},
    )).single;
    return {
      'days': days,
      'relays': [
        for (final [
              relay as String,
              last as DateTime,
              bytes as int,
              opened as int,
              listeners as int,
              sessions as int,
            ]
            in relays)
          {
            'relay': relay,
            'lastReportAt': _iso(last),
            'listeners': listeners,
            'sessions': sessions,
            'sessionsOpened': opened,
            'bytes': bytes,
            'nodesAssigned': nodesByRelay[relay] ?? 0,
          },
      ],
      'nodesOnRelay': nodesByRelay.values.fold<int>(0, (a, b) => a + b),
      'accountsUsingRelay': accountsUsingRelay,
      'traffic': byMethod,
      'relayShare': total == 0
          ? null
          : double.parse((relayed / total).toStringAsFixed(4)),
    };
  });

  /// Последние записи журнала, новые сначала.
  Future<List<AuditRecord>> audit({int limit = 50}) async {
    final rows = await _db.run(
      (s) => s.execute(
        Sql.named('''
          SELECT id, at, os_user, db_user, command, arguments, reason, result
            FROM admin_audit ORDER BY id DESC LIMIT @n:int4'''),
        parameters: {'n': limit},
      ),
    );
    return [
      for (final [
            id as int,
            at as DateTime,
            osUser as String,
            dbUser as String,
            command as String,
            arguments,
            reason as String?,
            result as String,
          ]
          in rows)
        {
          'id': id,
          'at': _iso(at),
          'osUser': osUser,
          'dbUser': dbUser,
          'command': command,
          'arguments': arguments,
          'reason': reason,
          'result': result,
        },
    ];
  }

  /// Изменяющее действие [body] и запись журнала в одной транзакции;
  /// неудача — запись с ошибкой отдельно.
  Future<Map<String, Object?>> _audited(
    String command,
    Map<String, Object?> arguments,
    AdminActor actor,
    Future<Map<String, Object?>> Function(TxSession tx) body,
  ) async {
    if (actor.reason.trim().isEmpty) {
      throw const AdminException('укажите причину (--reason)');
    }
    Future<AuditRecord> write(Session s, String result) async {
      final rows = await s.execute(
        Sql.named('''
          INSERT INTO admin_audit (os_user, command, arguments, reason, result)
            VALUES (@u:text, @c:text, @g:jsonb, @r:text, @s:text)
            RETURNING id, at, db_user'''),
        parameters: {
          'u': actor.osUser,
          'c': command,
          'g': jsonEncode(arguments),
          'r': actor.reason,
          's': result,
        },
      );
      final [id as int, at as DateTime, dbUser as String] = rows.single;
      return {
        'id': id,
        'at': _iso(at),
        'osUser': actor.osUser,
        'dbUser': dbUser,
        'command': command,
        'arguments': arguments,
        'reason': actor.reason,
        'result': result,
      };
    }

    try {
      final (outcome, record) = await _db.transaction((tx) async {
        final outcome = await body(tx);
        final changed = outcome['changed'] == true;
        return (outcome, await write(tx, changed ? 'ok' : 'unchanged'));
      });
      _copy(record);
      return {...outcome, 'auditId': record['id']};
    } on AdminException catch (e) {
      _copy(await _db.run((s) => write(s, 'error: ${e.message}')));
      rethrow;
    }
  }

  void _copy(AuditRecord record) {
    try {
      journal?.call(record);
    } on Object {
      // Копия в журнал ОС — дополнительная; основная запись в базе.
    }
  }

  static String _segmentState(int state) => switch (state) {
    0 => 'allocated',
    1 => 'stored',
    _ => 'needsRepair',
  };

  static String? _iso(DateTime? t) => t?.toUtc().toIso8601String();
}
