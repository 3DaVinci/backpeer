import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:test/test.dart';
import 'package:test_vectors/test_vectors.dart';

void main() {
  late CryptoProvider crypto;
  setUpAll(() async => crypto = await SodiumCryptoProvider.load());

  group('chunk-id', () {
    for (final c in vectorCases(loadVectors('crypto/chunk-id.json'))) {
      test(c['name'], () {
        final input = c['input']! as Map<String, Object?>;
        final hasher = ChunkIdHasher(
          crypto,
          SecretBytes(hexToBytes(input['chunkIdKey']! as String)),
        );
        final id = hasher.of(
          patternBytes(input['dataPattern']! as Map<String, Object?>),
        );
        final expected =
            (c['expected']! as Map<String, Object?>)['chunkId']! as String;
        expect('$id', expected);
        expect(id, ChunkId(hexToBytes(expected)));
        expect(id.hashCode, ChunkId(hexToBytes(expected)).hashCode);
      });
    }
  });

  test('разные ключи — разные идентификаторы одного чанка', () {
    final data = Uint8List.fromList([1, 2, 3]);
    final a = ChunkIdHasher(crypto, SecretBytes(Uint8List(32))).of(data);
    final b = ChunkIdHasher(
      crypto,
      SecretBytes(Uint8List(32)..[0] = 1),
    ).of(data);
    expect(a, isNot(b));
    expect({a, ChunkId(a.bytes)}, hasLength(1));
  });

  test('проверка длины', () {
    expect(() => ChunkId(Uint8List(31)), throwsArgumentError);
    expect(
      () => ChunkIdHasher(crypto, SecretBytes(Uint8List(16))),
      throwsArgumentError,
    );
  });

  test('bytes — копия', () {
    final id = ChunkId(Uint8List(32));
    id.bytes[0] = 9;
    expect(id.bytes[0], 0);
  });
}
