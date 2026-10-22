import 'dart:math' as math;

import 'package:core/src/password/dictionaries.g.dart';
import 'package:core/src/password/keyboard.dart';

/// Какой узор нашла оценка в части пароля.
enum PasswordPattern {
  /// Слово из словаря (частые пароли, слова, имена, фамилии).
  dictionary,

  /// Соседние клавиши: `qwerty`, `zxcvbn`, `1qaz2wsx`.
  spatial,

  /// Повтор: `aaaa`, `abcabc`.
  repeat,

  /// Последовательность с постоянным шагом: `abcd`, `9753`.
  sequence,

  /// Год 1900–2039.
  year,

  /// Дата: `19011987`, `11.11.1991`.
  date,

  /// Ничего не найдено: перебор по 10 вариантов на символ.
  bruteforce,
}

/// Узор в пароле: символы с [i] по [j] включительно (кодовые точки).
final class PasswordMatch {
  new _({
    required this.pattern,
    required this.i,
    required this.j,
    required this.token,
    this.dictionary,
    this.word,
    this.rank = 0,
    this.reversed = false,
    this.l33t = const {},
    this.otherLayout = false,
    this.graph,
    this.turns = 0,
    this.shifted = 0,
    this.baseGuesses = 0,
    this.repeatCount = 0,
    this.ascending = true,
    this.year = 0,
    this.separator = false,
  });

  final PasswordPattern pattern;
  final int i;
  final int j;

  /// Символы пароля [i]…[j].
  final List<int> token;

  /// Словарь, слово и его ранг.
  final String? dictionary;
  final String? word;
  final int rank;

  /// Слово записано задом наперёд.
  final bool reversed;

  /// Замены вида `4` → `a`, сделанные в этом слове.
  final Map<int, int> l33t;

  /// Слово набрано в другой раскладке (`gfhjkm` — «пароль»).
  final bool otherLayout;

  /// Клавиатурный узор: граф, повороты, символы с Shift.
  final String? graph;
  final int turns;
  final int shifted;

  /// Повтор: оценка повторяемой части и число повторов.
  final double baseGuesses;
  final int repeatCount;

  /// Последовательность: по возрастанию.
  final bool ascending;

  /// Год даты или года.
  final int year;

  /// Дата с разделителем.
  final bool separator;

  /// Оценка числа попыток; задаётся при поиске лучшего разбиения.
  double guesses = 0;

  int get length => j - i + 1;

  @override
  String toString() =>
      '${pattern.name}[$i..$j] «${String.fromCharCodes(token)}» '
      '${guesses.toStringAsExponential(2)}';
}

/// Результат оценки: число попыток подбора и лучшее разбиение пароля на
/// узоры.
final class PasswordEstimate {
  const new _(this.guesses, this.sequence);

  /// Сколько попыток нужно атакующему, который перебирает пароли от
  /// простых к сложным (модель zxcvbn).
  final double guesses;

  final List<PasswordMatch> sequence;

  double get log10 => math.log(guesses) / math.ln10;

  double get bits => math.log(guesses) / math.ln2;
}

/// Оценка стойкости пароля по модели zxcvbn 4.4.2 (Wheeler, «zxcvbn:
/// Low-Budget Password Strength Estimation», USENIX Security 2016):
/// поиск словарных слов (с заменами, задом наперёд, в другой раскладке),
/// клавиатурных узоров, повторов, последовательностей, дат; затем
/// разбиение пароля на узоры с наименьшим числом попыток.
///
/// Отличия от zxcvbn: работа с кодовыми точками, а не UTF-16; русский
/// словарь, его транслитерация и набор в чужой раскладке (ЙЦУКЕН ↔ QWERTY);
/// годы до 2039; год отсчёта по умолчанию — текущий. Числа — `double`, а
/// не точные целые: на оценку это не влияет.
final class PasswordEstimator {
  new({int? referenceYear})
    : referenceYear = referenceYear ?? DateTime.now().year;

  /// Год, от которого считается «близость» дат и годов.
  final int referenceYear;

  /// Длиннее оценивается только начало: оценка не уменьшается от
  /// дописанных символов, а время поиска растёт как квадрат длины.
  static const maxLength = 100;

