/// Очистка текста отчёта о сбое от путей и похожих на секреты
/// последовательностей (`docs/spec/crash-reports.md`, раздел 4).
///
/// Общая для приложения (`CrashReporter`) и приёмника панели оператора:
/// отчёт очищается дважды — перед сохранением у пользователя и повторно на
/// сервере, чтобы старые или чужие клиенты не принесли лишнего.
library;

/// Заменяет в [input] абсолютные пути на `<path>`, длинные
/// шестнадцатеричные и base64-последовательности на `<secret>`, а строки,
/// где встречаются слова про пароли и фразы, выбрасывает целиком.
String redactCrashText(String input) {
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

bool _mentionsSecret(String line) {
  final lower = line.toLowerCase();
  return const [
    'password',
    'passwd',
    'phrase',
    'пароль',
    'фраза',
  ].any(lower.contains);
}
