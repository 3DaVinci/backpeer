/// Правила исключения в синтаксисе `.gitignore`:
///
/// - пустые строки и строки с `#` в начале пропускаются;
/// - `!шаблон` возвращает ранее исключённое (кроме содержимого
///   исключённого каталога — в него обход не заходит);
/// - `шаблон/` — только каталоги;
/// - шаблон со `/` в начале или в середине привязан к корню бэкапа, без
///   `/` — сравнивается с именем на любой глубине;
/// - `*` и `?` не переходят через `/`, `**` — любое число каталогов,
///   `[abc]`, `[a-z]`, `[!a]` — классы символов, `\` экранирует символ.
///
/// Пути — относительно корня бэкапа, с `/` как разделителем. Последнее
/// совпавшее правило решает.
final class ExcludeRules {
  factory(Iterable<String> lines, {bool caseSensitive = true}) =>
      ExcludeRules._([
        for (final line in lines)
          ?_Rule.parse(line, caseSensitive: caseSensitive),
      ]);

  const new _(this._rules);

  static const none = ExcludeRules._([]);

  final List<_Rule> _rules;

  bool get isEmpty => _rules.isEmpty;

  /// Исключён ли [relativePath] (без `/` в начале и в конце).
  bool excludes(String relativePath, {required bool isDirectory}) {
    var excluded = false;
    for (final rule in _rules) {
      if (rule.directoryOnly && !isDirectory) continue;
      // Как git: каталог сравнивается и с завершающим «/», поэтому
      // «foo/**» исключает и сам каталог foo.
      if (rule.pattern.hasMatch(relativePath) ||
          (isDirectory && rule.pattern.hasMatch('$relativePath/'))) {
        excluded = !rule.negated;
      }
    }
    return excluded;
  }
}

final class _Rule {
  new(this.pattern, {required this.negated, required this.directoryOnly});

  static _Rule? parse(String line, {required bool caseSensitive}) {
    var text = _trimTrailingSpaces(line);
    if (text.isEmpty || text.startsWith('#')) return null;
    var negated = false;
    if (text.startsWith('!')) {
      negated = true;
      text = text.substring(1);
    } else if (text.startsWith(r'\!') || text.startsWith(r'\#')) {
      text = text.substring(1);
    }
    var directoryOnly = false;
    if (text.endsWith('/') && !text.endsWith(r'\/')) {
      directoryOnly = true;
      text = text.substring(0, text.length - 1);
    }
    if (text.isEmpty) return null;
    final anchored = text.contains('/');
    if (text.startsWith('/')) text = text.substring(1);
    final body = _translate(text);
    final source = anchored ? '^$body\$' : '^(?:.*/)?$body\$';
    return _Rule(
      RegExp(source, caseSensitive: caseSensitive),
      negated: negated,
      directoryOnly: directoryOnly,
    );
  }

  final RegExp pattern;
  final bool negated;
  final bool directoryOnly;

  static String _trimTrailingSpaces(String line) {
    var end = line.length;
    while (end > 0 &&
        line[end - 1] == ' ' &&
        !(end > 1 && line[end - 2] == r'\')) {
      end--;
    }
    return line.substring(0, end);
  }

  static String _translate(String glob) {
    final out = StringBuffer();
    var i = 0;
    while (i < glob.length) {
      final c = glob[i];
      if (c == r'\' && i + 1 < glob.length) {
        out.write(RegExp.escape(glob[i + 1]));
        i += 2;
      } else if (glob.startsWith('**', i)) {
        final atStart = i == 0 || glob[i - 1] == '/';
        final atEnd = i + 2 == glob.length || glob[i + 2] == '/';
        if (atStart && i + 2 < glob.length && glob[i + 2] == '/') {
          out.write('(?:.*/)?'); // «**/» — ноль или больше каталогов
          i += 3;
        } else if (atStart && atEnd) {
          out.write('.*'); // «/**» в конце — всё внутри
          i += 2;
        } else {
          out.write('[^/]*'); // «**» внутри имени — как «*»
          i += 2;
        }
      } else if (c == '*') {
        out.write('[^/]*');
        i++;
      } else if (c == '?') {
        out.write('[^/]');
        i++;
      } else if (c == '[') {
        final close = glob.indexOf(']', i + 2);
        if (close < 0) {
          out.write(r'\[');
          i++;
        } else {
          var cls = glob.substring(i + 1, close);
          if (cls.startsWith('!')) cls = '^${cls.substring(1)}';
          out.write('[${cls.replaceAll(r'\', r'\\')}]');
          i = close + 1;
        }
      } else {
        out.write(RegExp.escape(c));
        i++;
      }
    }
    return out.toString();
  }
}
