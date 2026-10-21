// Контракт ObjectStore: те же проверки прогоняются на локальной реализации
// и потом на сетевой (координатор, этап 2).

import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:test/test.dart';

void objectStoreContract(Future<ObjectStore> Function() create) {
  late ObjectStore store;
  setUp(() async => store = await create());

  Uint8List id(int b) => Uint8List(32)..[0] = b;
  Uint8List blob(int n) => Uint8List.fromList(List.generate(n, (i) => i));

  test('put, get, list по возрастанию идентификатора', () async {
    await store.put(ObjectKind.snapshot, id(2), blob(10), sequence: 5);
    await store.put(ObjectKind.snapshot, id(1), blob(3), sequence: 4);
    await store.put(ObjectKind.indexObject, id(1), blob(7));
    expect(await store.get(ObjectKind.snapshot, id(2)), blob(10));
    final listed = await store.list(ObjectKind.snapshot);
    expect(listed.map((o) => o.id[0]), [1, 2]);
    expect(listed.map((o) => o.sequence), [4, 5]);
    expect(listed.map((o) => o.size), [3, 10]);
    expect((await store.list(ObjectKind.indexObject)).single.sequence, 0);
  });

  test('повторный put заменяет', () async {
    await store.put(ObjectKind.snapshot, id(1), blob(3), sequence: 1);
    await store.put(ObjectKind.snapshot, id(1), blob(5), sequence: 2);
    final listed = await store.list(ObjectKind.snapshot);
    expect(listed.single.sequence, 2);
    expect(await store.get(ObjectKind.snapshot, id(1)), blob(5));
  });

  test('delete и отсутствующий объект', () async {
    await store.put(ObjectKind.snapshot, id(1), blob(3));
    await store.delete(ObjectKind.snapshot, id(1));
    await store.delete(ObjectKind.snapshot, id(1));
    expect(await store.list(ObjectKind.snapshot), isEmpty);
    await expectLater(
      store.get(ObjectKind.snapshot, id(1)),
      throwsA(
        isA<StorageException>().having(
          (e) => e.problem,
          'problem',
          StorageProblem.notFound,
        ),
      ),
    );
  });

  test('виды объектов не пересекаются', () async {
    await store.put(ObjectKind.indexObject, id(1), blob(3));
    await expectLater(
      store.get(ObjectKind.snapshot, id(1)),
      throwsA(isA<StorageException>()),
    );
  });
}
