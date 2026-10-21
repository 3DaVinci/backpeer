import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:test/test.dart';

import 'support/object_store_contract.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('fs-objects-'));
  tearDown(() => dir.deleteSync(recursive: true));

  group('LocalObjectStore', () {
    objectStoreContract(
      () async => LocalObjectStore(Directory('${dir.path}/o')),
    );

    test('посторонние и временные файлы в папке не видны', () async {
      final store = LocalObjectStore(dir);
      await store.put(ObjectKind.snapshot, Uint8List(32), Uint8List(1));
      File('${dir.path}/snapshot/junk.txt').writeAsStringSync('x');
      File('${dir.path}/snapshot/${'0' * 64}.1.blob.tmp-1')
          .writeAsStringSync('x');
      expect(await store.list(ObjectKind.snapshot), hasLength(1));
    });
  });

  group('placeFragments', () {
    final nodes = [for (var i = 0; i < 25; i++) 'node-$i'];

    test('n разных узлов, начало зависит от сегмента', () {
      final starts = <String>{};
      for (var s = 0; s < 50; s++) {
        final segmentId = Uint8List(32)..[3] = s;
        final placed = placeFragments(segmentId, nodes, 20);
        expect(placed, hasLength(20));
        expect(placed.toSet(), hasLength(20), reason: 'по фрагменту на узел');
        starts.add(placed.first);
      }
      expect(starts.length, greaterThan(10));
    });

    test('узлов меньше n или повторы — ошибка', () {
      expect(
        () => placeFragments(Uint8List(32), nodes, 26),
        throwsArgumentError,
      );
      expect(
        () => placeFragments(Uint8List(32), ['a', 'a', 'b'], 2),
        throwsArgumentError,
      );
    });
  });
}
