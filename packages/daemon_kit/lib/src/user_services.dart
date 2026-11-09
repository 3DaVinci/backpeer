import 'dart:convert';
import 'dart:io';

/// Запуск внешней программы: `systemctl`, `launchctl`, `schtasks`,
/// `powershell.exe`. В тестах — подделка, которая записывает вызовы.
typedef CommandRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

Future<ProcessResult> _run(String executable, List<String> arguments) =>
    Process.run(executable, arguments);

/// Фоновый процесс как служба уровня пользователя (задача 5.6.1): что
/// запускать и как называть.
final class ServiceSpec {
  const new({
    required this.name,
    required this.description,
    required this.executable,
    this.arguments = const [],
    this.environment = const {},
  });

  /// Короткое имя: `agent`, `node`. Полное имя службы —
  /// [UserServices.serviceName].
  final String name;

  /// Для человека: «агент бэкапа».
  final String description;

  /// Абсолютный путь исполняемого файла.
  final String executable;
  final List<String> arguments;

  /// Переменные окружения службы: `FS_HOME`, если каталог не стандартный.
  final Map<String, String> environment;
}

/// Состояние службы.
enum ServiceState {
  /// Службы нет: не устанавливалась или удалена.
  notInstalled,

  /// Установлена, но не работает (остановлена, упала, ещё не запускалась).
  stopped,

  /// Работает.
  running,
}