  static const _bruteforceCardinality = 10.0;
  static const _minGuessesBeforeGrowingSequence = 10000.0;
  static const _minSubmatchGuessesSingleChar = 10.0;
  static const _minSubmatchGuessesMultiChar = 50.0;
  static const _minYearSpace = 20;
  static const _maxDelta = 5;
  static const _dateMinYear = 1000;
  static const _dateMaxYear = 2050;

  /// Словари: русский — только для кириллицы и набора в чужой раскладке.
  static final Map<String, Map<String, int>> _dictionaries = {
    for (final MapEntry(:key, :value) in passwordDictionaries.entries)
      key: _ranked(value.split(',')),
  };

  static final int _maxWordLength = _dictionaries.values
      .expand((d) => d.keys)
      .fold(0, (m, w) => math.max(m, w.runes.length));

  static const _russian = 'russian';

  static const _l33tTable = <String, List<String>>{
    'a': ['4', '@'],
    'b': ['8'],
    'c': ['(', '{', '[', '<'],
    'e': ['3'],
    'g': ['6', '9'],
    'i': ['1', '!', '|'],
    'l': ['1', '|', '7'],
    'o': ['0'],
    's': [r'$', '5'],
    't': ['+', '7'],
    'x': ['%'],
    'z': ['2'],
  };

  static const _shifted = r'~!@#$%^&*()_+QWERTYUIOP{}|ASDFGHJKL:"ZXCVBNM<>?';

  static const _dateSplits = <int, List<(int, int)>>{
    4: [(1, 2), (2, 3)],
    5: [(1, 3), (2, 3)],
    6: [(1, 2), (2, 4), (4, 5)],
    7: [(1, 3), (2, 3), (4, 5), (4, 6)],
    8: [(2, 4), (4, 6)],
  };

  /// Оценивает [password]. [userInputs] — слова, которые атакующий знает о
  /// пользователе (имя, адрес почты): считаются словарём с рангом по
  /// порядку.
  PasswordEstimate estimate(
    String password, {
    List<String> userInputs = const [],
  }) {
    var runes = password.runes.toList();
    if (runes.length > maxLength) runes = runes.sublist(0, maxLength);
    final user = _ranked([
      for (final w in userInputs)
        if (w.isNotEmpty) _lower(w.runes.toList()).join(),
    ]);
    return _mostGuessable(runes, _omnimatch(runes, user));
  }

  // --- поиск узоров -------------------------------------------------------

  List<PasswordMatch> _omnimatch(List<int> runes, Map<String, int> user) => [
    ..._dictionaryMatches(runes, user),
    ..._reverseDictionaryMatches(runes, user),
    ..._l33tMatches(runes, user),
    ..._layoutMatches(runes),
    ..._spatialMatches(runes),
    ..._repeatMatches(runes, user),
    ..._sequenceMatches(runes),
    ..._yearMatches(runes),
    ..._dateMatches(runes),
  ];

  Iterable<(String, Map<String, int>)> _latinDictionaries(
    Map<String, int> user,
  ) sync* {
    for (final MapEntry(:key, :value) in _dictionaries.entries) {
      if (key != _russian) yield (key, value);
    }
    yield ('user_inputs', user);
  }

  Iterable<(String, Map<String, int>)> _allDictionaries(
    Map<String, int> user,
  ) sync* {
    yield* _latinDictionaries(user);
    yield (_russian, _dictionaries[_russian]!);
  }

  /// Словарные слова в [lowered] (уже в нижнем регистре); токен берётся из
  /// [runes].
  List<PasswordMatch> _dictionaryMatches(
    List<int> runes,
    Map<String, int> user, {
    List<int>? lowered,
    Iterable<(String, Map<String, int>)>? dictionaries,
    bool reversed = false,
    bool otherLayout = false,
  }) {
    final low = lowered ?? _lowerRunes(runes);
    // В чужой раскладке ищем только там, где раскладка что-то изменила.
    final original = otherLayout ? _lowerRunes(runes) : null;
    final out = <PasswordMatch>[];
    final n = runes.length;
    final maxWord = math.max(
      _maxWordLength,
      user.keys.fold(0, (m, w) => math.max(m, w.runes.length)),
    );
    for (final (name, dict) in dictionaries ?? _allDictionaries(user)) {
      if (dict.isEmpty) continue;
      for (var i = 0; i < n; i++) {
        final limit = math.min(n, i + maxWord);
        for (var j = i; j < limit; j++) {
          final word = String.fromCharCodes(low, i, j + 1);
          final rank = dict[word];
          if (rank == null) continue;
          if (original != null &&
              word == String.fromCharCodes(original, i, j + 1)) {
            continue;
          }
          out.add(
            PasswordMatch._(
              pattern: PasswordPattern.dictionary,
              i: i,
              j: j,
              token: runes.sublist(i, j + 1),
              dictionary: name,
              word: word,
              rank: rank,
              reversed: reversed,
              otherLayout: otherLayout,
            ),
          );
        }
      }
    }
    return out;
  }

