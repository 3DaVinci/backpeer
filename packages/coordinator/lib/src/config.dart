import 'dart:io';

import 'package:coordinator/src/audits/audit_service.dart';
import 'package:coordinator/src/nodes/node_channels.dart';
import 'package:coordinator/src/nodes/node_policy.dart';
import 'package:coordinator/src/nodes/rendezvous.dart';
import 'package:coordinator/src/placement/placement_policy.dart';
import 'package:coordinator/src/relay/relay_policy.dart';
import 'package:coordinator/src/repair/repair_service.dart';
import 'package:logging/logging.dart';
import 'package:yaml/yaml.dart';

/// Ошибка в настройках: сообщение для оператора.
final class ConfigException implements Exception {
  const new(this.message);

  final String message;

  @override
  String toString() => 'ConfigException: $message';
}

/// Режим TLS соединения с PostgreSQL.
enum DatabaseSsl { disable, require, verifyFull }

/// Подключение к PostgreSQL.
final class DatabaseConfig {
  const new({
    this.host = '127.0.0.1',
    this.port = 5432,
    this.name = 'fs_coordinator',
    this.user = 'fs_coordinator',
    this.password,
    this.ssl = DatabaseSsl.disable,
    this.maxConnections = 10,
  });

  final String host;
  final int port;
  final String name;
  final String user;
  final String? password;
  final DatabaseSsl ssl;
  final int maxConnections;

  @override
  String toString() =>
      'DatabaseConfig($user@$host:$port/$name, ssl: ${ssl.name})';
}

/// Пределы частоты запросов (protocol.md, раздел 4.5).
final class RateLimits {
  const new({
    this.ipPerSecond = 50,
    this.ipBurst = 200,
    this.keyPerSecond = 20,
    this.keyBurst = 100,
    this.loginPerMinute = 10,
    this.loginBurst = 20,
  });

  final double ipPerSecond;
  final int ipBurst;
  final double keyPerSecond;
  final int keyBurst;

  /// `GetLoginParams` и `GetKeyBundle` по IP — строже (protocol.md,
  /// раздел 4.7).
  final double loginPerMinute;
  final int loginBurst;
}

/// Настройки координатора: YAML-файл и переменные окружения
/// `FS_COORDINATOR_<РАЗДЕЛ>_<КЛЮЧ>` поверх него (`docs/ops/coordinator.md`).
final class CoordinatorConfig {
  const new({
    this.host = '127.0.0.1',
    this.port = 8443,
    this.trustForwardedFor = false,
    this.tlsCertificate,
    this.tlsPrivateKey,
    this.database = const DatabaseConfig(),
    this.limits = const RateLimits(),
    this.maxDevicesPerAccount = 5,
    this.maxObjectBytesPerAccount = 1 << 30,
    this.nodes = const NodePolicy(),
    this.channels = const ChannelPolicy(),
    this.rendezvous = const RendezvousPolicy(),
    this.placement = const PlacementPolicy(),
    this.relay = const RelayPolicy(),
    this.audits = const AuditPolicy(),
    this.repair = const RepairPolicy(),
    this.signerSocket,
    this.adminRole = 'fs_admin',
    this.logLevel = Level.INFO,
  });

  /// Из YAML-текста [yaml] (может быть пустым) и окружения [environment].
  factory parse(String yaml, Map<String, String> environment) {
    final Object? doc;
    try {
      doc = loadYaml(yaml);
    } on YamlException catch (e) {
      throw ConfigException('YAML не разбирается: ${e.message}');
    }
    if (doc != null && doc is! YamlMap) {
      throw const ConfigException('корень настроек должен быть словарём');
    }
    final values = <String, Object?>{};
    void flatten(String prefix, YamlMap map) {
      for (final MapEntry(:key, :value) in map.entries) {
        final name = prefix.isEmpty ? '$key' : '$prefix.$key';
        if (value is YamlMap) {
          flatten(name, value);
        } else {
          values[name] = value;
        }
      }
    }

    if (doc is YamlMap) flatten('', doc);
    final unknown = values.keys.where((k) => !_keys.contains(k)).toList();
    if (unknown.isNotEmpty) {
      throw ConfigException('неизвестные настройки: ${unknown.join(', ')}');
    }
    for (final key in _keys) {
      final env = environment[envName(key)];
      if (env != null) values[key] = env;
    }
    return _Reader(values).build();
  }

