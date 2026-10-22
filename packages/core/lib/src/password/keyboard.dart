/// Клавиатуры для оценки стойкости пароля: графы соседства клавиш для
/// поиска узоров вроде `qwerty` и `1qaz2wsx` и соответствие раскладок
/// ЙЦУКЕН и QWERTY. Графы строятся так же, как в zxcvbn 4.4.2
/// (`data-scripts/build_keyboard_adjacency_graphs.py`).
library;

/// Граф соседства клавиш. Для символа — список соседей по направлениям;
/// сосед — строка символов одной клавиши (`"2@"`: без Shift и с Shift)
/// или `null`, если клавиши нет.
final class KeyboardGraph {
  new _(this.name, this.adjacency, {required this.shiftable})
    : startingPositions = adjacency.length,
      averageDegree =
          adjacency.values
              .map((n) => n.where((k) => k != null).length)
              .fold(0, (a, b) => a + b) /
          adjacency.length;

  /// Ряды со сдвигом (обычная клавиатура): 6 соседей.
  factory slanted(String name, String layout) =>
      KeyboardGraph._(name, _build(layout, slanted: true), shiftable: true);

  /// Ровная сетка (цифровой блок): 8 соседей.
  factory aligned(String name, String layout) =>
      KeyboardGraph._(name, _build(layout, slanted: false), shiftable: false);

  final String name;
  final Map<String, List<String?>> adjacency;

  /// Есть ли у клавиш второй символ с Shift.
  final bool shiftable;

  final int startingPositions;
  final double averageDegree;

  static Map<String, List<String?>> _build(
    String layout, {
    required bool slanted,
  }) {
    final positions = <(int, int), String>{};
    // Как в zxcvbn, строка 0 — пустая (у Python-строки в начале перевод
    // строки, Dart его отбрасывает): от номера строки зависит сдвиг ряда.
    final lines = ['', ...layout.split('\n')];
    final tokenSize = layout.trim().split(RegExp(r'\s+')).first.length;
    final xUnit = tokenSize + 1;
    for (var y = 0; y < lines.length; y++) {
      final line = lines[y];
      final slant = slanted ? y - 1 : 0;
      for (final m in RegExp(r'\S+').allMatches(line)) {
        final offset = m.start - slant;
        assert(offset % xUnit == 0, 'клавиша не на сетке: ${m[0]}');
        positions[(offset ~/ xUnit, y)] = m[0]!;
      }
    }
    final graph = <String, List<String?>>{};
    for (final MapEntry(key: (x, y), value: chars) in positions.entries) {
      final around = slanted
          ? [
              (x - 1, y),
              (x, y - 1),
              (x + 1, y - 1),
              (x + 1, y),
              (x, y + 1),
              (x - 1, y + 1),
            ]
          : [
              (x - 1, y),
              (x - 1, y - 1),
              (x, y - 1),
              (x + 1, y - 1),
              (x + 1, y),
              (x + 1, y + 1),
              (x, y + 1),
              (x - 1, y + 1),
            ];
      for (final c in chars.split('')) {
        graph[c] = [for (final p in around) positions[p]];
      }
    }
    return graph;
  }
}

/// Графы, которые проверяет оценка, — как в zxcvbn.
final List<KeyboardGraph> keyboardGraphs = [
  KeyboardGraph.slanted('qwerty', _qwerty),
  KeyboardGraph.slanted('dvorak', _dvorak),
  KeyboardGraph.aligned('keypad', _keypad),
  KeyboardGraph.aligned('mac_keypad', _macKeypad),
];

/// Буква ЙЦУКЕН → символ той же клавиши в QWERTY (`п` → `g`).
final Map<int, int> cyrillicToLatinKey = {
  for (var i = 0; i < _cyrillicKeys.length; i++)
    _cyrillicKeys.codeUnitAt(i): _latinKeys.codeUnitAt(i),
};

/// Символ QWERTY → буква ЙЦУКЕН той же клавиши (`g` → `п`, `;` → `ж`).
final Map<int, int> latinToCyrillicKey = {
  for (final MapEntry(:key, :value) in cyrillicToLatinKey.entries) value: key,
};

// Клавиши в одном порядке: строчные, затем заглавные (с Shift).
const _cyrillicKeys =
    'ёйцукенгшщзхъфывапролджэячсмитьбю'
    'ЁЙЦУКЕНГШЩЗХЪФЫВАПРОЛДЖЭЯЧСМИТЬБЮ';
const _latinKeys =
    "`qwertyuiop[]asdfghjkl;'zxcvbnm,."
    '~QWERTYUIOP{}ASDFGHJKL:"ZXCVBNM<>';

const _qwerty = r'''
`~ 1! 2@ 3# 4$ 5% 6^ 7& 8* 9( 0) -_ =+
    qQ wW eE rR tT yY uU iI oO pP [{ ]} \|
     aA sS dD fF gG hH jJ kK lL ;: '"
      zZ xX cC vV bB nN mM ,< .> /?
''';

const _dvorak = r'''
`~ 1! 2@ 3# 4$ 5% 6^ 7& 8* 9( 0) [{ ]}
    '" ,< .> pP yY fF gG cC rR lL /? =+ \|
     aA oO eE uU iI dD hH tT nN sS -_
      ;: qQ jJ kK xX bB mM wW vV zZ
''';

const _keypad = '''
  / * -
7 8 9 +
4 5 6
1 2 3
  0 .
''';

const _macKeypad = '''
  = / *
7 8 9 -
4 5 6 +
1 2 3
  0 .
''';