  List<PasswordMatch> _reverseDictionaryMatches(
    List<int> runes,
    Map<String, int> user,
  ) {
    final n = runes.length;
    final reversed = runes.reversed.toList();
    return [
      for (final m in _dictionaryMatches(reversed, user, reversed: true))
        PasswordMatch._(
          pattern: PasswordPattern.dictionary,
          i: n - 1 - m.j,
          j: n - 1 - m.i,
          token: m.token.reversed.toList(),
          dictionary: m.dictionary,
          word: m.word,
          rank: m.rank,
          reversed: true,
        ),
    ];
  }

  List<PasswordMatch> _l33tMatches(List<int> runes, Map<String, int> user) {
    final present = runes.toSet();
    final subtable = <String, List<String>>{
      for (final MapEntry(key: letter, value: subs) in _l33tTable.entries)
        if (subs.where((s) => present.contains(s.codeUnitAt(0))).toList()
            case final relevant when relevant.isNotEmpty)
          letter: relevant,
    };
    final out = <PasswordMatch>[];
    final seen = <String>{};
    for (final sub in _enumerateL33tSubs(subtable)) {
      if (sub.isEmpty) break;
      final translated = [for (final r in runes) sub[r] ?? r];
      final lowered = _lowerRunes(translated);
      for (final m in _dictionaryMatches(
        translated,
        user,
        lowered: lowered,
        dictionaries: _latinDictionaries(user),
      )) {
        final token = runes.sublist(m.i, m.j + 1);
        if (token.length <= 1) continue;
        if (_lower(token).join() == m.word) continue;
        final used = <int, int>{
          for (final MapEntry(:key, :value) in sub.entries)
            if (token.contains(key)) key: value,
        };
        // Разные наборы замен дают одно и то же совпадение.
        if (!seen.add('${m.i}:${m.j}:${m.dictionary}:${m.word}:$used')) {
          continue;
        }
        out.add(
          PasswordMatch._(
            pattern: PasswordPattern.dictionary,
            i: m.i,
            j: m.j,
            token: token,
            dictionary: m.dictionary,
            word: m.word,
            rank: m.rank,
            l33t: used,
          ),
        );
      }
    }
    return out;
  }

  /// Все способы прочитать символы замен буквами (`1` — `i` или `l`), как
  /// `enumerate_l33t_subs` в zxcvbn.
  static List<Map<int, int>> _enumerateL33tSubs(
    Map<String, List<String>> table,
  ) {
    var subs = <List<(String, String)>>[[]];
    for (final MapEntry(key: letter, value: chars) in table.entries) {
      final next = <List<(String, String)>>[];
      for (final c in chars) {
        for (final sub in subs) {
          final dup = sub.indexWhere((p) => p.$1 == c);
          if (dup == -1) {
            next.add([...sub, (c, letter)]);
          } else {
            next
              ..add(sub)
              ..add(
                [...sub]
                  ..removeAt(dup)
                  ..add((c, letter)),
              );
          }
        }
      }
      final seen = <String>{};
      subs = [
        for (final sub in next)
          if (seen.add(
            (sub.map((p) => '${p.$2},${p.$1}').toList()..sort()).join('-'),
          ))
            sub,
      ];
    }
    return [
      for (final sub in subs)
        {for (final (c, letter) in sub) c.codeUnitAt(0): letter.codeUnitAt(0)},
    ];
  }

