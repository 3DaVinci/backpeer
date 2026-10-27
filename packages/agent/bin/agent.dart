import 'dart:convert';
import 'dart:io';

import 'package:agent/agent.dart';
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

/// Агент бэкапа (`docs/ops/agent.md`).
Future<void> main(List<String> arguments) async {
  exitCode = await _main(arguments);
  // Isolate libsodium и таймеры не должны держать процесс.
  await stdout.flush();
  await stderr.flush();
  exit(exitCode);
}

Future<int> _main(List<String> arguments) async {
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
  final parser = ArgParser()
    ..addFlag('version', negatable: false, help: 'Версия программы')
    ..addFlag('help', abbr: 'h', negatable: false)
    ..addCommand('run', run)
    ..addCommand('status', withHome())
    ..addCommand('unlock', unlock)
    ..addCommand('backup', withHome())
    ..addCommand('stop', withHome());
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
      ..writeln()
      ..writeln('Подробно — docs/ops/agent.md.');
    return command == null && !args.flag('help') ? _Exit.usage : _Exit.ok;
  }
  final env = Platform.environment;
  final home = AppHome.resolve(env: env, override: command.option('home'));
  if (command.name == 'run') return await _run(home, command, env);
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
