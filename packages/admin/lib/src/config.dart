import 'dart:io';

import 'package:coordinator/coordinator.dart'
    show DatabaseConfig, DatabaseSsl, EconomyPolicy;
import 'package:logging/logging.dart';
import 'package:yaml/yaml.dart';

/// Ошибка в настройках панели: сообщение для оператора.
final class AdminConfigException implements Exception {
  const new(this.message);

  final String message;

  @override
  String toString() => 'AdminConfigException: $message';
}

/// Настройки панели оператора: YAML-файл и переменные окружения
/// `FS_ADMIN_<РАЗДЕЛ>_<КЛЮЧ>` поверх него.
///
/// Файл настроек — не для всех: он содержит хэши паролей операторов,
/// поэтому права 0640 и группа администраторов (`docs/ops/admin.md`).
final class AdminConfig {
  const new({
    this.host = '127.0.0.1',
    this.port = 8092,
    this.cookieSecure = true,
    this.trustForwardedFor = false,
    this.publicUrl,
    this.database = const DatabaseConfig(
      user: 'fs_admin_web',
      maxConnections: 4,
    ),
    this.readOnlyRole = 'fs_admin_web',
    this.staticDir = 'apps/admin/dist',
    this.reportsDir = 'var/reports',
    this.reportRetentionDays = 90,
    this.reportPerHour = 120,
    this.reportMaxBodyBytes = 64 * 1024,
    this.reportMaxEntries = 20000,
    this.reportMaxMemoryBytes = 64 << 20,
    this.users = const {},
    this.sessionLifetime = const Duration(hours: 12),
    this.maxFailedLogins = 10,
    this.loginLock = const Duration(minutes: 15),
    this.onlineWindow = const Duration(minutes: 15),
    this.probation = const Duration(hours: 72),
    this.economy = const EconomyPolicy(),
    this.logLevel = Level.INFO,
  });

  /// Из YAML-текста [yaml] (может быть пустым) и окружения [environment].
  factory parse(String yaml, Map<String, String> environment) {
    final Object? doc;
    try {
      doc = loadYaml(yaml);
    } on YamlException catch (e) {
      throw AdminConfigException('YAML не разбирается: ${e.message}');
    }
    if (doc != null && doc is! YamlMap) {
      throw const AdminConfigException('корень настроек должен быть словарём');
    }
    final values = <String, Object?>{};
    void flatten(String prefix, YamlMap map) {
      for (final MapEntry(:key, :value) in map.entries) {
        final name = prefix.isEmpty ? '$key' : '$prefix.$key';
        if (value is YamlMap && name != 'auth.users') {
          flatten(name, value);
        } else {
          values[name] = value;
        }
      }
    }

    if (doc is YamlMap) flatten('', doc);
    final unknown = values.keys.where((k) => !_keys.contains(k)).toList();
    if (unknown.isNotEmpty) {
      throw AdminConfigException(
        'неизвестные настройки: ${unknown.join(', ')}',
      );
    }
    for (final key in _keys) {
      if (key == 'auth.users') continue;
      final env = environment[envName(key)];
      if (env != null && env.isNotEmpty) values[key] = env;
    }
    return _Reader(values).build();
  }

  /// Из файла [path] (если задан) и окружения процесса.
  factory load(String? path) => AdminConfig.parse(
    path == null ? '' : File(path).readAsStringSync(),
    Platform.environment,
  );

  /// `listen.host`.
  final String host;

  /// `listen.port`.
  final int port;

  /// `listen.cookie_secure`: `true` — cookie только по HTTPS (боевой режим
  /// за прокси); `false` — только локальный стенд по HTTP.
  final bool cookieSecure;

  /// `listen.trust_forwarded_for`: брать адрес клиента из
  /// `X-Forwarded-For` (панель за обратным прокси).
  final bool trustForwardedFor;

  /// `listen.public_url`: внешний адрес панели, например
  /// `https://backpeer-admin.example.org`. Нужен для проверки `Origin` при
  /// входе; без него проверяется только заголовок запроса.
  final String? publicUrl;

  /// Подключение к базе координатора под ролью только для чтения.
  final DatabaseConfig database;

  /// `database.read_only_role`: роль, членство в которой проверяется при
  /// старте. Пусто — проверка выключена (только стенд).
  final String readOnlyRole;

  /// Папка собранной панели (`apps/admin/dist`).
  final String staticDir;

  /// Папка принятых отчётов о сбоях.
  final String reportsDir;

  /// Сколько суток хранить отчёты.
  final int reportRetentionDays;

  /// Сколько отчётов принимать с одного адреса в час.
  final int reportPerHour;

  /// Предел тела отчёта.
  final int reportMaxBodyBytes;

  /// Предел числа отчётов, загружаемых в память.
  final int reportMaxEntries;

  /// Предел памяти под отчёты в панели.
  final int reportMaxMemoryBytes;