  /// Слова, набранные в чужой раскладке: русские латиницей (`gfhjkm`) и
  /// английские кириллицей (`зфыыцщкв`).
  List<PasswordMatch> _layoutMatches(List<int> runes) {
    final low = _lowerRunes(runes);
    final out = <PasswordMatch>[];
    final asCyrillic = [for (final r in low) latinToCyrillicKey[r] ?? r];
    if (!_same(asCyrillic, low)) {
      out.addAll(
        _dictionaryMatches(
          runes,
          const {},
          lowered: asCyrillic,
          dictionaries: [(_russian, _dictionaries[_russian]!)],
          otherLayout: true,
        ),
      );
    }
    final asLatin = [for (final r in low) cyrillicToLatinKey[r] ?? r];
    if (!_same(asLatin, low)) {
      out.addAll(
        _dictionaryMatches(
          runes,
          const {},
          lowered: asLatin,
          dictionaries: _latinDictionaries(const {}),
          otherLayout: true,
        ),
      );
    }
    return out;
  }

  List<PasswordMatch> _spatialMatches(List<int> runes) {
    final out = <PasswordMatch>[];
    for (final graph in keyboardGraphs) {
      out.addAll(_spatialHelper(runes, runes, graph));
    }
    // Узоры на русской раскладке — те же клавиши: «йцукен» = «qwerty».
    final asLatin = [for (final r in runes) cyrillicToLatinKey[r] ?? r];
    if (!_same(asLatin, runes)) {
      out.addAll(_spatialHelper(asLatin, runes, keyboardGraphs.first));
    }
    return out;
  }

  /// Цепочки соседних клавиш в [keys]; токен берётся из [runes].
  List<PasswordMatch> _spatialHelper(
    List<int> keys,
    List<int> runes,
    KeyboardGraph graph,
  ) {
    final out = <PasswordMatch>[];
    final n = keys.length;
    var i = 0;
    while (i < n - 1) {
      var j = i + 1;
      int? lastDirection;
      var turns = 0;
      var shifted =
          graph.shiftable && _shifted.contains(String.fromCharCode(keys[i]))
          ? 1
          : 0;
      while (true) {
        final adjacents =
            graph.adjacency[String.fromCharCode(keys[j - 1])] ?? const [];
        var found = false;
        if (j < n) {
          final cur = String.fromCharCode(keys[j]);
          for (var d = 0; d < adjacents.length; d++) {
            final adj = adjacents[d];
            if (adj == null || !adj.contains(cur)) continue;
            found = true;
            if (adj.indexOf(cur) == 1) shifted++;
            if (lastDirection != d) {
              turns++;
              lastDirection = d;
            }
            break;
          }
        }
        if (found) {
          j++;
          continue;
        }
        if (j - i > 2) {
          out.add(
            PasswordMatch._(
              pattern: PasswordPattern.spatial,
              i: i,
              j: j - 1,
              token: runes.sublist(i, j),
              graph: graph.name,
              turns: turns,
              shifted: shifted,
            ),
          );
        }
        i = j;
        break;
      }
    }
    return out;
  }

  List<PasswordMatch> _repeatMatches(List<int> runes, Map<String, int> user) {
    final out = <PasswordMatch>[];
    final n = runes.length;
    var last = 0;
    while (last < n) {
      // Самое левое начало, с которого что-то повторяется хотя бы дважды.
      int? start;
      for (var i = last; i < n && start == null; i++) {
        for (var b = 1; i + 2 * b <= n; b++) {
          if (_repeats(runes, i, b) >= 2) {
            start = i;
            break;
          }
        }
      }
      if (start == null) break;
      final i = start;
      // Ленивый (.+?)\1+ — самая короткая основа; жадный (.+)\1+ — самая
      // длинная.
      var lazyBase = 0;
      var greedyBase = 0;
      for (var b = 1; i + 2 * b <= n; b++) {
        if (_repeats(runes, i, b) >= 2) {
          if (lazyBase == 0) lazyBase = b;
          greedyBase = b;
        }
      }
      final lazyLength = lazyBase * _repeats(runes, i, lazyBase);
      final greedyLength = greedyBase * _repeats(runes, i, greedyBase);
      final int length;
      final int base;
      if (greedyLength > lazyLength) {
        length = greedyLength;
        // Основа жадного совпадения сама может повторяться: ищем
        // наименьший период всей строки.
        var p = 1;
        while (length % p != 0 || _repeats(runes, i, p) * p < length) {
          p++;
        }
        base = p;
      } else {
        length = lazyLength;
        base = lazyBase;
      }
      final j = i + length - 1;
      final baseToken = runes.sublist(i, i + base);
      final baseEstimate = _mostGuessable(
        baseToken,
        _omnimatch(baseToken, user),
      );
      out.add(
        PasswordMatch._(
          pattern: PasswordPattern.repeat,
          i: i,
          j: j,
          token: runes.sublist(i, j + 1),
          baseGuesses: baseEstimate.guesses,
          repeatCount: length ~/ base,
        ),
      );
      last = j + 1;
    }
    return out;
  }

