import 'dart:math';
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

/// Настройки привязки узла к учётной записи без ввода фразы (задачи 6.1.1,
/// 6.1.2; protocol.md, раздел 4.17).
final class PairingPolicy {
  const new({
    this.ttl = const Duration(minutes: 10),
    this.maxAttempts = 5,
    this.codeLength = 8,
  });

  /// Сколько действует код привязки.
  final Duration ttl;

  /// Предел неудачных подтверждений кода, после которого он перестаёт
  /// действовать.
  final int maxAttempts;

  /// Длина кода в символах [alphabet].
  final int codeLength;

  /// Алфавит Crockford base32 без неоднозначных I, L, O, U (32 символа).
  static const alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
}

/// Привязка узла к учётной записи (protocol.md, раздел 4.17): узел без
/// сертификата начинает привязку и показывает одноразовый код; владелец
/// вводит код на устройстве, где уже вошёл, сверяет отпечаток ключа узла и
/// передаёт подписанный `NodeCertificate`; узел забирает его.
final class NodePairingService {
  new(
    this._db,
    this._checks, {
    this.policy = const PairingPolicy(),
    DateTime Function()? clock,
    Random? random,
  }) : _clock = clock ?? DateTime.now,
       _random = random ?? Random.secure();

  final Database _db;
  final CertificateChecks _checks;
  final PairingPolicy policy;
  final DateTime Function() _clock;
  final Random _random;

  static final _log = Logger('pairing');

  /// Узел начинает привязку: сохраняет свой открытый ключ X25519 и получает
  /// одноразовый код. Повторный вызов тем же узлом перезаписывает привязку
  /// новым кодом.
  Future<pb.NodePairStartResponse> start(
    CallContext context,
    pb.NodePairStartRequest request,
  ) async {
    final nodeId = context.caller!.publicKey;
    final nodeDh = _key(request.nodeDh, 'node_dh');
    final now = _clock();
    final expires = now.add(policy.ttl);
    for (var attempt = 0; ; attempt++) {
      final code = _code();
      try {
        await _db.transaction(
          (tx) => tx.execute(
            Sql.named('''
              INSERT INTO node_pairings
                (node_id, node_dh, code, created_at, expires_at)
              VALUES (@n:bytea, @d:bytea, @c:text, @t:timestamptz,
                      @e:timestamptz)
              ON CONFLICT (node_id) DO UPDATE
                SET node_dh = excluded.node_dh, code = excluded.code,
                    created_at = excluded.created_at,
                    expires_at = excluded.expires_at, attempts = 0,
                    account_id = NULL, certificate = NULL, signed_at = NULL'''),
            parameters: {
              'n': nodeId,
              'd': nodeDh,
              'c': code,
              't': now,
              'e': expires,
            },
          ),
        );
        _log.info(LogEvent('node_pairing_started', {'rid': context.requestId}));
        return pb.NodePairStartResponse(
          code: code,
          expiresAtUnixMs: Int64(expires.millisecondsSinceEpoch),
        );
      } on ServerException catch (e) {
        // Очень редкое совпадение кодов двух узлов.
        if (e.code == '23505' && attempt < 8) continue;
        rethrow;
      }
    }
  }

  /// Узел спрашивает, не подписан ли его сертификат.
  Future<pb.NodePairStatusResponse> status(
    CallContext context,
    pb.NodePairStatusRequest request,
  ) async {
    final nodeId = context.caller!.publicKey;
    final rows = await _db.run(
      (s) => s.execute(
        Sql.named('''
          SELECT expires_at, certificate FROM node_pairings
            WHERE node_id = @n:bytea'''),
        parameters: {'n': nodeId},
      ),
    );
    if (rows.isEmpty) {
      return pb.NodePairStatusResponse(
        status: pb.NodePairStatus.NODE_PAIR_STATUS_EXPIRED,
      );
    }
    final expires = rows.single[0]! as DateTime;
    final certificate = rows.single[1] as List<int>?;
    if (certificate != null) {
      return pb.NodePairStatusResponse(
        status: pb.NodePairStatus.NODE_PAIR_STATUS_SIGNED,
        nodeCertificate: pb.Signed.fromBuffer(certificate),
      );
    }
    if (!expires.isAfter(_clock())) {
      return pb.NodePairStatusResponse(
        status: pb.NodePairStatus.NODE_PAIR_STATUS_EXPIRED,
      );
    }
    return pb.NodePairStatusResponse(
      status: pb.NodePairStatus.NODE_PAIR_STATUS_PENDING,
      expiresAtUnixMs: Int64(expires.millisecondsSinceEpoch),
    );
  }

