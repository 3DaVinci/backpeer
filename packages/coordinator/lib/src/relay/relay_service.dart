import 'dart:typed_data';

import 'package:coordinator/src/auth/key_directory.dart';
import 'package:coordinator/src/db/database.dart';
import 'package:coordinator/src/log.dart';
import 'package:coordinator/src/relay/relay_policy.dart';
import 'package:coordinator/src/rpc/call_context.dart';
import 'package:coordinator/src/rpc/errors.dart';
import 'package:core/core.dart';
import 'package:fixnum/fixnum.dart';
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:protocol/protocol.dart' as pb;

/// Relay на координаторе (задачи 3.8.2, 3.8.3; protocol.md, раздел 4.12):
/// выдача пропусков, объём через relay на учётную запись, отчёты relay и
/// отчёты клиентов о трафике по способам подключения.
///
/// - **LISTEN** — узлу на самого себя: координатор назначает узлу relay
///   (прежний, если он ещё в настройках, иначе — по хэшу `node_id` среди
///   relay из настроек) и запоминает его до срока пропуска.
/// - **CONNECT** — устройству или узлу при ремонте к узлу, у которого
///   действует LISTEN: на тот же relay. Предел байт пропуска — меньшее из
///   [RelayPolicy.passBytes] и остатка суточного предела учётной записи
///   по отчётам relay; остатка нет — `QUOTA_EXCEEDED`.
///
/// Пропуска подписывает ключ пропусков [passKey] в процессе веб-сервера,
/// а не подписант талонов: пропуск даёт только трафик через relay, но не
/// доступ к данным (модель угроз, С-13).
final class RelayService {
  new({
    required this._db,
    required this._crypto,
    this.policy = const RelayPolicy(),
    this.passKey,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now,
       _limiter = RateLimiter(
         perSecond: policy.perMinute / 60,
         burst: policy.burst,
         clock: clock,
       );

  final Database _db;
  final CryptoProvider _crypto;
  final RelayPolicy policy;

  /// Ключ пропусков; `null` — relay выключен.
  final Ed25519KeyPair? passKey;
  final DateTime Function() _clock;
  final RateLimiter _limiter;

  static final _log = Logger('relay');

  /// Записей в отчёте relay не больше.
  static const maxUsageEntries = 10000;

  /// Байт в одной записи отчёта не больше: защита счётчиков от
  /// переполнения.
  static const int maxReportedBytes = 1 << 50;

  bool get enabled => passKey != null && policy.servers.isNotEmpty;

  Future<pb.GetRelayPassResponse> getPass(
    CallContext context,
    pb.GetRelayPassRequest request,
  ) async {
    final caller = context.caller!;
    final info = caller.info!;
    final nodeId = Uint8List.fromList(request.nodeId);
    if (nodeId.length != 32) throw _bad('node_id — 32 байта');
    if (_limiter.take(bytesToHex(caller.publicKey)) case final wait?) {
      throw RpcException(
        pb.ErrorCode.ERROR_CODE_RATE_LIMITED,
        'превышена частота пропусков relay',
        retryAfter: wait,
      );
    }
    final key = passKey;
    if (key == null || policy.servers.isEmpty) {
      throw const RpcException(
        pb.ErrorCode.ERROR_CODE_NOT_FOUND,
        'relay выключен',
      );
    }
    final now = _clock();
    final expires = now.add(policy.passLifetime);
    final listen =
        info.kind == KeyKind.node &&
        constantTimeEquals(nodeId, caller.publicKey);
    final RelayServerInfo relay;
    final int maxBytes;
    if (listen) {
      relay = await _assign(nodeId, expires);
      maxBytes = 0;
    } else {
      relay = await _relayOf(nodeId, now);
      final used = await _usedToday(info.accountId, now);
      final left = policy.accountBytesPerDay - used;
      if (left <= 0) {
        throw RpcException(
          pb.ErrorCode.ERROR_CODE_QUOTA_EXCEEDED,
          'исчерпан суточный объём через relay',
          retryAfter: _untilNextDay(now),
        );
      }
      maxBytes = left < policy.passBytes ? left : policy.passBytes;
    }
    final pass = await RelayPasses.issue(
      _crypto,
      key,
      pb.RelayPass(
        role: listen
            ? pb.RelayRole.RELAY_ROLE_LISTEN
            : pb.RelayRole.RELAY_ROLE_CONNECT,
        holder: caller.publicKey,
        nodeId: nodeId,
        accountId: info.accountId,
        relay: relay.name,
        passId: _crypto.randomBytes(RelayWire.passIdLength),
        expiresAtUnixMs: Int64(expires.millisecondsSinceEpoch),
        maxBytes: Int64(maxBytes),
      ),
    );
    _log.fine(
      LogEvent('pass', {
        'rid': context.requestId,
        'role': listen ? 'listen' : 'connect',
        'relay': relay.name,
      }),
    );
    return pb.GetRelayPassResponse(relayEndpoint: relay.endpoint, pass: pass);
  }

  /// Relay узла для LISTEN: прежний, если он ещё в настройках, иначе
  /// новый; запоминается до [until].
  Future<RelayServerInfo> _assign(Uint8List nodeId, DateTime until) =>
      _db.transaction((tx) async {
        final rows = await tx.execute(
          Sql.named(
            'SELECT relay FROM nodes WHERE node_id = @n:bytea FOR UPDATE',
          ),
          parameters: {'n': nodeId},
        );
        if (rows.isEmpty) {
          throw const RpcException(
            pb.ErrorCode.ERROR_CODE_NOT_FOUND,
            'узел не зарегистрирован',
          );
        }
        final current = rows.single.single as String?;
        final relay =
            (current == null ? null : policy.byName(current)) ?? choose(nodeId);
        await tx.execute(
          Sql.named('''
            UPDATE nodes SET relay = @r:text, relay_until = @u:timestamptz
              WHERE node_id = @n:bytea'''),
          parameters: {'n': nodeId, 'r': relay.name, 'u': until},
        );
        return relay;
      });

  /// Relay из настроек для узла без назначенного: наибольший
  /// `H(node_id || имя)` — одинаково на любом экземпляре координатора, и
  /// при добавлении relay переезжает только часть узлов.
  RelayServerInfo choose(Uint8List nodeId) {
    RelayServerInfo? best;
    Uint8List? bestScore;
    for (final s in policy.servers) {
      final score = _crypto.blake2b256(
        Uint8List.fromList([...nodeId, ...s.name.codeUnits]),
      );
      if (bestScore == null || _compare(score, bestScore) > 0) {
        best = s;
        bestScore = score;
      }
    }
    return best!;
  }

  static int _compare(Uint8List a, Uint8List b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return a[i] - b[i];
    }
    return 0;
  }

  /// Relay узла с действующим LISTEN; нет — `NOT_FOUND`.
  Future<RelayServerInfo> _relayOf(Uint8List nodeId, DateTime now) async {
    final rows = await _db.run(
      (s) => s.execute(
        Sql.named('''
          SELECT n.relay FROM nodes n JOIN accounts a USING (account_id)
            WHERE n.node_id = @n:bytea AND n.removed_at IS NULL
              AND a.blocked_at IS NULL AND n.relay_until > @t:timestamptz'''),
        parameters: {'n': nodeId, 't': now},
      ),
    );
    final name = rows.isEmpty ? null : rows.single.single as String?;
    final relay = name == null ? null : policy.byName(name);
    if (relay == null) {
      throw const RpcException(
        pb.ErrorCode.ERROR_CODE_NOT_FOUND,
        'узел не на relay',
      );
    }
    return relay;
  }

  Future<int> _usedToday(Uint8List accountId, DateTime now) async {
    final rows = await _db.run(
      (s) => s.execute(
        Sql.named('''
          SELECT bytes FROM relay_usage
            WHERE account_id = @a:bytea AND day = @d:date'''),
        parameters: {'a': accountId, 'd': _day(now)},
      ),
    );
    return rows.isEmpty ? 0 : rows.single.single! as int;
  }

  Future<pb.ReportRelayUsageResponse> report(
    CallContext context,
    pb.ReportRelayUsageRequest request,
  ) async {
    final relay = policy.byKey(context.caller!.publicKey);
    if (relay == null) {
      // Ключ из настроек, но relay убран из них между проверкой и вызовом.
      throw const RpcException(
        pb.ErrorCode.ERROR_CODE_UNAUTHENTICATED,
        'relay не в настройках',
      );
    }
    if (request.relay != relay.name) {
      throw _bad('relay: имя не этого ключа');
    }
    if (request.usage.length > maxUsageEntries) {
      throw _bad('usage: не больше $maxUsageEntries записей');
    }
    final ids = <Uint8List>[];
    final bytes = <int>[];
    final sessions = <int>[];
    final seen = <String>{};
    for (final u in request.usage) {
      final b = u.bytes.toInt();
      if (u.accountId.length != 32 || b < 0 || b > maxReportedBytes) {
        throw _bad('usage: account_id — 32 байта, bytes — до 2^50');
      }
      if (!seen.add(bytesToHex(u.accountId))) {
        throw _bad('usage: учётная запись повторяется');
      }
      ids.add(Uint8List.fromList(u.accountId));
      bytes.add(b);
      sessions.add(u.sessions);
    }
    final total = request.bytes.toInt();
    final opened = request.sessionsOpened.toInt();
    if (total < 0 ||
        total > maxReportedBytes ||
        opened < 0 ||
        opened > maxReportedBytes) {
      throw _bad('bytes и sessions_opened — до 2^50');
    }
    final now = _clock();
    await _db.transaction((tx) async {
      if (ids.isNotEmpty) {
        // Учётные записи, которых координатор не знает, пропускаются:
        // пропуск выдан другим экземпляром или до очистки базы стенда.
        await tx.execute(
          Sql.named('''
            INSERT INTO relay_usage (account_id, day, bytes, sessions)
            SELECT u.a, @d:date, u.b, u.s
              FROM unnest(@ids:_bytea, @b:_int8, @s:_int8) AS u(a, b, s)
              WHERE EXISTS (
                SELECT 1 FROM accounts WHERE account_id = u.a)
            ON CONFLICT (account_id, day) DO UPDATE SET
              bytes = relay_usage.bytes + EXCLUDED.bytes,
              sessions = relay_usage.sessions + EXCLUDED.sessions'''),
          parameters: {'d': _day(now), 'ids': ids, 'b': bytes, 's': sessions},
        );
      }
      await tx.execute(
        Sql.named('''
          INSERT INTO relay_reports
            (relay, at, listeners, sessions, sessions_opened, bytes)
          VALUES (@r:text, @t:timestamptz, @l:int4, @s:int4, @o:int8,
                  @b:int8)'''),
        parameters: {
          'r': relay.name,
          't': now,
          'l': request.listeners,
          's': request.sessions,
          'o': opened,
          'b': total,
        },
      );
      await tx.execute(
        Sql.named('DELETE FROM relay_reports WHERE at < @t:timestamptz'),
        parameters: {'t': now.subtract(reportRetention)},
      );
    });
    _log.fine(
      LogEvent('relay_report', {
        'rid': context.requestId,
        'relay': relay.name,
        'bytes': total,
        'listeners': request.listeners,
      }),
    );
    return pb.ReportRelayUsageResponse(
      nextReportMs: policy.reportInterval.inMilliseconds,
    );
  }

  /// Сколько хранить отчёты relay.
  static const reportRetention = Duration(days: 90);

  Future<pb.ReportTrafficResponse> traffic(
    CallContext context,
    pb.ReportTrafficRequest request,
  ) async {
    final accountId = context.caller!.info!.accountId;
    final methods = <int>[];
    final bytes = <int>[];
    final connections = <int>[];
    for (final t in request.traffic) {
      final m = t.method.value;
      final b = t.bytes.toInt();
      if (t.method == pb.ConnectionMethod.CONNECTION_METHOD_UNSPECIFIED ||
          methods.contains(m)) {
        throw _bad('traffic: способ не задан или повторяется');
      }
      if (b < 0 || b > maxReportedBytes) throw _bad('bytes — до 2^50');
      methods.add(m);
      bytes.add(b);
      connections.add(t.connections);
    }
    if (methods.isEmpty) return pb.ReportTrafficResponse();
    await _db.transaction(
      (tx) => tx.execute(
        Sql.named('''
          INSERT INTO traffic_daily (account_id, day, method, bytes, connections)
          SELECT @a:bytea, @d:date, u.m, u.b, u.c
            FROM unnest(@m:_int2, @b:_int8, @c:_int8) AS u(m, b, c)
          ON CONFLICT (account_id, day, method) DO UPDATE SET
            bytes = traffic_daily.bytes + EXCLUDED.bytes,
            connections = traffic_daily.connections + EXCLUDED.connections'''),
        parameters: {
          'a': accountId,
          'd': _day(_clock()),
          'm': methods,
          'b': bytes,
          'c': connections,
        },
      ),
    );
    return pb.ReportTrafficResponse();
  }

  /// Сутки UTC, к которым относится [t].
  static DateTime _day(DateTime t) {
    final u = t.toUtc();
    return DateTime.utc(u.year, u.month, u.day);
  }

  static Duration _untilNextDay(DateTime now) =>
      _day(now).add(const Duration(days: 1)).difference(now.toUtc());

  static RpcException _bad(String message) =>
      RpcException(pb.ErrorCode.ERROR_CODE_BAD_REQUEST, message);
}