  /// Сколько раз подряд повторяется `runes[i, i + b)` начиная с [i].
  static int _repeats(List<int> runes, int i, int b) {
    var count = 1;
    while (i + (count + 1) * b <= runes.length) {
      for (var k = 0; k < b; k++) {
        if (runes[i + count * b + k] != runes[i + k]) return count;
      }
      count++;
    }
    return count;
  }

  List<PasswordMatch> _sequenceMatches(List<int> runes) {
    final n = runes.length;
    if (n <= 1) return const [];
    final out = <PasswordMatch>[];
    void update(int i, int j, int delta) {
      if (j - i > 1 || delta.abs() == 1) {
        if (delta.abs() > 0 && delta.abs() <= _maxDelta) {
          out.add(
            PasswordMatch._(
              pattern: PasswordPattern.sequence,
              i: i,
              j: j,
              token: runes.sublist(i, j + 1),
              ascending: delta > 0,
            ),
          );
        }
      }
    }

    var i = 0;
    int? lastDelta;
    for (var k = 1; k < n; k++) {
      final delta = runes[k] - runes[k - 1];
      lastDelta ??= delta;
      if (delta == lastDelta) continue;
      final j = k - 1;
      update(i, j, lastDelta);
      i = j;
      lastDelta = delta;
    }
    update(i, n - 1, lastDelta!);
    return out;
  }

  /// Годы 1900–2039 без перекрытий, слева направо (`recent_year` zxcvbn).
  List<PasswordMatch> _yearMatches(List<int> runes) {
    final out = <PasswordMatch>[];
    var i = 0;
    while (i + 4 <= runes.length) {
      final year = _digits(runes, i, i + 4);
      if (year != null && year >= 1900 && year <= 2039) {
        out.add(
          PasswordMatch._(
            pattern: PasswordPattern.year,
            i: i,
            j: i + 3,
            token: runes.sublist(i, i + 4),
            year: year,
          ),
        );
        i += 4;
      } else {
        i++;
      }
    }
    return out;
  }

  List<PasswordMatch> _dateMatches(List<int> runes) {
    final n = runes.length;
    final found = <PasswordMatch>[];
    // Без разделителей: от 4 (1191) до 8 (11111991) цифр.
    for (var i = 0; i + 3 < n; i++) {
      for (var j = i + 3; j < i + 8 && j < n; j++) {
        if (_digits(runes, i, j + 1) == null) continue;
        final length = j - i + 1;
        ({int year, int month, int day})? best;
        for (final (k, l) in _dateSplits[length]!) {
          final dmy = _mapIntsToDmy([
            _digits(runes, i, i + k)!,
            _digits(runes, i + k, i + l)!,
            _digits(runes, i + l, j + 1)!,
          ]);
          if (dmy == null) continue;
          if (best == null ||
              (dmy.year - referenceYear).abs() <
                  (best.year - referenceYear).abs()) {
            best = dmy;
          }
        }
        if (best == null) continue;
        found.add(
          PasswordMatch._(
            pattern: PasswordPattern.date,
            i: i,
            j: j,
            token: runes.sublist(i, j + 1),
            year: best.year,
          ),
        );
      }
    }
    // С разделителями: от 6 (1/1/91) до 10 (11/11/1991) символов.
    for (var i = 0; i + 5 < n; i++) {
      for (var j = i + 5; j < i + 10 && j < n; j++) {
        final parts = _separatedDate(runes, i, j + 1);
        if (parts == null) continue;
        final dmy = _mapIntsToDmy(parts);
        if (dmy == null) continue;
        found.add(
          PasswordMatch._(
            pattern: PasswordPattern.date,
            i: i,
            j: j,
            token: runes.sublist(i, j + 1),
            year: dmy.year,
            separator: true,
          ),
        );
      }
    }
    // Дату внутри другой даты отбрасываем: в «2015_06_04» есть и «15_06_04».
    return [
      for (final m in found)
        if (!found.any((o) => !identical(o, m) && o.i <= m.i && o.j >= m.j)) m,
    ];
  }