  /// Из файла [path] (если задан) и окружения процесса.
  factory load(String? path) => CoordinatorConfig.parse(
    path == null ? '' : File(path).readAsStringSync(),
    Platform.environment,
  );

  /// Имя переменной окружения для ключа: `database.password` →
  /// `FS_COORDINATOR_DATABASE_PASSWORD`.
  static String envName(String key) =>
      'FS_COORDINATOR_${key.replaceAll('.', '_').toUpperCase()}';

  static const _keys = {
    'listen.host',
    'listen.port',
    'listen.trust_forwarded_for',
    'tls.certificate',
    'tls.private_key',
    'database.host',
    'database.port',
    'database.name',
    'database.user',
    'database.password',
    'database.password_file',
    'database.ssl',
    'database.max_connections',
    'limits.ip_per_second',
    'limits.ip_burst',
    'limits.key_per_second',
    'limits.key_burst',
    'limits.login_per_minute',
    'limits.login_burst',
    'accounts.max_devices',
    'accounts.max_object_bytes',
    'nodes.min_capacity_bytes',
    'nodes.max_per_account',
    'nodes.heartbeat_seconds',
    'nodes.check_private_addresses',
    'nodes.reachability_timeout_ms',
    'channels.max_connections',
    'channels.ping_seconds',
    'rendezvous.public_host',
    'rendezvous.host',
    'rendezvous.port',
    'rendezvous.per_minute',
    'placement.min_availability',
    'placement.probation_hours',
    'placement.max_probation_share',
    'placement.probation_max_bytes',
    'placement.min_reputation',
    'placement.ticket_minutes',
    'placement.distinct_subnets',
    'placement.candidates_cache_ms',
    'relay.servers',
    'relay.pass_key_file',
    'relay.pass_minutes',
    'relay.pass_bytes',
    'relay.account_bytes_per_day',
    'relay.report_seconds',
    'relay.per_minute',
    'audits.enabled',
    'audits.interval_minutes',
    'audits.new_node_interval_minutes',
    'audits.new_node_days',
    'audits.suspect_interval_minutes',
    'audits.recheck_minutes',
    'audits.window',
    'audits.exclude_failures',
    'audits.max_per_second',
    'audits.max_concurrent',
    'audits.retention_days',
    'repair.enabled',
    'repair.offline_hours',
    'repair.lazy_margin',
    'repair.lazy_hours',
    'repair.max_jobs',
    'repair.max_bytes_per_hour',
    'repair.retry_minutes',
    'repair.job_minutes',
    'repair.executor_min_reputation',
    'signer.socket',
    'admin.role',
    'log.level',
  };

  final String host;
  final int port;
  final bool trustForwardedFor;

  /// Пути к цепочке сертификатов и закрытому ключу в PEM. Без них сервер
  /// слушает HTTP — только за обратным прокси с TLS.
  final String? tlsCertificate;
  final String? tlsPrivateKey;

  final DatabaseConfig database;
  final RateLimits limits;

  /// Действующих устройств на учётную запись (mvp-scope.md).
  final int maxDevicesPerAccount;

  /// Объём снимков и индексов на учётную запись: 1 ГиБ, индексы 1 ТБ
  /// данных занимают около 100 МиБ.
  final int maxObjectBytesPerAccount;

  /// Реестр узлов: минимум места, предел узлов, период heartbeat.
  final NodePolicy nodes;

  /// Канал команд узлов: предел каналов, период ping.
  final ChannelPolicy channels;

  /// Сведение узлов: адрес и порты сводника, предел сведений.
  final RendezvousPolicy rendezvous;

  /// Размещение: пороги доступности и репутации, испытательный срок,
  /// срок талонов.
  final PlacementPolicy placement;

  /// Relay: серверы, ключ пропусков, пределы трафика.
  final RelayPolicy relay;

  /// Аудиты хранения: частота, повторная проверка, исключение узлов.
  final AuditPolicy audits;

