import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cli/cli.dart';
import 'package:core/core.dart';
import 'package:daemon_kit/daemon_kit.dart';
import 'package:logging/logging.dart';
import 'package:node/node.dart'
    show
        NodeConfigException,
        NodeIdentity,
        NodeIdentityException,
        SpeedRule,
        defaultNodeDataDir,
        diskAvailableBytes;

/// Как включена роль хранителя: `agent/keeper.json` (задача 5.5.1).
final class KeeperSettings {
  const new({
    required this.enabled,
    required this.storageDir,
    required this.quotaBytes,
    this.uploadBytesPerSecond = 0,
    this.downloadBytesPerSecond = 0,
    this.schedule = const [],
    this.enabledAt,
    this.lingerByAgent = false,
  });

  factory fromJson(Map<String, Object?> json) => KeeperSettings(
    enabled: json['enabled'] == true,
    storageDir: json['storageDir']! as String,
    quotaBytes: json['quotaBytes']! as int,
    uploadBytesPerSecond: json['uploadBytesPerSecond'] as int? ?? 0,
    downloadBytesPerSecond: json['downloadBytesPerSecond'] as int? ?? 0,
    schedule: [
      for (final r in json['schedule'] as List<Object?>? ?? const [])
        r! as String,
    ],
    enabledAt: switch (json['enabledAt']) {
      final String s => DateTime.parse(s),
      _ => null,
    },
    lingerByAgent: json['lingerByAgent'] == true,
  );

  /// Нет файла — роль не включалась; испорчен — тоже `null`, приложение
  /// предложит включить заново.
  static KeeperSettings? load(File file) {
    if (!file.existsSync()) return null;
    try {
      return KeeperSettings.fromJson(
        jsonDecode(file.readAsStringSync()) as Map<String, Object?>,
      );
    } on Object {
      return null;
    }
  }

  final bool enabled;

  /// Папка фрагментов (`storage.dir` узла), например на другом диске.
  final String storageDir;
  final int quotaBytes;

  /// 0 — без предела.
  final int uploadBytesPerSecond;
  final int downloadBytesPerSecond;

  /// Правила `limits.schedule` узла: `mon-fri 09:00-18:00 upload=1000000`.
  final List<String> schedule;
  final DateTime? enabledAt;

  /// Работу служб без входа (`loginctl enable-linger`, задача 5.6.4)
  /// включил агент: при выключении роли он же её и выключит.
  final bool lingerByAgent;

  KeeperSettings copyWith({required bool enabled, bool? lingerByAgent}) =>
      KeeperSettings(
        enabled: enabled,
        lingerByAgent: lingerByAgent ?? this.lingerByAgent,
        storageDir: storageDir,
        quotaBytes: quotaBytes,
        uploadBytesPerSecond: uploadBytesPerSecond,
        downloadBytesPerSecond: downloadBytesPerSecond,
        schedule: schedule,
        enabledAt: enabledAt,
      );

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'storageDir': storageDir,
    'quotaBytes': quotaBytes,
    'uploadBytesPerSecond': uploadBytesPerSecond,
    'downloadBytesPerSecond': downloadBytesPerSecond,
    'schedule': schedule,
    'enabledAt': enabledAt?.toUtc().toIso8601String(),
    'lingerByAgent': lingerByAgent,
  };

  void save(File file) {
    file.parent.createSync(recursive: true);
    File('${file.path}.tmp-$pid')
      ..writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(toJson()),
        flush: true,
      )
      ..renameSync(file.path);
  }
}

/// Запуск демона `node` в фоне: службой ОС (`ServiceNodeLauncher`,
/// задачи 5.6.1, 5.6.4) или, если служб нет, отдельным процессом
/// ([ProcessNodeLauncher]).
abstract interface class NodeLauncher {
  /// Исполняемый файл `node`; `null` — не найден.
  String? get executable;

  /// Чем запускается: `process`, `systemd`, `launchd`, `task-scheduler`.
  String get kind;

  /// Запускает `node run --data [dataDir]` отдельно от агента; `false` —
  /// запускать нечем.
  Future<bool> start(String dataDir);

