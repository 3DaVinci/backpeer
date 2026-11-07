/// Команды агента (`agent run`, `status`, `unlock`, `backup`, `stop`,
/// `service …`, `uninstall`): разбор аргументов и выполнение.
///
/// Вынесено из `bin/agent.dart` (задачи 5.1.3, 5.7.3), чтобы можно было
/// проверить тестами: точка входа вызывает `exit()`, а тест — нет
/// (регрессия `agent service …`: `--home` объявлена у подкоманд).
library;

import 'dart:convert';
import 'dart:io';

import 'package:agent/src/backup_agent.dart';
import 'package:agent/src/desktop/notifier.dart';
import 'package:agent/src/desktop/power.dart';
import 'package:agent/src/desktop/system_events.dart';
import 'package:agent/src/keeper.dart';
import 'package:agent/src/paths.dart';
import 'package:agent/src/secrets/secret_store.dart';
import 'package:agent/src/services.dart';
import 'package:args/args.dart';
import 'package:cli/cli.dart';
import 'package:core/core.dart';
import 'package:daemon_kit/daemon_kit.dart';
import 'package:logging/logging.dart';

/// Коды выхода, как у node (sysexits).
abstract final class _Exit {
  static const ok = 0;
  static const error = 1;
  static const usage = 64;
  static const unavailable = 69;
}

/// Разбор команд агента и их выполнение (вынесено из `bin/agent.dart`,
/// чтобы проверять тестами без `exit`). Возвращает код выхода.
Future<int> runAgent(
  List<String> arguments, {
  Map<String, String>? environment,
}) async {
  final env = environment ?? Platform.environment;
  ArgParser withHome() => ArgParser()
    ..addOption(
      'home',
      help: 'Каталог программы (по умолчанию FS_HOME или стандартный для ОС)',
    );
  final run = withHome()
    ..addOption(
      'log',
      help: 'Файл журнала; - — stderr (по умолчанию <home>/agent/logs)',
    )
    ..addOption(
      'log-level',
      allowed: ['fine', 'info', 'warning', 'severe'],
      defaultsTo: 'info',
    );
  final unlock = withHome()
    ..addFlag(
      'remember',
      defaultsTo: true,
      help: 'Сохранить ключ в хранилище ОС для работы без пароля',
    );
  final service = ArgParser()
    ..addCommand('install', withHome())
    ..addCommand('uninstall', withHome())
    ..addCommand('status', withHome());
  final uninstall = withHome()
    ..addFlag(
      'purge',
      negatable: false,
      help: 'Удалить и данные: каталог программы, папку узла, ключ агента',
    )
    ..addFlag('yes', abbr: 'y', negatable: false, help: 'Не спрашивать');
  final parser = ArgParser()
    ..addFlag('version', negatable: false, help: 'Версия программы')
    ..addFlag('help', abbr: 'h', negatable: false)
    ..addCommand('run', run)
    ..addCommand('status', withHome())
    ..addCommand('unlock', unlock)
    ..addCommand('backup', withHome())
    ..addCommand('stop', withHome())
    ..addCommand('service', service)
    ..addCommand('uninstall', uninstall);
  final ArgResults args;
  try {
    args = parser.parse(arguments);
  } on FormatException catch (e) {
    stderr.writeln(e.message);
    return _Exit.usage;
  }
  if (args.flag('version')) {
    stdout.writeln(versionLine('agent'));
    return _Exit.ok;
  }
  final command = args.command;
  if (args.flag('help') || command == null) {
    stdout
      ..writeln('agent run [--home DIR] [--log FILE|-]   запустить агента')
      ..writeln('agent status                            состояние (JSON)')
      ..writeln(
        'agent unlock [--no-remember]            открыть ключи паролем '
        '(FS_PASSWORD или ввод)',
      )
      ..writeln('agent backup                            бэкап сейчас')
      ..writeln('agent stop                              остановить агента')
      ..writeln('agent service install|uninstall|status  служба ОС для агента')
      ..writeln(
        'agent uninstall [--purge] [--yes]       удалить службы '
        '(--purge — и данные)',
      )
      ..writeln()
      ..writeln('Подробно — docs/ops/agent.md.');
    return command == null && !args.flag('help') ? _Exit.usage : _Exit.ok;
  }
  // У `service` опция `--home` объявлена у подкоманд, поэтому для самой
  // команды `service` `command.option('home')` вызывать нельзя.
  if (command.name == 'run') {
    return await _run(
      AppHome.resolve(env: env, override: command.option('home')),
      command,
      env,
    );
  }
  if (command.name == 'service') {
    final sub = command.command;
    if (sub == null) {
      stderr.writeln('agent service install|uninstall|status');
      return _Exit.usage;
    }
    return await _service(
      AppHome.resolve(env: env, override: sub.option('home')),
      sub,
      env,
    );
  }
  final home = AppHome.resolve(env: env, override: command.option('home'));
  if (command.name == 'uninstall') return await _uninstall(home, command, env);
  return await _call(home, command, env);
}

