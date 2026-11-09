import 'dart:io';

import 'package:agent/agent.dart';

/// Агент бэкапа (`docs/ops/agent.md`). Разбор команд — `runAgent` в
/// `lib/src/cli.dart`: так его проверяют тесты, а точка входа только
/// вызывает `exit`.
Future<void> main(List<String> arguments) async {
  exitCode = await runAgent(arguments);
  // Isolate libsodium и таймеры не должны держать процесс.
  await stdout.flush();
  await stderr.flush();
  exit(exitCode);
}
