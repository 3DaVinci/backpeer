import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:test/test.dart';
import 'package:test_vectors/test_vectors.dart';

void main() {
  late CryptoProvider crypto;
  setUpAll(() async => crypto = await SodiumCryptoProvider.load());

  GearTable gear(Map<String, Object?> input) => GearTable.derive(
    crypto,
    SecretBytes(hexToBytes(input['gearKey']! as String)),
  );

  test('gear', () {
    final c = vectorCases(loadVectors('format/gear.json')).single;
    final table = gear(c['input']! as Map<String, Object?>);
    final expected = (c['expected']! as Map<String, Object?>)['gear']!;
    expect([for (var i = 0; i < 256; i++) _hex64(table[i])], expected);
  });

  group('fastcdc', () {
    for (final c in vectorCases(loadVectors('format/fastcdc.json'))) {
      test(c['name'], () {
        final input = c['input']! as Map<String, Object?>;
        final data = input.containsKey('dataZeros')
            ? Uint8List(input['dataZeros']! as int)
            : patternBytes(input['dataPattern']! as Map<String, Object?>);
        expect(
          FastCdc(gear(input)).chunkLengths(data),
          (c['expected']! as Map<String, Object?>)['chunkLengths'],
        );
      });
    }
  });

  group('свойства', () {
    late FastCdc cdc;
    late Uint8List data;
    setUpAll(() {
      cdc = FastCdc(GearTable.derive(crypto, SecretBytes(Uint8List(32))));
      data = splitmix64Bytes(2026, 64 * 1024 * 1024);
    });

    test('средний размер на случайных данных — около 1,2 МиБ', () {
      final lengths = cdc.chunkLengths(data);
      final mean = data.length / lengths.length;
      expect(mean, inInclusiveRange(1.0 * 1024 * 1024, 1.45 * 1024 * 1024));
      expect(
        lengths.take(lengths.length - 1),
        everyElement(inInclusiveRange(FastCdc.minSize + 1, FastCdc.maxSize)),
      );
    });

    test('вставка байта в начало меняет не больше двух чанков', () {
      final shifted = Uint8List(data.length + 1)
        ..[0] = 0x5A
        ..setAll(1, data);
      final before = _chunkHashes(crypto, data, cdc.chunkLengths(data));
      final after = _chunkHashes(crypto, shifted, cdc.chunkLengths(shifted));
      expect(after.difference(before).length, lessThanOrEqualTo(2));
      expect(before.difference(after).length, lessThanOrEqualTo(2));
    });

    test('окно cut: start и end', () {
      final lengths = cdc.chunkLengths(data);
      expect(cdc.cut(data, lengths[0]), lengths[1]);
      expect(cdc.cut(data, 0, 1000), 1000);
      expect(() => cdc.cut(data, 10, 5), throwsRangeError);
    });
  });
}

Set<String> _chunkHashes(
  CryptoProvider crypto,
  Uint8List data,
  List<int> lengths,
) {
  final out = <String>{};
  var pos = 0;
  for (final length in lengths) {
    out.add(
      bytesToHex(
        crypto.blake2b256(Uint8List.sublistView(data, pos, pos + length)),
      ),
    );
    pos += length;
  }
  return out;
}

String _hex64(int value) =>
    (value >>> 32).toRadixString(16).padLeft(8, '0') +
    (value & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0');
