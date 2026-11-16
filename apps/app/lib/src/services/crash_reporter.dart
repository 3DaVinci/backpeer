import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart' show appVersion, redactCrashText;

/// Отчёт о сбое приложения (задача 5.9.3, docs/spec/crash-reports.md):
/// только тип ошибки, сообщение и стек **после очистки** от путей и ключей,
/// и только с согласия пользователя. Без согласия отчёт не создаётся.
final class CrashReporter {
  new({this.file, this.upload, this.maxBytes = 256 * 1024});

  /// Куда дописывать отчёт (`crash-reports.jsonl`); `null` — никуда.
  final File? file;

  /// Отправка отчёта на свой сервер; `null` — приёмник не настроен.
  final Future<void> Function(Map<String, Object?> report)? upload;

  /// Предел размера локального журнала отчётов.
  final int maxBytes;

  /// Собирает и сохраняет отчёт об [error] и [stack]; ошибки сохранения и
  /// отправки не влияют на приложение.
  Future<void> capture(Object error, StackTrace stack) async {
    final report = <String, Object?>{
      'version': appVersion,
      'os': '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
      'error': redact('$error'),
      'stack': redact('$stack'),
      'at': DateTime.now().toUtc().toIso8601String(),
    };
    await _store(report);
    try {
      await upload?.call(report);
    } on Object {
      // Отправка не должна влиять на приложение: отчёт остался локально.
    }
  }

  /// Отправляет [report] на приёмник панели оператора
  /// (`CRASH_REPORT_URL/api/v1/crash-reports`). Ошибки сети, таймаут и
  /// не-2xx ответ — `false`; приложение продолжает работу.
  static Future<bool> uploadTo(
    Uri endpoint,
    Map<String, Object?> report, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.postUrl(endpoint).timeout(timeout);
      request.headers.contentType = ContentType.json;
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'backpeer-app/${report['version'] ?? ''}',
      );
      request.add(utf8.encode(jsonEncode(report)));
      final response = await request.close().timeout(timeout);
      await response.drain<void>().timeout(timeout);
      return response.statusCode >= 200 && response.statusCode < 300;
    } on Object {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _store(Map<String, Object?> report) async {
    final f = file;
    if (f == null) return;
    try {
      f.parent.createSync(recursive: true);
      final line = '${jsonEncode(report)}\n';
      f.openSync(mode: FileMode.append)
        ..writeStringSync(line)
        ..closeSync();
      _trim();
    } on FileSystemException {
      // Не сохранилось — отчёт пропадает, приложение продолжает.
    }
  }

  void _trim() {
    final f = file;
    if (f == null || !f.existsSync()) return;
    try {
      if (f.lengthSync() <= maxBytes) return;
      final lines = f.readAsLinesSync();
      var keep = lines.length;
      var size = f.lengthSync();
      while (keep > 0 && size > maxBytes) {
        keep--;
        size -= utf8.encode(lines[lines.length - keep]).length + 1;
      }
      f.writeAsStringSync('${lines.sublist(lines.length - keep).join('\n')}\n');
    } on FileSystemException {
      // Не получилось усечь — в следующий раз.
    }
  }

  /// Очищает текст от путей и похожих на секреты последовательностей
  /// (docs/spec/crash-reports.md, раздел 4). Общая реализация — в `core`,
  /// её же использует приёмник панели оператора.
  static String redact(String input) => redactCrashText(input);
}
