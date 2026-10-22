import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';

/// Каталог программы: конфигурация, ключи устройства, локальный индекс.
/// По умолчанию — стандартный для ОС, иначе `--home` или `FS_HOME`.
final class AppHome {
  new(this.dir);

  factory resolve({required Map<String, String> env, String? override}) {
    if (override != null) return AppHome(Directory(override));
    if (env['FS_HOME'] case final String home) return AppHome(Directory(home));
    if (Platform.isWindows) {
      return AppHome(Directory('${env['APPDATA']}\\file_storage'));
    }
    final home = env['HOME'] ?? '.';
    if (Platform.isMacOS) {
      return AppHome(
        Directory('$home/Library/Application Support/file_storage'),
      );
    }
    final xdg = env['XDG_CONFIG_HOME'] ?? '$home/.config';
    return AppHome(Directory('$xdg/file_storage'));
  }

  final Directory dir;

  File get configFile => File('${dir.path}/config.json');
  File get keysFile => File('${dir.path}/keys.bundle');
  String get indexPath => '${dir.path}/index.db';

  bool get initialized => keysFile.existsSync() && configFile.existsSync();
}

/// Настройки (`config.json`). Пока сети нет, хранители — папки-«узлы»,
/// координатор — папка объектов.
final class AppConfig {
  new({
    required this.nodes,
    required this.nodeCount,
    required this.objects,
    required this.durability,
    required this.deviceId,
    this.excludes = const [],
  });

  /// Чтение с проверкой; ошибки — [ConfigException].
  factory parse(String text) {
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException catch (e) {
      throw ConfigException(key: 'config.json', reason: e.message);
    }
    if (json is! Map<String, Object?>) {
      throw const ConfigException(key: 'config.json', reason: 'нужен объект');
    }
    final map = json;
    T field<T>(String key) {
      final value = map[key];
      if (value is! T) {
        throw ConfigException(
          key: key,
          reason: 'нет значения или неверный тип',
        );
      }
      return value;
    }

    final config = AppConfig(
      nodes: field<String>('nodes'),
      nodeCount: field<int>('nodeCount'),
      objects: field<String>('objects'),
      durability: DurabilityParameters.fromConfig(map),
      deviceId: _hex('deviceId', field<String>('deviceId')),
      excludes: [
        for (final e in (map['excludes'] as List<Object?>?) ?? const [])
          if (e is String)
            e
          else
            throw const ConfigException(
              key: 'excludes',
              reason: 'нужны строки',
            ),
      ],
    )..check();
    return config;
  }

  static AppConfig load(AppHome home) {
    try {
      return AppConfig.parse(home.configFile.readAsStringSync());
    } on PathNotFoundException {
      throw ConfigException(
        key: home.configFile.path,
        reason: 'нет конфигурации; сначала init или recover',
      );
    }
  }

  String nodes;
  int nodeCount;
  String objects;
  DurabilityParameters durability;
  final Uint8List deviceId;
  List<String> excludes;

  /// Узлов должно хватать на n разных (placeFragments).
  void check() {
    if (nodeCount < durability.n) {
      throw ConfigException(
        key: 'nodeCount',
        reason: 'узлов $nodeCount, нужно не меньше n = ${durability.n}',
      );
    }
  }

  Map<String, Object?> toJson() => {
    'nodes': nodes,
    'nodeCount': nodeCount,
    'objects': objects,
    ...durability.toConfig(),
    'deviceId': bytesToHex(deviceId),
    'excludes': excludes,
  };

  void save(AppHome home) {
    check();
    home.dir.createSync(recursive: true);
    final text = const JsonEncoder.withIndent('  ').convert(toJson());
    File('${home.configFile.path}.tmp')
      ..writeAsStringSync('$text\n')
      ..renameSync(home.configFile.path);
  }

  static Uint8List _hex(String key, String value) {
    try {
      final bytes = hexToBytes(value);
      if (bytes.length != 32) throw const FormatException();
      return bytes;
    } on FormatException {
      throw ConfigException(key: key, reason: 'нужно 32 байта в hex');
    }
  }
}