  /// Роль выключена: больше не запускать (служба удаляется). Сам демон
  /// останавливает [KeeperApi] через его локальный API.
  Future<void> disable();
}

/// [NodeLauncher] отдельным процессом: `FS_NODE_EXECUTABLE`, иначе `node`
/// рядом с агентом (один бандл), в соседнем бандле пакета приложения
/// (`daemons/node/bin/node`) или сборки (`build/bin/<ОС>-<арх>/node/
/// bundle/bin/node`). Программу Node.js с тем же именем из `PATH` не ищет.
final class ProcessNodeLauncher implements NodeLauncher {
  new({Map<String, String>? environment})
    : executable = find(environment ?? Platform.environment);

  @override
  final String? executable;

  @override
  String get kind => 'process';

  static String? find(Map<String, String> env) {
    if (env['FS_NODE_EXECUTABLE'] case final path? when path.isNotEmpty) {
      return File(path).existsSync() ? path : null;
    }
    final name = Platform.isWindows ? 'node.exe' : 'node';
    final self = File(Platform.resolvedExecutable).parent;
    for (final candidate in [
      '${self.path}/$name',
      '${self.path}/../../node/bin/$name',
      '${self.path}/../../../node/bundle/bin/$name',
    ]) {
      if (File(candidate).existsSync()) {
        // Без `..`: путь попадёт в юнит службы.
        return File(candidate).resolveSymbolicLinksSync();
      }
    }
    return null;
  }

  @override
  Future<void> disable() async {}

  @override
  Future<bool> start(String dataDir) async {
    final exe = executable;
    if (exe == null) return false;
    await Process.start(exe, [
      'run',
      '--data',
      dataDir,
    ], mode: ProcessStartMode.detached);
    return true;
  }
}

/// Методы `keeper.*` локального API агента (задачи 5.5.1, 5.5.2): включить
/// роль хранителя из приложения — ключи узла, сертификат ключом учётной
/// записи, настройки `node.yaml`, запуск демона; выключить. Ключи
/// учётной записи есть только у агента, поэтому сертификат выпускает он.
final class KeeperApi {
  new({
    required this.home,
    required this.file,
    required this.crypto,
    required this.withKeys,
    required this.launcher,
    required this.dataDir,
    this.linger,
    this.stopTimeout = const Duration(seconds: 45),
  });

  final AppHome home;

  /// `agent/keeper.json`.
  final File file;
  final CryptoProvider crypto;
  final Future<Map<String, Object?>> Function(
    Future<Map<String, Object?>> Function(AccountKeys) body,
  )
  withKeys;
  final NodeLauncher launcher;

  /// Папка данных узла: ключи, сертификат, `node.yaml`, сокет.
  final String dataDir;

  /// Хранитель без входа пользователя (Linux, задача 5.6.4); `null` —
  /// не нужно (нет служб systemd).
  final Linger? linger;
  final Duration stopTimeout;

  static final _log = Logger('agent.keeper');

  /// Самая маленькая квота, которую предлагает приложение. Координатор
  /// может требовать больше (`nodes.min_capacity_bytes`, по умолчанию
  /// 10 ГБ) — тогда узел не зарегистрируется, и приложение покажет
  /// ошибку координатора из `status` узла.
  static const int minQuotaBytes = 1 << 30;

  bool _busy = false;

  /// Папка данных узла по умолчанию — та же, где её ищет приложение.
  static String defaultDataDir([Map<String, String>? environment]) {
    final env = environment ?? Platform.environment;
    return env['FS_NODE_DATA_DIR'] ?? defaultNodeDataDir(env);
  }

  KeeperSettings? get settings => KeeperSettings.load(file);

  ControlEndpoint get _endpoint =>
      ControlEndpoint.forDataDir(dataDir, process: 'хранитель');