/// Служба уровня пользователя не установилась или не управляется.
final class ServiceException implements Exception {
  const new(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Службы уровня пользователя ОС для фоновых процессов клиента (задача
/// 5.6.1, ADR-011): запуск при входе пользователя, перезапуск после сбоя,
/// работа без открытого окна приложения.
///
/// | ОС | Чем | Где |
/// |---|---|---|
/// | Linux | пользовательский юнит systemd | `~/.config/systemd/user/<prefix>-<name>.service` |
/// | macOS | LaunchAgent | `~/Library/LaunchAgents/<id>.<name>.plist` |
/// | Windows | задание Планировщика «при входе» | `\<prefix>\<name>` |
abstract interface class UserServices {
  /// Для текущей ОС; `FS_SERVICES=none` или нет менеджера служб (Linux
  /// без systemd) — [NoUserServices].
  factory forPlatform({
    Map<String, String>? environment,
    CommandRunner? runner,
  }) {
    final env = environment ?? Platform.environment;
    final run = runner ?? _run;
    if (env['FS_SERVICES'] == 'none') {
      return const NoUserServices('отключено FS_SERVICES=none');
    }
    if (Platform.isLinux) {
      if (!Directory('/run/systemd/system').existsSync()) {
        return const NoUserServices('нет systemd');
      }
      return SystemdUserServices(
        unitDir: SystemdUserServices.defaultUnitDir(env),
        runner: run,
      );
    }
    if (Platform.isMacOS) {
      return LaunchAgentServices(
        agentsDir: '${env['HOME']}/Library/LaunchAgents',
        runner: run,
      );
    }
    if (Platform.isWindows) {
      return ScheduledTaskServices(
        user: '${env['USERDOMAIN']}\\${env['USERNAME']}',
        tempDir: Directory.systemTemp.path,
        runner: run,
      );
    }
    return const NoUserServices('ОС не поддерживается');
  }

  /// Для журнала и приложения: `systemd`, `launchd`, `task-scheduler`,
  /// `none`.
  String get kind;

  /// Есть ли менеджер служб: иначе фоновые процессы запускает тот, кому
  /// они нужны (приложение, агент).
  bool get available;

  /// Полное имя службы для [name]: `backpeer-agent.service`.
  String serviceName(String name);

  Future<ServiceState> state(String name);

  /// Ставит службу (заменяет прежнюю с тем же именем), включает запуск
  /// при входе и запускает ([start]). Уже работающая служба с другими
  /// параметрами перезапускается.
  Future<void> install(ServiceSpec spec, {bool start = true});

  /// Останавливает и удаляет службу; её не было — ничего не делает.
  Future<void> uninstall(String name);

  Future<void> start(String name);

  Future<void> stop(String name);

  /// Перезапускает работающую службу, не выгружая её: так приложение
  /// поднимает зависшего агента, не оставляя службу незагруженной
  /// (у launchd `bootout` + `bootstrap` подряд иногда отвечает
  /// «Bootstrap failed: 5: Input/output error»).
  Future<void> restart(String name);
}

/// Префикс имён служб и файлов. Название продукта ещё не выбрано
/// (С.1.2) — временное, общее с пакетами (`tool/linux_package`).
const servicePrefix = 'backpeer';

/// Идентификатор для macOS (обратная запись домена), временный, как
/// [servicePrefix].
const serviceBundleId = 'org.backpeer';

/// Windows: запускатель без консольного окна (`backpeer-launcher.exe`,
/// `tool/windows_package/launcher.cs`). `dart build cli` собирает
/// консольные программы, а задание Планировщика запускает их в сеансе
/// пользователя — окно консоли висело бы всё время работы демона. Задание
/// запускает этот запускатель (подсистема WINDOWS), а он — программу
/// службы с `CREATE_NO_WINDOW`: окна нет, а stdin/stdout/stderr — каналы
/// запускателя, поэтому демон может писать в stderr и с `--log -`.
final class QuietLauncher {
  /// Имя файла рядом с программой службы (`agent.exe`, `node.exe`).
  static const fileName = 'backpeer-launcher.exe';

  /// `FS_QUIET_LAUNCHER` — явный путь (`''` — не использовать); иначе
  /// [fileName] рядом с [executable]. `null` — запускателя нет: служба
  /// запускает программу напрямую (запуск из исходников без упаковки).
  static String? find(
    String executable, {
    Map<String, String>? environment,
    bool windows = true,
  }) {
    final env = environment ?? Platform.environment;
    if (env['FS_QUIET_LAUNCHER'] case final String override) {
      return override.isEmpty ? null : override;
    }
    if (!windows) return null;
    final candidate = File(
      '${File(executable).parent.path}${Platform.pathSeparator}$fileName',
    );
    return candidate.existsSync() ? candidate.path : null;
  }
}

/// Менеджера служб нет: [available] — `false`, методы бросают
/// [ServiceException].
final class NoUserServices implements UserServices {
  const new(this.reason);

  final String reason;

  @override
  String get kind => 'none';

  @override
  bool get available => false;

  @override
  String serviceName(String name) => name;

  @override
  Future<ServiceState> state(String name) async => ServiceState.notInstalled;

  @override
  Future<void> install(ServiceSpec spec, {bool start = true}) =>
      throw ServiceException('службы ОС недоступны: $reason');

  @override
  Future<void> uninstall(String name) async {}

  @override
  Future<void> start(String name) =>
      throw ServiceException('службы ОС недоступны: $reason');

  @override
  Future<void> stop(String name) async {}

  @override
  Future<void> restart(String name) =>
      throw ServiceException('службы ОС недоступны: $reason');
}

/// Linux: пользовательский юнит systemd (`systemctl --user`). Юнит
/// включён в `default.target`: запускается при входе пользователя, а с
/// `loginctl enable-linger` ([Linger]) — при загрузке, без входа.
final class SystemdUserServices implements UserServices {
  new({
    required this.unitDir,
    this.prefix = servicePrefix,
    CommandRunner? runner,
  }) : _runner = runner ?? _run;

  /// `$XDG_CONFIG_HOME/systemd/user` или `~/.config/systemd/user`.
  static String defaultUnitDir(Map<String, String> env) {
    final config = env['XDG_CONFIG_HOME'] ?? '${env['HOME']}/.config';
    return '$config/systemd/user';
  }

  final String unitDir;
  final String prefix;
  final CommandRunner _runner;

  @override
  String get kind => 'systemd';

  @override
  bool get available => true;

  @override
  String serviceName(String name) => '$prefix-$name.service';

  File _unit(String name) => File('$unitDir/${serviceName(name)}');

  /// Текст юнита. `ConditionPathExists` — программа удалена вместе с
  /// пакетом, а юнит остался у пользователя, который не входил: служба
  /// тихо не запускается, без перезапусков с ошибкой. Коды 64 и 69 (неверный
  /// вызов, уже запущен) — не сбой: перезапуск не поможет.
  static String unitText(ServiceSpec spec) {
    final command = [spec.executable, ...spec.arguments].map(_quote);
    final buffer = StringBuffer()
      ..writeln('# Создано приложением (задача 5.6.1). Изменения перезапишет')
      ..writeln('# следующая установка службы.')
      ..writeln('[Unit]')
      ..writeln('Description=${spec.description}')
      ..writeln('ConditionPathExists=${_escapePath(spec.executable)}')
      ..writeln()
      ..writeln('[Service]')
      ..writeln('Type=simple')
      ..writeln('ExecStart=${command.join(' ')}');
    for (final MapEntry(:key, :value) in spec.environment.entries) {
      buffer.writeln('Environment=${_quote('$key=$value')}');
    }
    buffer
      ..writeln('Restart=on-failure')
      ..writeln('RestartSec=10')
      ..writeln('RestartPreventExitStatus=64 69')
      // Агент дописывает сегмент, узел закрывает соединения.
      ..writeln('TimeoutStopSec=60')
      ..writeln()
      ..writeln('[Install]')
      ..writeln('WantedBy=default.target');
    return buffer.toString();
  }

  /// Аргумент командной строки юнита: в двойных кавычках, `%` — `%%`
  /// (спецификаторы systemd), `$` — `$$` (подстановка переменных).
  static String _quote(String s) {
    final escaped = s
        .replaceAll(r'\', r'\\')
        .replaceAll('"', r'\"')
        .replaceAll('%', '%%')
        .replaceAll(r'$', r'$$');
    return '"$escaped"';
  }

  static String _escapePath(String s) => s.replaceAll('%', '%%');

  Future<ProcessResult> _systemctl(List<String> args) async {
    try {
      return await _runner('systemctl', ['--user', ...args]);
    } on ProcessException catch (e) {
      throw ServiceException('systemctl не запускается: ${e.message}');
    }
  }

  Future<void> _check(List<String> args) async {
    final result = await _systemctl(args);
    if (result.exitCode != 0) {
      throw ServiceException(
        'systemctl --user ${args.join(' ')}: '
        '${'${result.stderr}'.trim()}',
      );
    }
  }

  @override
  Future<ServiceState> state(String name) async {
    if (!_unit(name).existsSync()) return ServiceState.notInstalled;
    final result = await _systemctl(['is-active', serviceName(name)]);
    return '${result.stdout}'.trim() == 'active'
        ? ServiceState.running
        : ServiceState.stopped;
  }

  @override
  Future<void> install(ServiceSpec spec, {bool start = true}) async {
    final unit = _unit(spec.name);
    final text = unitText(spec);
    final changed = !unit.existsSync() || unit.readAsStringSync() != text;
    if (changed) {
      unit.parent.createSync(recursive: true);
      File('${unit.path}.tmp-$pid')
        ..writeAsStringSync(text, flush: true)
        ..renameSync(unit.path);
      await _check(['daemon-reload']);
    }
    await _check(['enable', serviceName(spec.name)]);
    if (!start) return;
    // Новый юнит у работающей службы — перезапуск, иначе — запуск.
    await _check([if (changed) 'restart' else 'start', serviceName(spec.name)]);
  }

  @override
  Future<void> uninstall(String name) async {
    final unit = _unit(name);
    if (!unit.existsSync()) return;
    await _systemctl(['disable', '--now', serviceName(name)]);
    unit.deleteSync();
    await _systemctl(['daemon-reload']);
    await _systemctl(['reset-failed', serviceName(name)]);
  }

  @override
  Future<void> start(String name) => _check(['start', serviceName(name)]);

  @override
  Future<void> stop(String name) => _check(['stop', serviceName(name)]);

  @override
  Future<void> restart(String name) => _check(['restart', serviceName(name)]);
}

/// macOS: LaunchAgent в `~/Library/LaunchAgents` (`launchctl` в домене
/// `gui/<uid>`): запуск при входе, перезапуск после сбоя
/// (`KeepAlive.SuccessfulExit = false`: остановка методом `stop` — не сбой).
final class LaunchAgentServices implements UserServices {
  new({
    required this.agentsDir,
    this.bundleId = serviceBundleId,
    CommandRunner? runner,
  }) : _runner = runner ?? _run;

  final String agentsDir;
  final String bundleId;
  final CommandRunner _runner;
  String? _uid;

  @override
  String get kind => 'launchd';

  @override
  bool get available => true;

  @override
  String serviceName(String name) => '$bundleId.$name';

  File _plist(String name) => File('$agentsDir/${serviceName(name)}.plist');

  /// [keepAlive] — перезапускать после сбоя (фоновые процессы); значок
  /// приложения при входе — без перезапуска.
  static String plistText(
    String label,
    ServiceSpec spec, {
    bool keepAlive = true,
  }) {
    String esc(String s) => const HtmlEscape(HtmlEscapeMode.element).convert(s);
    final buffer = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln(
        '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
        '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">',
      )
      ..writeln('<plist version="1.0">')
      ..writeln('<dict>')
      ..writeln('  <key>Label</key>')
      ..writeln('  <string>${esc(label)}</string>')
      ..writeln('  <key>ProgramArguments</key>')
      ..writeln('  <array>');
    for (final arg in [spec.executable, ...spec.arguments]) {
      buffer.writeln('    <string>${esc(arg)}</string>');
    }
    buffer.writeln('  </array>');
    if (spec.environment.isNotEmpty) {
      buffer
        ..writeln('  <key>EnvironmentVariables</key>')
        ..writeln('  <dict>');
      for (final MapEntry(:key, :value) in spec.environment.entries) {
        buffer
          ..writeln('    <key>${esc(key)}</key>')
          ..writeln('    <string>${esc(value)}</string>');
      }
      buffer.writeln('  </dict>');
    }
    buffer
      ..writeln('  <key>RunAtLoad</key>')
      ..writeln('  <true/>');
    if (keepAlive) {
      buffer
        ..writeln('  <key>KeepAlive</key>')
        ..writeln('  <dict>')
        ..writeln('    <key>SuccessfulExit</key>')
        ..writeln('    <false/>')
        ..writeln('  </dict>')
        ..writeln('  <key>ThrottleInterval</key>')
        ..writeln('  <integer>10</integer>')
        ..writeln('  <key>ProcessType</key>')
        ..writeln('  <string>Background</string>');
    }
    buffer
      ..writeln('</dict>')
      ..writeln('</plist>');
    return buffer.toString();
  }

  Future<String> _domain() async {
    if (_uid == null) {
      final result = await _runner('id', ['-u']);
      _uid = '${result.stdout}'.trim();
    }
    return 'gui/$_uid';
  }

  Future<ProcessResult> _launchctl(List<String> args) async {
    try {
      return await _runner('launchctl', args);
    } on ProcessException catch (e) {
      throw ServiceException('launchctl не запускается: ${e.message}');
    }
  }

  @override
  Future<ServiceState> state(String name) async {
    if (!_plist(name).existsSync()) return ServiceState.notInstalled;
    final result = await _launchctl([
      'print',
      '${await _domain()}/${serviceName(name)}',
    ]);
    if (result.exitCode != 0) return ServiceState.stopped;
    return RegExp(
          r'^\s*state = running',
          multiLine: true,
        ).hasMatch('${result.stdout}')
        ? ServiceState.running
        : ServiceState.stopped;
  }

  @override
  Future<void> install(ServiceSpec spec, {bool start = true}) async {
    final label = serviceName(spec.name);
    final plist = _plist(spec.name);
    final domain = await _domain();
    // Заменить загруженное задание: bootout, затем bootstrap.
    await _launchctl(['bootout', '$domain/$label']);
    plist.parent.createSync(recursive: true);
    File('${plist.path}.tmp-$pid')
      ..writeAsStringSync(plistText(label, spec), flush: true)
      ..renameSync(plist.path);
    if (!start) return;
    final result = await _launchctl(['bootstrap', domain, plist.path]);
    if (result.exitCode != 0) {
      throw ServiceException(
        'launchctl bootstrap: ${'${result.stderr}'.trim()}',
      );
    }
  }

  @override
  Future<void> uninstall(String name) async {
    final plist = _plist(name);
    if (!plist.existsSync()) return;
    await _launchctl(['bootout', '${await _domain()}/${serviceName(name)}']);
    plist.deleteSync();
  }

  @override
  Future<void> start(String name) async {
    final domain = await _domain();
    final label = serviceName(name);
    var result = await _launchctl(['kickstart', '$domain/$label']);
    if (result.exitCode != 0) {
      // Задание не загружено (после bootout) — загрузить.
      result = await _launchctl(['bootstrap', domain, _plist(name).path]);
    }
    if (result.exitCode != 0) {
      throw ServiceException('launchctl: ${'${result.stderr}'.trim()}');
    }
  }

  @override
  Future<void> stop(String name) async {
    await _launchctl(['bootout', '${await _domain()}/${serviceName(name)}']);
  }

  @override
  Future<void> restart(String name) async {
    final domain = await _domain();
    final label = serviceName(name);
    // `-k` — завершить текущий процесс и запустить заново, задание
    // остаётся загруженным.
    var result = await _launchctl(['kickstart', '-k', '$domain/$label']);
    if (result.exitCode != 0) {
      // Задание не загружено — загрузить из плиста, как [start].
      result = await _launchctl(['bootstrap', domain, _plist(name).path]);
    }
    if (result.exitCode != 0) {
      throw ServiceException('launchctl: ${'${result.stderr}'.trim()}');
    }
  }
}

/// Windows: задание Планировщика «при входе пользователя» с перезапуском
/// после сбоя (ADR-011: служба Windows работает в другом сеансе и не
/// видит сетевых дисков и секретов DPAPI пользователя). Задание —
/// `\<prefix>\<name>`, только для текущего пользователя, без прав
/// администратора.
final class ScheduledTaskServices implements UserServices {
  new({
    required this.user,
    required this.tempDir,
    this.prefix = servicePrefix,
    Map<String, String>? environment,
    CommandRunner? runner,
  }) : _env = environment ?? Platform.environment,
       _runner = runner ?? _run;

  /// `DOMAIN\user` — для триггера входа и принципала задания.
  final String user;
  final String tempDir;
  final String prefix;
  final Map<String, String> _env;
  final CommandRunner _runner;

  @override
  String get kind => 'task-scheduler';

  @override
  bool get available => true;

  @override
  String serviceName(String name) => '\\$prefix\\$name';

  /// XML задания (схема Task Scheduler 1.2): вход пользователя, без
  /// ограничения времени, без остановки от батареи, перезапуск раз в
  /// минуту после сбоя, один экземпляр.
  ///
  /// [launcher] — запускатель без консольного окна ([QuietLauncher]): тогда
  /// действие задания — он, а программа службы и её аргументы идут ему
  /// аргументами. Без запускателя действие — сама программа (запуск из
  /// исходников; на Windows это окно консоли).
  static String taskXml(String user, ServiceSpec spec, {String? launcher}) {
    String esc(String s) =>
        const HtmlEscape(HtmlEscapeMode.attribute).convert(s);
    String arg(String s) => s.isEmpty || s.contains(RegExp(r'[\s"]'))
        ? '"${s.replaceAll('"', r'\"')}"'
        : s;
    // Переменных окружения у действия задания нет — через cmd не идём,
    // FS_HOME передаётся аргументом `--home` (его добавляет вызывающий).
    final command = launcher ?? spec.executable;
    final arguments = launcher == null
        ? spec.arguments
        : [spec.executable, ...spec.arguments];
    return '<?xml version="1.0" encoding="UTF-16"?>\n'
        '<Task version="1.2" '
        'xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">\n'
        '  <RegistrationInfo>\n'
        '    <Description>${esc(spec.description)}</Description>\n'
        '  </RegistrationInfo>\n'
        '  <Triggers>\n'
        '    <LogonTrigger>\n'
        '      <Enabled>true</Enabled>\n'
        '      <UserId>${esc(user)}</UserId>\n'
        '    </LogonTrigger>\n'
        '  </Triggers>\n'
        '  <Principals>\n'
        '    <Principal id="Author">\n'
        '      <UserId>${esc(user)}</UserId>\n'
        '      <LogonType>InteractiveToken</LogonType>\n'
        '      <RunLevel>LeastPrivilege</RunLevel>\n'
        '    </Principal>\n'
        '  </Principals>\n'
        '  <Settings>\n'
        '    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>\n'
        '    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>\n'
        '    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>\n'
        '    <AllowHardTerminate>true</AllowHardTerminate>\n'
        '    <StartWhenAvailable>true</StartWhenAvailable>\n'
        '    <AllowStartOnDemand>true</AllowStartOnDemand>\n'
        '    <Enabled>true</Enabled>\n'
        '    <Hidden>true</Hidden>\n'
        '    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>\n'
        '    <Priority>7</Priority>\n'
        '    <RestartOnFailure>\n'
        '      <Interval>PT1M</Interval>\n'
        '      <Count>999</Count>\n'
        '    </RestartOnFailure>\n'
        '  </Settings>\n'
        '  <Actions Context="Author">\n'
        '    <Exec>\n'
        '      <Command>${esc(command)}</Command>\n'
        '      <Arguments>${esc(arguments.map(arg).join(' '))}'
        '</Arguments>\n'
        '    </Exec>\n'
        '  </Actions>\n'
        '</Task>\n';
  }

  Future<ProcessResult> _schtasks(List<String> args) async {
    try {
      return await _runner('schtasks', args);
    } on ProcessException catch (e) {
      throw ServiceException('schtasks не запускается: ${e.message}');
    }
  }

  /// Состояние задания. `schtasks` печатает состояние словами на языке
  /// Windows («Running», «Выполняется»), поэтому спрашиваем PowerShell:
  /// `Get-ScheduledTask` возвращает перечисление, одинаковое на всех
  /// языках. PowerShell недоступен — запасной разбор CSV (английская
  /// Windows).
  @override
  Future<ServiceState> state(String name) async {
    final task = serviceName(name);
    final sep = task.lastIndexOf(r'\');
    final path = task.substring(0, sep + 1);
    final taskName = task.substring(sep + 1);
    final script = StringBuffer()
      ..write(r'$t = Get-ScheduledTask -TaskPath ')
      ..write("'${_psString(path)}'")
      ..write(' -TaskName ')
      ..write("'${_psString(taskName)}'")
      ..write(' -ErrorAction SilentlyContinue; ')
      ..write(r"if ($null -eq $t) { 'none' } else { [int]$t.State }");
    ProcessResult? ps;
    try {
      ps = await _runner('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        script.toString(),
      ]);
    } on ProcessException {
      ps = null;
    }
    switch ('${ps?.stdout}'.trim()) {
      case 'none':
        return ServiceState.notInstalled;
      // Disabled (1), Ready (3) — задание есть, процесс не работает.
      case '1' || '3':
        return ServiceState.stopped;
      // Queued (2) — запускается, Running (4) — работает.
      case '2' || '4':
        return ServiceState.running;
    }
    final result = await _schtasks([
      '/Query',
      '/TN',
      task,
      '/FO',
      'CSV',
      '/NH',
    ]);
    if (result.exitCode != 0) return ServiceState.notInstalled;
    return '${result.stdout}'.contains('"Running"')
        ? ServiceState.running
        : ServiceState.stopped;
  }

  /// Строка PowerShell в одинарных кавычках: кавычка удваивается.
  static String _psString(String s) => s.replaceAll("'", "''");

  @override
  Future<void> install(ServiceSpec spec, {bool start = true}) async {
    final xml = File('$tempDir\\$prefix-${spec.name}-$pid.xml');
    // Запускатель рядом с программой — без окна консоли (Б-2). Нет его
    // (запуск из исходников) — задание запускает программу напрямую.
    final launcher = QuietLauncher.find(spec.executable, environment: _env);
    // schtasks читает XML в UTF-16 LE с BOM.
    final units = '﻿${taskXml(user, spec, launcher: launcher)}'.codeUnits;
    final bytes = <int>[
      for (final u in units) ...[u & 0xFF, u >> 8],
    ];
    xml.writeAsBytesSync(bytes, flush: true);
    try {
      await _schtasks(['/End', '/TN', serviceName(spec.name)]);
      final result = await _schtasks([
        '/Create',
        '/TN',
        serviceName(spec.name),
        '/XML',
        xml.path,
        '/F',
      ]);
      if (result.exitCode != 0) {
        throw ServiceException(
          'schtasks /Create: ${'${result.stderr}'.trim()}',
        );
      }
    } finally {
      if (xml.existsSync()) xml.deleteSync();
    }
    if (start) await this.start(spec.name);
  }

  @override
  Future<void> uninstall(String name) async {
    if (await state(name) == ServiceState.notInstalled) return;
    await _schtasks(['/End', '/TN', serviceName(name)]);
    await _schtasks(['/Delete', '/TN', serviceName(name), '/F']);
  }

  @override
  Future<void> start(String name) async {
    final result = await _schtasks(['/Run', '/TN', serviceName(name)]);
    if (result.exitCode != 0) {
      throw ServiceException('schtasks /Run: ${'${result.stderr}'.trim()}');
    }
  }

  @override
  Future<void> stop(String name) async {
    await _schtasks(['/End', '/TN', serviceName(name)]);
  }

  @override
  Future<void> restart(String name) async {
    await stop(name);
    // `/End` завершает задание, но не обязательно дожидается выхода
    // процессов: `/Run` сразу после него иногда получает «уже
    // выполняется». Небольшая пауза — и запуск заново.
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await start(name);
  }
}

/// Linux: работа пользовательских служб без входа в систему (задача
/// 5.6.4) — `loginctl enable-linger`. Без него пользовательский менеджер
/// systemd стартует при входе и останавливается при выходе.
final class Linger {
  new({
    required this.user,
    CommandRunner? runner,
    this.lingerDir = '/var/lib/systemd/linger',
  }) : _runner = runner ?? _run;

  factory forCurrentUser({
    Map<String, String>? environment,
    CommandRunner? runner,
  }) {
    final env = environment ?? Platform.environment;
    return Linger(user: env['USER'] ?? env['LOGNAME'] ?? '', runner: runner);
  }

  final String user;
  final String lingerDir;
  final CommandRunner _runner;

  /// Как включить вручную, если политика polkit не даёт сделать это без
  /// администратора.
  String get manualCommand => 'sudo loginctl enable-linger $user';

  /// Включён ли: файл `/var/lib/systemd/linger/<user>` (так его хранит
  /// systemd-logind).
  bool get enabled => File('$lingerDir/$user').existsSync();

  /// Включает; `null` — включён, иначе причина отказа (polkit, нет
  /// `loginctl`).
  Future<String?> enable() => _set(true);

  Future<String?> disable() => _set(false);

  Future<String?> _set(bool on) async {
    if (user.isEmpty) return 'неизвестен пользователь';
    try {
      final result = await _runner('loginctl', [
        if (on) 'enable-linger' else 'disable-linger',
        user,
      ]);
      if (result.exitCode == 0) return null;
      final reason = '${result.stderr}'.trim();
      return reason.isEmpty ? 'loginctl: код ${result.exitCode}' : reason;
    } on ProcessException catch (e) {
      return 'loginctl не запускается: ${e.message}';
    }
  }
}