  /// Операторы: имя → хэш Argon2id (`admin hash-password`).
  final Map<String, String> users;

  /// Срок сессии оператора.
  final Duration sessionLifetime;

  /// Неудачных попыток входа до блокировки имени.
  final int maxFailedLogins;

  /// На сколько блокируется имя после неудачных попыток.
  final Duration loginLock;

  /// Узел в сети, если heartbeat не старше этого срока; совпадает с
  /// `nodes.heartbeat_seconds × 3` координатора.
  final Duration onlineWindow;

  /// Испытательный срок новых узлов; совпадает с
  /// `placement.probation_hours` координатора.
  final Duration probation;

  /// Тарифы бартерной экономики; должны совпадать с `economy.*`
  /// координатора, иначе квота в панели разойдётся с `GetQuota`.
  final EconomyPolicy economy;

  /// `log.level`.
  final Level logLevel;

  /// Имя переменной окружения для ключа: `database.password` →
  /// `FS_ADMIN_DATABASE_PASSWORD`.
  static String envName(String key) =>
      'FS_ADMIN_${key.replaceAll('.', '_').toUpperCase()}';

  static const _keys = {
    'listen.host',
    'listen.port',
    'listen.cookie_secure',
    'listen.trust_forwarded_for',
    'listen.public_url',
    'database.host',
    'database.port',
    'database.name',
    'database.user',
    'database.password',
    'database.password_file',
    'database.ssl',
    'database.max_connections',
    'database.read_only_role',
    'static.dir',
    'reports.dir',
    'reports.retention_days',
    'reports.per_hour',
    'reports.max_body_bytes',
    'reports.max_entries',
    'reports.max_memory_bytes',
    'auth.users',
    'auth.session_hours',
    'auth.max_failed_attempts',
    'auth.lock_minutes',
    'network.online_window_minutes',
    'network.probation_hours',
    'economy.data_credits_per_tb_month',
    'economy.store_credits_per_tb_month',
    'economy.barter_ratio',
    'economy.starter_credits',
    'economy.grace_days',
    'log.level',
  };
}

final class _Reader {
  new(this.values);

  final Map<String, Object?> values;

  AdminConfig build() {
    const d = AdminConfig();
    const db = DatabaseConfig();
    final password = _password();
    var publicUrl = _string('listen.public_url');
    if (publicUrl != null) {
      final uri = Uri.tryParse(publicUrl);
      if (uri == null ||
          uri.host.isEmpty ||
          (uri.scheme != 'http' && uri.scheme != 'https') ||
          uri.hasQuery ||
          uri.hasFragment ||
          (uri.path.isNotEmpty && uri.path != '/')) {
        throw const AdminConfigException(
          'listen.public_url должен быть вида https://admin.example.org',
        );
      }
      if (uri.path == '/') {
        publicUrl = publicUrl.replaceFirst(RegExp(r'/+$'), '');
      }
    }
    return AdminConfig(
      host: _string('listen.host') ?? d.host,
      port: _int('listen.port', 1, 65535) ?? d.port,
      cookieSecure: _bool('listen.cookie_secure') ?? d.cookieSecure,
      trustForwardedFor:
          _bool('listen.trust_forwarded_for') ?? d.trustForwardedFor,
      publicUrl: publicUrl,
      database: DatabaseConfig(
        host: _string('database.host') ?? db.host,
        port: _int('database.port', 1, 65535) ?? db.port,
        name: _string('database.name') ?? db.name,
        user: _string('database.user') ?? d.database.user,
        password: password,
        ssl:
            _enum('database.ssl', {
              'disable': DatabaseSsl.disable,
              'require': DatabaseSsl.require,
              'verify-full': DatabaseSsl.verifyFull,
            }) ??
            DatabaseSsl.disable,
        maxConnections:
            _int('database.max_connections', 1, 100) ??
            d.database.maxConnections,
      ),
      readOnlyRole: _role('database.read_only_role') ?? d.readOnlyRole,
      staticDir: _string('static.dir') ?? d.staticDir,
      reportsDir: _string('reports.dir') ?? d.reportsDir,
      reportRetentionDays:
          _int('reports.retention_days', 1, 3650) ?? d.reportRetentionDays,
      reportPerHour: _int('reports.per_hour', 1, 100000) ?? d.reportPerHour,
      reportMaxBodyBytes:
          _int('reports.max_body_bytes', 1024, 1 << 20) ?? d.reportMaxBodyBytes,
      reportMaxEntries:
          _int('reports.max_entries', 100, 1000000) ?? d.reportMaxEntries,
      reportMaxMemoryBytes:
          _int('reports.max_memory_bytes', 1 << 20, 1 << 30) ??
          d.reportMaxMemoryBytes,
      users: _users(),
      sessionLifetime: Duration(
        hours:
            _int('auth.session_hours', 1, 24 * 30) ?? d.sessionLifetime.inHours,
      ),
      maxFailedLogins:
          _int('auth.max_failed_attempts', 1, 1000) ?? d.maxFailedLogins,
      loginLock: Duration(
        minutes: _int('auth.lock_minutes', 1, 24 * 60) ?? d.loginLock.inMinutes,
      ),
      onlineWindow: Duration(
        minutes:
            _int('network.online_window_minutes', 1, 24 * 60) ??
            d.onlineWindow.inMinutes,
      ),
      probation: Duration(
        hours:
            _int('network.probation_hours', 0, 24 * 365) ?? d.probation.inHours,
      ),
      economy: EconomyPolicy(
        dataCreditsPerTbMonth:
            _int('economy.data_credits_per_tb_month', 1, 1 << 30) ??
            d.economy.dataCreditsPerTbMonth,
        storeCreditsPerTbMonth:
            _int('economy.store_credits_per_tb_month', 1, 1 << 30) ??
            d.economy.storeCreditsPerTbMonth,
        barterRatio: _double('economy.barter_ratio') ?? d.economy.barterRatio,
        starterCredits:
            _int('economy.starter_credits', 0, 1 << 30) ??
            d.economy.starterCredits,
        graceDays: _int('economy.grace_days', 0, 3650) ?? d.economy.graceDays,
      ),
      logLevel:
          _enum('log.level', {
            'fine': Level.FINE,
            'info': Level.INFO,
            'warning': Level.WARNING,
            'severe': Level.SEVERE,
          }) ??
          d.logLevel,
    );
  }

