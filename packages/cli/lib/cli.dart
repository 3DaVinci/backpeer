/// Консольный клиент. Без Flutter.
library;

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:cli/src/app_config.dart';
import 'package:cli/src/commands/account.dart';
import 'package:cli/src/commands/data.dart';
import 'package:cli/src/console.dart';
import 'package:cli/src/context.dart';
import 'package:core/core.dart';

export 'src/console.dart' show Console, StdConsole;
export 'src/context.dart' show ExitCode;

/// Запуск CLI; возвращает код возврата ([ExitCode]).
Future<int> runCli(
  List<String> arguments, {
  Console console = const StdConsole(),
  Map<String, String>? environment,
}) async {
  final env = environment ?? Platform.environment;
  final global = ArgParserForHome.parseHome(arguments);
  final ctx = CliContext(
    console: console,
    env: env,
    home: AppHome.resolve(env: env, override: global),
  );
  final runner =
      _Runner(
          console,
          'cli',
          'Зашифрованный бэкап с резервированием (этап 1: хранители — '
              'локальные папки).',
        )
        ..argParser.addOption(
          'home',
          help:
              'Каталог программы (по умолчанию FS_HOME или стандартный для ОС)',
        )
        ..argParser.addFlag(
          'version',
          negatable: false,
          help: 'Версия программы',
        )
        ..addCommand(InitCommand(ctx))
        ..addCommand(RecoverCommand(ctx))
        ..addCommand(BackupCommand(ctx))
        ..addCommand(SnapshotsCommand(ctx))
        ..addCommand(RestoreCommand(ctx))
        ..addCommand(VerifyCommand(ctx))
        ..addCommand(ForgetCommand(ctx))
        ..addCommand(ShowPhraseCommand(ctx))
        ..addCommand(ConfigCommand(ctx));
  try {
    final top = runner.parse(arguments);
    if (top.flag('version')) {
      console.out(versionLine('cli'));
      final crypto = await ctx.crypto();
      if (crypto is SodiumCryptoProvider) {
        console.out('libsodium ${crypto.libraryVersion}');
      }
      return ExitCode.ok;
    }
    return await runner.runCommand(top) ?? ExitCode.ok;
  } on UsageException catch (e) {
    console
      ..err(e.message)
      ..err('')
      ..err(e.usage);
    return ExitCode.usage;
  } on CliException catch (e) {
    console.err('Ошибка: ${e.message}');
    return e.exitCode;
  } on CoreException catch (e) {
    console.err('Ошибка: ${e.message}');
    return ExitCode.error;
  }
}

/// Значение `--home` до разбора команд: каталог нужен командам при создании.
abstract final class ArgParserForHome {
  static String? parseHome(List<String> arguments) {
    for (var i = 0; i < arguments.length; i++) {
      final a = arguments[i];
      if (a == '--home' && i + 1 < arguments.length) return arguments[i + 1];
      if (a.startsWith('--home=')) return a.substring('--home='.length);
    }
    return null;
  }
}

final class _Runner extends CommandRunner<int> {
  new(this.console, super.executableName, super.description);

  final Console console;

  @override
  void printUsage() => console.out(usage);
}
