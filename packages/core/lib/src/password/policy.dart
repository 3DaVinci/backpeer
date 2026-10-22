import 'package:core/src/password/estimator.dart';
import 'package:core/src/password/unicode.g.dart';

/// Итог проверки пароля (crypto.md, раздел 4.3).
enum PasswordVerdict {
  /// Пароль нельзя принять.
  rejected,

  /// Можно принять, но только после явного согласия пользователя.
  weak,

  /// Годится.
  strong,
}

/// Почему пароль отклонён.
enum PasswordProblem {
  /// Короче [PasswordPolicy.minLength] символов.
  tooShort,

  /// Управляющий символ, суррогат или символ, не назначенный в
  /// [PasswordPolicy.unicodeVersion] (модель угроз, Кр-5).
  forbiddenCharacter,

  /// Подбирается быстрее, чем за [PasswordPolicy.rejectBelowLog10]
  /// порядков попыток.
  tooGuessable,
}

/// Что сделало пароль предсказуемым: подсказка для пользователя.
enum PasswordHint {
  /// Из списка частых паролей.
  commonPassword,

  /// Обычное слово.
  dictionaryWord,

  /// Имя или фамилия.
  name,

  /// Сведения о пользователе (имя учётной записи, почта).
  personalInfo,

  /// Слово набрано в другой раскладке.
  otherLayout,

  /// Замены вида `@` вместо `a`.
  substitution,

  /// Слово задом наперёд.
  reversed,

  /// Соседние клавиши.
  keyboardPattern,

  /// Повтор.
  repeat,

  /// Последовательность.
  sequence,

  /// Дата или год.
  date,
}

/// Результат [PasswordPolicy.assess].
final class PasswordAssessment {
  const new({
    required this.verdict,
    required this.problems,
    required this.hints,
    required this.estimate,
  });

  final PasswordVerdict verdict;

  /// Пусто, если пароль не отклонён.
  final Set<PasswordProblem> problems;

  /// Подсказки по найденным узорам, от самого длинного; пусто для
  /// стойкого пароля.
  final List<PasswordHint> hints;

  final PasswordEstimate estimate;

  double get log10Guesses => estimate.log10;

  double get bits => estimate.bits;
}

/// Требования к паролю, общие для CLI и приложения (crypto.md,
/// раздел 4.3; модель угроз, К-3 и Кр-5).
abstract final class PasswordPolicy {
  /// Минимальная длина в символах (кодовых точках).
  static const minLength = 12;

  /// Меньше 10^10 попыток — отклоняется: при утечке копии мастер-ключа
  /// такой пароль подбирается за дни (crypto.md, раздел 4.3).
  static const rejectBelowLog10 = 10.0;

  /// Меньше 10^12 — принимается только с согласия пользователя.
  static const weakBelowLog10 = 12.0;

  /// Версия Unicode таблицы запрещённых символов.
  static const String unicodeVersion = passwordUnicodeVersion;

  static final PasswordEstimator _estimator = PasswordEstimator();

  /// Проверяет [password]. [userInputs] — что атакующий знает о
  /// пользователе (имя учётной записи, почта).
  static PasswordAssessment assess(
    String password, {
    List<String> userInputs = const [],
    PasswordEstimator? estimator,
  }) {
    final estimate = (estimator ?? _estimator).estimate(
      password,
      userInputs: userInputs,
    );
    final problems = <PasswordProblem>{
      if (password.runes.length < minLength) PasswordProblem.tooShort,
      if (firstForbiddenCharacter(password) != null)
        PasswordProblem.forbiddenCharacter,
      if (estimate.log10 < rejectBelowLog10) PasswordProblem.tooGuessable,
    };
    final verdict = problems.isNotEmpty
        ? PasswordVerdict.rejected
        : estimate.log10 < weakBelowLog10
        ? PasswordVerdict.weak
        : PasswordVerdict.strong;
    return PasswordAssessment(
      verdict: verdict,
      problems: problems,
      hints: verdict == PasswordVerdict.strong ? const [] : _hints(estimate),
      estimate: estimate,
    );
  }

  /// Первый запрещённый символ пароля или `null`.
  static int? firstForbiddenCharacter(String password) {
    // Строка Dart может содержать одиночный суррогат: runes отдаёт его
    // как есть, и он попадает в диапазон Cs.
    for (final r in password.runes) {
      if (_isForbidden(r)) return r;
    }
    return null;
  }

  static final List<int> _forbidden = [
    for (final range in passwordForbiddenRanges.split(','))
      ...switch (range.split('-')) {
        [final a] => [int.parse(a, radix: 16), int.parse(a, radix: 16)],
        [final a, final b] => [
          int.parse(a, radix: 16),
          int.parse(b, radix: 16),
        ],
        _ => throw StateError('таблица Unicode повреждена: $range'),
      },
  ];

  static bool _isForbidden(int r) {
    // Двоичный поиск по парам «начало, конец».
    var lo = 0;
    var hi = _forbidden.length ~/ 2 - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (r < _forbidden[2 * mid]) {
        hi = mid - 1;
      } else if (r > _forbidden[2 * mid + 1]) {
        lo = mid + 1;
      } else {
        return true;
      }
    }
    return false;
  }

  static List<PasswordHint> _hints(PasswordEstimate estimate) {
    final matches =
        estimate.sequence
            .where((m) => m.pattern != PasswordPattern.bruteforce)
            .toList()
          ..sort((a, b) => b.length.compareTo(a.length));
    final hints = <PasswordHint>{};
    for (final m in matches) {
      switch (m.pattern) {
        case PasswordPattern.dictionary:
          hints.add(switch (m.dictionary) {
            'passwords' => PasswordHint.commonPassword,
            'female_names' || 'male_names' || 'surnames' => PasswordHint.name,
            'user_inputs' => PasswordHint.personalInfo,
            _ => PasswordHint.dictionaryWord,
          });
          if (m.otherLayout) hints.add(PasswordHint.otherLayout);
          if (m.l33t.isNotEmpty) hints.add(PasswordHint.substitution);
          if (m.reversed) hints.add(PasswordHint.reversed);
        case PasswordPattern.spatial:
          hints.add(PasswordHint.keyboardPattern);
        case PasswordPattern.repeat:
          hints.add(PasswordHint.repeat);
        case PasswordPattern.sequence:
          hints.add(PasswordHint.sequence);
        case PasswordPattern.year || PasswordPattern.date:
          hints.add(PasswordHint.date);
        case PasswordPattern.bruteforce:
          break;
      }
    }
    return hints.toList();
  }
}
