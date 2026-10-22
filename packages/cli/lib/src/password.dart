import 'package:core/core.dart';

/// Сообщения о пароле для консоли. Проверка и оценка — `PasswordPolicy`
/// из core (crypto.md, раздел 4.3); здесь только слова.

/// Оценка словами.
String passwordRating(PasswordVerdict verdict) => switch (verdict) {
  PasswordVerdict.rejected => 'слабый',
  PasswordVerdict.weak => 'средний',
  PasswordVerdict.strong => 'стойкий',
};

/// Почему пароль не принят — одной строкой.
String passwordProblems(PasswordAssessment a) => [
  for (final p in a.problems)
    switch (p) {
      PasswordProblem.tooShort => 'короче ${PasswordPolicy.minLength} символов',
      PasswordProblem.forbiddenCharacter =>
        'есть управляющий символ или символ, не назначенный в Unicode '
            '${PasswordPolicy.unicodeVersion}',
      PasswordProblem.tooGuessable =>
        'подбирается слишком быстро (≈ ${a.bits.round()} бит, нужно не '
            'меньше ${_bits(PasswordPolicy.rejectBelowLog10)})',
    },
].join('; ');

/// Подсказки: что сделало пароль предсказуемым.
List<String> passwordHints(PasswordAssessment a) => [
  for (final h in a.hints)
    switch (h) {
      PasswordHint.commonPassword => 'это один из частых паролей',
      PasswordHint.dictionaryWord => 'словарные слова подбираются первыми',
      PasswordHint.name => 'имена и фамилии подбираются первыми',
      PasswordHint.personalInfo => 'в пароле сведения об учётной записи',
      PasswordHint.otherLayout =>
        'слово в другой раскладке не сложнее самого слова',
      PasswordHint.substitution =>
        'замены вроде @ вместо a почти не усложняют подбор',
      PasswordHint.reversed => 'слово задом наперёд не сложнее самого слова',
      PasswordHint.keyboardPattern =>
        'соседние клавиши (qwerty, 1qaz) подбираются первыми',
      PasswordHint.repeat => 'повторы почти не добавляют стойкости',
      PasswordHint.sequence => 'последовательности (abc, 123) предсказуемы',
      PasswordHint.date => 'даты и годы предсказуемы',
    },
];

int _bits(double log10) => (log10 * 3.321928).round();
