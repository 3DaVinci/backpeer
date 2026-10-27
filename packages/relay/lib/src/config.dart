import 'dart:io';

import 'package:core/core.dart';
import 'package:logging/logging.dart';
import 'package:yaml/yaml.dart';

/// Ошибка в настройках relay: сообщение для оператора.
final class RelayConfigException implements Exception {
  const new(this.message);

  final String message;

  @override
  String toString() => 'RelayConfigException: $message';
}

/// Пределы relay (`docs/ops/relay.md`).
final class RelayLimits {
  const new({
    this.maxConnections = 10000,
    this.maxSessionsPerPass = 16,
    this.maxPendingPerNode = 32,
    this.opensPerIpPerSecond = 20,
    this.opensPerIpBurst = 100,
    this.handshakeTimeout = const Duration(seconds: 10),
    this.acceptTimeout = const Duration(seconds: 10),
    this.idleTimeout = const Duration(minutes: 10),
    this.pingInterval = const Duration(seconds: 30),
  });

  /// Открытых TCP-соединений всего: управляющие, сеансы, рукопожатия.
  final int maxConnections;

  /// Одновременных сеансов по одному пропуску CONNECT.
  final int maxSessionsPerPass;

  /// Сеансов узла, ждущих его соединения приёма.
  final int maxPendingPerNode;

  /// Новых соединений с одного IP в секунду и запас.
  final double opensPerIpPerSecond;
  final int opensPerIpBurst;

  /// Сколько ждать `RelayOpen` после вызова.
  final Duration handshakeTimeout;

  /// Сколько ждать соединения приёма узла после `RelayIncoming`.
  final Duration acceptTimeout;

  /// Сеанс без байт в обе стороны дольше — закрывается.
  final Duration idleTimeout;

  /// Период ping управляющего соединения; молчание узла три периода —
  /// соединение закрывается.
  final Duration pingInterval;
}

/// Настройки relay: YAML-файл и переменные окружения
/// `FS_RELAY_<РАЗДЕЛ>_<КЛЮЧ>` поверх него, как у координатора.
final class RelayConfig {
  const new({
    required this.name,
    required this.passKeys,
    this.host,
    this.port = 7350,
    this.keyFile,
    this.coordinatorUrl,
    this.coordinatorCa,
    this.limits = const RelayLimits(),
    this.reportInterval = const Duration(seconds: 60),
    this.logLevel = Level.INFO,
  });

  /// Из YAML-текста [yaml] (может быть пустым) и окружения [environment].
  factory parse(String yaml, Map<String, String> environment) {
    final Object? doc;
    try {
      doc = loadYaml(yaml);
    } on YamlException catch (e) {
      throw RelayConfigException('YAML не разбирается: ${e.message}');
    }
    if (doc != null && doc is! YamlMap) {
      throw const RelayConfigException('корень настроек должен быть словарём');
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
      throw RelayConfigException(
        'неизвестные настройки: ${unknown.join(', ')}',
      );
    }
    for (final key in _keys) {
      final env = environment[envName(key)];
      if (env != null) values[key] = env;
    }
    return _Reader(values).build();
  }

  /// Из файла [path] (если задан) и окружения процесса.
  factory load(String? path) => RelayConfig.parse(
    path == null ? '' : File(path).readAsStringSync(),
    Platform.environment,
  );

  /// `listen.port` → `FS_RELAY_LISTEN_PORT`.
  static String envName(String key) =>
      'FS_RELAY_${key.replaceAll('.', '_').toUpperCase()}';

  static const _keys = {
    'name',
    'pass_keys',
    'key_file',
    'listen.host',
    'listen.port',
    'coordinator.url',
    'coordinator.ca',
    'limits.max_connections',
    'limits.max_sessions_per_pass',
    'limits.max_pending_per_node',
    'limits.opens_per_ip_per_second',
    'limits.opens_per_ip_burst',
    'limits.handshake_seconds',
    'limits.idle_seconds',
    'report.seconds',
    'log.level',
  };

  /// Имя relay: его же называет координатор в пропусках
  /// (`relay.servers`).
  final String name;

  /// Открытые ключи пропусков координатора (`relay.pass_key_file`): при
  /// ротации — два.
  final CoordinatorKeySet passKeys;

  /// Адрес приёма; `null` — все адреса IPv6 и IPv4.
  final String? host;
  final int port;

