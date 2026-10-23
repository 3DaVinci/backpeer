import 'dart:io';

import 'package:logging/logging.dart';
import 'package:yaml/yaml.dart';

/// Ошибка в настройках узла: сообщение для владельца.
final class NodeConfigException implements Exception {
  const new(this.message);

  final String message;

  @override
  String toString() => 'NodeConfigException: $message';
}

/// Пределы скорости, байт в секунду; 0 — без предела. Расписание
/// («днём медленнее») — задача 3.4.3.
final class SpeedLimits {
  const new({this.uploadBytesPerSecond = 0, this.downloadBytesPerSecond = 0});

  /// Отдача фрагментов собеседникам.
  final int uploadBytesPerSecond;

  /// Приём фрагментов.
  final int downloadBytesPerSecond;

  Map<String, Object?> toJson() => {
    'uploadBytesPerSecond': uploadBytesPerSecond,
    'downloadBytesPerSecond': downloadBytesPerSecond,
  };
}

/// Журнал: уровень и файл с ротацией по размеру.
final class LogConfig {
  const new({
    this.level = Level.INFO,
    this.file,
    this.maxBytes = 10 << 20,
    this.files = 5,
  });

  final Level level;

  /// Путь к файлу журнала; `null` — `<data>/logs/node.log`, `-` — stderr
  /// без ротации (Docker, systemd).
  final String? file;

  /// Размер файла, после которого он переименовывается в `.1`.
  final int maxBytes;

  /// Сколько файлов хранить вместе с текущим.
  final int files;
}

/// Настройки демона `node` (`docs/ops/node.md`): YAML-файл и переменные
/// окружения `FS_NODE_<РАЗДЕЛ>_<КЛЮЧ>` поверх него, как у координатора.
final class NodeConfig {
  const new({
    required this.dataDir,
    this.quotaBytes = 100000000000,
    this.listenPort = 7340,
    this.endpoints = const [],
    this.limits = const SpeedLimits(),
    this.coordinatorUrl,
    this.coordinatorCa,
    this.coordinatorKeys = const [],
    this.controlSocket,
    this.shutdownGrace = const Duration(seconds: 30),
    this.log = const LogConfig(),
  });

  /// Из YAML-текста [yaml] (может быть пустым) и окружения [environment];
  /// [dataDir] — папка данных, если её нет ни в файле, ни в окружении.
  factory parse(
    String yaml,
    Map<String, String> environment, {
    required String dataDir,
  }) {
    final Object? doc;
    try {
      doc = loadYaml(yaml);
    } on YamlException catch (e) {
      throw NodeConfigException('YAML не разбирается: ${e.message}');
    }
    if (doc != null && doc is! YamlMap) {
      throw const NodeConfigException('корень настроек должен быть словарём');
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
      throw NodeConfigException('неизвестные настройки: ${unknown.join(', ')}');
    }
    for (final key in _keys) {
      final env = environment[envName(key)];
      if (env != null) values[key] = env;
    }
    return _Reader(values, dataDir).build();
  }

  /// Имя переменной окружения для ключа: `storage.quota_bytes` →
  /// `FS_NODE_STORAGE_QUOTA_BYTES`.
  static String envName(String key) =>
      'FS_NODE_${key.replaceAll('.', '_').toUpperCase()}';

  static const _keys = {
    'data.dir',
    'storage.quota_bytes',
    'listen.port',
    'listen.endpoints',
    'limits.upload_bytes_per_second',
    'limits.download_bytes_per_second',
    'coordinator.url',
    'coordinator.ca',
    'coordinator.keys',
    'control.socket',
    'shutdown.grace_seconds',
    'log.level',
    'log.file',
    'log.max_bytes',
    'log.files',
  };

  /// Папка данных: ключи, сертификат, фрагменты, журнал, сокет.
  final String dataDir;

  /// Сколько места узел отдаёт под чужие фрагменты; сообщается
  /// координатору как ёмкость.
  final int quotaBytes;

  /// Порт входящих соединений (TCP и UDP, задачи 3.5 и 3.7).
  final int listenPort;

  /// Адреса `хост:порт`, которые узел сообщает координатору; пусто — узел
  /// без прямого адреса (определение адреса — задача 3.5.1).
  final List<String> endpoints;

  final SpeedLimits limits;

  /// Адрес координатора; без него узел не регистрируется.
  final String? coordinatorUrl;

  /// Сертификат УЦ координатора в PEM (тестовый стенд со своим УЦ).
  final String? coordinatorCa;

