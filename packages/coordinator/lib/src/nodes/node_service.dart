import 'dart:io';
import 'dart:typed_data';

import 'package:coordinator/src/accounts/certificates.dart';
import 'package:coordinator/src/auth/key_directory.dart';
import 'package:coordinator/src/db/database.dart';
import 'package:coordinator/src/log.dart';
import 'package:coordinator/src/nodes/node_address.dart';
import 'package:coordinator/src/nodes/node_policy.dart';
import 'package:coordinator/src/nodes/uptime.dart';
import 'package:coordinator/src/placement/placement.dart';
import 'package:coordinator/src/rpc/call_context.dart';
import 'package:coordinator/src/rpc/errors.dart';
import 'package:core/core.dart'
    show NoiseProbe, NoiseProbeResult, bytesToHex, constantTimeEquals;
import 'package:fixnum/fixnum.dart';
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:protocol/protocol.dart' as pb;

/// Реестр узлов: регистрация, heartbeat, доступность (задачи 2.6.1,
/// 2.6.2; protocol.md, раздел 4.9).
final class NodeService {
  new(
    this._db,
    this._checks, {
    this.policy = const NodePolicy(),
    this._coordinatorKeys,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Database _db;
  final CertificateChecks _checks;
  final NodePolicy policy;

  /// Ключи, которыми подписант подписывает талоны сейчас (protocol.md,
  /// раздел 5.1); `null` — подписант не настроен.
  final Future<List<Uint8List>> Function()? _coordinatorKeys;
  final DateTime Function() _clock;

  /// Версии протокола, которые знает координатор (protocol.md, раздел 2).
  static const supportedVersions = {1};

  static const _maxSoftwareLength = 64;

  static final _log = Logger('nodes');

  Future<pb.RegisterNodeResponse> register(
    CallContext context,
    pb.RegisterNodeRequest request,
  ) async {
    final caller = context.caller!;
    final nodeId = caller.publicKey;
    final known = caller.info;
    if (known != null && known.kind != KeyKind.node) {
      throw const RpcException(
        pb.ErrorCode.ERROR_CODE_PERMISSION_DENIED,
        'ключ зарегистрирован не как узел',
      );
    }
    final cert = await _checks.nodeCertificate(request.nodeCertificate, nodeId);
    final owner = Uint8List.fromList(cert.accountId);
    if (!request.versions.any(supportedVersions.contains)) {
      throw const RpcException(
        pb.ErrorCode.ERROR_CODE_VERSION_UNSUPPORTED,
        'нет общей версии протокола',
      );
    }
    final capacity = _capacity(request.capacityBytes);
    if (capacity < policy.minCapacityBytes) {
      throw _bad('ёмкость меньше ${policy.minCapacityBytes} байт');
    }
    _checkEndpoints(request.endpoints);
    final software = request.software;
    if (software.length > _maxSoftwareLength ||
        software.codeUnits.any((c) => c < 0x20 || c > 0x7e)) {
      throw _bad('software — до 64 печатных символов ASCII');
    }
    final subnet = _subnet(context);
    final now = _clock();

    final created = await _db.transaction((tx) async {
      // Блокировка учётной записи: одновременные регистрации не превысят
      // предел узлов.
      final account = await tx.execute(
        Sql.named(
          'SELECT blocked_at IS NOT NULL FROM accounts '
          'WHERE account_id = @a:bytea FOR UPDATE',
        ),
        parameters: {'a': owner},
      );
      if (account.isEmpty) {
        throw const RpcException(
          pb.ErrorCode.ERROR_CODE_UNAUTHENTICATED,
          'владелец узла не зарегистрирован',
        );
      }
      if (account.single.single! as bool) {
        throw const RpcException(
          pb.ErrorCode.ERROR_CODE_PERMISSION_DENIED,
          'учётная запись владельца заблокирована',
        );
      }
      final count = await tx.execute(
        Sql.named('''
          SELECT count(*) FROM nodes
            WHERE account_id = @a:bytea AND removed_at IS NULL
              AND node_id <> @n:bytea'''),
        parameters: {'a': owner, 'n': nodeId},
      );
      if ((count.single.single! as int) >= policy.maxPerAccount) {
        throw RpcException(
          pb.ErrorCode.ERROR_CODE_QUOTA_EXCEEDED,
          'не больше ${policy.maxPerAccount} узлов на учётную запись',
        );
      }
      // Повторная регистрация того же узла тем же владельцем обновляет
      // сведения; чужой узел не перехватывается.
      final rows = await tx.execute(
        Sql.named('''
          INSERT INTO nodes
            (node_id, account_id, certificate, registered_at, capacity_bytes,
             endpoints, versions, software, subnet)
          VALUES (@n:bytea, @a:bytea, @c:bytea, @t:timestamptz, @cap:int8,
                  @e:_text, @v:_int4, @sw:text, @sub:text)
          ON CONFLICT (node_id) DO UPDATE
            SET certificate = excluded.certificate,
                capacity_bytes = excluded.capacity_bytes,
                endpoints = excluded.endpoints,
                versions = excluded.versions,
                software = excluded.software,
                subnet = excluded.subnet
            WHERE nodes.account_id = excluded.account_id
              AND nodes.removed_at IS NULL
          RETURNING registered_at = @t:timestamptz'''),
        parameters: {
          'n': nodeId,
          'a': owner,
          'c': request.nodeCertificate.writeToBuffer(),
          't': now,
          'cap': capacity,
          'e': request.endpoints.toList(),
          'v': request.versions.toList(),
          'sw': software,
          'sub': subnet,
        },
      );
      if (rows.isEmpty) {
        throw const RpcException(
          pb.ErrorCode.ERROR_CODE_ALREADY_EXISTS,
          'узел зарегистрирован другой учётной записью',
        );
      }
      await _beat(tx, nodeId, now);
      return rows.single.single! as bool;
    });
    _log.info(
      LogEvent(created ? 'node_registered' : 'node_updated', {
        'rid': context.requestId,
      }),
    );
    return pb.RegisterNodeResponse(coordinatorKeys: await _keys());
  }

  /// Ключи подписанта; недоступен — пустой список: регистрация узла от
  /// подписанта не зависит, узел доверяет только вшитому списку.
  Future<List<Uint8List>> _keys() async {
    final keys = _coordinatorKeys;
    if (keys == null) return const [];
    try {
      return await keys();
    } on RpcException catch (e) {
      _log.warning(LogEvent('signer_key_unavailable', {'code': e.code.value}));
      return const [];
    }
  }

  Future<pb.HeartbeatResponse> heartbeat(
    CallContext context,
    pb.HeartbeatRequest request,
  ) async {
    final nodeId = context.caller!.publicKey;
    final capacity = _capacity(request.capacityBytes);
    if (request.usedBytes.isNegative || request.usedBytes.toInt() > capacity) {
      throw _bad('used_bytes больше ёмкости');
    }
    int? free;
    if (request.hasFreeBytes()) {
      free = _capacity(request.freeBytes);
      if (free > capacity) throw _bad('free_bytes больше ёмкости');
    }
    _checkEndpoints(request.endpoints);
    final subnet = _subnet(context);
    final now = _clock();
    await _db.transaction((tx) async {
      await tx.execute(
        Sql.named('''
          UPDATE nodes SET capacity_bytes = @cap:int8, used_bytes = @u:int8,
                 free_bytes = @free:int8, endpoints = @e:_text,
                 subnet = @sub:text
            WHERE node_id = @n:bytea'''),
        parameters: {
          'n': nodeId,
          'cap': capacity,
          'u': request.usedBytes.toInt(),
          'free': free,
          'e': request.endpoints.toList(),
          'sub': subnet,
        },
      );
      await _beat(tx, nodeId, now);
    });
    return pb.HeartbeatResponse(
      nextHeartbeatMs: policy.heartbeatInterval.inMilliseconds,
    );
  }

  /// Наибольшее число фрагментов в одном `ReportDamagedFragments`.
  static const maxDamagedPerReport = 1000;

  /// `ReportDamagedFragments` (задача 3.2.4): отмечает фрагменты этого
  /// узла повреждёнными. Фрагменты, которых координатор не знает на этом
  /// узле, пропускаются: узел может хранить фрагменты без ссылок
  /// (protocol.md, раздел 5.2). Повторный отчёт — не ошибка.
  Future<pb.ReportDamagedFragmentsResponse> reportDamaged(
    CallContext context,
    pb.ReportDamagedFragmentsRequest request,
  ) async {
    final ids = request.fragmentIds;
    if (ids.isEmpty || ids.length > maxDamagedPerReport) {
      throw _bad('fragment_ids: от 1 до $maxDamagedPerReport');
    }
    if (ids.any((id) => id.length != 32)) {
      throw _bad('fragment_ids: по 32 байта');
    }
    final nodeId = context.caller!.publicKey;
    final rows = await _db.transaction(
      (tx) => tx.execute(
        Sql.named('''
          UPDATE fragments
            SET damaged_at = coalesce(damaged_at, @t:timestamptz)
            WHERE node_id = @n:bytea AND fragment_id = ANY(@ids:_bytea)
            RETURNING 1'''),
        parameters: {
          'n': nodeId,
          't': _clock(),
          'ids': [for (final id in ids) Uint8List.fromList(id)],
        },
      ),
    );
    _log.warning(
      LogEvent('fragments_damaged', {
        'node_id': bytesToHex(nodeId),
        'reported': ids.length,
        'known': rows.length,
      }),
    );
    return pb.ReportDamagedFragmentsResponse(known: rows.length);
  }

  /// Портов в одном `CheckReachability`.
  static const maxReachabilityPorts = 4;

  int _probing = 0;

  /// `CheckReachability` (задача 3.5.1): подключается к адресу, с которого
  /// пришёл запрос, на каждый порт и проверяет, что отвечает этот узел
  /// (первые два сообщения Noise XX, ключ `node_dh` из сертификата
  /// узла). Другие адреса не проверяются: координатор не должен
  /// подключаться туда, куда укажет узел. С частного адреса — без
  /// проверки, если не включено [NodePolicy.checkPrivateAddresses].
  Future<pb.CheckReachabilityResponse> checkReachability(
    CallContext context,
    pb.CheckReachabilityRequest request,
  ) async {
    final ports = request.ports;
    if (ports.isEmpty || ports.length > maxReachabilityPorts) {
      throw _bad('ports: от 1 до $maxReachabilityPorts');
    }
    if (ports.toSet().length != ports.length ||
        ports.any((p) => p < 1 || p > 65535)) {
      throw _bad('ports: разные числа от 1 до 65535');
    }
    final address = NodeAddresses.observed(context.clientAddress);
    if (address == null) {
      throw const RpcException(
        pb.ErrorCode.ERROR_CODE_INTERNAL,
        'адрес клиента не определён',
      );
    }
    final nodeId = context.caller!.publicKey;
    final rows = await _db.run(
      (s) => s.execute(
        Sql.named(
          'SELECT certificate FROM nodes '
          'WHERE node_id = @n:bytea AND removed_at IS NULL',
        ),
        parameters: {'n': nodeId},
      ),
    );
    if (rows.isEmpty) {
      throw const RpcException(
        pb.ErrorCode.ERROR_CODE_NOT_FOUND,
        'узел не зарегистрирован',
      );
    }
    final certificate = pb.NodeCertificate.fromBuffer(
      pb.Signed.fromBuffer(rows.single.single! as List<int>).body,
    );
    final nodeDh = Uint8List.fromList(certificate.nodeDh);
    final List<pb.ReachabilityStatus> statuses;
    if (!policy.checkPrivateAddresses && !NodeAddresses.isPublic(address)) {
      statuses = [
        for (final _ in ports)
          pb.ReachabilityStatus.REACHABILITY_STATUS_NOT_CHECKED,
      ];
    } else {
      if (_probing + ports.length > policy.maxReachabilityChecks) {
        throw const RpcException(
          pb.ErrorCode.ERROR_CODE_UNAVAILABLE,
          'слишком много проверок достижимости',
          retryAfter: Duration(seconds: 30),
        );
      }
      _probing += ports.length;
      try {
        statuses = await Future.wait([
          for (final port in ports) _probe(address, port, nodeDh),
        ]);
      } finally {
        _probing -= ports.length;
      }
    }
    _log.info(
      LogEvent('reachability_checked', {
        'rid': context.requestId,
        'node_id': bytesToHex(nodeId),
        'results': [
          for (var i = 0; i < ports.length; i++)
            '${ports[i]}:${_statusName(statuses[i])}',
        ],
      }),
    );
    return pb.CheckReachabilityResponse(
      observedAddress: address.address,
      results: [
        for (var i = 0; i < ports.length; i++)
          pb.ReachabilityResult(port: ports[i], status: statuses[i]),
      ],
    );
  }

  Future<pb.ReachabilityStatus> _probe(
    InternetAddress address,
    int port,
    Uint8List nodeDh,
  ) async {
    final result = await NoiseProbe.probe(
      _checks.crypto,
      address: address,
      port: port,
      expectedStatic: nodeDh,
      timeout: policy.reachabilityTimeout,
    );
    return switch (result) {
      NoiseProbeResult.reachable =>
        pb.ReachabilityStatus.REACHABILITY_STATUS_REACHABLE,
      NoiseProbeResult.refused =>
        pb.ReachabilityStatus.REACHABILITY_STATUS_REFUSED,
      NoiseProbeResult.timeout =>
        pb.ReachabilityStatus.REACHABILITY_STATUS_TIMEOUT,
      NoiseProbeResult.wrongPeer =>
        pb.ReachabilityStatus.REACHABILITY_STATUS_WRONG_PEER,
    };
  }

  static String _statusName(pb.ReachabilityStatus s) =>
      s.name.replaceFirst('REACHABILITY_STATUS_', '').toLowerCase();

  /// Доступность узла на момент [at] (по умолчанию — сейчас) или `null`,
  /// если узла нет.
  Future<double?> availability(Uint8List nodeId, {DateTime? at}) async {
    final now = at ?? _clock();
    return await _db.transaction((tx) async {
      final rows = await tx.execute(
        Sql.named('SELECT registered_at FROM nodes WHERE node_id = @n:bytea'),
        parameters: {'n': nodeId},
      );
      if (rows.isEmpty) return null;
      return await _availability(
        tx,
        nodeId,
        rows.single.single! as DateTime,
        now,
      );
    });
  }

  /// Узлы, подходящие для размещения фрагментов размера [fragmentSize]
  /// (задача 2.7.1): в сети, не удалены и не исключены оператором, владелец
  /// не заблокирован, свободного места хватает, доступность не ниже
  /// [minAvailability], подсеть известна. Свободное место — ёмкость минус
  /// большее из занятого по словам узла и выданного координатором под
  /// фрагменты. Узлы владельца сегмента [exceptOwner] исключаются; узлы
  /// моложе [probation] помечаются. Разнообразие владельцев и подсетей
  /// обеспечивает [Placement].
  ///
  /// Список узлов в сети кэшируется на [cacheFor] (настройка
  /// `placement.candidates_cache_ms`): выборка и разбор тысячи строк на
  /// каждое размещение занимали ядро координатора (нагрузочный тест
  /// 2.9.3). Место, выданное за время жизни кэша, вычитается в нём же
  /// ([noteAssigned]); изменения от heartbeat видны после обновления кэша.
  Future<List<NodeCandidate>> candidates({
    required int fragmentSize,
    required double minAvailability,
    Uint8List? exceptOwner,
    Duration probation = Duration.zero,
    Duration cacheFor = Duration.zero,
  }) async {
    final now = _clock();
    final online = await _online(now, cacheFor);
    final probationStart = now.subtract(probation);
    return [
      for (final node in online)
        if (node.freeBytes >= fragmentSize &&
            node.availability >= minAvailability &&
            (exceptOwner == null ||
                !constantTimeEquals(node.ownerId, exceptOwner)))
          NodeCandidate(
            nodeId: node.nodeId,
            ownerId: node.ownerId,
            subnet: node.subnet,
            freeBytes: node.freeBytes,
            availability: node.availability,
            endpoints: node.endpoints,
            onProbation: node.registeredAt.isAfter(probationStart),
          ),
    ];
  }

  /// Координатор выдал узлам [nodeIds] ещё по [bytes] байт: учесть в кэше
  /// кандидатов до его обновления.
  void noteAssigned(Iterable<Uint8List> nodeIds, int bytes) {
    final cache = _cache;
    if (cache == null) return;
    for (final id in nodeIds) {
      cache.byId[bytesToHex(id)]?.freeBytes -= bytes;
    }
  }

  _OnlineCache? _cache;
  Future<_OnlineCache>? _loading;

  Future<List<_OnlineNode>> _online(DateTime now, Duration cacheFor) async {
    final cache = _cache;
    if (cache != null && cache.age.elapsed < cacheFor) return cache.nodes;
    // Одновременные размещения ждут одну выборку, а не делают свои.
    final loading = _loading ??= _load(now).whenComplete(() => _loading = null);
    final fresh = await loading;
    if (cacheFor > Duration.zero) _cache = fresh;
    return fresh.nodes;
  }

  Future<_OnlineCache> _load(DateTime now) async {
    final rows = await _db.run(
      (s) => s.execute(
        Sql.named('''
          SELECT node_id, account_id, subnet,
                 least(capacity_bytes - greatest(used_bytes, assigned_bytes),
                       free_bytes - greatest(assigned_bytes - used_bytes, 0)),
                 availability, endpoints, registered_at
            FROM nodes
            WHERE removed_at IS NULL
              AND excluded_at IS NULL
              AND account_id NOT IN (
                SELECT account_id FROM accounts WHERE blocked_at IS NOT NULL)
              AND last_heartbeat_at >= @online:timestamptz
              AND subnet IS NOT NULL'''),
        parameters: {'online': now.subtract(policy.onlineWindow)},
      ),
    );
    final nodes = [
      for (final [
            id as List<int>,
            owner as List<int>,
            subnet as String,
            free as int,
            availability as double,
            endpoints as List<Object?>,
            registered as DateTime,
          ]
          in rows)
        _OnlineNode(
          nodeId: Uint8List.fromList(id),
          ownerId: Uint8List.fromList(owner),
          subnet: subnet,
          freeBytes: free,
          availability: availability,
          endpoints: [for (final e in endpoints) e! as String],
          registeredAt: registered,
        ),
    ];
    return _OnlineCache(nodes);
  }

  /// Отмечает узел в сети: интервал засчитан, доступность пересчитана,
  /// история старше окна удалена.
  Future<void> _beat(TxSession tx, Uint8List nodeId, DateTime now) async {
    final slot = Uptime.slotAt(now);
    final day = Uptime.dayOf(slot);
    await tx.execute(
      Sql.named('''
        INSERT INTO node_uptime (node_id, day, slots)
          VALUES (@n:bytea, @d:int4, set_bit(@empty:bytea, @b:int4, 1))
          ON CONFLICT (node_id, day) DO UPDATE
            SET slots = set_bit(node_uptime.slots, @b:int4, 1)'''),
      parameters: {
        'n': nodeId,
        'd': day,
        'empty': Uptime.emptyDay(),
        'b': Uptime.bitOf(slot),
      },
    );
    await tx.execute(
      Sql.named(
        'DELETE FROM node_uptime WHERE node_id = @n:bytea AND day < @d:int4',
      ),
      parameters: {'n': nodeId, 'd': day - Uptime.windowDays},
    );
    final registered = await tx.execute(
      Sql.named(
        // Не FOR UPDATE: она конфликтует с KEY SHARE вставок фрагментов в
        // AllocateSegment и давала взаимоблокировку (2.9.3).
        'SELECT registered_at FROM nodes WHERE node_id = @n:bytea '
        'FOR NO KEY UPDATE',
      ),
      parameters: {'n': nodeId},
    );
    final availability = await _availability(
      tx,
      nodeId,
      registered.single.single! as DateTime,
      now,
    );
    await tx.execute(
      Sql.named('''
        UPDATE nodes SET last_heartbeat_at = @t:timestamptz,
               availability = @av:float8
          WHERE node_id = @n:bytea'''),
      parameters: {'n': nodeId, 't': now, 'av': availability},
    );
  }

  static Future<double> _availability(
    Session s,
    Uint8List nodeId,
    DateTime registeredAt,
    DateTime now,
  ) async {
    final rows = await s.execute(
      Sql.named('''
        SELECT day, slots FROM node_uptime
          WHERE node_id = @n:bytea AND day >= @d:int4'''),
      parameters: {
        'n': nodeId,
        'd': Uptime.dayOf(Uptime.slotAt(now)) - Uptime.windowDays,
      },
    );
    return Uptime.availability(
      {
        for (final [day as int, slots as List<int>] in rows)
          day: Uint8List.fromList(slots),
      },
      registeredAt: registeredAt,
      now: now,
    );
  }

  /// Ёмкость — uint64; больше 2^63 − 1 приходит отрицательным Int64.
  static int _capacity(Int64 capacity) {
    if (capacity.isNegative) throw _bad('capacity_bytes слишком велик');
    return capacity.toInt();
  }

  static void _checkEndpoints(List<String> endpoints) {
    final problem = NodeAddresses.endpointsProblem(endpoints);
    if (problem != null) throw _bad('endpoints: $problem');
  }

  /// Подсеть — по адресу, с которого пришёл запрос, а не по заявленным
  /// `endpoints`: их узел может указать любые.
  static String _subnet(CallContext context) =>
      NodeAddresses.subnetOf(context.clientAddress) ??
      (throw const RpcException(
        pb.ErrorCode.ERROR_CODE_INTERNAL,
        'адрес клиента не определён',
      ));

  static RpcException _bad(String message) =>
      RpcException(pb.ErrorCode.ERROR_CODE_BAD_REQUEST, message);
}

/// Узел в сети для кэша кандидатов.
final class _OnlineNode {
  new({
    required this.nodeId,
    required this.ownerId,
    required this.subnet,
    required this.freeBytes,
    required this.availability,
    required this.endpoints,
    required this.registeredAt,
  });

  final Uint8List nodeId;
  final Uint8List ownerId;
  final String subnet;
  int freeBytes;
  final double availability;
  final List<String> endpoints;
  final DateTime registeredAt;
}

final class _OnlineCache {
  new(this.nodes) : byId = {for (final n in nodes) bytesToHex(n.nodeId): n};

  final List<_OnlineNode> nodes;
  final Map<String, _OnlineNode> byId;

  /// Возраст по монотонным часам: подменённые часы тестов не продлевают
  /// кэш.
  final Stopwatch age = Stopwatch()..start();
}
