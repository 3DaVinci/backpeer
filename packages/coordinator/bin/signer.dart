import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:coordinator/coordinator.dart';
import 'package:core/core.dart';
import 'package:logging/logging.dart';

const _usage = '''
Подписант талонов координатора: держит ключ подписи отдельно от
веб-сервера (docs/ops/coordinator.md, раздел «Подписант»).

  signer keygen     --key <файл>
  signer public-key --key <файл>
  signer serve      --key <файл> --socket <путь> [--allow-uid <uid>]...
                    [--max-lifetime-minutes 60] [--rate 500] [--burst 5000]
                    [--log-level info]
''';

Future<void> main(List<String> arguments) async {
  final serve = ArgParser()
    ..addOption('key')
    ..addOption('socket')
    ..addMultiOption('allow-uid')
    ..addOption('max-lifetime-minutes', defaultsTo: '60')
    ..addOption('rate', defaultsTo: '500')
    ..addOption('burst', defaultsTo: '5000')
    ..addOption(
      'log-level',
      defaultsTo: 'info',
      allowed: ['fine', 'info', 'warning', 'severe'],
    );
  final parser = ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false)
    ..addCommand('keygen', ArgParser()..addOption('key'))
    ..addCommand('public-key', ArgParser()..addOption('key'))
    ..addCommand('serve', serve);

  final ArgResults args;
  final ArgResults command;
  final _ServeOptions? options;
  try {
    args = parser.parse(arguments);
    if (args.flag('help') || args.command == null) {
      stdout.write(_usage);
      exit(args.flag('help') ? 0 : 64);
    }
    command = args.command!;
    if (command.option('key') == null ||
        (command.name == 'serve' && command.option('socket') == null)) {
      throw const FormatException('Нужны --key и для serve --socket');
    }
    options = command.name == 'serve' ? _ServeOptions.parse(command) : null;
  } on FormatException catch (e) {
    stderr.writeln('${e.message}\n\n$_usage');
    exit(64);
  }

  final crypto = await SodiumCryptoProvider.load();
  final keyPath = command.option('key')!;
  try {
    switch (command.name) {
      case 'keygen':
        final key = await SignerKeyFile.generate(keyPath, crypto);
        stdout.writeln(bytesToHex(key.publicKey));
      case 'public-key':
        final key = await SignerKeyFile.load(keyPath, crypto);
        stdout.writeln(bytesToHex(key.publicKey));
      case 'serve':
        await _serve(crypto, keyPath, options!);
    }
  } on SignerKeyException catch (e) {
    stderr.writeln(e.message);
    exitCode = 78;
  } on FileSystemException catch (e) {
    stderr.writeln('${e.message}: ${e.path}');
    exitCode = 1;
  }
}

Future<void> _serve(
  CryptoProvider crypto,
  String keyPath,
  _ServeOptions options,
) async {
  JsonLogWriter(stdout).attach(options.logLevel);
  final key = await SignerKeyFile.load(keyPath, crypto);
  final service = TicketSigningService(
    crypto: crypto,
    key: key,
    limiter: RateLimiter(perSecond: options.rate, burst: options.burst),
    maxLifetime: options.maxLifetime,
  );
  final server = await SignerServer.bind(
    options.socket,
    service,
    allowedUids: options.allowedUids,
  );
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
  key.seed.dispose();
}

final class _ServeOptions {
  const new({
    required this.socket,
    required this.allowedUids,
    required this.maxLifetime,
    required this.rate,
    required this.burst,
    required this.logLevel,
  });

  factory parse(ArgResults a) {
    int number(String name, int min, int max) {
      final n = int.tryParse(a.option(name)!);
      if (n == null || n < min || n > max) {
        throw FormatException('--$name: ожидается целое от $min до $max');
      }
      return n;
    }

    return _ServeOptions(
      socket: a.option('socket')!,
      allowedUids: {
        for (final uid in a.multiOption('allow-uid'))
          int.tryParse(uid) ??
              (throw FormatException('--allow-uid: не число: $uid')),
      },
      maxLifetime: Duration(
        minutes: number(
          'max-lifetime-minutes',
          1,
          FragmentTickets.maxLifetime.inMinutes,
        ),
      ),
      rate: number('rate', 1, 1000000).toDouble(),
      burst: number('burst', SignerWire.maxBatch, 1 << 30),
      logLevel: switch (a.option('log-level')) {
        'fine' => Level.FINE,
        'warning' => Level.WARNING,
        'severe' => Level.SEVERE,
        _ => Level.INFO,
      },
    );
  }

  final String socket;
  final Set<int> allowedUids;
  final Duration maxLifetime;
  final double rate;
  final int burst;
  final Level logLevel;
}