  /// Ключи координатора в hex для тестового стенда; пусто — вшитый список
  /// (`protocol.md`, раздел 5.1).
  final List<String> coordinatorKeys;

  /// Путь к Unix-сокету локального API; `null` — `<data>/run/control.sock`.
  final String? controlSocket;

  /// Сколько ждать завершения текущих передач при остановке.
  final Duration shutdownGrace;

  final LogConfig log;
}

final class _Reader {
  new(this._values, this._dataDir);

  final Map<String, Object?> _values;
  final String _dataDir;

  NodeConfig build() {
    const d = NodeConfig(dataDir: '');
    const l = LogConfig();
    final url = _string('coordinator.url');
    if (url != null) {
      final uri = Uri.tryParse(url);
      if (uri == null ||
          !(uri.scheme == 'https' || uri.scheme == 'http') ||
          uri.host.isEmpty) {
        throw const NodeConfigException(
          'coordinator.url: ожидается адрес https://…',
        );
      }
    }
    final keys = _list('coordinator.keys');
    for (final k in keys) {
      if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(k)) {
        throw const NodeConfigException(
          'coordinator.keys: ключ — 64 hex-символа в нижнем регистре',
        );
      }
    }
    final dir = _string('data.dir') ?? _dataDir;
    if (dir.isEmpty) throw const NodeConfigException('data.dir не задан');
    return NodeConfig(
      dataDir: dir,
      quotaBytes: _int('storage.quota_bytes', 1 << 20, 1 << 60) ?? d.quotaBytes,
      listenPort: _int('listen.port', 1, 65535) ?? d.listenPort,
      endpoints: _list('listen.endpoints'),
      limits: SpeedLimits(
        uploadBytesPerSecond:
            _int('limits.upload_bytes_per_second', 0, 1 << 40) ?? 0,
        downloadBytesPerSecond:
            _int('limits.download_bytes_per_second', 0, 1 << 40) ?? 0,
      ),
      coordinatorUrl: url,
      coordinatorCa: _string('coordinator.ca'),
      coordinatorKeys: keys,
      controlSocket: _string('control.socket'),
      shutdownGrace: Duration(
        seconds:
            _int('shutdown.grace_seconds', 0, 3600) ??
            d.shutdownGrace.inSeconds,
      ),
      log: LogConfig(
        level:
            _enum('log.level', {
              'fine': Level.FINE,
              'info': Level.INFO,
              'warning': Level.WARNING,
              'severe': Level.SEVERE,
            }) ??
            l.level,
        file: _string('log.file'),
        maxBytes: _int('log.max_bytes', 1 << 16, 1 << 30) ?? l.maxBytes,
        files: _int('log.files', 1, 100) ?? l.files,
      ),
    );
  }

  String? _string(String key) {
    final v = _values[key];
    if (v == null) return null;
    if (v is String || v is num) return '$v';
    throw NodeConfigException('$key: ожидается строка');
  }

  /// Список строк: YAML-список или строка через запятую (окружение).
  List<String> _list(String key) {
    final v = _values[key];
    if (v == null) return const [];
    if (v is YamlList) return [for (final e in v) '$e'];
    if (v is String) {
      return [
        for (final e in v.split(','))
          if (e.trim().isNotEmpty) e.trim(),
      ];
    }
    throw NodeConfigException('$key: ожидается список');
  }

  int? _int(String key, int min, int max) {
    final v = _values[key];
    if (v == null) return null;
    final n = v is int ? v : int.tryParse('$v');
    if (n == null || n < min || n > max) {
      throw NodeConfigException('$key: ожидается целое от $min до $max');
    }
    return n;
  }

  T? _enum<T>(String key, Map<String, T> options) {
    final v = _string(key);
    if (v == null) return null;
    return options[v] ??
        (throw NodeConfigException(
          '$key: ожидается одно из ${options.keys.join(', ')}',
        ));
  }
}

/// Папка данных узла по умолчанию: `$XDG_DATA_HOME/file_storage/node`
/// (`~/.local/share/…`) на Linux, `~/Library/Application Support/
/// file_storage/node` на macOS, `%LOCALAPPDATA%\file_storage\node` на
/// Windows.
String defaultNodeDataDir(Map<String, String> env) {
  if (Platform.isWindows) {
    return '${env['LOCALAPPDATA'] ?? env['APPDATA']}\\file_storage\\node';
  }
  final home = env['HOME'] ?? '.';
  if (Platform.isMacOS) {
    return '$home/Library/Application Support/file_storage/node';
  }
  final xdg = env['XDG_DATA_HOME'] ?? '$home/.local/share';
  return '$xdg/file_storage/node';
}