  /// `^(\d{1,4})([\s/\\_.-])(\d{1,2})\2(\d{1,4})$` на `runes[start, end)`.
  static List<int>? _separatedDate(List<int> runes, int start, int end) {
    int digitRun(int from) {
      var k = from;
      while (k < end && _isDigit(runes[k])) {
        k++;
      }
      return k - from;
    }

    final a = digitRun(start);
    if (a < 1 || a > 4 || start + a >= end) return null;
    final sep = runes[start + a];
    if (!_isDateSeparator(sep)) return null;
    final bStart = start + a + 1;
    final b = digitRun(bStart);
    if (b < 1 || b > 2 || bStart + b >= end || runes[bStart + b] != sep) {
      return null;
    }
    final cStart = bStart + b + 1;
    final c = digitRun(cStart);
    if (c < 1 || c > 4 || cStart + c != end) return null;
    return [
      _digits(runes, start, start + a)!,
      _digits(runes, bStart, bStart + b)!,
      _digits(runes, cStart, end)!,
    ];
  }

  static bool _isDateSeparator(int r) =>
      r == 0x2F ||
      r == 0x5C ||
      r == 0x5F ||
      r == 0x2E ||
      r == 0x2D ||
      _isWhitespace(r);

  // \s в Python: пробельные символы Unicode.
  static bool _isWhitespace(int r) =>
      (r >= 0x09 && r <= 0x0D) ||
      (r >= 0x1C && r <= 0x20) ||
      r == 0x85 ||
      r == 0xA0 ||
      r == 0x1680 ||
      (r >= 0x2000 && r <= 0x200A) ||
      r == 0x2028 ||
      r == 0x2029 ||
      r == 0x202F ||
      r == 0x205F ||
      r == 0x3000;

  ({int year, int month, int day})? _mapIntsToDmy(List<int> ints) {
    if (ints[1] > 31 || ints[1] <= 0) return null;
    var over12 = 0;
    var over31 = 0;
    var under1 = 0;
    for (final v in ints) {
      if ((v > 99 && v < _dateMinYear) || v > _dateMaxYear) return null;
      if (v > 31) over31++;
      if (v > 12) over12++;
      if (v <= 0) under1++;
    }
    if (over31 >= 2 || over12 == 3 || under1 >= 2) return null;
    final splits = [
      (ints[2], [ints[0], ints[1]]),
      (ints[0], [ints[1], ints[2]]),
    ];
    for (final (y, rest) in splits) {
      if (y >= _dateMinYear && y <= _dateMaxYear) {
        final dm = _mapIntsToDm(rest);
        // Четырёхзначный год есть, а день и месяц не сходятся — не дата.
        return dm == null ? null : (year: y, month: dm.$2, day: dm.$1);
      }
    }
    for (final (y, rest) in splits) {
      final dm = _mapIntsToDm(rest);
      if (dm != null) {
        final year = y > 99 ? y : (y > 50 ? y + 1900 : y + 2000);
        return (year: year, month: dm.$2, day: dm.$1);
      }
    }
    return null;
  }

  static (int, int)? _mapIntsToDm(List<int> ints) {
    for (final (d, m) in [(ints[0], ints[1]), (ints[1], ints[0])]) {
      if (d >= 1 && d <= 31 && m >= 1 && m <= 12) return (d, m);
    }
    return null;
  }

  // --- оценка -------------------------------------------------------------

