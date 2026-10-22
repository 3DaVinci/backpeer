// Оценка стойкости и требования к паролю (задача 2.4.4, crypto.md,
// раздел 4.3).

import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  group('PasswordEstimator совпадает с zxcvbn', () {
    // Значения — Python-порт zxcvbn 4.5.0 (данные zxcvbn 4.4.2) с годом
    // отсчёта 2017. Расхождения допустимы только в меньшую сторону и
    // только из-за русских словарей и раскладки; на выборке из 3866
    // латинских паролей совпали 3811, остальные 55 — русские слова в
    // транслите и в чужой раскладке.
    const reference = <String, double>{
      'password': 3,
      'correcthorsebatterystaple': 273500327700640,
      'Tr0ub4dour&3': 19058000,
      'asdfghjkl': 233,
      '1q2w3e4r5t': 291,
      'abcabcabc': 40,
      '19011987': 10951,
      '11.11.1991': 37961,
      '!QAZ@WSX3edc': 52342776064,
      'zxcvbnm': 40,
      'aaaaaaaaaaaa': 145,
      'abcdefghijkl': 49,
      'P@ssw0rd': 17,
      'iloveyou2010': 15000,
      'drowssap': 5,
      'Tiger1985': 52000,
      'qwerty123456': 1851,
      '147258369': 427,
      'correct horse battery staple': 2.13811968952e+20,
      r'tK9#vQ2$mZ7!pL': 100000000000001,
      '2015_06_04': 29201,
      'MaRiA1990!': 21010000,
    };
    final estimator = PasswordEstimator(referenceYear: 2017);
    for (final MapEntry(key: password, value: guesses) in reference.entries) {
      test(password, () {
        final g = estimator.estimate(password).guesses;
        expect(g, closeTo(guesses, guesses * 1e-9));
      });
    }
  });

  group('русские пароли', () {
    final estimator = PasswordEstimator(referenceYear: 2026);
    double log10(String p) => estimator.estimate(p).log10;

    test('словарь, раскладка и клавиатура ЙЦУКЕН', () {
      expect(log10('пароль'), lessThan(1), reason: 'первое слово словаря');
      expect(log10('gfhjkm'), lessThan(1), reason: '«пароль» латиницей');
      expect(log10('зфыыцщкв'), lessThan(1), reason: '«password» кириллицей');
      expect(log10('Наташа'), lessThan(3));
      expect(log10('natasha'), lessThan(3));
      expect(log10('йцукенгшщз'), lessThan(3), reason: 'как qwertyuiop');
      expect(log10('ЙЦУКЕН'), lessThan(3));
      // «ё» вне порядка кодов, последовательность — без неё.
      expect(log10('абвгдежз'), lessThan(3), reason: 'последовательность');
    });

    test('ё и е равноценны', () {
      // Ранги соседние: «котёнок» в списке, «котенок» добавлен за ним.
      expect(log10('котёнок'), closeTo(log10('котенок'), 0.01));
    });
  });

  group('PasswordPolicy', () {
    PasswordVerdict verdict(String p, {List<String> userInputs = const []}) =>
        PasswordPolicy.assess(p, userInputs: userInputs).verdict;

    // Набор слабых паролей не короче 12 символов: всё отклоняет оценка,
    // а не длина.
    const weak = [
      'password1234',
      'Password1234!',
      'qwertyuiop12',
      'Qwerty123456!',
      '1q2w3e4r5t6y',
      '1qaz2wsx3edc',
      'P@ssw0rd2024',
      'iloveyou1234',
      'aaaaaaaaaaaa',
      'abcdefghijkl',
      '123456789012',
      'йцукенгшщзхъ',
      'Пароль123456',
      'gfhjkm123456',
      'Наташа1985!!',
      'Moscow2024!!',
      'spartak1922!',
      'zxcvbnm,./12',
      'qwertyqwerty',
      'dragon123456',
      'Superman2000',
      'sunshine1990',
      '01.01.1990!!',
      'ЛюблюМаму123',
    ];
    for (final p in weak) {
      test('отклоняется: $p', () {
        final a = PasswordPolicy.assess(p);
        expect(
          a.verdict,
          PasswordVerdict.rejected,
          reason: '${a.estimate.sequence}',
        );
        expect(a.problems, {PasswordProblem.tooGuessable});
        expect(a.hints, isNotEmpty);
      });
    }

    const strong = [
      'correct horse battery staple',
      'другой пароль на новом устройстве',
      'кот бегемот читает Канта по вторникам',
      r'tK9#vQ2$mZ7!pL',
      'mx7Qd-v2Lr-9wTe',
      'серый Волк ест 7 зелёных слив',
    ];
    for (final p in strong) {
      test('принимается: $p', () {
        final a = PasswordPolicy.assess(p);
        expect(
          a.verdict,
          PasswordVerdict.strong,
          reason: '${a.estimate.sequence}',
        );
        expect(a.problems, isEmpty);
        expect(a.hints, isEmpty);
      });
    }

    test('короче 12 символов — отклоняется при любой оценке', () {
      final a = PasswordPolicy.assess(r'k9#Vq2$mZ7!');
      expect(a.problems, contains(PasswordProblem.tooShort));
      expect(a.verdict, PasswordVerdict.rejected);
      // Длина — в кодовых точках, а не в UTF-16.
      expect(
        PasswordPolicy.assess('😀' * 11).problems,
        contains(PasswordProblem.tooShort),
      );
    });

    test('средний пароль требует согласия', () {
      // Три частых слова: 10^10…10^12 попыток.
      final a = PasswordPolicy.assess('another long password');
      expect(a.log10Guesses, inInclusiveRange(10, 12));
      expect(a.verdict, PasswordVerdict.weak);
      expect(a.hints, contains(PasswordHint.dictionaryWord));
    });

    test('подсказки', () {
      expect(
        PasswordPolicy.assess('gfhjkm').hints,
        containsAll([PasswordHint.dictionaryWord, PasswordHint.otherLayout]),
      );
      expect(
        PasswordPolicy.assess('P@ssw0rd').hints,
        containsAll([PasswordHint.commonPassword, PasswordHint.substitution]),
      );
      expect(
        PasswordPolicy.assess('1qaz2wsx').hints.first,
        anyOf(PasswordHint.keyboardPattern, PasswordHint.commonPassword),
      );
      expect(PasswordPolicy.assess('11.11.1991').hints, [PasswordHint.date]);
    });

    test('сведения о пользователе снижают оценку', () {
      const p = 'aslangery2026!';
      final plain = PasswordPolicy.assess(p);
      final known = PasswordPolicy.assess(p, userInputs: ['aslangery']);
      expect(known.log10Guesses, lessThan(plain.log10Guesses));
      expect(known.verdict, PasswordVerdict.rejected);
      expect(known.hints, contains(PasswordHint.personalInfo));
    });

    test('запрещённые символы', () {
      const base = 'correct horse battery staple';
      for (final c in [
        '\u0000',
        '\n',
        '\t',
        '\u007F',
        '\u0085',
        '͸', // не назначен
        '￿', // не символ
        '\u{10FFFF}',
      ]) {
        expect(
          PasswordPolicy.firstForbiddenCharacter('$base$c'),
          c.runes.single,
          reason: 'U+${c.runes.single.toRadixString(16)}',
        );
        expect(verdict('$base$c'), PasswordVerdict.rejected);
      }
      // Одиночный суррогат: строка Dart может его содержать.
      final lone = '$base${String.fromCharCode(0xD800)}';
      expect(PasswordPolicy.firstForbiddenCharacter(lone), 0xD800);
      for (final c in ['ё', 'É', '😀', '', ' ', '€', '中']) {
        expect(
          PasswordPolicy.firstForbiddenCharacter('$base$c'),
          isNull,
          reason: c,
        );
      }
      expect(PasswordPolicy.unicodeVersion, '16.0.0');
    });

    test('длинный пароль оценивается быстро', () {
      final sw = Stopwatch()..start();
      final a = PasswordPolicy.assess('ab1!' * 500);
      expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
      expect(a.verdict, isNot(PasswordVerdict.strong), reason: 'повтор');
      expect(
        PasswordEstimator().estimate('x' * 10000).sequence.last.j,
        PasswordEstimator.maxLength - 1,
      );
    });
  });
}
