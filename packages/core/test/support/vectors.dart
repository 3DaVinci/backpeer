// Тесты работают только в Dart VM (64-битный int), JavaScript не нужен.
// ignore_for_file: avoid_js_rounded_ints

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Загружает файл тестовых векторов из каталога test-vectors/ в корне
/// репозитория (формат: docs/spec/test-vectors.md).
Map<String, Object?> loadVectors(String fileName) {
  var dir = Directory.current.absolute;
  while (!File('${dir.path}/test-vectors/$fileName').existsSync()) {
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('Не найден test-vectors/$fileName');
    }
    dir = parent;
  }
  final text = File('${dir.path}/test-vectors/$fileName').readAsStringSync();
  return jsonDecode(text) as Map<String, Object?>;
}

/// Случаи (`cases`) из файла векторов.
List<Map<String, Object?>> vectorCases(Map<String, Object?> vectors) =>
    (vectors['cases']! as List<Object?>).cast<Map<String, Object?>>();

/// Детерминированные данные из docs/spec/test-vectors.md: little-endian
/// байты последовательных выходов splitmix64. Арифметика `int` на нативной
/// платформе — 64-битная с переполнением, что и нужно алгоритму.
Uint8List splitmix64Bytes(int seed, int length) {
  final out = Uint8List(length);
  var state = seed;
  var i = 0;
  while (i < length) {
    state += 0x9E3779B97F4A7C15;
    var z = state;
    z = (z ^ (z >>> 30)) * 0xBF58476D1CE4E5B9;
    z = (z ^ (z >>> 27)) * 0x94D049BB133111EB;
    z ^= z >>> 31;
    for (var b = 0; b < 8 && i < length; b++, i++) {
      out[i] = (z >>> (8 * b)) & 0xFF;
    }
  }
  return out;
}

/// Данные из описания `{"type": "splitmix64-le", "seed": …, "length": …}`.
Uint8List patternBytes(Map<String, Object?> pattern) {
  if (pattern['type'] != 'splitmix64-le') {
    throw ArgumentError('Неизвестный генератор данных: ${pattern['type']}');
  }
  return splitmix64Bytes(pattern['seed']! as int, pattern['length']! as int);
}
