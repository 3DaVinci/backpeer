import 'dart:convert';
import 'dart:io';

/// Ввод и вывод CLI. Отдельный интерфейс — чтобы тесты отвечали на
/// вопросы программы и читали её вывод.
abstract interface class Console {
  void out(String line);

  void err(String line);

  /// Строка с подсказкой; конец ввода — `null`.
  String? ask(String prompt);

  /// Секрет без эха (пароль, фраза); конец ввода — `null`.
  String? askSecret(String prompt);

  /// Строка прогресса, перезаписываемая на месте (только в терминале).
  void progress(String line);
}

/// Терминал: пароль вводится без эха.
final class StdConsole implements Console {
  const new();

  @override
  void out(String line) => stdout.writeln(line);

  @override
  void err(String line) => stderr.writeln(line);

  @override
  String? ask(String prompt) {
    stdout.write(prompt);
    return stdin.readLineSync(encoding: utf8);
  }

  @override
  String? askSecret(String prompt) {
    stdout.write(prompt);
    final terminal = stdin.hasTerminal;
    if (terminal) stdin.echoMode = false;
    try {
      return stdin.readLineSync(encoding: utf8);
    } finally {
      if (terminal) {
        stdin.echoMode = true;
        stdout.writeln();
      }
    }
  }

  @override
  void progress(String line) {
    if (stdout.hasTerminal) stdout.write('\r\x1B[2K$line');
  }
}