  /// Ключ relay для отчётов координатору; без него и без
  /// [coordinatorUrl] отчётов нет.
  final String? keyFile;
  final String? coordinatorUrl;

  /// Свой УЦ координатора в PEM (тестовый стенд).
  final String? coordinatorCa;

  final RelayLimits limits;

  /// Период отчёта `ReportRelayUsage`; координатор может назначить свой.
  final Duration reportInterval;
  final Level logLevel;
}

final class _Reader {
  new(this._values);

  final Map<String, Object?> _values;

  RelayConfig build() {
    const d = RelayLimits();
    final name = _string('name');
    if (name == null || !RelayWire.relayName.hasMatch(name)) {
      throw const RelayConfigException(
        'name: имя relay из a–z, 0–9, «.», «-», до 64 символов',
      );
    }
    final keys = _list('pass_keys');
    if (keys.isEmpty) {
      throw const RelayConfigException(
        'pass_keys: нужен открытый ключ пропусков координатора',
      );
    }
    for (final k in keys) {
      if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(k)) {
        throw const RelayConfigException(
          'pass_keys: ключ — 64 hex-символа в нижнем регистре',
        );
      }
    }
    final url = _string('coordinator.url');
    final keyFile = _string('key_file');
    if ((url == null) != (keyFile == null)) {
      throw const RelayConfigException(
        'coordinator.url и key_file задаются вместе',
      );
    }
    if (url != null) {
      final uri = Uri.tryParse(url);
      if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http')) {
        throw const RelayConfigException(
          'coordinator.url: ожидается адрес https://…',
        );
      }
    }
    return RelayConfig(
      name: name,
      passKeys: CoordinatorKeySet.fromHex(keys),
      host: _string('listen.host'),
      port: _int('listen.port', 0, 65535) ?? 7350,
      keyFile: keyFile,
      coordinatorUrl: url,
      coordinatorCa: _string('coordinator.ca'),
      limits: RelayLimits(
        maxConnections:
            _int('limits.max_connections', 1, 1000000) ?? d.maxConnections,
        maxSessionsPerPass:
            _int('limits.max_sessions_per_pass', 1, 1000) ??
            d.maxSessionsPerPass,
        maxPendingPerNode:
            _int('limits.max_pending_per_node', 1, 1000) ?? d.maxPendingPerNode,
        opensPerIpPerSecond:
            _double('limits.opens_per_ip_per_second') ?? d.opensPerIpPerSecond,
        opensPerIpBurst:
            _int('limits.opens_per_ip_burst', 1, 1 << 20) ?? d.opensPerIpBurst,
        handshakeTimeout: Duration(
          seconds:
              _int('limits.handshake_seconds', 1, 120) ??
              d.handshakeTimeout.inSeconds,
        ),
        idleTimeout: Duration(
          seconds:
              _int('limits.idle_seconds', 10, 86400) ?? d.idleTimeout.inSeconds,
        ),
      ),
      reportInterval: Duration(seconds: _int('report.seconds', 5, 3600) ?? 60),
      logLevel:
          switch (_string('log.level')) {
            null => null,
            'fine' => Level.FINE,
            'info' => Level.INFO,
            'warning' => Level.WARNING,
            'severe' => Level.SEVERE,
            _ => throw const RelayConfigException(
              'log.level: ожидается одно из fine, info, warning, severe',
            ),
          } ??
          Level.INFO,
    );
  }

  String? _string(String key) {
    final v = _values[key];
    if (v == null) return null;
    if (v is String || v is num) return '$v';
    throw RelayConfigException('$key: ожидается строка');
  }

  /// Список YAML или строка через запятую (переменная окружения).
  List<String> _list(String key) {
    final v = _values[key];
    if (v == null) return const [];
    if (v is YamlList) return [for (final e in v) '$e'.trim()];
    return [
      for (final part in '$v'.split(','))
        if (part.trim().isNotEmpty) part.trim(),
    ];
  }

  int? _int(String key, int min, int max) {
    final v = _values[key];
    if (v == null) return null;
    final n = v is int ? v : int.tryParse('$v');
    if (n == null || n < min || n > max) {
      throw RelayConfigException('$key: ожидается целое от $min до $max');
    }
    return n;
  }

  double? _double(String key) {
    final v = _values[key];
    if (v == null) return null;
    final n = v is num ? v.toDouble() : double.tryParse('$v');
    if (n == null || !n.isFinite || n <= 0) {
      throw RelayConfigException('$key: ожидается положительное число');
    }
    return n;
  }
}
