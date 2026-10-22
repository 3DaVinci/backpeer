import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:coordinator/src/accounts/certificates.dart';
import 'package:coordinator/src/auth/replay_cache.dart';
import 'package:coordinator/src/db/database.dart';
import 'package:coordinator/src/limits/rate_limiter.dart';
import 'package:coordinator/src/log.dart';
import 'package:coordinator/src/rpc/call_context.dart';
import 'package:coordinator/src/rpc/errors.dart';
import 'package:core/core.dart';
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:protocol/protocol.dart' as pb;

/// Вход по паролю на новом устройстве и смена KeyBundle (задачи 2.4.1,
/// 2.4.2; protocol.md, раздел 4.7; crypto.md, раздел 4.4).
final class LoginService {
  new(
    this._db,
    this._checks, {
    required this._ipLimiter,
    DateTime Function()? clock,
    int replayCapacity = 1 << 16,
  }) : _clock = clock ?? DateTime.now,
       _replay = ReplayCache(capacity: replayCapacity);

  final Database _db;
  final CertificateChecks _checks;
  final RateLimiter _ipLimiter;
  final DateTime Function() _clock;
  final ReplayCache _replay;

  /// Неудач подряд до первой паузы.
  static const freeFailures = 5;

  /// Первая пауза; дальше удваивается до [maxPause].
  static const firstPause = Duration(minutes: 1);
  static const maxPause = Duration(hours: 1);

  static final _log = Logger('login');
  static final int _skewMs = RequestAuth.maxClockSkew.inMilliseconds;

  CryptoProvider get _crypto => _checks.crypto;

  SecretBytes? _secret;
  Uint8List? _dummyVerifier;

  /// Пауза после [failures] неудач подряд или `null`.
  static Duration? pauseAfter(int failures) {
    if (failures < freeFailures) return null;
    final shift = math.min(failures - freeFailures, 10);
    final pause = firstPause * (1 << shift);
    return pause > maxPause ? maxPause : pause;
  }

  Future<pb.GetLoginParamsResponse> getLoginParams(
    CallContext context,
    pb.GetLoginParamsRequest request,
  ) async {
    _limitIp(context);
    final login = _login(request.login);
    final rows = await _db.run(
      (s) => s.execute(
        Sql.named('SELECT key_bundle FROM accounts WHERE login = @l:text'),
        parameters: {'l': login},
      ),
    );
    final stored = rows.isEmpty ? null : rows.single.single as List<int>?;
    if (stored != null) {
      final bundle = KeyBundle.parse(Uint8List.fromList(stored));
      return _params(bundle.salt, bundle.params);
    }
    // Имени нет или нет копии: правдоподобная и постоянная соль.
    final salt = _crypto
        .blake2b256(
          Uint8List.fromList(utf8.encode('fs/v1/login-salt/$login')),
          key: await _loginSecret(),
        )
        .sublist(0, KeyBundle.saltLength);
    return _params(salt, const Argon2Params());
  }

  Future<pb.GetKeyBundleResponse> getKeyBundle(
    CallContext context,
    pb.GetKeyBundleRequest request,
  ) async {
    _limitIp(context);
    final login = _login(request.login);
    final proof = Uint8List.fromList(request.authProof);
    if (proof.length != CryptoProvider.ed25519SignatureLength) {
      throw _bad('auth_proof — 64 байта');
    }
    final now = _clock();
    final nowMs = now.millisecondsSinceEpoch;
    final timeMs = request.timeUnixMs.toInt();
    final loginHash = _crypto.blake2b256(
      Uint8List.fromList(utf8.encode(login)),
    );
    final dummy = await _dummy();

    final result = await _db.transaction((tx) async {
      await tx.execute(
        Sql.named('''
          INSERT INTO login_attempts (login_hash, failures)
            VALUES (@h:bytea, 0) ON CONFLICT DO NOTHING'''),
        parameters: {'h': loginHash},
      );
      final attempts = await tx.execute(
        Sql.named('''
          SELECT failures, locked_until FROM login_attempts
            WHERE login_hash = @h:bytea FOR UPDATE'''),
        parameters: {'h': loginHash},
      );
      final [failures as int, lockedUntil as DateTime?] = attempts.single;
      if (lockedUntil != null && lockedUntil.isAfter(now)) {
        return _Locked(lockedUntil.difference(now));
      }
      final rows = await tx.execute(
        Sql.named('''
          SELECT key_bundle, auth_verifier FROM accounts
            WHERE login = @l:text'''),
        parameters: {'l': login},
      );
      final bundle = rows.isEmpty ? null : rows.single[0] as List<int>?;
      final verifier = rows.isEmpty ? null : rows.single[1] as List<int>?;
      // Подпись проверяется и для несуществующего имени: время ответа не
      // должно выдавать, есть ли учётная запись.
      final signed = await PasswordLogin.verify(
        _crypto,
        verifier: verifier == null ? dummy : Uint8List.fromList(verifier),
        login: login,
        timeMs: timeMs < 0 ? 0 : timeMs,
        proof: proof,
      );
      final fresh = (timeMs - nowMs).abs() <= _skewMs;
      if (signed && fresh && bundle != null && verifier != null) {
        if (!_remember(proof, timeMs, nowMs)) {
          return const _Failed(replay: true);
        }
        await tx.execute(
          Sql.named('DELETE FROM login_attempts WHERE login_hash = @h:bytea'),
          parameters: {'h': loginHash},
        );
        return _Success(Uint8List.fromList(bundle));
      }
      final count = failures + 1;
      final pause = pauseAfter(count);
      await tx.execute(
        Sql.named('''
          UPDATE login_attempts
            SET failures = @f:int4, locked_until = @u:timestamptz,
                updated_at = @t:timestamptz
            WHERE login_hash = @h:bytea'''),
        parameters: {
          'f': count,
          'u': pause == null ? null : now.add(pause),
          't': now,
          'h': loginHash,
        },
      );
      return _Failed(pause: pause);
    });

    switch (result) {
      case _Success(:final bundle):
        _log.info(LogEvent('login', {'rid': context.requestId}));
        return pb.GetKeyBundleResponse(keyBundle: bundle);
      case _Locked(:final wait):
        throw RpcException(
          pb.ErrorCode.ERROR_CODE_RATE_LIMITED,
          'вход по паролю временно закрыт',
          retryAfter: wait,
        );
      case _Failed(:final pause, :final replay):
        _log.info(
          LogEvent('login_failed', {
            'rid': context.requestId,
            if (replay) 'replay': true,
            if (pause != null) 'pause_s': pause.inSeconds,
          }),
        );
        throw const RpcException(
          pb.ErrorCode.ERROR_CODE_UNAUTHENTICATED,
          'вход не выполнен',
        );
    }
  }

