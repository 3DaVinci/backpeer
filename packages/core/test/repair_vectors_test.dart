// Векторы ремонта test-vectors/format/repair.json (protocol.md,
// раздел 4.14; генератор tool/format_vectors.py): пересоздание недостающих
// фрагментов из любых k байт в байт как при полном кодировании.

import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:test/test.dart';
import 'package:test_vectors/test_vectors.dart';

void main() {
  late CryptoProvider crypto;
  setUpAll(() async => crypto = await SodiumCryptoProvider.load());

  for (final c in vectorCases(loadVectors('format/repair.json'))) {
    final input = c['input']! as Map<String, Object?>;
    final expected = c['expected']! as Map<String, Object?>;
    test(c['name'], () {
      final fragments = [
        for (final f in input['fragments']! as List<Object?>)
          Fragment.parse(hexToBytes(f! as String)),
      ];
      final indexes = (input['indexes']! as List<Object?>).cast<int>();
      final ids = {
        for (final MapEntry(:key, :value)
            in (input['expectedFragmentIds']! as Map<String, Object?>).entries)
          int.parse(key): hexToBytes(value! as String),
      };
      List<Fragment> rebuild() => rebuildFragments(
        crypto,
        fragments,
        indexes,
        expectedFragmentIds: ids,
      );

      switch (expected['error']) {
        case 'insufficient':
          expect(rebuild, throwsA(isA<InsufficientShardsException>()));
        case 'integrity':
          expect(rebuild, throwsA(isA<IntegrityException>()));
        case null:
          final rebuilt = rebuild();
          final want = (expected['fragments']! as List<Object?>)
              .cast<Map<String, Object?>>();
          expect(rebuilt, hasLength(want.length));
          for (var i = 0; i < want.length; i++) {
            expect(rebuilt[i].header.index, want[i]['index']);
            expect(bytesToHex(rebuilt[i].toBytes()), want[i]['bytes']);
            expect(
              bytesToHex(rebuilt[i].header.fragmentId(crypto)),
              want[i]['fragmentId'],
            );
            rebuilt[i].verify(
              crypto,
              expectedFragmentId: hexToBytes(want[i]['fragmentId']! as String),
            );
          }
        default:
          fail('неизвестная ошибка ${expected['error']}');
      }
    });
  }

  test('номер не меньше n — ошибка программы', () {
    final fragments = encodeFragments(
      crypto,
      blob: Uint8List(300),
      segmentId: Uint8List(32),
      k: 2,
      n: 4,
    );
    expect(
      () => rebuildFragments(crypto, fragments.sublist(0, 2), [4]),
      throwsRangeError,
    );
  });
}
