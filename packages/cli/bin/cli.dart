import 'dart:io';

import 'package:cli/cli.dart';

Future<void> main(List<String> arguments) async {
  exitCode = await runCli(arguments);
  // Isolate libsodium и таймеры не должны держать процесс.
  await stdout.flush();
  exit(exitCode);
}
