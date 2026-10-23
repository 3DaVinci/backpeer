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
  coordinator admin [--config <файл>] … (coordinator admin --help)

Настройки — YAML-файл и переменные FS_COORDINATOR_* (docs/ops/coordinator.md).
''';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('config', abbr: 'c', help: 'YAML-файл настроек')
    ..addFlag('help', abbr: 'h', negatable: false)
    ..addCommand('serve', ArgParser()..addFlag('migrate', negatable: false))
    ..addCommand('migrate')
    ..addCommand('admin', ArgParser.allowAnything());

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
  if (command.name == 'admin') {
    exit(await _admin(config, command.rest));
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
          final granted = await AdminAccess.grant(db, config.adminRole);
          log.info(
            LogEvent('admin_grants', {
              'role': config.adminRole,
              'granted': granted,
            }),
          );
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

/// `coordinator admin …`: настройки администратора (роль базы
/// [CoordinatorConfig.adminRole]), журнал — в базе и в журнале ОС.
Future<int> _admin(CoordinatorConfig config, List<String> arguments) async {
  if (arguments.isEmpty || arguments.contains('--help')) {
    stdout.write(adminUsage);
    return arguments.isEmpty ? AdminExit.usage : AdminExit.ok;
  }
  final db = Database.open(config.database);
  try {
    await AdminAccess.check(db, config.adminRole);
    return await runAdmin(
      arguments,
      service: AdminService(
        db,
        onlineWindow: config.nodes.onlineWindow,
        probation: config.placement.probation,
        journal: systemJournal,
      ),
      osUser: osUserName(Platform.environment),
    );
  } on AdminAccessException catch (e) {
    stderr.writeln('Нет прав: ${e.message}');
    return AdminExit.noPermission;
  } on Object catch (e) {
    stderr.writeln('Ошибка: $e');
    return AdminExit.error;
  } finally {
    await db.close();
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