  /// Разбиение пароля на узоры с наименьшим
  /// `l! · Π guesses + 10000^(l − 1)` (`most_guessable_match_sequence`).
  PasswordEstimate _mostGuessable(
    List<int> runes,
    List<PasswordMatch> matches,
  ) {
    final n = runes.length;
    if (n == 0) return const PasswordEstimate._(1, []);
    final byJ = List.generate(n, (_) => <PasswordMatch>[]);
    for (final m in matches) {
      byJ[m.j].add(m);
    }
    for (final list in byJ) {
      list.sort((a, b) => a.i.compareTo(b.i));
    }
    final optM = List.generate(n, (_) => <int, PasswordMatch>{});
    final optPi = List.generate(n, (_) => <int, double>{});
    final optG = List.generate(n, (_) => <int, double>{});

    void update(PasswordMatch m, int l) {
      final k = m.j;
      var pi = _estimateGuesses(m, n);
      if (l > 1) pi *= optPi[m.i - 1][l - 1]!;
      var g = _factorial(l) * pi;
      g += math.pow(_minGuessesBeforeGrowingSequence, l - 1);
      for (final MapEntry(key: cl, value: cg) in optG[k].entries) {
        if (cl > l) continue;
        if (cg <= g) return;
      }
      optG[k][l] = g;
      optM[k][l] = m;
      optPi[k][l] = pi;
    }

    PasswordMatch bruteforce(int i, int j) => PasswordMatch._(
      pattern: PasswordPattern.bruteforce,
      i: i,
      j: j,
      token: runes.sublist(i, j + 1),
    );

    for (var k = 0; k < n; k++) {
      for (final m in byJ[k]) {
        if (m.i > 0) {
          for (final l in optM[m.i - 1].keys.toList()) {
            update(m, l + 1);
          }
        } else {
          update(m, 1);
        }
      }
      update(bruteforce(0, k), 1);
      for (var i = 1; i <= k; i++) {
        final m = bruteforce(i, k);
        for (final MapEntry(key: l, value: last)
            in optM[i - 1].entries.toList()) {
          // Два перебора подряд хуже одного общего.
          if (last.pattern == PasswordPattern.bruteforce) continue;
          update(m, l + 1);
        }
      }
    }

    var k = n - 1;
    int? bestL;
    var bestG = double.infinity;
    for (final MapEntry(key: l, value: g) in optG[k].entries) {
      if (g < bestG) {
        bestL = l;
        bestG = g;
      }
    }
    final sequence = <PasswordMatch>[];
    var l = bestL!;
    while (k >= 0) {
      final m = optM[k][l]!;
      sequence.insert(0, m);
      k = m.i - 1;
      l--;
    }
    return PasswordEstimate._(optG[n - 1][sequence.length]!, sequence);
  }

  double _estimateGuesses(PasswordMatch m, int passwordLength) {
    if (m.guesses > 0) return m.guesses;
    var minGuesses = 1.0;
    if (m.length < passwordLength) {
      minGuesses = m.length == 1
          ? _minSubmatchGuessesSingleChar
          : _minSubmatchGuessesMultiChar;
    }
    final guesses = switch (m.pattern) {
      PasswordPattern.bruteforce => math.max(
        math.pow(_bruteforceCardinality, m.length).toDouble(),
        m.length == 1
            ? _minSubmatchGuessesSingleChar + 1
            : _minSubmatchGuessesMultiChar + 1,
      ),
      PasswordPattern.dictionary =>
        m.rank *
            _uppercaseVariations(m.token) *
            _l33tVariations(m) *
            (m.reversed ? 2 : 1) *
            (m.otherLayout ? 2 : 1),
      PasswordPattern.spatial => _spatialGuesses(m),
      PasswordPattern.repeat => m.baseGuesses * m.repeatCount,
      PasswordPattern.sequence => _sequenceGuesses(m),
      PasswordPattern.year =>
        math.max((m.year - referenceYear).abs(), _minYearSpace).toDouble(),
      PasswordPattern.date =>
        math.max((m.year - referenceYear).abs(), _minYearSpace) *
            365.0 *
            (m.separator ? 4 : 1),
    };
    return m.guesses = math.max(guesses, minGuesses);
  }

