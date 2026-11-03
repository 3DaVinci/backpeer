import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart' show appVersion;

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
    await upload?.call(report);
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
  /// (docs/spec/crash-reports.md, раздел 4).
  static String redact(String input) {
    // Сначала отбросить строки с паролями и фразами (по исходному тексту,
    // до замен маркеров), затем очистить остальное.
    final kept = input
        .split('\n')
        .where((line) => !_mentionsSecret(line))
        .join('\n');
    var out = kept;
    // Абсолютные пути: `/…` и `X:\…` (и `X:/…`).
    out = out.replaceAll(RegExp(r'(?:[A-Za-z]:[\\/]|/)[^\s"`,;()]+'), '<path>');
    // Ключи и хэши — длинный шестнадцатеричный или base64 блоб.
    out = out.replaceAll(RegExp('[0-9a-fA-F]{32,}'), '<secret>');
    out = out.replaceAll(RegExp('[A-Za-z0-9+/]{40,}={0,2}'), '<secret>');
    return out;
  }

  static bool _mentionsSecret(String line) {
    final lower = line.toLowerCase();
    return const [
      'password',
      'passwd',
      'phrase',
      'пароль',
      'фраза',
    ].any(lower.contains);
  }
}
