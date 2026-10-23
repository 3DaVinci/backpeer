import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:core/core.dart';
import 'package:node/node.dart';

/// Коды выхода, как у подписанта координатора (sysexits).
abstract final class _Exit {
  static const ok = 0;
  static const error = 1;
  static const usage = 64;
  static const config = 78;
}

/// Демон хранителя (`docs/ops/node.md`) и узлы-заглушки этапа 2
/// (`docs/ops/coordinator.md`, раздел «Docker»).
Future<void> main(List<String> arguments) async {
  exitCode = await _main(arguments);
  // Isolate libsodium и таймеры не должны держать процесс.
  await stdout.flush();
  await stderr.flush();
  exit(exitCode);
}

Future<int> _main(List<String> arguments) async {
  ArgParser daemonOptions() => ArgParser()
    ..addOption(
      'config',
      help:
          'Файл настроек YAML (по умолчанию FS_NODE_CONFIG или '
          '<data>/node.yaml, если есть)',
    )
    ..addOption(
      'data',
      help: 'Папка данных (data.dir; по умолчанию стандартная для ОС)',
    );
  final parser = ArgParser()
    ..addFlag('version', negatable: false, help: 'Версия программы')
    ..addFlag('help', abbr: 'h', negatable: false);
  final init = daemonOptions()
    ..addFlag('json', negatable: false, help: 'Вывод одним объектом JSON');
  final importCert = daemonOptions();
  final run = daemonOptions();
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
  parser
    ..addCommand('init', init)
    ..addCommand('import-cert', importCert)
    ..addCommand('run', run)
    ..addCommand('stub', stub);
  final ArgResults args;
  try {
    args = parser.parse(arguments);
  } on FormatException catch (e) {
    stderr.writeln(e.message);
    return _Exit.usage;
  }
  if (args.flag('version')) {
    stdout.writeln(versionLine('node'));
    return _Exit.ok;
  }
  final command = args.command;
  if (args.flag('help') || command == null) {
    stdout
      ..writeln('node init [--data DIR] [--json]   создать ключи узла')
      ..writeln(
        'node import-cert FILE [--data DIR] сертификат от cli node-cert',
      )
      ..writeln('node run [--config FILE] [--data DIR]  запустить демон')
      ..writeln('node stub create|run --dir DIR --coordinator URL')
      ..writeln('Подробности — docs/ops/node.md.');
    return _Exit.ok;
  }
  try {
    switch (command.name) {
      case 'init':
        return await _init(command);
      case 'import-cert':
        return await _importCert(command);
      case 'run':
        return await _run(command);
      default:
        return await _stub(command, stub);
    }
  } on NodeConfigException catch (e) {
    stderr.writeln('Ошибка в настройках: ${e.message}');
    return _Exit.config;
  } on NodeIdentityException catch (e) {
    stderr.writeln('Ошибка: ${e.message}');
    return _Exit.config;
  } on FileSystemException catch (e) {
    stderr.writeln(
      'Ошибка: ${e.message}${e.path == null ? '' : ' (${e.path})'}',
    );
    return _Exit.error;
  } on CoreException catch (e) {
    stderr.writeln('Ошибка: ${e.message}');
    return _Exit.error;
  }
}

/// Настройки: `--config`, `FS_NODE_CONFIG` или `<data>/node.yaml`, поверх
/// — окружение `FS_NODE_*`; `--data` важнее `data.dir` из файла.
NodeConfig _config(ArgResults args) {
  final env = Platform.environment;
  final dataFlag = args.option('data');
  final fallbackData =
      dataFlag ??
      env[NodeConfig.envName('data.dir')] ??
      defaultNodeDataDir(env);
  var path = args.option('config') ?? env['FS_NODE_CONFIG'];
  if (path == null && File('$fallbackData/node.yaml').existsSync()) {
    path = '$fallbackData/node.yaml';
  }
  final String yaml;
  try {
    yaml = path == null ? '' : File(path).readAsStringSync();
  } on FileSystemException {
    throw NodeConfigException('файл настроек $path не читается');
  }
  return NodeConfig.parse(yaml, {
    ...env,
    NodeConfig.envName('data.dir'): ?dataFlag,
  }, dataDir: fallbackData);
}

Future<int> _init(ArgResults args) async {
  if (args.rest.isNotEmpty) return _usage('init без аргументов');
  final config = _config(args);
  final crypto = await SodiumCryptoProvider.load();
  final dir = Directory(config.dataDir);
  final created = await NodeIdentity.ensureKeys(dir, crypto);
  final identity = await NodeIdentity.load(dir, crypto);
  try {
    final nodeId = bytesToHex(identity.nodeId);
    final nodeDh = bytesToHex(identity.nodeDh);
    if (args.flag('json')) {
      stdout.writeln(
        jsonEncode({
          'dataDir': config.dataDir,
          'created': created,
          'nodeId': nodeId,
          'nodeDh': nodeDh,
          'certificate': identity.certificate != null,
        }),
      );
      return _Exit.ok;
    }
    stdout
      ..writeln(
        created
            ? 'Ключи узла созданы в ${config.dataDir}.'
            : 'Ключи узла уже есть в ${config.dataDir}.',
      )
      ..writeln('node_id: $nodeId')
      ..writeln('node_dh: $nodeDh');
    if (identity.certificate == null) {
      stdout
        ..writeln()
        ..writeln('Выпустите сертификат на устройстве владельца:')
        ..writeln(
          '  cli node-cert --node-id $nodeId --node-dh $nodeDh '
          '--out node.cert',
        )
        ..writeln('и импортируйте его здесь: node import-cert node.cert');
    }
    return _Exit.ok;
  } finally {
    identity.dispose();
  }
}

Future<int> _importCert(ArgResults args) async {
  if (args.rest.length != 1) return _usage('import-cert FILE');
  final config = _config(args);
  final crypto = await SodiumCryptoProvider.load();
  final file = File(args.rest.single);
  final owner = await NodeIdentity.importCertificate(
    Directory(config.dataDir),
    crypto,
    file.readAsBytesSync(),
    source: file.path,
  );
  stdout.writeln(
    'Сертификат импортирован, владелец ${bytesToHex(owner).substring(0, 16)}….',
  );
  return _Exit.ok;
}

Future<int> _run(ArgResults args) async {
  if (args.rest.isNotEmpty) return _usage('run без аргументов');
  final config = _config(args);
  final crypto = await SodiumCryptoProvider.load();
  final daemon = await NodeDaemon.start(config, crypto: crypto);
  if (config.log.file != '-') {
    stderr.writeln(
      'Узел ${bytesToHex(daemon.identity.nodeId).substring(0, 16)}… '
      'запущен; журнал — ${config.log.file ?? '${config.dataDir}/logs'}.',
    );
  }
  await daemon.done;
  return _Exit.ok;
}

int _usage(String text) {
  stderr.writeln('Использование: node $text');
  return _Exit.usage;
}

Future<int> _stub(ArgResults command, ArgParser parser) async {
  if (command.rest.length != 1) {
    stdout
      ..writeln('node stub create|run --dir DIR --coordinator URL')
      ..writeln('  create — зарегистрировать --count узлов-заглушек')
      ..writeln('  run    — heartbeat узлов из DIR по расписанию координатора')
      ..writeln(parser.usage);
    return _Exit.ok;
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
        return _Exit.usage;
    }
    return _Exit.ok;
  } finally {
    client.close();
  }
}
