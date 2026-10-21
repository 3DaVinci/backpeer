import 'package:test/test.dart';
import 'package:test_vectors/test_vectors.dart';

void main() {
  test('splitmix64: первый выход при seed 0 — 0xE220A8397B1DCDAF', () {
    expect(toHex(splitmix64Bytes(0, 8)), 'afcd1d7b39a820e2');
  });

  test('splitmix64: последний выход обрезается до длины', () {
    final full = splitmix64Bytes(14, 24);
    expect(splitmix64Bytes(14, 21), full.sublist(0, 21));
  });

  test('patternBytes отвергает неизвестный генератор', () {
    expect(
      () => patternBytes({'type': 'zeros', 'seed': 0, 'length': 1}),
      throwsArgumentError,
    );
  });

  test('загрузка векторов из каталога test-vectors/', () {
    final vectors = loadVectors('erasure/reed-solomon.json');
    expect(vectors['spec'], 'erasure/reed-solomon');
    expect(vectorCases(vectors), isNotEmpty);
  });

  test('hex туда и обратно', () {
    expect(toHex(fromHex('00ff7a')), '00ff7a');
  });
}