Future<int> _run(AppHome home, ArgResults args, Map<String, String> env) async {
  final CryptoProvider crypto;
  try {
    crypto = await SodiumCryptoProvider.load();
  } on Object catch (e) {
    stderr.writeln('libsodium не загружается: $e');
    return _Exit.error;
  }
  final services = UserServices.forPlatform(environment: env);
  final BackupAgent agent;
  try {
    agent = await BackupAgent.start(
      home: home,
      crypto: crypto,
      // `none` — без хранилища ОС: тесты и машины без Secret Service.
      secrets: env['FS_AGENT_SECRETS'] == 'none'
          ? const UnavailableSecretStore('отключено FS_AGENT_SECRETS=none')
          : null,
      argon2: env['FS_ARGON2_FAST'] == '1'
          ? const Argon2Params(memoryKiB: 1024, iterations: 1)
          : const Argon2Params(),
      power: PowerSource.forPlatform(env),
      notifier: Notifier.forPlatform(env),
      systemEvents: SystemEvents.forPlatform(env),
      // Хранитель — службой ОС, если она есть (5.6.1): так он не зависит
      // от агента и с linger работает без входа пользователя (5.6.4).
      nodeLauncher: services.available
          ? ServiceNodeLauncher(
              services: services,
              executable: ProcessNodeLauncher.find(env),
            )
          : ProcessNodeLauncher(environment: env),
      linger: services.kind == 'systemd'
          ? Linger.forCurrentUser(environment: env)
          : null,
      logFile: args.option('log'),
      logLevel: Level.LEVELS.firstWhere(
        (l) => l.name.toLowerCase() == args.option('log-level'),
      ),
    );
  } on FileSystemException catch (e) {
    stderr.writeln('${e.message}: ${e.path}');
    return _Exit.unavailable;
  }
  await agent.done;
  return _Exit.ok;
}

Future<int> _call(
  AppHome home,
  ArgResults args,
  Map<String, String> env,
) async {
  final ControlClient client;
  try {
    client = await ControlClient.connect(AgentPaths(home).endpoint());
  } on ControlException catch (e) {
    stderr.writeln(e.message);
    return _Exit.unavailable;
  }
  try {
    final result = switch (args.name) {
      'status' => await client.call('status'),
      'backup' => await client.call('backup'),
      'stop' => await client.call('stop'),
      'unlock' => await client.call(
        'unlock',
        {'password': _password(env), 'remember': args.flag('remember')},
        // Argon2id и запрос к хранилищу ОС.
        const Duration(minutes: 2),
      ),
      _ => throw StateError(args.name!),
    };
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(result));
    return _Exit.ok;
  } on ControlException catch (e) {
    stderr.writeln('Ошибка: ${e.message}');
    return _Exit.error;
  } finally {
    await client.close();
  }
}

