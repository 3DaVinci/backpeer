// Контракт FragmentStore: те же проверки — на локальных папках и потом на
// сетевой реализации (этап 3).

import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:test/test.dart';
import 'package:test_vectors/test_vectors.dart';

/// Фрагменты сегмента из случайного блоба.
List<Fragment> sampleFragments(
  CryptoProvider crypto, {
  int seed = 1,
  int k = 2,
  int n = 4,
  int length = 5000,
}) => encodeFragments(
  crypto,
  blob: splitmix64Bytes(seed, length),
  segmentId: Uint8List(32)..[0] = seed,
  k: k,
  n: n,
);

void fragmentStoreContract(
  Future<FragmentStore> Function() create,
  CryptoProvider Function() crypto,
) {
  late FragmentStore store;
  late List<Fragment> fragments;
  setUp(() async {
    store = await create();
    fragments = sampleFragments(crypto());
  });

  test('put возвращает fragment_id, get отдаёт те же байты', () async {
    final node = store.nodes.first;
    final bytes = fragments[0].toBytes();
    final id = await store.put(node, bytes);
    expect(id, fragments[0].header.fragmentId(crypto()));
    expect(await store.get(node, id), bytes);
    // Повторная запись — не ошибка.
    expect(await store.put(node, bytes), id);
  });

  test('has по порядку запроса, delete', () async {
    final node = store.nodes.first;
    final a = await store.put(node, fragments[0].toBytes());
    final b = fragments[1].header.fragmentId(crypto());
    expect(await store.has(node, [b, a]), [false, true]);
    await store.delete(node, a);
    await store.delete(node, a);
    expect(await store.has(node, [a]), [false]);
    await expectLater(
      store.get(node, a),
      throwsA(
        isA<StorageException>().having(
          (e) => e.problem,
          'problem',
          StorageProblem.notFound,
        ),
      ),
    );
  });

  test('узлы независимы', () async {
    final id = await store.put(store.nodes[0], fragments[0].toBytes());
    expect(await store.has(store.nodes[1], [id]), [false]);
  });

  test('узел отклоняет битый и чужой фрагмент', () async {
    final node = store.nodes.first;
    final broken = fragments[0].toBytes()..[0] ^= 1;
    await expectLater(
      store.put(node, broken),
      throwsA(isA<DataFormatException>()),
    );
    final tampered = fragments[0].toBytes()..[200] ^= 1;
    await expectLater(
      store.put(node, tampered),
      throwsA(isA<IntegrityException>()),
    );
    await expectLater(
      store.put(
        node,
        fragments[0].toBytes(),
        expectedFragmentId: fragments[1].header.fragmentId(crypto()),
      ),
      throwsA(isA<IntegrityException>()),
    );
    expect(await store.has(node, [fragments[0].header.fragmentId(crypto())]), [
      false,
    ]);
  });
}
