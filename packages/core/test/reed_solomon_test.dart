import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:test/test.dart';

import 'support/vectors.dart';

void main() {
  final vectors = loadVectors('erasure/reed-solomon.json');

  group('ReedSolomon совпадает с reed-solomon-erasure', () {
    for (final testCase in vectorCases(vectors)) {
      final input = testCase['input']! as Map<String, Object?>;
      final expected = testCase['expected']! as Map<String, Object?>;
      final k = input['dataShards']! as int;
      final n = input['totalShards']! as int;
      final data = [
        for (final hex in (input['data']! as List<Object?>).cast<String>())
          hexToBytes(hex),
      ];
      final parity = (expected['parity']! as List<Object?>).cast<String>();
      final erased =
          ((testCase['reconstruct']! as Map<String, Object?>)['erased']!
                  as List<Object?>)
              .cast<int>();

      test('${testCase['name']}: encode', () {
        final shards = [
          ...data.map(Uint8List.fromList),
          for (var i = k; i < n; i++) Uint8List(data.first.length),
        ];
        ReedSolomon(k, n - k).encode(shards);
        expect(shards.sublist(k).map(bytesToHex).toList(), parity);
      });

      test('${testCase['name']}: reconstruct', () {
        final full = [...data, ...parity.map(hexToBytes)];
        final shards = <Uint8List?>[...full.map(Uint8List.fromList)];
        for (final e in erased) {
          shards[e] = null;
        }
        ReedSolomon(k, n - k).reconstruct(shards);
        expect(
          shards.map((s) => bytesToHex(s!)).toList(),
          full.map(bytesToHex).toList(),
        );
      });
    }
  });

  test('слишком мало фрагментов — ошибка', () {
    final rs = ReedSolomon(2, 1);
    expect(
      () => rs.reconstruct([Uint8List(4), null, null]),
      throwsA(isA<InsufficientShardsException>()),
    );
  });
}
