import 'dart:io';

import 'package:cli/cli.dart';
import 'package:test/test.dart';

/// Консоль CLI для тестов: отвечает на вопросы функцией, копит вывод.
final class TestConsole implements Console {
  new([this.answer]);

  final String? Function(String prompt, List<String> out)? answer;
  final List<String> lines = [];
  final List<String> errors = [];

  @override
  void out(String line) => lines.add(line);

  @override
  void err(String line) => errors.add(line);

  @override
  String? ask(String prompt) => answer?.call(prompt, lines);

  @override
  String? askSecret(String prompt) => answer?.call(prompt, lines);

  @override
  void progress(String line) {}
}

const testPassword = 'correct horse battery staple';

/// Окружение CLI и агента для каталога программы [home].
Map<String, String> testEnv(String home) => {
  'FS_HOME': home,
  'FS_PASSWORD': testPassword,
  'FS_ARGON2_FAST': '1',
  'FS_AGENT_SECRETS': 'none',
};

/// `cli init` без координатора: ключи и папки-«узлы» в [home].
Future<void> initHome(String home) async {
  String? answer(String prompt, List<String> out) {
    final m = RegExp(r'Слово №(\d+)').firstMatch(prompt);
    if (m == null) return null;
    final words = {
      for (final line in out)
        for (final w in RegExp(r'(\d+)\. ([a-z]+)').allMatches(line))
          int.parse(w[1]!): w[2]!,
    };
    return words[int.parse(m[1]!)];
  }

  final console = TestConsole(answer);
  final code = await runCli(
    ['init'],
    console: console,
    environment: testEnv(home),
  );
  expect(code, ExitCode.ok, reason: console.errors.join('\n'));
}

/// Ждёт [ready] до [timeout].
Future<void> until(
  bool Function() ready,
  String what, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) fail('не дождались: $what');
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

/// Папка с файлами для бэкапа.
Directory sampleData(String path) {
  final dir = Directory(path)..createSync(recursive: true);
  File('${dir.path}/a.txt').writeAsStringSync('первый файл\n' * 100);
  Directory('${dir.path}/sub').createSync();
  File('${dir.path}/sub/b.txt').writeAsStringSync('второй файл\n' * 50);
  return dir;
}
