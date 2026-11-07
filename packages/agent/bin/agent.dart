import 'dart:io';

import 'package:agent/agent.dart';

/// Агент бэкапа (`docs/ops/agent.md`). Разбор команд — `runAgent`
/// (`packages/agent/lib/src/cli.dart`), здесь только код выхода и остановка
/// процесса: `exit()` в тестах не проверить.
Future<void> main(List<String> arguments) async {
  exitCode = await runAgent(arguments);
  // Isolate libsodium и таймеры не должны держать процесс.
  await stdout.flush();
  await stderr.flush();
  exit(exitCode);
}
