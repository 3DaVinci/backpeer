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

Uint8List hexToBytes(String hex) {
  final bytes = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] = int.parse(hex.substring(2 * i, 2 * i + 2), radix: 16);
  }
  return bytes;
}

String bytesToHex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
