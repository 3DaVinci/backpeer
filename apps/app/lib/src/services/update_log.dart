import 'dart:convert';
import 'dart:io';

/// Журнал и итог обновления (задача 5.8.2).
///
/// Обновление ставит не само приложение, а вспомогательная оболочка
/// (`powershell.exe` на Windows, `sh` на macOS и Linux), причём приложение к
/// этому моменту уже завершается. Поэтому и приложение, и оболочка пишут в
/// один журнал `<home>/app/update.log`, а итог попытки кладут рядом в
/// `update-result.json`. По журналу видно, на каком шаге обновление
/// оборвалось: строки приложения — до выхода, строки оболочки — из скрипта.
final class UpdateLog {
  const new({this.log, this.result});

  /// Журнал; `null` — не вести.
  final File? log;

  /// Итог последней попытки; `null` — не записывать и не читать.
  final File? result;

  /// Предел журнала: старые записи не нужны, а расти без конца файл не
  /// должен.
  static const int maxBytes = 256 * 1024;

  /// Добавить строку. Ошибки записи не мешают обновлению: журнал —
  /// вспомогательный.
  void write(String message) {
    final file = log;
    if (file == null) return;
    final stamp = DateTime.now().toUtc().toIso8601String();
    try {
      file.parent.createSync(recursive: true);
      if (file.existsSync() && file.lengthSync() > maxBytes) {
        file.writeAsStringSync('', flush: true);
      }
      file.writeAsStringSync(
        '$stamp $message\n',
        mode: FileMode.append,
        flush: true,
      );
    } on FileSystemException {
      // Без журнала обновление продолжается.
    }
  }

  /// Итог прошлой попытки для человека: `null` — итога нет или обновление
  /// установилось. Файл удаляется: сообщение показывается один раз.
  String? takeResult() {
    final file = result;
    if (file == null || !file.existsSync()) return null;
    String text;
    try {
      text = file.readAsStringSync();
    } on FileSystemException {
      return null;
    }
    try {
      file.deleteSync();
    } on FileSystemException {
      // Не удалось удалить — сообщение всё равно покажем.
    }
    final Object? decoded;
    try {
      // PowerShell 5.1 пишет UTF-8 с BOM, если не задать кодировку явно.
      decoded = jsonDecode(text.replaceFirst('\uFEFF', ''));
    } on FormatException {
      return 'итог обновления не разобран';
    }
    if (decoded is! Map<String, Object?>) return 'итог обновления не разобран';
    if (decoded['ok'] == true) return null;
    final stage = '${decoded['stage'] ?? ''}';
    final message = '${decoded['message'] ?? ''}';
    final logPath = '${decoded['log'] ?? ''}';
    final where = logPath.isEmpty ? '' : ', журнал: $logPath';
    if (message.isEmpty || stage == 'started') {
      return 'обновление не завершилось$where';
    }
    return '$message$where';
  }
}