  Future<Map<String, Object?>> handle(
    String method,
    Map<String, Object?> params,
  ) async {
    if (_busy && method != 'keeper.info' && method != 'keeper.disk') {
      throw const ControlException('busy', 'роль хранителя уже меняется');
    }
    try {
      return switch (method) {
        'keeper.info' => _info(),
        'keeper.disk' => _disk(params),
        'keeper.enable' => await _exclusive(() => _enable(params)),
        'keeper.disable' => await _exclusive(_disable),
        _ => throw ControlException(
          'unknown_method',
          'неизвестный метод $method',
        ),
      };
    } on NodeIdentityException catch (e) {
      throw ControlException('failed', e.message);
    } on FileSystemException catch (e) {
      throw ControlException(
        'failed',
        '${e.message}${e.path == null ? '' : ' (${e.path})'}',
      );
    }
  }

  Future<Map<String, Object?>> _exclusive(
    Future<Map<String, Object?>> Function() body,
  ) async {
    _busy = true;
    try {
      return await body();
    } finally {
      _busy = false;
    }
  }

  Map<String, Object?> _info() {
    final s = settings;
    return {
      'enabled': s?.enabled ?? false,
      'settings': s?.toJson(),
      'dataDir': dataDir,
      'defaultStorageDir': dataDir,
      'hasKeys': File('$dataDir/${NodeIdentity.keyFile}').existsSync(),
      'hasCertificate': File('$dataDir/${NodeIdentity.certificateFile}')
          .existsSync(),
      'nodeExecutable': launcher.executable,
      'launcher': launcher.kind,
      'linger': _lingerJson(),
      'minQuotaBytes': minQuotaBytes,
    };
  }

  /// `null` — не применимо (не Linux, не служба systemd).
  Map<String, Object?>? _lingerJson([String? problem]) {
    final l = linger;
    if (l == null) return null;
    return {
      'enabled': l.enabled,
      'problem': ?problem,
      if (!l.enabled) 'command': l.manualCommand,
    };
  }

  /// Свободное место для папки [params] `path` (папки может ещё не быть —
  /// считается по ближайшей существующей).
  Map<String, Object?> _disk(Map<String, Object?> params) {
    final path = params['path'] ?? dataDir;
    if (path is! String || !Directory(path).isAbsolute) {
      throw const ControlException('bad_request', 'path — абсолютный путь');
    }
    var existing = Directory(path).absolute;
    while (!existing.existsSync() && existing.parent.path != existing.path) {
      existing = existing.parent;
    }
    return {'path': path, 'availableBytes': diskAvailableBytes(existing.path)};
  }

  Future<Map<String, Object?>> _enable(Map<String, Object?> params) async {
    final config = _appConfig();
    final coordinator = config.coordinator;
    if (coordinator == null) {
      throw const ControlException(
        'no_coordinator',
        'учётная запись без координатора: хранителю некуда '
            'регистрироваться',
      );
    }
    final next = _parse(params);
    final keysParam = params['coordinatorKeys'];
    if (keysParam != null &&
        (keysParam is! List<Object?> ||
            keysParam.any(
              (k) => k is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(k),
            ))) {
      throw const ControlException(
        'bad_request',
        'coordinatorKeys — ключи по 64 hex-символа',
      );
    }
    final available =
        _disk({'path': next.storageDir})['availableBytes'] as int?;
    final used = await _usedBytes();
    if (available != null && next.quotaBytes > available + used) {
      throw ControlException(
        'no_space',
        'на диске свободно ${available + used} байт, меньше квоты',
      );
    }

    final dir = Directory(dataDir);
    await NodeIdentity.ensureKeys(dir, crypto);
    final certified = await _certify(dir);

    _writeNodeConfig(
      next,
      coordinator: coordinator,
      ca: config.coordinatorCa,
      keys: (keysParam as List<Object?>?)?.cast<String>(),
    );
    final lingerProblem = await _enableLinger();
    next.copyWith(enabled: true, lingerByAgent: _lingerByAgent).save(file);
    _log.info(
      LogEvent('keeper_enabled', {
        'quotaBytes': next.quotaBytes,
        'storageDir': next.storageDir,
        'certificateIssued': certified,
      }),
    );
    final restarted = await _stopNode();
    final started = await _startNode();
    final identity = await NodeIdentity.load(dir, crypto);
    try {
      return {
        'nodeId': bytesToHex(identity.nodeId),
        'certificateIssued': certified,
        'restarted': restarted,
        'started': started,
        if (!started) 'reason': 'node_not_found',
        'launcher': launcher.kind,
        'linger': _lingerJson(lingerProblem),
        'settings': next.toJson(),
      };
    } finally {
      identity.dispose();
    }
  }

