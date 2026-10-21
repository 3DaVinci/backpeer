import 'package:fixnum/fixnum.dart';
import 'package:protocol/protocol.dart';
import 'package:test/test.dart';

import 'package:test_vectors/test_vectors.dart';

void main() {
  // Векторы test-vectors/manifest/encoding.json закодированы protoc.
  // Разбор и повторная сериализация в Dart обязаны дать те же байты:
  // от этого зависит дедупликация деревьев каталогов (manifest.md, раздел 5).
  group('каноническая сериализация совпадает с protoc', () {
    for (final c in vectorCases(loadVectors('manifest/encoding.json'))) {
      final type = (c['input']! as Map<String, Object?>)['messageType'];
      final bytes = fromHex(
        (c['expected']! as Map<String, Object?>)['bytes']! as String,
      );
      test(c['name'], () {
        final message = switch (type) {
          'fs.v1.Tree' => Tree.fromBuffer(bytes),
          'fs.v1.Snapshot' => Snapshot.fromBuffer(bytes),
          'fs.v1.Index' => Index.fromBuffer(bytes),
          _ => throw StateError('Неизвестный тип $type'),
        };
        expect(message.unknownFields.isEmpty, isTrue);
        expect(toHex(message.writeToBuffer()), toHex(bytes));
      });
    }
  });

  test('дерево, собранное в Dart, совпадает с protoc', () {
    final vectors = vectorCases(loadVectors('manifest/encoding.json'));
    final expected = vectors.firstWhere(
      (c) => c['name'] == 'tree-file-dir-symlink',
    );
    List<int> id(int b) => List.filled(32, b);
    final tree = Tree(
      nodes: [
        Node(
          name: 'a.txt'.codeUnits,
          type: NodeType.NODE_TYPE_FILE,
          size: Int64(1000),
          mtimeNs: Int64.parseInt('1700000000123456789'),
          mode: 420,
          uid: 1000,
          gid: 1000,
          content: [id(1), id(2)],
        ),
        Node(
          name: 'dir'.codeUnits,
          type: NodeType.NODE_TYPE_DIRECTORY,
          mtimeNs: Int64(-5),
          mode: 493,
          subtree: [id(3)],
        ),
        Node(
          name: 'link'.codeUnits,
          type: NodeType.NODE_TYPE_SYMLINK,
          symlinkTarget: 'a.txt'.codeUnits,
        ),
      ],
    );
    expect(
      toHex(tree.writeToBuffer()),
      (expected['expected']! as Map<String, Object?>)['bytes'],
    );
  });
}
