import 'dart:typed_data';

import 'package:coordinator/src/accounts/certificates.dart';
import 'package:coordinator/src/db/database.dart';
import 'package:coordinator/src/log.dart';
import 'package:coordinator/src/rpc/call_context.dart';
import 'package:coordinator/src/rpc/errors.dart';
import 'package:core/core.dart';
import 'package:fixnum/fixnum.dart';
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:protocol/protocol.dart' as pb;

/// Учётные записи, устройства и отзывы (задачи 2.3.1–2.3.3, protocol.md,
/// раздел 4.7).
final class AccountService {
  new(this._db, this._checks, {this.maxDevices = 5, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final Database _db;
  final CertificateChecks _checks;
  final DateTime Function() _clock;

  /// Действующих устройств на учётную запись.
  final int maxDevices;

  /// Страница `ListRevocations` по умолчанию и наибольшая.
  static const maxRevocationsPage = 1000;

  static final _log = Logger('accounts');

  // Отзывы получают номер и фиксируются по одному: иначе узел, который
  // читает отзывы после номера N, пропустил бы отзыв с меньшим номером,
  // зафиксированный позже.
  static const _revocationLock = 0x46530002;

  Future<pb.RegisterAccountResponse> register(
    CallContext context,
    pb.RegisterAccountRequest request,
  ) async {
    final accountId = context.caller!.publicKey;
    final login = LoginName.normalize(request.login);
    if (login == null) throw _bad('имя для входа недопустимо');
    final cert = await _checks.deviceCertificate(
      request.deviceCertificate,
      accountId,
    );
    final bundle = _checks.keyBundle(
      request.keyBundle,
      request.authVerifier,
      accountId,
    );
    await _uniqueOr(() async {
      await _db.transaction((tx) async {
        await tx.execute(
          Sql.named('''
            INSERT INTO accounts
              (account_id, login, key_bundle, auth_verifier,
               key_bundle_updated_at)
            VALUES (@a:bytea, @l:text, @b:bytea, @v:bytea, @t:timestamptz)'''),
          parameters: {
            'a': accountId,
            'l': login,
            'b': bundle?.toBytes(),
            'v': bundle == null
                ? null
                : Uint8List.fromList(request.authVerifier),
            't': bundle == null ? null : _clock(),
          },
        );
        await _insertDevice(tx, accountId, cert, request.deviceCertificate);
      });
    });
    _log.info(
      LogEvent('account_registered', {
        'rid': context.requestId,
        'key_copy': bundle != null,
      }),
    );
    return pb.RegisterAccountResponse();
  }

  Future<pb.AddDeviceResponse> addDevice(
    CallContext context,
    pb.AddDeviceRequest request,
  ) async {
    final accountId = context.caller!.publicKey;
    final cert = await _checks.deviceCertificate(
      request.deviceCertificate,
      accountId,
    );
    await _uniqueOr(() async {
      await _db.transaction((tx) async {
        // Блокировка учётной записи: два одновременных AddDevice не
        // превысят предел.
        await tx.execute(
          Sql.named(
            'SELECT 1 FROM accounts WHERE account_id = @a:bytea FOR UPDATE',
          ),
          parameters: {'a': accountId},
        );
        final known = await tx.execute(
          Sql.named('SELECT 1 FROM devices WHERE device_sign = @d:bytea'),
          parameters: {'d': cert.deviceSign},
        );
        if (known.isNotEmpty) {
          throw const RpcException(
            pb.ErrorCode.ERROR_CODE_ALREADY_EXISTS,
            'устройство уже зарегистрировано',
          );
        }
        final active = await tx.execute(
          Sql.named(
            'SELECT count(*) FROM devices '
            'WHERE account_id = @a:bytea AND revoked_at IS NULL',
          ),
          parameters: {'a': accountId},
        );
        if ((active.single.single! as int) >= maxDevices) {
          throw RpcException(
            pb.ErrorCode.ERROR_CODE_QUOTA_EXCEEDED,
            'не больше $maxDevices действующих устройств',
          );
        }
        await _insertDevice(tx, accountId, cert, request.deviceCertificate);
      });
    });
    _log.info(LogEvent('device_added', {'rid': context.requestId}));
    return pb.AddDeviceResponse();
  }

  Future<pb.ListDevicesResponse> listDevices(
    CallContext context,
    pb.ListDevicesRequest request,
  ) async {
    final rows = await _db.run(
      (s) => s.execute(
        Sql.named('''
          SELECT certificate,
                 (extract(epoch FROM created_at) * 1000)::int8,
                 coalesce((extract(epoch FROM revoked_at) * 1000)::int8, 0)
            FROM devices WHERE account_id = @a:bytea
            ORDER BY created_at, device_sign'''),
        parameters: {'a': context.caller!.publicKey},
      ),
    );
    return pb.ListDevicesResponse(
      devices: [
        for (final [cert as List<int>, added as int, revoked as int] in rows)
          pb.DeviceInfo(
            certificate: pb.Signed.fromBuffer(cert),
            addedAtUnixMs: Int64(added),
            revokedAtUnixMs: Int64(revoked),
          ),
      ],
    );
  }

  Future<pb.RevokeDeviceResponse> revokeDevice(
    CallContext context,
    pb.RevokeDeviceRequest request,
  ) async {
    final accountId = context.caller!.publicKey;
    final revocation = await _checks.revocation(request.revocation, accountId);
    final changed = await _db.transaction((tx) async {
      await tx.execute(
        Sql.named('SELECT pg_advisory_xact_lock(@id:int8)'),
        parameters: {'id': _revocationLock},
      );
      final rows = await tx.execute(
        Sql.named('''
          SELECT revocation IS NOT NULL FROM devices
            WHERE device_sign = @d:bytea AND account_id = @a:bytea
            FOR UPDATE'''),
        parameters: {'d': revocation.deviceSign, 'a': accountId},
      );
      if (rows.isEmpty) {
        throw const RpcException(
          pb.ErrorCode.ERROR_CODE_NOT_FOUND,
          'устройство не найдено',
        );
      }
      // Отзыв без подписи учётной записи (оператор, `coordinator admin
      // device revoke`) дополняется подписанным: его получат узлы.
      if (rows.single.single! as bool) return false;
      await tx.execute(
        Sql.named('''
          UPDATE devices SET revoked_at = coalesce(revoked_at, @t:timestamptz),
                 revocation = @r:bytea,
                 revocation_seq = nextval('device_revocation_seq')
            WHERE device_sign = @d:bytea'''),
        parameters: {
          't': _clock(),
          'r': request.revocation.writeToBuffer(),
          'd': revocation.deviceSign,
        },
      );
      return true;
    });
    if (changed) {
      _log.info(LogEvent('device_revoked', {'rid': context.requestId}));
    }
    return pb.RevokeDeviceResponse();
  }

  Future<pb.ListRevocationsResponse> listRevocations(
    CallContext context,
    pb.ListRevocationsRequest request,
  ) async {
    final limit = request.limit == 0 || request.limit > maxRevocationsPage
        ? maxRevocationsPage
        : request.limit;
    final rows = await _db.run(
      (s) => s.execute(
        Sql.named('''
          SELECT revocation_seq, revocation FROM devices
            WHERE revocation_seq > @after:int8
            ORDER BY revocation_seq LIMIT @n:int4'''),
        parameters: {
          // uint64 больше 2^63 − 1 приходит отрицательным Int64; номеров
          // PostgreSQL (int8 со знаком) таких нет.
          'after': request.afterSequence.isNegative
              ? Int64.MAX_VALUE.toInt()
              : request.afterSequence.toInt(),
          'n': limit + 1,
        },
      ),
    );
    final page = rows.take(limit);
    return pb.ListRevocationsResponse(
      revocations: [
        for (final [seq as int, revocation as List<int>] in page)
          pb.RevocationEntry(
            sequence: Int64(seq),
            revocation: pb.Signed.fromBuffer(revocation),
          ),
      ],
      more: rows.length > limit,
    );
  }

  Future<void> _insertDevice(
    TxSession tx,
    Uint8List accountId,
    pb.DeviceCertificate cert,
    pb.Signed signed,
  ) => tx.execute(
    Sql.named('''
      INSERT INTO devices (device_sign, account_id, certificate, created_at)
      VALUES (@d:bytea, @a:bytea, @c:bytea, @t:timestamptz)'''),
    parameters: {
      'd': cert.deviceSign,
      'a': accountId,
      'c': signed.writeToBuffer(),
      't': _clock(),
    },
  );

  /// Нарушение уникальности (учётная запись, имя, устройство) —
  /// `ALREADY_EXISTS`.
  static Future<void> _uniqueOr(Future<void> Function() fn) async {
    try {
      await fn();
    } on ServerException catch (e) {
      if (e.code != '23505') rethrow;
      throw RpcException(
        pb.ErrorCode.ERROR_CODE_ALREADY_EXISTS,
        switch (e.constraintName) {
          'accounts_pkey' => 'учётная запись уже зарегистрирована',
          'accounts_login_key' => 'имя для входа занято',
          'devices_pkey' => 'устройство уже зарегистрировано',
          _ => 'уже существует',
        },
      );
    }
  }

  static RpcException _bad(String message) =>
      RpcException(pb.ErrorCode.ERROR_CODE_BAD_REQUEST, message);
}
