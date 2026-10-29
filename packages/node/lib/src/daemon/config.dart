import 'dart:io';

import 'package:logging/logging.dart';
import 'package:node/src/net/port_mapping/port_mapper.dart';
import 'package:node/src/net/relay_peers.dart';
import 'package:node/src/peers/speed_schedule.dart';
import 'package:yaml/yaml.dart';

/// Ошибка в настройках узла: сообщение для владельца.
final class NodeConfigException implements Exception {
  const new(this.message);

  final String message;

  @override
  String toString() => 'NodeConfigException: $message';
}

/// Пределы скорости, байт в секунду; 0 — без предела. Расписание
/// («днём медленнее») — [SpeedSchedule].
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

/// Пределы для собеседников по каналу Noise (задачи 3.4.2, 3.4.3).
final class PeerLimits {
  const new({
    this.maxConnections = 256,
    this.maxConnectionsPerPeer = 8,
    this.maxRequestsPerPeer = 32,
    this.requestsPerSecond = 100,
    this.transferTimeout = const Duration(seconds: 30),
    this.idleTimeout = const Duration(minutes: 5),
    this.bufferBytes = 1 << 20,
  });

  /// Одновременных соединений всего, вместе с идущими рукопожатиями.
  final int maxConnections;

  /// Одновременных соединений одного собеседника (ключ из сертификата).
  final int maxConnectionsPerPeer;

  /// Одновременных запросов одного собеседника по всем его соединениям.
  final int maxRequestsPerPeer;

  /// Новых запросов собеседника в секунду (в среднем; запас — вдвое).
  final int requestsPerSecond;

  /// Сколько ждать очередной части загрузки или приёма отправленной
  /// части выдачи.
  final Duration transferTimeout;

  /// Соединение без запросов дольше этого закрывается.
  final Duration idleTimeout;

