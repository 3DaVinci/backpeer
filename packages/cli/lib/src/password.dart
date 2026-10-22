import 'dart:math';

/// Минимальная длина пароля (модель угроз, К-3).
const int minPasswordLength = 12;

/// Грубая оценка стойкости пароля, бит. Учитывает длину, классы символов,
/// повторы и самые частые пароли; это ориентир для предупреждения, а не
/// гарантия.
double estimatePasswordBits(String password) {
  final runes = password.runes.toList();
  if (runes.isEmpty) return 0;
  final lower = password.toLowerCase();
  for (final common in _common) {
    if (lower.contains(common)) return 10;
  }
  var pool = 0;
  if (runes.any((r) => r >= 0x61 && r <= 0x7A)) pool += 26;
  if (runes.any((r) => r >= 0x41 && r <= 0x5A)) pool += 26;
  if (runes.any((r) => r >= 0x30 && r <= 0x39)) pool += 10;
  if (runes.any((r) => r >= 0x20 && r < 0x7F && !_isAlnum(r))) pool += 33;
  if (runes.any((r) => r >= 0x80)) pool += 100;
  final unique = runes.toSet().length;
  // Повторы и короткий набор символов: считаем только «полезную» длину.
  final effective = min(runes.length, unique * 2);
  return effective * log(pool) / ln2;
}

/// Оценка словами.
String passwordRating(double bits) => bits < 50
    ? 'слабый'
    : bits < 70
    ? 'средний'
    : 'стойкий';

bool _isAlnum(int r) =>
    (r >= 0x30 && r <= 0x39) ||
    (r >= 0x41 && r <= 0x5A) ||
    (r >= 0x61 && r <= 0x7A);

const _common = [
  'password',
  'qwerty',
  '123456',
  'йцукен',
  'пароль',
  'letmein',
  'iloveyou',
  'admin',
];