  /// Выключить роль: демон останавливается, фрагменты и ключи узла
  /// остаются. Выход с переносом фрагментов на другие узлы — задача
  /// 4.4.1; до неё координатор восстановит их ремонтом (4.3).
  Future<Map<String, Object?>> _disable() async {
    final s = settings;
    final stopped = await _stopNode();
    await launcher.disable();
    if (s != null && s.lingerByAgent && linger != null) {
      final problem = await linger!.disable();
      _log.info(LogEvent('linger_disabled', {'problem': ?problem}));
    }
    s?.copyWith(enabled: false, lingerByAgent: false).save(file);
    _log.info(LogEvent('keeper_disabled', {'stopped': stopped}));
    return {'enabled': false, 'stopped': stopped};
  }

  bool _lingerByAgent = false;

  /// Хранитель без входа пользователя: `loginctl enable-linger`. Уже
  /// включено (администратором или прежним включением роли) — не трогает;
  /// политика polkit не разрешает — причина для приложения, роль всё
  /// равно включается: узел работает, пока пользователь в системе.
  Future<String?> _enableLinger() async {
    _lingerByAgent = settings?.lingerByAgent ?? false;
    final l = linger;
    if (l == null || l.enabled) return null;
    final problem = await l.enable();
    if (problem == null) _lingerByAgent = true;
    _log.info(LogEvent('linger_enabled', {'problem': ?problem}));
    return problem;
  }

  /// Роль включена, а демон не запущен — запустить (старт агента).
  Future<void> ensureRunning() async {
    if (settings?.enabled != true) return;
    if (await _running()) return;
    final started = await _startNode();
    _log.info(LogEvent('keeper_started', {'started': started}));
  }

  KeeperSettings _parse(Map<String, Object?> params) {
    final storageDir = params['storageDir'] ?? dataDir;
    final quota = params['quotaBytes'];
    final up = params['uploadBytesPerSecond'] ?? 0;
    final down = params['downloadBytesPerSecond'] ?? 0;
    final schedule = params['schedule'] ?? const <Object?>[];
    if (storageDir is! String || !Directory(storageDir).isAbsolute) {
      throw const ControlException(
        'bad_request',
        'storageDir — абсолютный путь',
      );
    }
    if (quota is! int || quota < minQuotaBytes) {
      throw const ControlException(
        'bad_request',
        'quotaBytes — не меньше $minQuotaBytes',
      );
    }
    if (up is! int || down is! int || up < 0 || down < 0) {
      throw const ControlException(
        'bad_request',
        'пределы скорости — байт в секунду, 0 — без предела',
      );
    }
    if (schedule is! List<Object?> || schedule.any((r) => r is! String)) {
      throw const ControlException('bad_request', 'schedule — список правил');
    }
    for (final rule in schedule.cast<String>()) {
      try {
        SpeedRule.parse(rule);
      } on NodeConfigException catch (e) {
        throw ControlException('bad_request', 'schedule: ${e.message}');
      }
    }
    return KeeperSettings(
      enabled: true,
      storageDir: Directory(storageDir).absolute.path,
      quotaBytes: quota,
      uploadBytesPerSecond: up,
      downloadBytesPerSecond: down,
      schedule: schedule.cast<String>(),
      enabledAt: settings?.enabledAt ?? DateTime.now(),
    );
  }

  AppConfig _appConfig() {
    if (!home.initialized) {
      throw const ControlException(
        'not_configured',
        'нет учётной записи на этом устройстве',
      );
    }
    try {
      return AppConfig.load(home);
    } on ConfigException catch (e) {
      throw ControlException('failed', e.message);
    }
  }

