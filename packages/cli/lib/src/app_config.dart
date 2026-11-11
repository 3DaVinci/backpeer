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
      return AppHome(Directory('${env['APPDATA']}\\backpeer'));
    }
    final home = env['HOME'] ?? '.';
    if (Platform.isMacOS) {
      return AppHome(Directory('$home/Library/Application Support/backpeer'));
    }
    final xdg = env['XDG_CONFIG_HOME'] ?? '$home/.config';
    return AppHome(Directory('$xdg/backpeer'));
  }

  final Directory dir;

  File get configFile => File('${dir.path}/config.json');
  File get keysFile => File('${dir.path}/keys.bundle');
  String get indexPath => '${dir.path}/index.db';

  bool get initialized => keysFile.existsSync() && configFile.existsSync();
}

/// Настройки (`config.json`). Без координатора хранители — папки-«узлы»,
/// координатор — папка объектов. С координатором ([coordinator]) объекты и
/// размещение — на нём, а фрагменты идут на узлы по сети
/// ([fragments] = `network`, задача 3.9) или пишутся в папки-«узлы»,
/// зарегистрированные на координаторе (`node stub`, по умолчанию).
final class AppConfig {
  new({
    required this.nodes,
    required this.nodeCount,
    required this.objects,
    required this.durability,
    required this.deviceId,
    this.excludes = const [],
    this.coordinator,
    this.coordinatorCa,
    this.login,
    this.keyCopy,
    this.fragments = FragmentsMode.folders,
    this.distinctSubnets = true,
    this.retention = RetentionPolicy.defaults,
    this.uploadBytesPerSecond = 0,
    this.downloadBytesPerSecond = 0,
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

    T? optional<T extends Object>(String key) {
      final value = map[key];
      if (value != null && value is! T) {
        throw ConfigException(key: key, reason: 'неверный тип');
      }
      return value as T?;
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
      coordinator: optional<String>('coordinator'),
      coordinatorCa: optional<String>('coordinatorCa'),
      login: optional<String>('login'),
      keyCopy: optional<bool>('keyCopy'),
      fragments: FragmentsMode.parse(
        optional<String>('fragments') ?? FragmentsMode.folders.name,
      ),
      distinctSubnets: optional<bool>('distinctSubnets') ?? true,
      retention: switch (map) {
        {'retention': null} => null,
        {'retention': final Map<String, Object?> r} => RetentionPolicy.fromJson(
          r,
        ),
        {'retention': _} => throw const ConfigException(
          key: 'retention',
          reason: 'нужен объект или null',
        ),
        _ => RetentionPolicy.defaults,
      },
      uploadBytesPerSecond: _speed('uploadBytesPerSecond', map),
      downloadBytesPerSecond: _speed('downloadBytesPerSecond', map),
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
  Uint8List deviceId;
  List<String> excludes;

  /// Адрес координатора (`https://…`; `http` — только localhost); `null` —
  /// без координатора.
  String? coordinator;

  /// Сертификат УЦ координатора в PEM — для тестового стенда со своим УЦ.
  String? coordinatorCa;

  /// Имя для входа по паролю.
  String? login;

  /// Есть ли копия мастер-ключа на координаторе (вход по паролю);
  /// `null` — неизвестно (устройство восстановлено по фразе).
  bool? keyCopy;

  /// Куда идут фрагменты при работе с координатором.
  FragmentsMode fragments;

  /// Проверять, что узлы сегмента в разных подсетях (protocol.md,
  /// раздел 5); `false` — только для стенда, где все узлы в одной сети.
  bool distinctSubnets;

  /// Политика хранения снимков устройства (задача 5.3.5): агент применяет
  /// её после каждого бэкапа, `cli forget --policy` — по команде. `null` —
  /// хранить все снимки. Нет в файле — [RetentionPolicy.defaults].
  RetentionPolicy? retention;

  /// Предел отдачи в сеть, байт в секунду (0 — без предела): бэкап,
  /// проверка и восстановление по сети делят один предел.
  int uploadBytesPerSecond;

  /// Предел приёма из сети, байт в секунду (0 — без предела).
  int downloadBytesPerSecond;

  bool get usesCoordinator => coordinator != null;

  /// Фрагменты по сети на настоящие узлы.
  bool get usesNetwork =>
      coordinator != null && fragments == FragmentsMode.network;

  /// Без координатора узлов должно хватать на n разных (placeFragments).
  void check() {
    if (coordinator case final String url) {
      final uri = Uri.tryParse(url);
      if (uri == null || !(uri.isScheme('https') || uri.isScheme('http'))) {
        throw const ConfigException(
          key: 'coordinator',
          reason: 'нужен адрес https',
        );
      }
      return;
    }
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
    'coordinator': ?coordinator,
    'coordinatorCa': ?coordinatorCa,
    'login': ?login,
    'keyCopy': ?keyCopy,
    if (fragments != FragmentsMode.folders) 'fragments': fragments.name,
    if (!distinctSubnets) 'distinctSubnets': false,
    'retention': retention?.toJson(),
    if (uploadBytesPerSecond > 0) 'uploadBytesPerSecond': uploadBytesPerSecond,
    if (downloadBytesPerSecond > 0)
      'downloadBytesPerSecond': downloadBytesPerSecond,
  };

  void save(AppHome home) {
    check();
    home.dir.createSync(recursive: true);
    final text = const JsonEncoder.withIndent('  ').convert(toJson());
    File('${home.configFile.path}.tmp')
      ..writeAsStringSync('$text\n')
      ..renameSync(home.configFile.path);
  }

  /// Предел скорости из файла: нет поля — 0 (без предела), иначе
  /// целое от 0 до 1 ГиБ/с.
  static int _speed(String key, Map<String, Object?> map) {
    final value = map[key];
    if (value == null) return 0;
    if (value is int && value >= 0 && value <= 1 << 30) return value;
    throw ConfigException(
      key: key,
      reason: 'целое число байт в секунду от 0 до ${1 << 30}',
    );
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

/// Где хранятся фрагменты при работе с координатором.
enum FragmentsMode {
  /// Папки-«узлы», зарегистрированные на координаторе (`node stub`).
  folders,

  /// Узлы-хранители по сети: TCP, UDP после сведения, relay.
  network;

  static FragmentsMode parse(String value) => values.firstWhere(
    (m) => m.name == value,
    orElse: () => throw ConfigException(
      key: 'fragments',
      reason: 'нужно ${values.map((m) => m.name).join(' или ')}',
    ),
  );
}
