import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:core/core.dart';

/// Хэш пароля оператора: Argon2id в формате
/// `argon2id$v=19$m=65536,t=3,p=1$<соль>$<хэш>`.
///
/// Параметры в хэше ограничены при проверке: чужой или испорченный файл
/// настроек не должен заставить панель считать Argon2id с гигантской
/// памятью.
final class PasswordHasher {
  new(this.crypto, {this.params = const Argon2Params(memoryKiB: 64 * 1024)});

  final CryptoProvider crypto;

  /// Параметры для новых хэшей; при проверке берутся из самого хэша.
  final Argon2Params params;

  static const minPasswordLength = 12;
  static const maxPasswordLength = 1024;
  static const _saltLength = 16;
  static const _hashLength = 32;

  /// libsodium, а если он не загрузился — запасная реализация на Dart.
  /// Argon2id считается один раз на вход, поэтому скорость не важна.
  static Future<PasswordHasher> load() async {
    try {
      return PasswordHasher(await SodiumCryptoProvider.load());
    } on Object {
      return PasswordHasher(DartCryptoProvider());
    }
  }

  Future<String> hashPassword(String password) async {
    if (password.length < minPasswordLength ||
        password.length > maxPasswordLength) {
      throw const PasswordPolicyException(
        'пароль оператора: от $minPasswordLength до '
        '$maxPasswordLength символов',
      );
    }
    final salt = crypto.randomBytes(_saltLength);
    final hash = await _derive(password, salt, params, _hashLength);
    try {
      return [
        'argon2id',
        'v=19',
        'm=${params.memoryKiB},t=${params.iterations},p=${params.parallelism}',
        _b64(salt),
        _b64(hash.bytes),
      ].join(r'$');
    } finally {
      hash.dispose();
    }
  }

  Future<bool> verify(String password, String encoded) async {
    if (password.length > maxPasswordLength) return false;
    final parsed = _parse(encoded);
    if (parsed == null) return false;
    final SecretBytes actual;
    try {
      actual = await _derive(
        password,
        parsed.salt,
        parsed.params,
        parsed.hash.length,
      );
    } on Object {
      return false;
    }
    try {
      return _constantTimeEquals(actual.bytes, parsed.hash);
    } finally {
      actual.dispose();
    }
  }

  /// Сжечь столько же времени, сколько заняла бы проверка: по имени
  /// пользователя нельзя узнать, зарегистрирован ли оператор.
  Future<void> burnPasswordCheck(String password) async {
    final salt = crypto.randomBytes(_saltLength);
    final ignored = await _derive(
      password.length > maxPasswordLength
          ? password.substring(0, maxPasswordLength)
          : password,
      salt,
      params,
      _hashLength,
    );
    ignored.dispose();
  }

  Future<SecretBytes> _derive(
    String password,
    Uint8List salt,
    Argon2Params params,
    int length,
  ) => crypto.argon2id(
    password: normalizePassword(password),
    salt: salt,
    params: params,
    length: length,
  );

  static _ParsedHash? _parse(String encoded) {
    final parts = encoded.split(r'$');
    if (parts.length != 5 || parts[0] != 'argon2id' || parts[1] != 'v=19') {
      return null;
    }
    final fields = <String, int>{};
    for (final pair in parts[2].split(',')) {
      final eq = pair.indexOf('=');
      if (eq <= 0) return null;
      final value = int.tryParse(pair.substring(eq + 1));
      if (value == null) return null;
      fields[pair.substring(0, eq)] = value;
    }
    final m = fields['m'];
    final t = fields['t'];
    final p = fields['p'];
    if (m == null ||
        t == null ||
        p == null ||
        m < 8 * 1024 ||
        m > 256 * 1024 ||
        t < 1 ||
        t > 10 ||
        p < 1 ||
        p > 4) {
      return null;
    }
    final salt = _unb64(parts[3]);
    final hash = _unb64(parts[4]);
    if (salt == null ||
        salt.length < 8 ||
        salt.length > 64 ||
        hash == null ||
        hash.length < 16 ||
        hash.length > 64) {
      return null;
    }
    return _ParsedHash(
      salt,
      hash,
      Argon2Params(memoryKiB: m, iterations: t, parallelism: p),
    );
  }

