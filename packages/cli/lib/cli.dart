/// Консольный клиент. Без Flutter.
library;

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:cli/src/account_ops.dart';
import 'package:cli/src/app_config.dart';
import 'package:cli/src/commands/account.dart';
import 'package:cli/src/commands/data.dart';
import 'package:cli/src/commands/devices.dart';
import 'package:cli/src/commands/node.dart';
import 'package:cli/src/commands/status.dart';
import 'package:cli/src/console.dart';
import 'package:cli/src/context.dart';
import 'package:cli/src/session.dart';
import 'package:core/core.dart';

export 'src/account_ops.dart'
    show AccountDevice, AccountException, AccountOps, coordinatorFailure;
export 'src/app_config.dart' show AppConfig, AppHome, FragmentsMode;
export 'src/console.dart' show Console, StdConsole;
export 'src/context.dart' show ExitCode;
export 'src/session.dart'
    show Session, SessionException, openCoordinatorClient, openSession;

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
    json: arguments.contains('--json'),
  );
  final report = ctx.report;
  final runner =
      _Runner(
          console,
          'cli',
          'Зашифрованный бэкап с резервированием (хранители пока — '
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
        ..argParser.addFlag(
          'json',
          negatable: false,
          help:
              'Машинный вывод: JSON Lines в stdout, последняя строка — '
              'result или error (docs/cli.md)',
        )
        ..addCommand(InitCommand(ctx))
        ..addCommand(RegisterCommand(ctx))
        ..addCommand(LoginCommand(ctx))
        ..addCommand(RecoverCommand(ctx))
        ..addCommand(DevicesCommand(ctx))
        ..addCommand(RevokeCommand(ctx))
        ..addCommand(PasswdCommand(ctx))
        ..addCommand(KeyCopyCommand(ctx))
        ..addCommand(StatusCommand(ctx))
        ..addCommand(BackupCommand(ctx))
        ..addCommand(SnapshotsCommand(ctx))
        ..addCommand(RestoreCommand(ctx))
        ..addCommand(VerifyCommand(ctx))
        ..addCommand(ForgetCommand(ctx))
        ..addCommand(GcCommand(ctx))
        ..addCommand(ShowPhraseCommand(ctx))
        ..addCommand(NodeCertCommand(ctx))
        ..addCommand(NodeCommand(ctx))
        ..addCommand(ConfigCommand(ctx));
  try {
    final top = runner.parse(arguments);
    if (top.flag('version')) {
      final crypto = await ctx.crypto();
      final sodium = crypto is SodiumCryptoProvider
          ? crypto.libraryVersion
          : null;
      report.info(versionLine('cli'));
      if (sodium != null) report.info('libsodium $sodium');
      report.result({
        'version': appVersion,
        'commit': gitCommit,
        'libsodium': sodium,
      });
      return ExitCode.ok;
    }
    return await runner.runCommand(top) ?? ExitCode.ok;
  } on UsageException catch (e) {
    if (ctx.json) {
      report.error(e.message, ExitCode.usage);
    } else {
      console
        ..err(e.message)
        ..err('')
        ..err(e.usage);
    }
    return ExitCode.usage;
  } on CliException catch (e) {
    report.error(e.message, e.exitCode);
    return e.exitCode;
  } on AccountException catch (e) {
    final code = const {'not_found', 'current_device'}.contains(e.code)
        ? ExitCode.usage
        : ExitCode.error;
    report.error(e.message, code);
    return code;
  } on SessionException catch (e) {
    final code = e.usage ? ExitCode.usage : ExitCode.error;
    report.error(e.message, code);
    return code;
  } on CancelledException {
    report.error('операция прервана', ExitCode.cancelled);
    return ExitCode.cancelled;
  } on CoreException catch (e) {
    report.error(e.message, ExitCode.error);
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