  String? _password() {
    var password = _string('database.password');
    final file = _string('database.password_file');
    if (password != null && file != null) {
      throw const AdminConfigException(
        'database.password и database.password_file задаются по отдельности',
      );
    }
    if (file != null) {
      try {
        password = File(file).readAsStringSync().trim();
      } on FileSystemException catch (e) {
        throw AdminConfigException(
          'database.password_file не читается: ${e.message}',
        );
      }
    }
    return password;
  }

  Map<String, String> _users() {
    final value = values['auth.users'];
    if (value == null) {
      throw const AdminConfigException('auth.users: не задан ни один оператор');
    }
    if (value is! YamlMap) {
      throw const AdminConfigException('auth.users: нужен словарь имя → хэш');
    }
    if (value.isEmpty) {
      throw const AdminConfigException('auth.users: не задан ни один оператор');
    }
    final name = RegExp(r'^[a-z0-9][a-z0-9._-]{2,31}$');
    final users = <String, String>{};
    for (final MapEntry(:key, :value) in value.entries) {
      final user = '$key';
      if (!name.hasMatch(user)) {
        throw AdminConfigException(
          'auth.users: имя «$user» — строчные латинские буквы, цифры, '
          'точка, дефис, подчёркивание; 3–32 символа',
        );
      }
      final hash = '$value';
      if (!hash.startsWith(r'argon2id$') || hash.length > 512) {
        throw AdminConfigException(
          'auth.users.$user: нужен хэш Argon2id (admin hash-password)',
        );
      }
      users[user] = hash;
    }
    return users;
  }

  String? _string(String key) {
    final value = values[key];
    if (value == null) return null;
    if (value is String) return value;
    throw AdminConfigException('$key: ожидается строка');
  }

  int? _int(String key, int min, int max) {
    final value = values[key];
    if (value == null) return null;
    final parsed = value is int ? value : int.tryParse('$value');
    if (parsed == null || parsed < min || parsed > max) {
      throw AdminConfigException('$key: число от $min до $max');
    }
    return parsed;
  }

  bool? _bool(String key) {
    final value = values[key];
    if (value == null) return null;
    if (value is bool) return value;
    return switch ('$value'.toLowerCase()) {
      'true' || 'yes' || '1' => true,
      'false' || 'no' || '0' => false,
      _ => throw AdminConfigException('$key: true или false'),
    };
  }

  double? _double(String key) {
    final value = values[key];
    if (value == null) return null;
    final parsed = value is num ? value.toDouble() : double.tryParse('$value');
    if (parsed == null || !parsed.isFinite || parsed <= 0) {
      throw AdminConfigException('$key: положительное число');
    }
    return parsed;
  }

  T? _enum<T>(String key, Map<String, T> options) {
    final value = _string(key);
    if (value == null) return null;
    final found = options[value];
    if (found == null) {
      throw AdminConfigException('$key: одно из ${options.keys.join(', ')}');
    }
    return found;
  }

  String? _role(String key) {
    final value = _string(key);
    if (value == null) return null;
    if (value.isEmpty) return '';
    if (!RegExp(r'^[a-z_][a-z0-9_]{0,62}$').hasMatch(value)) {
      throw AdminConfigException('$key: недопустимое имя роли PostgreSQL');
    }
    return value;
  }
}
