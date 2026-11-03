// Инструмент ключей и подписи обновлений (docs/spec/updates.md, задача
// 5.8.2). Закрытый ключ обновлений — только на защищённой машине подписи
// (П-3); сюда он передаётся через окружение или флаг, в репозиторий не
// попадает.
//
//   dart run tool/updates/sign.dart gen-key            # новая пара ключей
//   dart run tool/updates/sign.dart sign --key SEED --in updates.json
//
// Подпись — отсоединённая Ed25519 над точными байтами манифеста в контексте
// `fs/v1/sign/updates`; записывается в `updates.json.sig`.
import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';

Future<void> main(List<String> args) async {
  final crypto = await SodiumCryptoProvider.load();
  if (args.contains('gen-key')) {
    await _genKey(crypto);
  } else if (args.contains('sign')) {
    await _sign(crypto, args);
  } else {
    stderr.writeln(
      'использование: sign.dart gen-key | sign --key SEED --in ФАЙЛ',
    );
    exit(64);
  }
}

Future<void> _genKey(CryptoProvider crypto) async {
  final seed = SecretBytes(crypto.randomBytes(CryptoProvider.keyLength));
  final pair = await crypto.ed25519FromSeed(seed);
  stdout
    ..writeln('seed=${base64Encode(seed.bytes)}')
    ..writeln('public=${base64Encode(pair.publicKey)}');
}

Future<void> _sign(CryptoProvider crypto, List<String> args) async {
  String value(String name) {
    final i = args.indexOf(name);
    if (i < 0 || i + 1 >= args.length) {
      stderr.writeln('нет флага $name');
      exit(64);
    }
    return args[i + 1];
  }

  final seedText = value('--key');
  final inFile = value('--in');
  final bytes = File(inFile).readAsBytesSync();
  final seed = SecretBytes(base64Decode(seedText));
  final pair = await crypto.ed25519FromSeed(seed);
  final signature = await crypto.ed25519Sign(
    pair,
    signingInput('updates', bytes),
  );
  File('$inFile.sig').writeAsBytesSync(signature, flush: true);
  stdout.writeln(
    'подписано: $inFile -> $inFile.sig (${signature.length} байт)',
  );
}
