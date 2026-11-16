import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:admin/admin.dart';
import 'package:args/args.dart';
import 'package:coordinator/coordinator.dart'
    show AdminAccessException, AdminReadAccess, Database;
import 'package:core/core.dart' show appVersion;

const _usage = '''
Панель оператора Backpeer (docs/ops/admin.md). Только просмотр:
пользователи, балансы, узлы, сеть, отчёты о сбоях и журнал.

  admin serve [--config <файл>]      запустить панель
  admin check [--config <файл>]      проверить настройки, базу и права
  admin hash-password                вывести хэш пароля оператора
  admin version                      версия продукта

Настройки — YAML-файл и переменные FS_ADMIN_* (docs/ops/admin.md).
Коды выхода: 0 — успех, 1 — ошибка, 64 — неверный вызов, 78 — настройки.
''';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('config', abbr: 'c', help: 'YAML-файл настроек')
    ..addFlag('help', abbr: 'h', negatable: false)
    ..addCommand('serve')
    ..addCommand('check')
    ..addCommand('hash-password')
    ..addCommand('version');
  final ArgResults args;
  try {
    args = parser.parse(arguments);
  } on FormatException catch (e) {
    stderr.writeln('${e.message}\n\n$_usage');
    exit(64);
  }
  if (args.flag('help') || args.command == null) {
    stdout.write(_usage);
    exit(args.command == null && !args.flag('help') ? 64 : 0);
  }
  final command = args.command!.name;
  if (command == 'version') {
    stdout.writeln('admin $appVersion');
    return;
  }
  if (command == 'hash-password') {
    exitCode = await _hashPassword();
    return;
  }
  final AdminConfig config;
  try {
    config = AdminConfig.load(args.option('config'));
  } on Object catch (e) {
    stderr.writeln('Настройки: $e');
    exit(78);
  }
  if (command == 'check') {
    exitCode = await _check(config);
    return;
  }
  try {
    final server = await AdminServer.start(config);
    stdout.writeln(
      jsonEncode({
        'event': 'listening',
        'url': 'http://${config.host}:${config.port}',
        'version': appVersion,
      }),
    );
    await _untilSignal();
    await server.close();
  } on AdminConfigException catch (e) {
    stderr.writeln('Настройки: ${e.message}');
    exitCode = 78;
  } on Object catch (e) {
    stderr.writeln('Ошибка: $e');
    exitCode = 1;
  }
}

Future<int> _hashPassword() async {
  final first = await _readPassword('Пароль оператора: ');
  if (first == null || first.isEmpty) {
    stderr.writeln('Пароль не прочитан');
    return 1;
  }
  if (stdin.hasTerminal) {
    final second = await _readPassword('Ещё раз: ');
    if (second != first) {
      stderr.writeln('Пароли не совпали');
      return 1;
    }
  }
  try {
    final hasher = await PasswordHasher.load();
    final hash = await hasher.hashPassword(first);
    stdout.writeln(hash);
    stderr.writeln(
      'Вставьте строку в auth.users файла настроек (docs/ops/admin.md).',
    );
    return 0;
  } on PasswordPolicyException catch (e) {
    stderr.writeln(e.message);
    return 1;
  }
}

Future<String?> _readPassword(String prompt) async {
  var hidden = false;
  if (stdin.hasTerminal && !Platform.isWindows) {
    try {
      final result = await Process.run('stty', ['-echo']);
      hidden = result.exitCode == 0;
    } on ProcessException {
      hidden = false;
    }
  }
  try {
    stderr.write(prompt);
    final line = stdin.readLineSync();
    if (hidden) stderr.writeln();
    return line;
  } finally {
    if (hidden) {
      try {
        await Process.run('stty', ['echo']);
      } on ProcessException {
        // Терминал вернёт эхо сам.
      }
    }
  }
}

Future<int> _check(AdminConfig config) async {
  final db = Database.open(config.database);
  try {
    if (config.readOnlyRole.isNotEmpty) {
      await AdminReadAccess.check(db, config.readOnlyRole);
    }
    final read = PostgresReadModel(
      db,
      onlineWindow: config.onlineWindow,
      probation: config.probation,
      economyPolicy: config.economy,
      readOnlyRole: config.readOnlyRole,
    );
    final info = await read.system();
    final latency = Stopwatch()..start();
    await read.ping();
    latency.stop();
    final database = info['database']! as Map;
    final counts = info['counts']! as Map;
    final staticDir = Directory(config.staticDir);
    final reports = Directory(config.reportsDir);
    stdout
      ..writeln('Панель: admin $appVersion')
      ..writeln(
        'База: ${config.database.user}@${config.database.host}:'
        '${config.database.port}/${config.database.name}',
      )
      ..writeln('Схема: ${database['schema']}')
      ..writeln(
        'Роль только для чтения: ${database['readOnlyRole']} '
        '(членство: ${database['readOnly']})',
      )
      ..writeln('Пинг базы: ${latency.elapsedMilliseconds} мс')
      ..writeln(
        'Учётных записей: ${counts['accounts']}, узлов: '
        '${counts['nodesActive']}, сегментов: ${counts['segments']}',
      )
      ..writeln(
        'Статика: ${config.staticDir} '
        '(${staticDir.existsSync() ? 'есть' : 'НЕТ — соберите apps/admin'})',
      )
      ..writeln(
        'Отчёты: ${config.reportsDir} '
        '(${reports.existsSync() ? 'есть' : 'будет создана'})',
      )
      ..writeln('Операторов: ${config.users.length}');
    return 0;
  } on AdminAccessException catch (e) {
    stderr.writeln('Нет прав: ${e.message}');
    return 77;
  } on Object catch (e) {
    stderr.writeln('Проверка не прошла: $e');
    return 1;
  } finally {
    await db.close();
  }
}

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