  static double _uppercaseVariations(List<int> token) {
    var upper = 0;
    var lower = 0;
    for (final r in token) {
      final c = String.fromCharCode(r);
      if (c.toLowerCase() != c) upper++;
      if (c.toUpperCase() != c) lower++;
    }
    if (upper == 0) return 1;
    bool isUpper(int r) {
      final c = String.fromCharCode(r);
      return c.toLowerCase() != c;
    }

    final first = isUpper(token.first);
    final last = isUpper(token.last);
    final startUpper = first && upper == 1 && token.length > 1;
    final endUpper = last && upper == 1 && token.length > 1;
    final allUpper = lower == 0;
    if (startUpper || endUpper || allUpper) return 2;
    var variations = 0.0;
    for (var i = 1; i <= math.min(upper, lower); i++) {
      variations += _nCk(upper + lower, i);
    }
    return variations;
  }

  static double _l33tVariations(PasswordMatch m) {
    if (m.l33t.isEmpty) return 1;
    var variations = 1.0;
    final chars = _lowerRunes(m.token);
    for (final MapEntry(key: subbed, value: unsubbed) in m.l33t.entries) {
      final s = chars.where((c) => c == subbed).length;
      final u = chars.where((c) => c == unsubbed).length;
      if (s == 0 || u == 0) {
        variations *= 2;
      } else {
        var possibilities = 0.0;
        for (var i = 1; i <= math.min(u, s); i++) {
          possibilities += _nCk(u + s, i);
        }
        variations *= possibilities;
      }
    }
    return variations;
  }

  static double _spatialGuesses(PasswordMatch m) {
    final graph = keyboardGraphs.firstWhere((g) => g.name == m.graph);
    // Для цифровых блоков — параметры обычного, как в zxcvbn: близко.
    final reference = graph.shiftable
        ? keyboardGraphs.first
        : keyboardGraphs.firstWhere((g) => g.name == 'keypad');
    final s = reference.startingPositions.toDouble();
    final d = reference.averageDegree;
    var guesses = 0.0;
    final length = m.length;
    for (var i = 2; i <= length; i++) {
      final possibleTurns = math.min(m.turns, i - 1) + 1;
      for (var j = 1; j < possibleTurns; j++) {
        guesses += _nCk(i - 1, j - 1) * s * math.pow(d, j);
      }
    }
    if (m.shifted > 0) {
      final shifted = m.shifted;
      final unshifted = length - shifted;
      if (unshifted == 0) {
        guesses *= 2;
      } else {
        var variations = 0.0;
        for (var i = 1; i <= math.min(shifted, unshifted); i++) {
          variations += _nCk(shifted + unshifted, i);
        }
        guesses *= variations;
      }
    }
    return guesses;
  }

  static double _sequenceGuesses(PasswordMatch m) {
    final first = m.token.first;
    double base;
    if ('aAzZ019'.runes.contains(first)) {
      base = 4;
    } else if (_isDigit(first)) {
      base = 10;
    } else {
      base = 26;
    }
    if (!m.ascending) base *= 2;
    return base * m.length;
  }

  // --- вспомогательное ----------------------------------------------------

  static Map<String, int> _ranked(List<String> words) {
    final out = <String, int>{};
    for (var i = 0; i < words.length; i++) {
      out.putIfAbsent(words[i], () => i + 1);
    }
    return out;
  }

  /// Нижний регистр по символу; если строчная форма — не один символ
  /// (`İ`), символ остаётся как есть: индексы не должны сдвигаться.
  static List<String> _lower(List<int> runes) => [
    for (final r in runes)
      if (String.fromCharCode(r).toLowerCase() case final l
          when l.runes.length == 1)
        l
      else
        String.fromCharCode(r),
  ];

  static List<int> _lowerRunes(List<int> runes) => [
    for (final c in _lower(runes)) c.runes.single,
  ];

  static bool _same(List<int> a, List<int> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool _isDigit(int r) => r >= 0x30 && r <= 0x39;

  static int? _digits(List<int> runes, int start, int end) {
    var v = 0;
    for (var k = start; k < end; k++) {
      if (!_isDigit(runes[k])) return null;
      v = v * 10 + runes[k] - 0x30;
    }
    return v;
  }

  static double _factorial(int n) {
    var f = 1.0;
    for (var i = 2; i <= n; i++) {
      f *= i;
    }
    return f;
  }

  static double _nCk(int n, int k) {
    if (k > n) return 0;
    if (k == 0) return 1;
    var r = 1.0;
    var nn = n;
    for (var d = 1; d <= k; d++) {
      r = r * nn / d;
      nn--;
    }
    return r;
  }
}
