import 'dart:io';

import 'package:args/args.dart';
import 'package:core/core.dart';
import 'package:node/node.dart';

/// Этап 2: узлы-заглушки для локального стенда (`docs/ops/coordinator.md`,
/// раздел «Docker»). Демон хранителя — этап 3.
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addFlag('version', negatable: false, help: 'Версия программы')
    ..addFlag('help', abbr: 'h', negatable: false);
  final stub = ArgParser()
    ..addOption('dir', help: 'Папка папок-«узлов»', mandatory: true)
    ..addOption(
      'coordinator',
      help: 'Адрес координатора (https://…, http — только localhost)',
      mandatory: true,
    )
    ..addOption('ca', help: 'Сертификат УЦ координатора в PEM (тестовый стенд)')
    ..addOption(
      'count',
      help: 'Сколько узлов создать (create)',
      defaultsTo: '20',
    )
    ..addFlag('once', negatable: false, help: 'run: один heartbeat и выход');
  parser.addCommand('stub', stub);
  final ArgResults args;
  try {
    args = parser.parse(arguments);
  } on FormatException catch (e) {
    stderr.writeln(e.message);
    exitCode = 2;
    return;
  }
  if (args.flag('version')) {
    stdout.writeln(versionLine('node'));
    return;
  }
  final command = args.command;
  if (args.flag('help') || command == null || command.rest.length != 1) {
    stdout
      ..writeln('node stub create|run --dir DIR --coordinator URL')
      ..writeln('  create — зарегистрировать --count узлов-заглушек')
      ..writeln('  run    — heartbeat узлов из DIR по расписанию координатора')
      ..writeln(stub.usage);
    return;
  }
  final crypto = await SodiumCryptoProvider.load();
  final SecurityContext? trusted;
  if (command.option('ca') case final String ca) {
    trusted = SecurityContext()..setTrustedCertificates(ca);
  } else {
    trusted = null;
  }
  final client = CoordinatorClient(
    baseUri: Uri.parse(command.option('coordinator')!),
    crypto: crypto,
    trustedCertificates: trusted,
    userAgent: 'node-stub/$appVersion',
  );
  final nodes = StubNodes(
    root: Directory(command.option('dir')!),
    client: client,
    crypto: crypto,
  );
  try {
    switch (command.rest.single) {
      case 'create':
        final count = int.tryParse(command.option('count')!) ?? 0;
        final ids = await nodes.create(count);
        stdout.writeln('Зарегистрировано узлов: ${ids.length}');
      case 'run':
        for (;;) {
          final next = await nodes.heartbeat();
          if (command.flag('once')) break;
          await Future<void>.delayed(next);
        }
      default:
        stderr.writeln('неизвестное действие: ${command.rest.single}');
        exitCode = 2;
    }
  } on CoreException catch (e) {
    stderr.writeln('Ошибка: ${e.message}');
    exitCode = 1;
  } finally {
    client.close();
  }
}
