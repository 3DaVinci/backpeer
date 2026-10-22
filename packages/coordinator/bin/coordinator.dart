import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:coordinator/coordinator.dart';
import 'package:core/core.dart';
import 'package:logging/logging.dart';

const _usage = '''
Координатор распределённого хранилища.

  coordinator serve [--config <файл>] [--migrate]
  coordinator migrate [--config <файл>]

Настройки — YAML-файл и переменные FS_COORDINATOR_* (docs/ops/coordinator.md).
''';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('config', abbr: 'c', help: 'YAML-файл настроек')
    ..addFlag('help', abbr: 'h', negatable: false)
    ..addCommand('serve', ArgParser()..addFlag('migrate', negatable: false))
    ..addCommand('migrate');

  final ArgResults args;
  try {
    args = parser.parse(arguments);
  } on FormatException catch (e) {
    stderr.writeln('${e.message}\n\n$_usage');
    exit(64);
  }
  final command = args.command;
  if (args.flag('help') || command == null) {
    stdout.write(_usage);
    exit(command == null && !args.flag('help') ? 64 : 0);
  }

  final CoordinatorConfig config;
  try {
    config = CoordinatorConfig.load(args.option('config'));
  } on Object catch (e) {
    stderr.writeln('Настройки: $e');
    exit(78);
  }
  JsonLogWriter(stdout).attach(config.logLevel);
  final log = Logger('coordinator');

  try {
    switch (command.name) {
      case 'migrate':
        final db = Database.open(config.database);
        try {
          final version = await Migrator(db).migrate();
          log.info(LogEvent('migrated', {'schema': version}));
        } finally {
          await db.close();
        }
      case 'serve':
        final server = await CoordinatorServer.start(
          config,
          crypto: await SodiumCryptoProvider.load(),
          migrate: command.flag('migrate'),
        );
        await _untilSignal();
        await server.close();
    }
  } on MigrationException catch (e) {
    log.severe(LogEvent('schema', {'message': e.message}));
    exitCode = 1;
  } on Object catch (e, stack) {
    log.severe(const LogEvent('fatal'), e, stack);
    exitCode = 1;
  }
}

/// Ждёт SIGINT или SIGTERM и снимает обе подписки: иначе оставшаяся
/// держала бы процесс.
Future<void> _untilSignal() async {
  final stop = Completer<void>();
  final subscriptions = [
    for (final signal in [ProcessSignal.sigint, ProcessSignal.sigterm])
      signal.watch().listen((_) {
        if (!stop.isCompleted) stop.complete();
      }),
  ];
  await stop.future;
  for (final s in subscriptions) {
    await s.cancel();
  }
}
