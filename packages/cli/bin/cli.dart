import 'dart:io';

import 'package:core/core.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.contains('--version')) {
    stdout.writeln(versionLine('cli'));
    // Заодно проверяет, что libsodium из папки сборки загружается.
    final crypto = await SodiumCryptoProvider.load();
    stdout.writeln('libsodium ${crypto.libraryVersion}');
    return;
  }
  stdout.writeln('cli: not implemented yet');
}
