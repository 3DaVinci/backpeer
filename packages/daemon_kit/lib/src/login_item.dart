import 'dart:io';

import 'package:daemon_kit/src/user_services.dart';

/// Запуск приложения при входе пользователя — для значка в трее (задача
/// 5.6.2). Фоновым процессам он не нужен: они — службы ([UserServices]).
///
/// | ОС | Как |
/// |---|---|
/// | Linux | `~/.config/autostart/<prefix>.desktop` (XDG Autostart: GNOME, KDE, XFCE) |
/// | macOS | LaunchAgent `<id>.app` с `RunAtLoad`, без перезапуска |
/// | Windows | значение `<prefix>` в `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` |
abstract interface class LoginItem {
  factory forPlatform({
    Map<String, String>? environment,
    CommandRunner? runner,
  }) {
    final env = environment ?? Platform.environment;
    if (Platform.isMacOS) {
      return LaunchAgentLoginItem(
        agentsDir: '${env['HOME']}/Library/LaunchAgents',
        runner: runner,
      );
    }
    if (Platform.isWindows) return RegistryLoginItem(runner: runner);
    final config = env['XDG_CONFIG_HOME'] ?? '${env['HOME']}/.config';
    return XdgLoginItem(autostartDir: '$config/autostart');
  }

  bool get enabled;

  /// Запускать [executable] с [arguments] при входе.
  Future<void> enable(String executable, List<String> arguments);

  Future<void> disable();
}

/// Linux: XDG Autostart. `TryExec` — программу удалили с пакетом, а файл
/// остался: сеанс его пропустит.
final class XdgLoginItem implements LoginItem {
  new({
    required this.autostartDir,
    this.name = servicePrefix,
    this.title = 'Backpeer',
  });

  final String autostartDir;
  final String name;
  final String title;

  File get file => File('$autostartDir/$name.desktop');

  @override
  bool get enabled => file.existsSync();

  static String desktopEntry(
    String title,
    String executable,
    List<String> arguments,
  ) {
    String quote(String s) => s.contains(RegExp(r'[\s"\\`$]'))
        ? '"${s.replaceAllMapped(RegExp(r'["\\`$]'), (m) => '\\${m[0]}')}"'
        : s;
    return '[Desktop Entry]\n'
        'Type=Application\n'
        'Name=$title\n'
        'TryExec=$executable\n'
        'Exec=${[executable, ...arguments].map(quote).join(' ')}\n'
        'Icon=$servicePrefix\n'
        'Terminal=false\n'
        'NoDisplay=true\n'
        'X-GNOME-Autostart-enabled=true\n';
  }

  @override
  Future<void> enable(String executable, List<String> arguments) async {
    file.parent.createSync(recursive: true);
    File('${file.path}.tmp-$pid')
      ..writeAsStringSync(desktopEntry(title, executable, arguments))
      ..renameSync(file.path);
  }

  @override
  Future<void> disable() async {
    if (file.existsSync()) file.deleteSync();
  }
}

/// macOS: LaunchAgent, который один раз запускает приложение при входе.
final class LaunchAgentLoginItem implements LoginItem {
  new({required this.agentsDir, CommandRunner? runner})
    : _services = LaunchAgentServices(agentsDir: agentsDir, runner: runner);

  final String agentsDir;
  final LaunchAgentServices _services;

  File get _plist => File('$agentsDir/${_services.serviceName('app')}.plist');

  @override
  bool get enabled => _plist.existsSync();

  @override
  Future<void> enable(String executable, List<String> arguments) async {
    final text = LaunchAgentServices.plistText(
      _services.serviceName('app'),
      ServiceSpec(
        name: 'app',
        description: 'значок в строке меню',
        executable: executable,
        arguments: arguments,
      ),
      // Приложение закрыли — не поднимать снова.
      keepAlive: false,
    );
    _plist.parent.createSync(recursive: true);
    _plist.writeAsStringSync(text);
  }

  @override
  Future<void> disable() async {
    if (_plist.existsSync()) _plist.deleteSync();
  }
}

/// Windows: ключ `Run` текущего пользователя (`reg.exe`).
final class RegistryLoginItem implements LoginItem {
  new({CommandRunner? runner, this.name = servicePrefix})
    : _runner = runner ?? Process.run;

  static const key = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';

  final String name;
  final CommandRunner _runner;
  bool? _enabled;

  @override
  bool get enabled {
    if (_enabled case final e?) return e;
    final result = Process.runSync('reg', ['query', key, '/v', name]);
    return _enabled = result.exitCode == 0;
  }

  @override
  Future<void> enable(String executable, List<String> arguments) async {
    final command = ['"$executable"', ...arguments].join(' ');
    final result = await _runner('reg', [
      'add',
      key,
      '/v',
      name,
      '/t',
      'REG_SZ',
      '/d',
      command,
      '/f',
    ]);
    if (result.exitCode != 0) {
      throw ServiceException('reg add: ${'${result.stderr}'.trim()}');
    }
    _enabled = true;
  }

  @override
  Future<void> disable() async {
    await _runner('reg', ['delete', key, '/v', name, '/f']);
    _enabled = false;
  }
}