/// Каталог программы не по умолчанию — передать службе аргументом.
String? _homeOverride(ArgResults args, Map<String, String> env) =>
    args.option('home') ?? env['FS_HOME'];

/// `agent service install|uninstall|status` (задача 5.6.1): служба ОС
/// для этого исполняемого файла агента. Хранителя ставит сам агент при
/// включённой роли.
Future<int> _service(
  AppHome home,
  ArgResults args,
  Map<String, String> env,
) async {
  final services = UserServices.forPlatform(environment: env);
  final client = ClientServices(
    services: services,
    home: _homeOverride(args, env),
  );
  try {
    switch (args.name) {
      case 'install':
        if (!services.available) {
          stderr.writeln('Службы ОС недоступны на этом компьютере');
          return _Exit.unavailable;
        }
        // Агент запущен вручную — остановить: служба займёт его место.
        if (await client.agentState() != ServiceState.running) {
          final paths = AgentPaths(home);
          await stopViaControl(paths.endpoint(), paths.lock);
        }
        await client.installAgent(Platform.resolvedExecutable);
      case 'uninstall':
        await services.uninstall(ClientServices.agentName);
      case 'status':
        break;
    }
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert({
        'kind': services.kind,
        'agent': {
          'service': services.serviceName(ClientServices.agentName),
          'state': (await client.agentState()).name,
        },
        'node': {
          'service': services.serviceName(ClientServices.nodeName),
          'state': (await client.nodeState()).name,
        },
      }),
    );
    return _Exit.ok;
  } on ServiceException catch (e) {
    stderr.writeln('Ошибка: ${e.message}');
    return _Exit.error;
  }
}

/// `agent uninstall [--purge]` (задача 5.7.3): то, что пакет удалить не
/// может, — службы и файлы пользователя.
Future<int> _uninstall(
  AppHome home,
  ArgResults args,
  Map<String, String> env,
) async {
  final purge = args.flag('purge');
  final nodeDir = KeeperApi.defaultDataDir(env);
  if (purge && !args.flag('yes')) {
    stderr
      ..writeln('Будут удалены без возможности восстановления:')
      ..writeln('  ${home.dir.path} — настройки, ключи этого устройства')
      ..writeln('  $nodeDir — хранитель и фрагменты других людей')
      ..writeln(
        'Бэкапы в сети останутся, войти к ним можно по паролю или фразе '
        'восстановления.',
      )
      ..write('Удалить? Введите «да»: ');
    final answer = stdin.readLineSync()?.trim().toLowerCase();
    if (answer != 'да' && answer != 'yes') {
      stderr.writeln('Отменено');
      return _Exit.error;
    }
  }
  try {
    final done = await uninstallClient(
      home: home,
      nodeDataDir: nodeDir,
      services: UserServices.forPlatform(environment: env),
      loginItem: LoginItem.forPlatform(environment: env),
      linger: Platform.isLinux ? Linger.forCurrentUser(environment: env) : null,
      persistent: Platform.isLinux ? PersistentDaemons.forUser(env) : null,
      purge: purge,
    );
    done.isEmpty
        ? stdout.writeln('Нечего удалять')
        : done.forEach(stdout.writeln);
    return _Exit.ok;
  } on ServiceException catch (e) {
    stderr.writeln('Ошибка: ${e.message}');
    return _Exit.error;
  } on FileSystemException catch (e) {
    stderr.writeln('Ошибка: ${e.message}: ${e.path}');
    return _Exit.error;
  }
}

String _password(Map<String, String> env) {
  if (env['FS_PASSWORD'] case final String p) return p;
  stderr.write('Пароль: ');
  final echo = stdin.hasTerminal && stdin.echoMode;
  if (stdin.hasTerminal) stdin.echoMode = false;
  try {
    return stdin.readLineSync() ?? '';
  } finally {
    if (stdin.hasTerminal) stdin.echoMode = echo;
    stderr.writeln();
  }
}