  static String _b64(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');

  static Uint8List? _unb64(String text) {
    try {
      if (text.isEmpty || text.length > 88) return null;
      final padded = text.padRight((text.length + 3) ~/ 4 * 4, '=');
      return Uint8List.fromList(base64Url.decode(padded));
    } on FormatException {
      return null;
    }
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}

final class _ParsedHash {
  const new(this.salt, this.hash, this.params);

  final Uint8List salt;
  final Uint8List hash;
  final Argon2Params params;
}

/// Пароль оператора не подходит по длине.
final class PasswordPolicyException implements Exception {
  const new(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Сессия оператора: случайный токен в cookie, срок и имя.
final class AdminSession {
  const new({required this.token, required this.user, required this.expiresAt});

  final String token;
  final String user;
  final DateTime expiresAt;
}

/// Сессии в памяти процесса. Перезапуск панели завершает все сессии —
/// оператор входит заново.
final class SessionStore {
  new({required this.lifetime, DateTime Function()? clock, Random? random})
    : _clock = clock ?? DateTime.now,
      _random = random ?? Random.secure();

  final Duration lifetime;
  final DateTime Function() _clock;
  final Random _random;
  final Map<String, AdminSession> _sessions = {};

  int get activeCount {
    _cleanup();
    return _sessions.length;
  }

  AdminSession create(String user) {
    _cleanup();
    final token = base64Url
        .encode(List<int>.generate(32, (_) => _random.nextInt(256)))
        .replaceAll('=', '');
    final session = AdminSession(
      token: token,
      user: user,
      expiresAt: _clock().add(lifetime),
    );
    _sessions[token] = session;
    return session;
  }

  AdminSession? lookup(String? token) {
    if (token == null || token.isEmpty) return null;
    final session = _sessions[token];
    if (session == null) return null;
    if (!session.expiresAt.isAfter(_clock())) {
      _sessions.remove(token);
      return null;
    }
    return session;
  }

  void destroy(String? token) {
    if (token != null) _sessions.remove(token);
  }

  void _cleanup() {
    final now = _clock();
    _sessions.removeWhere((_, session) => !session.expiresAt.isAfter(now));
  }
}

/// Итог входа.
final class LoginResult {
  const new _({this.session, this.error, this.lockedUntil});

  const new ok(AdminSession session) : this._(session: session);

  const new failed() : this._();

  const new locked(DateTime until)
    : this._(lockedUntil: until, error: 'слишком много неудачных попыток');

  final AdminSession? session;
  final String? error;
  final DateTime? lockedUntil;

  bool get ok => session != null;
}

/// Проверка пары имя/пароль и ограничение перебора. Счётчик неудач — по
/// имени; адрес клиента ограничивается отдельно на HTTP-уровне.
final class AdminAuthenticator {
  new({
    required Map<String, String> users,
    required this.hasher,
    required this.sessions,
    this.maxFailedAttempts = 10,
    this.lockDuration = const Duration(minutes: 15),
    DateTime Function()? clock,
  }) : _users = Map.unmodifiable(users),
       _clock = clock ?? DateTime.now;

  final Map<String, String> _users;
  final PasswordHasher hasher;
  final SessionStore sessions;
  final int maxFailedAttempts;
  final Duration lockDuration;
  final DateTime Function() _clock;
  final Map<String, _Failures> _failures = {};

  bool get hasUsers => _users.isNotEmpty;

  /// Вход. Неизвестное имя обрабатывается так же долго, как известное.
  Future<LoginResult> login(String user, String password) async {
    final name = user.trim().toLowerCase();
    final failures = _failures[name];
    final now = _clock();
    if (failures != null &&
        failures.lockedUntil != null &&
        failures.lockedUntil!.isAfter(now)) {
      return LoginResult.locked(failures.lockedUntil!);
    }
    final encoded = _users[name];
    final bool valid;
    if (encoded == null) {
      await hasher.burnPasswordCheck(password);
      valid = false;
    } else {
      valid = await hasher.verify(password, encoded);
    }
    if (!valid) {
      _recordFailure(name, now);
      final locked = _failures[name]?.lockedUntil;
      return locked != null
          ? LoginResult.locked(locked)
          : const LoginResult.failed();
    }
    _failures.remove(name);
    return LoginResult.ok(sessions.create(name));
  }

  void _recordFailure(String name, DateTime now) {
    final current = _failures[name] ?? const _Failures();
    final count = current.count + 1;
    _failures[name] = count >= maxFailedAttempts
        ? _Failures(lockedUntil: now.add(lockDuration))
        : _Failures(count: count);
  }
}

final class _Failures {
  const new({this.count = 0, this.lockedUntil});

  final int count;
  final DateTime? lockedUntil;
}
