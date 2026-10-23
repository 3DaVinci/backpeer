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
          'SELECT 1 FROM accounts WHERE account_id = @a:bytea FOR UPDATE',
        ),
        parameters: {'a': owner},
      );
      if (account.isEmpty) {
        throw const RpcException(
          pb.ErrorCode.ERROR_CODE_UNAUTHENTICATED,
          'владелец узла не зарегистрирован',
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
    _checkEndpoints(request.endpoints);
    final subnet = _subnet(context);
    final now = _clock();
    await _db.transaction((tx) async {
      await tx.execute(
        Sql.named('''
          UPDATE nodes SET capacity_bytes = @cap:int8, used_bytes = @u:int8,
                 endpoints = @e:_text, subnet = @sub:text
            WHERE node_id = @n:bytea'''),
        parameters: {
          'n': nodeId,
          'cap': capacity,
          'u': request.usedBytes.toInt(),
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
  /// (задача 2.7.1): в сети, не удалены, свободного места хватает,
  /// доступность не ниже [minAvailability], подсеть известна. Свободное
  /// место — ёмкость минус большее из занятого по словам узла и выданного
  /// координатором под фрагменты. Узлы владельца сегмента [exceptOwner]
  /// исключаются; узлы моложе [probation] помечаются. Разнообразие
  /// владельцев и подсетей обеспечивает [Placement].
  Future<List<NodeCandidate>> candidates({
    required int fragmentSize,
    required double minAvailability,
    Uint8List? exceptOwner,
    Duration probation = Duration.zero,
    Session? session,
  }) async {
    final now = _clock();
    final query = Sql.named('''
      SELECT node_id, account_id, subnet,
             capacity_bytes - greatest(used_bytes, assigned_bytes),
             availability, endpoints, registered_at > @probation:timestamptz
        FROM nodes
        WHERE removed_at IS NULL
          AND last_heartbeat_at >= @online:timestamptz
          AND subnet IS NOT NULL
          AND capacity_bytes - greatest(used_bytes, assigned_bytes)
              >= @size:int8
          AND availability >= @min:float8
          AND account_id <> @owner:bytea''');
    final parameters = {
      'online': now.subtract(policy.onlineWindow),
      'probation': now.subtract(probation),
      'size': fragmentSize,
      'min': minAvailability,
      'owner': exceptOwner ?? Uint8List(0),
    };
    final rows = session != null
        ? await session.execute(query, parameters: parameters)
        : await _db.run((s) => s.execute(query, parameters: parameters));
    return [
      for (final [
            id as List<int>,
            owner as List<int>,
            subnet as String,
            free as int,
            availability as double,
            endpoints as List<Object?>,
            onProbation as bool,
          ]
          in rows)
        NodeCandidate(
          nodeId: Uint8List.fromList(id),
          ownerId: Uint8List.fromList(owner),
          subnet: subnet,
          freeBytes: free,
          availability: availability,
          endpoints: [for (final e in endpoints) e! as String],
          onProbation: onProbation,
        ),
    ];
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
        'SELECT registered_at FROM nodes WHERE node_id = @n:bytea FOR UPDATE',
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