  /// Сертификат узла от учётной записи этого устройства; уже есть свой —
  /// не выпускает. Возвращает `true`, если выпустил.
  Future<bool> _certify(Directory dir) async {
    final identity = await NodeIdentity.load(dir, crypto);
    try {
      var issued = false;
      await withKeys((keys) async {
        final owner = identity.owner;
        if (owner != null && constantTimeEquals(owner, keys.accountId)) {
          return const {};
        }
        final signed = await NodeCertificates.issue(
          crypto,
          keys,
          nodeId: identity.nodeId,
          nodeDh: identity.nodeDh,
          issuedAt: DateTime.now(),
        );
        await NodeIdentity.importCertificate(
          dir,
          crypto,
          signed.writeToBuffer(),
        );
        issued = true;
        return const {};
      });
      return issued;
    } finally {
      identity.dispose();
    }
  }

  /// `node.yaml` в папке данных узла. YAML — надмножество JSON, поэтому
  /// пишется JSON: строки и пути не нужно экранировать по правилам YAML.
  void _writeNodeConfig(
    KeeperSettings s, {
    required String coordinator,
    String? ca,
    List<String>? keys,
  }) {
    final yaml = File('$dataDir/node.yaml');
    final previous = _previousKeys(yaml);
    final config = {
      'storage': {'dir': s.storageDir, 'quota_bytes': s.quotaBytes},
      'limits': {
        'upload_bytes_per_second': s.uploadBytesPerSecond,
        'download_bytes_per_second': s.downloadBytesPerSecond,
        if (s.schedule.isNotEmpty) 'schedule': s.schedule,
      },
      'coordinator': {
        'url': coordinator,
        'ca': ?ca,
        if (keys ?? previous case final k? when k.isNotEmpty) 'keys': k,
      },
    };
    File('${yaml.path}.tmp-$pid')
      ..writeAsStringSync(
        '# Создано агентом бэкапа при включении роли хранителя из '
        'приложения.\n'
        '# Изменение роли в приложении перезапишет файл.\n'
        '${const JsonEncoder.withIndent('  ').convert(config)}\n',
        flush: true,
      )
      ..renameSync(yaml.path);
  }

  /// Ключи координатора из прежнего `node.yaml` агента: при изменении
  /// квоты приложение их не передаёт.
  static List<String>? _previousKeys(File yaml) {
    if (!yaml.existsSync()) return null;
    try {
      final text = yaml.readAsStringSync();
      final json = jsonDecode(text.substring(text.indexOf('{')));
      final keys = (json as Map<String, Object?>)['coordinator'];
      return ((keys as Map<String, Object?>?)?['keys'] as List<Object?>?)
          ?.cast<String>();
    } on Object {
      return null;
    }
  }

  Future<bool> _running() async {
    try {
      final client = await ControlClient.connect(_endpoint);
      await client.close();
      return true;
    } on ControlException {
      return false;
    }
  }

  Future<int> _usedBytes() async {
    try {
      final client = await ControlClient.connect(_endpoint);
      try {
        final status = await client.call('status');
        return status['usedBytes'] as int? ?? 0;
      } finally {
        await client.close();
      }
    } on ControlException {
      return 0;
    }
  }

  /// Останавливает запущенный демон и ждёт, пока он освободит папку;
  /// `true` — был запущен.
  Future<bool> _stopNode() async {
    final ControlClient client;
    try {
      client = await ControlClient.connect(_endpoint);
    } on ControlException {
      return false;
    }
    try {
      await client.call('stop');
    } on ControlException {
      // Уже останавливается.
    } finally {
      await client.close();
    }
    final deadline = DateTime.now().add(stopTimeout);
    while (DateTime.now().isBefore(deadline)) {
      if (!await _running() && !_locked()) return true;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    throw const ControlException('failed', 'хранитель не остановился');
  }

  /// Папка данных ещё занята демоном (`node.lock`).
  bool _locked() {
    final lock = File('$dataDir/node.lock');
    if (!lock.existsSync()) return false;
    try {
      DirLock.acquire(lock, busy: '').release();
      return false;
    } on FileSystemException {
      return true;
    }
  }

  /// Запускает демон и ждёт его локальный API; `false` — запускать нечем
  /// или демон не поднялся (причина — в его журнале).
  Future<bool> _startNode() async {
    if (!await launcher.start(dataDir)) return false;
    for (var i = 0; i < 100; i++) {
      if (await _running()) return true;
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    return false;
  }
}