  /// Владелец вводит код и узнаёт ключи узла, чтобы сверить отпечаток.
  Future<pb.NodePairLookupResponse> lookup(
    CallContext context,
    pb.NodePairLookupRequest request,
  ) async {
    final code = _normalize(request.code);
    final rows = await _db.run(
      (s) => s.execute(
        Sql.named('''
          SELECT node_id, node_dh, expires_at, attempts, certificate
            FROM node_pairings WHERE code = @c:text'''),
        parameters: {'c': code},
      ),
    );
    if (rows.isEmpty) throw _notFound();
    final expires = rows.single[2]! as DateTime;
    final attempts = rows.single[3]! as int;
    if (rows.single[4] != null || !expires.isAfter(_clock())) {
      throw _notFound();
    }
    if (attempts >= policy.maxAttempts) throw _notFound();
    return pb.NodePairLookupResponse(
      nodeId: Uint8List.fromList(rows.single[0]! as List<int>),
      nodeDh: Uint8List.fromList(rows.single[1]! as List<int>),
      expiresAtUnixMs: Int64(expires.millisecondsSinceEpoch),
    );
  }

  /// Владелец подтвердил отпечаток и передаёт подписанный сертификат узла.
  Future<pb.NodePairSignResponse> sign(
    CallContext context,
    pb.NodePairSignRequest request,
  ) async {
    final code = _normalize(request.code);
    final account = context.caller!.publicKey;
    final rows = await _db.run(
      (s) => s.execute(
        Sql.named('''
          SELECT node_id, node_dh, expires_at, attempts, certificate
            FROM node_pairings WHERE code = @c:text'''),
        parameters: {'c': code},
      ),
    );
    if (rows.isEmpty) throw _notFound();
    final nodeId = Uint8List.fromList(rows.single[0]! as List<int>);
    final nodeDh = Uint8List.fromList(rows.single[1]! as List<int>);
    final expires = rows.single[2]! as DateTime;
    final attempts = rows.single[3]! as int;
    if (rows.single[4] != null) throw _used();
    if (!expires.isAfter(_clock())) throw _notFound();
    if (attempts >= policy.maxAttempts) throw _notFound();

    final pb.NodeCertificate cert;
    try {
      cert = await _checks.nodeCertificate(request.nodeCertificate, nodeId);
    } on RpcException {
      await _bump(code);
      rethrow;
    }
    if (!constantTimeEquals(cert.accountId, account)) {
      await _bump(code);
      throw const RpcException(
        pb.ErrorCode.ERROR_CODE_PERMISSION_DENIED,
        'сертификат подписан другой учётной записью',
      );
    }
    if (!constantTimeEquals(cert.nodeDh, nodeDh)) {
      await _bump(code);
      throw _bad('сертификат другого узла');
    }

    final updated = await _db.transaction(
      (tx) => tx.execute(
        Sql.named('''
          UPDATE node_pairings
            SET account_id = @a:bytea, certificate = @cert:bytea,
                signed_at = @t:timestamptz
            WHERE code = @c:text AND certificate IS NULL
              AND attempts < @max:int4
            RETURNING 1'''),
        parameters: {
          'a': cert.accountId,
          'cert': request.nodeCertificate.writeToBuffer(),
          't': _clock(),
          'c': code,
          'max': policy.maxAttempts,
        },
      ),
    );
    if (updated.isEmpty) throw _used();
    _log.info(LogEvent('node_pairing_signed', {'rid': context.requestId}));
    return pb.NodePairSignResponse();
  }

  /// Неудачная попытка подтверждения: счётчик попыток кода растёт.
  Future<void> _bump(String code) => _db.run(
    (s) => s.execute(
      Sql.named(
        'UPDATE node_pairings SET attempts = attempts + 1 '
        'WHERE code = @c:text',
      ),
      parameters: {'c': code},
    ),
  );

  /// Случайный код из [PairingPolicy.alphabet].
  String _code() => String.fromCharCodes([
    for (var i = 0; i < policy.codeLength; i++)
      PairingPolicy.alphabet.codeUnitAt(
        _random.nextInt(PairingPolicy.alphabet.length),
      ),
  ]);

  /// Код для сравнения с базой: в верхнем регистре, без пробелов и дефисов.
  static String _normalize(String code) {
    final upper = code.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
    if (!RegExp(r'^[0-9A-Z]{8}$').hasMatch(upper)) {
      throw const RpcException(
        pb.ErrorCode.ERROR_CODE_BAD_REQUEST,
        'код — 8 символов',
      );
    }
    return upper;
  }

  static Uint8List _key(List<int> bytes, String field) {
    final key = Uint8List.fromList(bytes);
    if (key.length != CryptoProvider.keyLength) {
      throw RpcException(
        pb.ErrorCode.ERROR_CODE_BAD_REQUEST,
        '$field — ${CryptoProvider.keyLength} байта',
      );
    }
    return key;
  }

  static RpcException _notFound() => const RpcException(
    pb.ErrorCode.ERROR_CODE_NOT_FOUND,
    'код неверный или просрочен',
  );

  static RpcException _used() => const RpcException(
    pb.ErrorCode.ERROR_CODE_ALREADY_EXISTS,
    'код уже использован',
  );

  static RpcException _bad(String message) =>
      RpcException(pb.ErrorCode.ERROR_CODE_BAD_REQUEST, message);
}
