// Проверяет правило зависимостей (задача 0.1.6): пакеты ядра не зависят
// от Flutter ни напрямую, ни транзитивно. Нужно, чтобы демон и CLI
// собирались через `dart compile exe` без Flutter SDK.
//
// Сначала обновляет разрешение зависимостей (`dart pub get`), затем читает
// граф пакетов `.dart_tool/package_graph.json`, который пишет pub.
// Без этого шага правка pubspec.yaml отдельного пакета не попала бы в граф.
// Запуск из корня репозитория:
//
//   dart run tool/check_no_flutter.dart

import 'dart:convert';
import 'dart:io';

/// Пакеты, которым запрещено зависеть от Flutter.
const restrictedPackages = [
  'core',
  'protocol',
  'cli',
  'node',
  'coordinator',
  'relay',
  'test_vectors',
];

/// Пакеты из Flutter SDK.
const flutterPackages = {
  'flutter',
  'flutter_driver',
  'flutter_localizations',
  'flutter_test',
  'flutter_web_plugins',
  'integration_test',
  'sky_engine',
};

void main() {
  final pubGet = Process.runSync(Platform.resolvedExecutable, ['pub', 'get']);
  if (pubGet.exitCode != 0) {
    stderr
      ..writeln('Не удалось разрешить зависимости (`dart pub get`):')
      ..write(pubGet.stdout)
      ..write(pubGet.stderr);
    exit(2);
  }

  final graphFile = File('.dart_tool/package_graph.json');

  final graph =
      jsonDecode(graphFile.readAsStringSync()) as Map<String, Object?>;
  final dependencies = <String, List<String>>{};
  final devDependencies = <String, List<String>>{};
  for (final entry in graph['packages']! as List<Object?>) {
    final package = entry! as Map<String, Object?>;
    final name = package['name']! as String;
    dependencies[name] = _names(package['dependencies']);
    devDependencies[name] = _names(package['devDependencies']);
  }

  final violations = <String>[];
  for (final root in restrictedPackages) {
    if (!dependencies.containsKey(root)) {
      violations.add('$root: пакет не найден в графе зависимостей');
      continue;
    }
    // Свои dev-зависимости пакета тоже проверяем: тесты на flutter_test
    // требовали бы Flutter SDK. Транзитивно идём только по обычным.
    final start = [...dependencies[root]!, ...devDependencies[root]!];
    final path = _findFlutter(root, start, dependencies);
    if (path != null) violations.add(path.join(' -> '));
  }

  if (violations.isEmpty) {
    stdout.writeln(
      'OK: ${restrictedPackages.join(', ')} не зависят от Flutter.',
    );
    return;
  }
  stderr
    ..writeln('Пакеты ядра не должны зависеть от Flutter (см. CLAUDE.md):')
    ..writeln(violations.map((v) => '  $v').join('\n'));
  exit(1);
}

List<String> _names(Object? list) =>
    (list as List<Object?>?)?.cast<String>() ?? const [];

/// Поиск в ширину от [root]; возвращает цепочку до первого пакета Flutter.
List<String>? _findFlutter(
  String root,
  List<String> start,
  Map<String, List<String>> dependencies,
) {
  final parent = <String, String>{for (final name in start) name: root};
  final queue = [...start];
  while (queue.isNotEmpty) {
    final name = queue.removeAt(0);
    if (flutterPackages.contains(name)) {
      final path = [name];
      var current = name;
      while (current != root) {
        current = parent[current]!;
        path.insert(0, current);
      }
      return path;
    }
    for (final next in dependencies[name] ?? const <String>[]) {
      if (next == root || parent.containsKey(next)) continue;
      parent[next] = name;
      queue.add(next);
    }
  }
  return null;
}
