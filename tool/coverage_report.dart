// Сводит отчёты о покрытии всех пакетов в один (задача 0.2.1).
//
// Перед запуском каждый пакет пишет `coverage/lcov.info`:
//   dart test --coverage-path=coverage/lcov.info   (Dart-пакеты)
//   dart test -t serial --coverage-path=coverage/serial.lcov.info
//                                                  (тесты с тегом serial)
//   flutter test --coverage                        (Flutter-приложение)
//
// Результат:
//   coverage/lcov.info      общий lcov с путями от корня репозитория;
//   coverage/cobertura.xml  отчёт Cobertura для показа покрытия в MR GitLab;
//   строка «Coverage: NN.NN%» для поля `coverage:` задания GitLab CI
//   (латиницей, чтобы не зависеть от поддержки Unicode в регулярном
//   выражении GitLab).

import 'dart:io';

void main() {
  final root = Directory.current.absolute.uri;
  final files = <String, Map<int, int>>{};

  for (final dir in ['packages', 'apps']) {
    final parent = Directory(dir);
    if (!parent.existsSync()) continue;
    for (final package in parent.listSync().whereType<Directory>()) {
      // serial.lcov.info — отдельный прогон тестов с тегом serial
      // (скрипт coverage-serial).
      for (final name in ['lcov.info', 'serial.lcov.info']) {
        final lcov = File('${package.path}/coverage/$name');
        if (!lcov.existsSync()) continue;
        _parseLcov(lcov, package.absolute.uri, root, files);
      }
    }
  }
  if (files.isEmpty) {
    stderr.writeln('Не найдено ни одного coverage/lcov.info в пакетах.');
    exit(1);
  }

  final sorted = files.keys.toList()..sort();
  var linesValid = 0;
  var linesCovered = 0;
  for (final lines in files.values) {
    linesValid += lines.length;
    linesCovered += lines.values.where((hits) => hits > 0).length;
  }

  Directory('coverage').createSync();
  File('coverage/lcov.info').writeAsStringSync(_lcov(sorted, files));
  File('coverage/cobertura.xml')
      .writeAsStringSync(_cobertura(sorted, files, linesValid, linesCovered));

  final percent = linesValid == 0 ? 100.0 : 100 * linesCovered / linesValid;
  stdout.writeln(
    'Coverage: ${percent.toStringAsFixed(2)}% '
    '($linesCovered of $linesValid lines, ${files.length} files)',
  );
}

/// Читает lcov и добавляет строки в [files]. Пути в lcov бывают абсолютными
/// (`dart test`) и относительными от пакета (`flutter test`); приводим их
/// к путям от корня репозитория.
void _parseLcov(
  File lcov,
  Uri packageDir,
  Uri root,
  Map<String, Map<int, int>> files,
) {
  Map<int, int>? current;
  for (final line in lcov.readAsLinesSync()) {
    if (line.startsWith('SF:')) {
      final path = line.substring(3);
      final absolute = File(path).isAbsolute
          ? Uri.file(path)
          : packageDir.resolveUri(Uri.file(path));
      final relative = absolute.path.substring(root.path.length);
      current = files.putIfAbsent(relative, () => {});
    } else if (line.startsWith('DA:') && current != null) {
      final parts = line.substring(3).split(',');
      final number = int.parse(parts[0]);
      final hits = int.parse(parts[1]);
      current[number] = (current[number] ?? 0) + hits;
    } else if (line == 'end_of_record') {
      current = null;
    }
  }
}

String _lcov(List<String> sorted, Map<String, Map<int, int>> files) {
  final out = StringBuffer();
  for (final path in sorted) {
    final lines = files[path]!;
    final numbers = lines.keys.toList()..sort();
    out.writeln('SF:$path');
    for (final number in numbers) {
      out.writeln('DA:$number,${lines[number]}');
    }
    out
      ..writeln('LF:${lines.length}')
      ..writeln('LH:${lines.values.where((hits) => hits > 0).length}')
      ..writeln('end_of_record');
  }
  return out.toString();
}

String _cobertura(
  List<String> sorted,
  Map<String, Map<int, int>> files,
  int linesValid,
  int linesCovered,
) {
  String rate(int covered, int valid) =>
      valid == 0 ? '1' : (covered / valid).toStringAsFixed(4);
  final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final out = StringBuffer()
    ..writeln('<?xml version="1.0" ?>')
    ..writeln(
      '<coverage line-rate="${rate(linesCovered, linesValid)}" '
      'branch-rate="0" lines-covered="$linesCovered" '
      'lines-valid="$linesValid" branches-covered="0" branches-valid="0" '
      'complexity="0" version="1" timestamp="$timestamp">',
    )
    ..writeln('  <sources><source>.</source></sources>')
    ..writeln('  <packages>');

  // Пакет Cobertura — каталог пакета монорепозитория (packages/core и т. п.).
  final byPackage = <String, List<String>>{};
  for (final path in sorted) {
    final segments = path.split('/');
    final package = segments.length > 2
        ? segments.take(2).join('/')
        : segments.first;
    byPackage.putIfAbsent(package, () => []).add(path);
  }

  for (final MapEntry(key: package, value: paths) in byPackage.entries) {
    var valid = 0;
    var covered = 0;
    for (final path in paths) {
      valid += files[path]!.length;
      covered += files[path]!.values.where((hits) => hits > 0).length;
    }
    out
      ..writeln(
        '    <package name="${_xml(package)}" '
        'line-rate="${rate(covered, valid)}" branch-rate="0" complexity="0">',
      )
      ..writeln('      <classes>');
    for (final path in paths) {
      final lines = files[path]!;
      final numbers = lines.keys.toList()..sort();
      final fileCovered = lines.values.where((hits) => hits > 0).length;
      out
        ..writeln(
          '        <class name="${_xml(path)}" filename="${_xml(path)}" '
          'line-rate="${rate(fileCovered, lines.length)}" branch-rate="0" '
          'complexity="0">',
        )
        ..writeln('          <methods/>')
        ..writeln('          <lines>');
      for (final number in numbers) {
        out.writeln(
          '            <line number="$number" hits="${lines[number]}"/>',
        );
      }
      out
        ..writeln('          </lines>')
        ..writeln('        </class>');
    }
    out
      ..writeln('      </classes>')
      ..writeln('    </package>');
  }
  out
    ..writeln('  </packages>')
    ..writeln('</coverage>');
  return out.toString();
}

String _xml(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