  Future<pb.SetKeyBundleResponse> setKeyBundle(
    CallContext context,
    pb.SetKeyBundleRequest request,
  ) async {
    final accountId = context.caller!.publicKey;
    final bundle = _checks.keyBundle(
      request.keyBundle,
      request.authVerifier,
      accountId,
    );
    await _db.transaction((tx) async {
      final rows = await tx.execute(
        Sql.named('''
          UPDATE accounts
            SET key_bundle = @b:bytea, auth_verifier = @v:bytea,
                key_bundle_updated_at = @t:timestamptz
            WHERE account_id = @a:bytea
            RETURNING login'''),
        parameters: {
          'b': bundle?.toBytes(),
          'v': bundle == null ? null : Uint8List.fromList(request.authVerifier),
          't': _clock(),
          'a': accountId,
        },
      );
      final login = rows.isEmpty ? null : rows.single.single as String?;
      if (login != null) {
        await tx.execute(
          Sql.named('DELETE FROM login_attempts WHERE login_hash = @h:bytea'),
          parameters: {
            'h': _crypto.blake2b256(Uint8List.fromList(utf8.encode(login))),
          },
        );
      }
    });
    _log.info(
      LogEvent('key_bundle_set', {
        'rid': context.requestId,
        'key_copy': bundle != null,
      }),
    );
    return pb.SetKeyBundleResponse();
  }

  void _limitIp(CallContext context) {
    final wait = _ipLimiter.take(context.clientAddress);
    if (wait != null) {
      throw RpcException(
        pb.ErrorCode.ERROR_CODE_RATE_LIMITED,
        'предел частоты входа по IP',
        retryAfter: wait,
      );
    }
  }

  bool _remember(Uint8List proof, int timeMs, int nowMs) {
    try {
      return _replay.remember(
        proof,
        expiresAtMs: timeMs + _skewMs,
        nowMs: nowMs,
      );
    } on ReplayCacheFullException {
      throw const RpcException(
        pb.ErrorCode.ERROR_CODE_UNAVAILABLE,
        'координатор перегружен',
        retryAfter: Duration(seconds: 1),
      );
    }
  }

  /// Секрет для соли несуществующих имён: создаётся один раз и хранится в
  /// базе, чтобы соль не менялась между запросами и перезапусками.
  Future<SecretBytes> _loginSecret() async {
    if (_secret case final s?) return s;
    final value = await _db.transaction((tx) async {
      await tx.execute(
        Sql.named('''
          INSERT INTO server_secrets (name, value) VALUES ('login-salt', @v:bytea)
            ON CONFLICT DO NOTHING'''),
        parameters: {'v': _crypto.randomBytes(32)},
      );
      final rows = await tx.execute(
        "SELECT value FROM server_secrets WHERE name = 'login-salt'",
      );
      return rows.single.single! as List<int>;
    });
    return _secret = SecretBytes(value);
  }

  /// Ключ, под которым проверяется подпись для несуществующего имени.
  Future<Uint8List> _dummy() async {
    if (_dummyVerifier case final d?) return d;
    final key = await _crypto.ed25519FromSeed(
      SecretBytes(_crypto.randomBytes(32)),
    );
    key.seed.dispose();
    return _dummyVerifier = key.publicKey;
  }

  static String _login(String raw) =>
      LoginName.normalize(raw) ?? (throw _bad('имя для входа недопустимо'));

  static pb.GetLoginParamsResponse _params(List<int> salt, Argon2Params p) =>
      pb.GetLoginParamsResponse(
        salt: salt,
        memoryKib: p.memoryKiB,
        iterations: p.iterations,
        parallelism: p.parallelism,
      );

  static RpcException _bad(String message) =>
      RpcException(pb.ErrorCode.ERROR_CODE_BAD_REQUEST, message);
}

sealed class _Outcome {
  const new();
}

final class _Success extends _Outcome {
  const new(this.bundle);

  final Uint8List bundle;
}

final class _Locked extends _Outcome {
  const new(this.wait);

  final Duration wait;
}

final class _Failed extends _Outcome {
  const new({this.pause, this.replay = false});

  final Duration? pause;
  final bool replay;
}