  /// Сколько принятых частей загрузок соединения может ждать записи на
  /// диск, байт: больше — чтение из соединения встаёт на паузу.
  final int bufferBytes;
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
    String? storageDir,
    this.quotaBytes = 100000000000,
    this.freeReserveBytes = 2000000000,
    this.checkInterval = const Duration(days: 30),
    this.checkBytesPerSecond = 10000000,
    this.cleanupQuarantine = const Duration(hours: 24),
    this.reconcileInterval = const Duration(days: 7),
    this.listenHost,
    this.listenPort = 7340,
    this.portMapping = PortMappingMode.auto,
    this.udp = true,
    this.relay = RelayMode.auto,
    this.endpoints = const [],
    this.limits = const SpeedLimits(),
    this.schedule = const SpeedSchedule(),
    this.peers = const PeerLimits(),
    this.coordinatorUrl,
    this.coordinatorCa,
    this.coordinatorKeys = const [],
    this.commandChannel = true,
    this.controlSocket,
    this.shutdownGrace = const Duration(seconds: 30),
    this.log = const LogConfig(),
  }) : storageDir = storageDir ?? dataDir;

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
    'storage.dir',
    'storage.quota_bytes',
    'storage.free_reserve_bytes',
    'storage.check_interval_days',
    'storage.check_bytes_per_second',
    'storage.cleanup_quarantine_hours',
    'storage.reconcile_interval_hours',
    'listen.host',
    'listen.port',
    'listen.endpoints',
    'listen.port_mapping',
    'listen.udp',
    'listen.relay',
    'limits.upload_bytes_per_second',
    'limits.download_bytes_per_second',
    'limits.schedule',
    'peers.max_connections',
    'peers.max_connections_per_peer',
    'peers.max_requests_per_peer',
    'peers.requests_per_second',
    'peers.transfer_timeout_seconds',
    'peers.idle_timeout_seconds',
    'coordinator.url',
    'coordinator.ca',
    'coordinator.keys',
    'coordinator.channel',
    'control.socket',
    'shutdown.grace_seconds',
    'log.level',
    'log.file',
    'log.max_bytes',
    'log.files',
  };

  /// Папка данных: ключи, сертификат, фрагменты, журнал, сокет.
  final String dataDir;

  /// Папка фрагментов и их индекса — например, на другом диске
  /// (задача 5.5.1); по умолчанию — [dataDir].
  final String storageDir;

  /// Сколько места узел отдаёт под чужие фрагменты; сообщается
  /// координатору как ёмкость.
  final int quotaBytes;

  /// Сколько места на диске оставлять свободным: фрагмент, после которого
  /// останется меньше, не принимается (задача 3.2.3).
  final int freeReserveBytes;

  /// Как часто фоновая проверка перечитывает каждый фрагмент (3.2.4).
  final Duration checkInterval;

  /// Предел скорости чтения фоновой проверки, байт в секунду; 0 — без
  /// предела.
  final int checkBytesPerSecond;

  /// Сколько фрагмент, который координатор не учитывает, лежит до
  /// удаления (задача 4.4.3): удаляется, если и после карантина не
  /// признан.
  final Duration cleanupQuarantine;

  /// Как часто сверять фрагменты с координатором без его просьбы.
  final Duration reconcileInterval;

  /// Адрес приёма соединений; `null` — все адреса IPv6 и IPv4.
  final String? listenHost;

  /// Порт входящих соединений (TCP и UDP, задачи 3.5 и 3.7); 0 — любой
  /// свободный (тесты).
  final int listenPort;

  /// Адреса `хост:порт`, которые узел сообщает координатору всегда, кроме
  /// найденных проверкой достижимости (задача 3.5.1): например, имя DNS
  /// или порт, проброшенный вручную на другой номер.
  final List<String> endpoints;

  /// Автоматический проброс порта на роутере (задача 3.5.2).
  final PortMappingMode portMapping;

  /// Принимать соединения по UDP после сведения через координатор
  /// (задача 3.7.2): сокет UDP на том же номере порта, что TCP, на всех
  /// адресах IPv4.
  final bool udp;

  /// Принимать соединения через relay (задача 3.8.1): `auto` — когда у
  /// узла нет адресов, `on` — всегда, `off` — никогда.
  final RelayMode relay;

  /// Основные пределы скорости.
  final SpeedLimits limits;

  /// Пределы скорости по времени суток и дням недели поверх [limits].
  final SpeedSchedule schedule;

  final PeerLimits peers;

  /// Адрес координатора; без него узел не регистрируется.
  final String? coordinatorUrl;

  /// Сертификат УЦ координатора в PEM (тестовый стенд со своим УЦ).
  final String? coordinatorCa;

  /// Ключи координатора в hex для тестового стенда; пусто — вшитый список
  /// (`protocol.md`, раздел 5.1).
  final List<String> coordinatorKeys;

  /// Держать канал команд координатора (WebSocket, `protocol.md`,
  /// раздел 4.10); `false` — только heartbeat по HTTP.
  final bool commandChannel;

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
    const p = PeerLimits();
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
    final storageDir = _string('storage.dir');
    if (storageDir != null && !Directory(storageDir).isAbsolute) {
      throw const NodeConfigException('storage.dir: нужен абсолютный путь');
    }
    return NodeConfig(
      dataDir: dir,
      storageDir: storageDir,
      quotaBytes: _int('storage.quota_bytes', 1 << 20, 1 << 60) ?? d.quotaBytes,
      freeReserveBytes:
          _int('storage.free_reserve_bytes', 0, 1 << 50) ?? d.freeReserveBytes,
      checkInterval: Duration(
        days:
            _int('storage.check_interval_days', 1, 3650) ??
            d.checkInterval.inDays,
      ),
      checkBytesPerSecond:
          _int('storage.check_bytes_per_second', 0, 1 << 40) ??
          d.checkBytesPerSecond,
      cleanupQuarantine: Duration(
        hours:
            _int('storage.cleanup_quarantine_hours', 0, 24 * 365) ??
            d.cleanupQuarantine.inHours,
      ),
      reconcileInterval: Duration(
        hours:
            _int('storage.reconcile_interval_hours', 1, 24 * 365) ??
            d.reconcileInterval.inHours,
      ),
      listenHost: _string('listen.host'),
      listenPort: _int('listen.port', 0, 65535) ?? d.listenPort,
      endpoints: _list('listen.endpoints'),
      portMapping:
          _enum('listen.port_mapping', {
            for (final m in PortMappingMode.values) m.name: m,
          }) ??
          d.portMapping,
      udp: _bool('listen.udp') ?? d.udp,
      relay:
          _enum('listen.relay', {
            for (final m in RelayMode.values) m.name: m,
          }) ??
          d.relay,
      limits: SpeedLimits(
        uploadBytesPerSecond:
            _int('limits.upload_bytes_per_second', 0, 1 << 40) ?? 0,
        downloadBytesPerSecond:
            _int('limits.download_bytes_per_second', 0, 1 << 40) ?? 0,
      ),
      schedule: SpeedSchedule.parse(_list('limits.schedule', separator: ';')),
      peers: PeerLimits(
        maxConnections:
            _int('peers.max_connections', 1, 100000) ?? p.maxConnections,
        maxConnectionsPerPeer:
            _int('peers.max_connections_per_peer', 1, 1000) ??
            p.maxConnectionsPerPeer,
        maxRequestsPerPeer:
            _int('peers.max_requests_per_peer', 1, 10000) ??
            p.maxRequestsPerPeer,
        requestsPerSecond:
            _int('peers.requests_per_second', 1, 1000000) ??
            p.requestsPerSecond,
        transferTimeout: Duration(
          seconds:
              _int('peers.transfer_timeout_seconds', 1, 3600) ??
              p.transferTimeout.inSeconds,
        ),
        idleTimeout: Duration(
          seconds:
              _int('peers.idle_timeout_seconds', 1, 86400) ??
              p.idleTimeout.inSeconds,
        ),
      ),
      coordinatorUrl: url,
      coordinatorCa: _string('coordinator.ca'),
      coordinatorKeys: keys,
      commandChannel: _bool('coordinator.channel') ?? d.commandChannel,
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

  /// Список строк: YAML-список или строка через [separator] (окружение).
  List<String> _list(String key, {String separator = ','}) {
    final v = _values[key];
    if (v == null) return const [];
    if (v is YamlList) return [for (final e in v) '$e'];
    if (v is String) {
      return [
        for (final e in v.split(separator))
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

  bool? _bool(String key) {
    final v = _values[key];
    if (v == null) return null;
    if (v is bool) return v;
    return switch ('$v') {
      'true' => true,
      'false' => false,
      _ => throw NodeConfigException('$key: ожидается true или false'),
    };
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

/// Папка данных узла по умолчанию: `$XDG_DATA_HOME/backpeer/node`
/// (`~/.local/share/…`) на Linux, `~/Library/Application Support/
/// backpeer/node` на macOS, `%LOCALAPPDATA%\backpeer\node` на
/// Windows.
String defaultNodeDataDir(Map<String, String> env) {
  if (Platform.isWindows) {
    return '${env['LOCALAPPDATA'] ?? env['APPDATA']}\\backpeer\\node';
  }
  final home = env['HOME'] ?? '.';
  if (Platform.isMacOS) {
    return '$home/Library/Application Support/backpeer/node';
  }
  final xdg = env['XDG_DATA_HOME'] ?? '$home/.local/share';
  return '$xdg/backpeer/node';
}
