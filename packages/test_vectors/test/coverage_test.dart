// Сторож для docs/spec/test-vectors.md: каждый файл векторов проверяется
// хотя бы одним тестом пакетов, а поле spec совпадает с путём файла.

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  final root = _repoRoot();
  final vectorsDir = Directory('${root.path}/test-vectors');
  final files =
      vectorsDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .map((f) => f.path.substring(vectorsDir.path.length + 1))
          .toList()
        ..sort();
  final testSources = [
    for (final pkg in Directory('${root.path}/packages').listSync())
      if (pkg is Directory &&
          !pkg.path.endsWith('test_vectors') &&
          Directory('${pkg.path}/test').existsSync())
        for (final f in Directory('${pkg.path}/test').listSync(recursive: true))
          if (f is File && f.path.endsWith('.dart')) f.readAsStringSync(),
  ].join('\n');

  test('файлы векторов найдены', () => expect(files, isNotEmpty));

  for (final name in files) {
    group(name, () {
      test('проверяется тестами пакетов', () {
        expect(testSources, contains("'$name'"));
      });

      test('поле spec совпадает с путём', () {
        final doc = jsonDecode(
          File('${vectorsDir.path}/$name').readAsStringSync(),
        ) as Map<String, Object?>;
        expect(doc['spec'], name.substring(0, name.length - '.json'.length));
        expect(doc['specVersion'], isA<int>());
        expect(doc['cases'], isNotEmpty);
      });
    });
  }
}

Directory _repoRoot() {
  var dir = Directory.current.absolute;
  while (!Directory('${dir.path}/test-vectors').existsSync()) {
    if (dir.parent.path == dir.path) {
      throw StateError('Не найден test-vectors/');
    }
    dir = dir.parent;
  }
  return dir;
}