  /// Ремонт: когда узел потерян, очередь, пределы трафика.
  final RepairPolicy repair;

  /// Unix-сокет подписанта талонов; без него методы размещения отвечают
  /// `UNAVAILABLE`.
  final String? signerSocket;

  /// Роль PostgreSQL администратора (`coordinator admin`, ADR-007): права
  /// ей выдаёт `coordinator migrate`.
  final String adminRole;

  final Level logLevel;
}

final class _Reader {
  new(this._values);

  final Map<String, Object?> _values;

  CoordinatorConfig build() {
    const d = CoordinatorConfig();
    const db = DatabaseConfig();
    const lim = RateLimits();
    const np = NodePolicy();
    const pp = PlacementPolicy();
    const cp = ChannelPolicy();
    const rp = RendezvousPolicy();
    const relay = RelayPolicy();
    const ap = AuditPolicy();
    final cert = _string('tls.certificate');
    final key = _string('tls.private_key');
    if ((cert == null) != (key == null)) {
      throw const ConfigException(
        'tls.certificate и tls.private_key задаются вместе',
      );
    }
    var password = _string('database.password');
    final passwordFile = _string('database.password_file');
    if (password != null && passwordFile != null) {
      throw const ConfigException(
        'database.password и database.password_file задаются по отдельности',
      );
    }
    if (passwordFile != null) {
      try {
        password = File(passwordFile).readAsStringSync().trim();
      } on FileSystemException catch (e) {
        throw ConfigException(
          'database.password_file не читается: ${e.message}',
        );
      }
    }
    return CoordinatorConfig(
      host: _string('listen.host') ?? d.host,
      port: _int('listen.port', 1, 65535) ?? d.port,
      trustForwardedFor:
          _bool('listen.trust_forwarded_for') ?? d.trustForwardedFor,
      tlsCertificate: cert,
      tlsPrivateKey: key,
      database: DatabaseConfig(
        host: _string('database.host') ?? db.host,
        port: _int('database.port', 1, 65535) ?? db.port,
        name: _string('database.name') ?? db.name,
        user: _string('database.user') ?? db.user,
        password: password,
        ssl:
            _enum('database.ssl', {
              'disable': DatabaseSsl.disable,
              'require': DatabaseSsl.require,
              'verify-full': DatabaseSsl.verifyFull,
            }) ??
            db.ssl,
        maxConnections:
            _int('database.max_connections', 1, 1000) ?? db.maxConnections,
      ),
      limits: RateLimits(
        ipPerSecond: _double('limits.ip_per_second') ?? lim.ipPerSecond,
        ipBurst: _int('limits.ip_burst', 1, 1 << 30) ?? lim.ipBurst,
        keyPerSecond: _double('limits.key_per_second') ?? lim.keyPerSecond,
        keyBurst: _int('limits.key_burst', 1, 1 << 30) ?? lim.keyBurst,
        loginPerMinute:
            _double('limits.login_per_minute') ?? lim.loginPerMinute,
        loginBurst: _int('limits.login_burst', 1, 1 << 30) ?? lim.loginBurst,
      ),
      maxDevicesPerAccount:
          _int('accounts.max_devices', 1, 100) ?? d.maxDevicesPerAccount,
      maxObjectBytesPerAccount:
          _int('accounts.max_object_bytes', 1 << 20, 1 << 50) ??
          d.maxObjectBytesPerAccount,
      nodes: NodePolicy(
        minCapacityBytes:
            _int('nodes.min_capacity_bytes', 0, 1 << 60) ?? np.minCapacityBytes,
        maxPerAccount:
            _int('nodes.max_per_account', 1, 1000) ?? np.maxPerAccount,
        heartbeatInterval: Duration(
          seconds:
              _int('nodes.heartbeat_seconds', 10, 3600) ??
              np.heartbeatInterval.inSeconds,
        ),
        checkPrivateAddresses:
            _bool('nodes.check_private_addresses') ?? np.checkPrivateAddresses,
        reachabilityTimeout: Duration(
          milliseconds:
              _int('nodes.reachability_timeout_ms', 100, 60000) ??
              np.reachabilityTimeout.inMilliseconds,
        ),
      ),
      channels: ChannelPolicy(
        maxConnections:
            _int('channels.max_connections', 0, 1000000) ?? cp.maxConnections,
        pingInterval: Duration(
          seconds:
              _int('channels.ping_seconds', 5, 600) ??
              cp.pingInterval.inSeconds,
        ),
      ),
      rendezvous: RendezvousPolicy(
        publicHost: _string('rendezvous.public_host'),
        host: _string('rendezvous.host') ?? rp.host,
        port: _int('rendezvous.port', 1, 65534) ?? rp.port,
        perMinute: _int('rendezvous.per_minute', 1, 10000) ?? rp.perMinute,
      ),
      placement: PlacementPolicy(
        minAvailability:
            _fraction('placement.min_availability') ?? pp.minAvailability,
        probation: Duration(
          hours:
              _int('placement.probation_hours', 0, 24 * 365) ??
              pp.probation.inHours,
        ),
        maxProbationShare:
            _fraction('placement.max_probation_share') ?? pp.maxProbationShare,
        probationMaxBytes:
            _int('placement.probation_max_bytes', 0, 1 << 62) ??
            pp.probationMaxBytes,
        minReputation:
            _fraction('placement.min_reputation') ?? pp.minReputation,
        ticketLifetime: Duration(
          minutes:
              _int('placement.ticket_minutes', 1, 60) ??
              pp.ticketLifetime.inMinutes,
        ),
        distinctSubnets:
            _bool('placement.distinct_subnets') ?? pp.distinctSubnets,
        candidatesCache: Duration(
          milliseconds:
              _int('placement.candidates_cache_ms', 0, 60000) ??
              pp.candidatesCache.inMilliseconds,
        ),
      ),
      relay: RelayPolicy(
        servers: _relays(),
        passKeyFile: _string('relay.pass_key_file'),
        passLifetime: Duration(
          minutes:
              _int('relay.pass_minutes', 5, 120) ??
              relay.passLifetime.inMinutes,
        ),
        passBytes:
            _int('relay.pass_bytes', 1 << 20, 1 << 50) ?? relay.passBytes,
        accountBytesPerDay:
            _int('relay.account_bytes_per_day', 0, 1 << 50) ??
            relay.accountBytesPerDay,
        reportInterval: Duration(
          seconds:
              _int('relay.report_seconds', 5, 3600) ??
              relay.reportInterval.inSeconds,
        ),
        perMinute: _int('relay.per_minute', 1, 10000) ?? relay.perMinute,
      ),
      audits: _audits(ap),
      repair: _repair(),
      signerSocket: _string('signer.socket'),
      adminRole: _role('admin.role') ?? d.adminRole,
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

  AuditPolicy _audits(AuditPolicy ap) {
    Duration minutes(String key, int max, Duration d) =>
        Duration(minutes: _int(key, 1, max) ?? d.inMinutes);
    final window = _int('audits.window', 1, 1000) ?? ap.window;
    final exclude =
        _int('audits.exclude_failures', 1, 1000) ?? ap.excludeFailures;
    if (exclude > window) {
      throw const ConfigException(
        'audits.exclude_failures не больше audits.window',
      );
    }
    return AuditPolicy(
      enabled: _bool('audits.enabled') ?? ap.enabled,
      interval: minutes('audits.interval_minutes', 30 * 24 * 60, ap.interval),
      newNodeInterval: minutes(
        'audits.new_node_interval_minutes',
        30 * 24 * 60,
        ap.newNodeInterval,
      ),
      newNodeAge: Duration(
        days: _int('audits.new_node_days', 0, 365) ?? ap.newNodeAge.inDays,
      ),
      suspectInterval: minutes(
        'audits.suspect_interval_minutes',
        24 * 60,
        ap.suspectInterval,
      ),
      recheckDelay: minutes('audits.recheck_minutes', 24 * 60, ap.recheckDelay),
      window: window,
      excludeFailures: exclude,
      maxPerSecond: _int('audits.max_per_second', 1, 10000) ?? ap.maxPerSecond,
      maxConcurrent:
          _int('audits.max_concurrent', 1, 10000) ?? ap.maxConcurrent,
      retention: Duration(
        days: _int('audits.retention_days', 1, 3650) ?? ap.retention.inDays,
      ),
    );
  }

  RepairPolicy _repair() {
    const rp = RepairPolicy();
    return RepairPolicy(
      enabled: _bool('repair.enabled') ?? rp.enabled,
      offline: Duration(
        hours: _int('repair.offline_hours', 1, 24 * 365) ?? rp.offline.inHours,
      ),
      lazyMargin: _int('repair.lazy_margin', 0, 254) ?? rp.lazyMargin,
      lazyDelay: Duration(
        hours: _int('repair.lazy_hours', 0, 24 * 30) ?? rp.lazyDelay.inHours,
      ),
      maxJobs: _int('repair.max_jobs', 1, 100000) ?? rp.maxJobs,
      maxBytesPerHour:
          _int('repair.max_bytes_per_hour', 1 << 20, 1 << 60) ??
          rp.maxBytesPerHour,
      retryDelay: Duration(
        minutes:
            _int('repair.retry_minutes', 1, 24 * 60) ?? rp.retryDelay.inMinutes,
      ),
      jobTimeout: Duration(
        minutes: _int('repair.job_minutes', 1, 60) ?? rp.jobTimeout.inMinutes,
      ),
      executorMinReputation:
          _double('repair.executor_min_reputation') ?? rp.executorMinReputation,
    );
  }

  /// `relay.servers`: список YAML или строка через запятую (переменная
  /// окружения), элемент — «имя хост:порт ключ».
  List<RelayServerInfo> _relays() {
    final v = _values['relay.servers'];
    if (v == null) return const [];
    final lines = v is YamlList
        ? [for (final e in v) '$e']
        : [
            for (final part in '$v'.split(','))
              if (part.trim().isNotEmpty) part,
          ];
    final out = <RelayServerInfo>[];
    for (final line in lines) {
      try {
        out.add(RelayServerInfo.parse(line));
      } on FormatException catch (e) {
        throw ConfigException('relay.servers: ${e.message}');
      }
    }
    final names = {for (final r in out) r.name};
    if (names.length != out.length) {
      throw const ConfigException('relay.servers: имена повторяются');
    }
    return out;
  }

  String? _role(String key) {
    final v = _string(key);
    if (v != null && !RegExp(r'^[a-z_][a-z0-9_]{0,62}$').hasMatch(v)) {
      throw ConfigException('$key: имя роли PostgreSQL из a–z, 0–9, «_»');
    }
    return v;
  }

  String? _string(String key) {
    final v = _values[key];
    if (v == null) return null;
    if (v is String || v is num) return '$v';
    throw ConfigException('$key: ожидается строка');
  }

  int? _int(String key, int min, int max) {
    final v = _values[key];
    if (v == null) return null;
    final n = v is int ? v : int.tryParse('$v');
    if (n == null || n < min || n > max) {
      throw ConfigException('$key: ожидается целое от $min до $max');
    }
    return n;
  }

  double? _double(String key) {
    final v = _values[key];
    if (v == null) return null;
    final n = v is num ? v.toDouble() : double.tryParse('$v');
    if (n == null || !n.isFinite || n <= 0) {
      throw ConfigException('$key: ожидается положительное число');
    }
    return n;
  }

  /// Доля от 0 до 1 включительно.
  double? _fraction(String key) {
    final v = _values[key];
    if (v == null) return null;
    final n = v is num ? v.toDouble() : double.tryParse('$v');
    if (n == null || n < 0 || n > 1) {
      throw ConfigException('$key: ожидается число от 0 до 1');
    }
    return n;
  }

  bool? _bool(String key) {
    final v = _values[key];
    if (v == null) return null;
    if (v is bool) return v;
    return switch ('$v') {
      'true' => true,
      'false' => false,
      _ => throw ConfigException('$key: ожидается true или false'),
    };
  }

  T? _enum<T>(String key, Map<String, T> options) {
    final v = _string(key);
    if (v == null) return null;
    return options[v] ??
        (throw ConfigException(
          '$key: ожидается одно из ${options.keys.join(', ')}',
        ));
  }
}
