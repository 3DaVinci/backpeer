import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:core/core.dart';
import 'package:relay/relay.dart';

const _usage = '''
Relay: ретранслятор соединений к узлам без входящих соединений
(docs/ops/relay.md).

  relay keygen     --key <файл>
  relay public-key --key <файл>
  relay serve      [--config <файл>]

Настройки serve — YAML-файл и переменные окружения FS_RELAY_*.
''';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false)
    ..addCommand('keygen', ArgParser()..addOption('key'))
    ..addCommand('public-key', ArgParser()..addOption('key'))
    ..addCommand('serve', ArgParser()..addOption('config'));
  final ArgResults command;
  try {
    final args = parser.parse(arguments);
    if (args.flag('help') || args.command == null) {
      stdout.write(_usage);
      exit(args.flag('help') ? 0 : 64);
    }
    command = args.command!;
    if (command.name != 'serve' && command.option('key') == null) {
      throw const FormatException('Нужен --key');
    }
  } on FormatException catch (e) {
    stderr.writeln('${e.message}\n\n$_usage');
    exit(64);
  }

  final crypto = await SodiumCryptoProvider.load();
  try {
    switch (command.name) {
      case 'keygen':
        final key = await Ed25519KeyFile.generate(
          command.option('key')!,
          crypto,
        );
        stdout.writeln(bytesToHex(key.publicKey));
      case 'public-key':
        final key = await Ed25519KeyFile.load(command.option('key')!, crypto);
        stdout.writeln(bytesToHex(key.publicKey));
      case 'serve':
        await _serve(crypto, RelayConfig.load(command.option('config')));
    }
  } on RelayConfigException catch (e) {
    stderr.writeln('Настройки: ${e.message}');
    exitCode = 78;
  } on KeyFileException catch (e) {
    stderr.writeln(e.message);
    exitCode = 78;
  } on FileSystemException catch (e) {
    stderr.writeln('${e.message}: ${e.path}');
    exitCode = 1;
  } on SocketException catch (e) {
    stderr.writeln('Порт не открыт: ${e.message}');
    exitCode = 1;
  }
}

Future<void> _serve(CryptoProvider crypto, RelayConfig config) async {
  final writer = JsonLogWriter(stdout)..attach(config.logLevel);
  final key = switch (config.keyFile) {
    final path? => await Ed25519KeyFile.load(path, crypto),
    null => null,
  };
  final server = await RelayServer.bind(
    crypto: crypto,
    name: config.name,
    passKeys: config.passKeys,
    host: config.host,
    port: config.port,
    limits: config.limits,
  );
  CoordinatorClient? client;
  RelayReporter? reporter;
  if (config.coordinatorUrl case final url? when key != null) {
    client = CoordinatorClient(
      baseUri: Uri.parse(url),
      crypto: crypto,
      trustedCertificates: switch (config.coordinatorCa) {
        final ca? => SecurityContext()..setTrustedCertificates(ca),
        null => null,
      },
      userAgent: 'relay/$appVersion',
    );
    reporter = RelayReporter(
      client: client,
      key: key,
      server: server,
      interval: config.reportInterval,
    )..start();
  }
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
  await server.close();
  await reporter?.stop().timeout(const Duration(seconds: 5), onTimeout: () {});
  client?.close(force: true);
  key?.seed.dispose();
  await writer.detach();
}
