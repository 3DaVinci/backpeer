// Проверка векторов docs/spec/data-format.md независимой реализацией на
// Dart. Векторы получены эталоном на Python (tool/format_vectors.py).
// Функции ниже — исполняемая версия спецификации. Рабочий код (FastCDC,
// сегменты, Меркл, фрагменты) проверяется этими же векторами в своих
// тестах; эталон оставлен как вторая независимая реализация (1.9.1).

import 'dart:convert';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:test/test.dart';
import 'package:test_vectors/test_vectors.dart';

import 'support/reference.dart';

const int _min = 512 * 1024;
const int _normal = 1024 * 1024;
const int _max = 8 * 1024 * 1024;
const _maskS = 0xFFFFFC0000000000;
const _maskL = 0xFFFFC00000000000;
const _block = 65536;

void main() {
  test('gear', () {
    final c = vectorCases(loadVectors('format/gear.json')).single;
    final key = hexToBytes(
      (c['input']! as Map<String, Object?>)['gearKey']! as String,
    );
    final expected = (c['expected']! as Map<String, Object?>)['gear']!;
    expect(_gear(key).map(_hex64).toList(), expected);
  });

  group('fastcdc', () {
    for (final c in vectorCases(loadVectors('format/fastcdc.json'))) {
      test(c['name'], () {
        final input = c['input']! as Map<String, Object?>;
        final gear = _gear(hexToBytes(input['gearKey']! as String));
        final data = input.containsKey('dataZeros')
            ? Uint8List(input['dataZeros']! as int)
            : patternBytes(input['dataPattern']! as Map<String, Object?>);
        final lengths = <int>[];
        for (var pos = 0; pos < data.length;) {
          final size = _cut(data, pos, gear);
          lengths.add(size);
          pos += size;
        }
        expect(
          lengths,
          (c['expected']! as Map<String, Object?>)['chunkLengths'],
        );
      });
    }
  });

  final segmentVectors = loadVectors('format/segment.json');
  final segmentCases = vectorCases(segmentVectors);
  final segmentCase = segmentCases.firstWhere(
    (c) => c['name'] == 'four-chunks',
  );
  Future<Uint8List>? blobFuture;
  Future<Uint8List> segmentBlobOnce() =>
      blobFuture ??= _segmentBlob(segmentCase);

  group('segment', () {
    test('four-chunks', () async {
      final input = segmentCase['input']! as Map<String, Object?>;
      final expected = segmentCase['expected']! as Map<String, Object?>;
      final chunkKey = hexToBytes(input['chunkIdKey']! as String);
      final chunks = [
        for (final spec
            in (input['chunks']! as List<Object?>).cast<Map<String, Object?>>())
          (
            data: patternBytes(spec['dataPattern']! as Map<String, Object?>),
            type: spec['type']! as int,
          ),
      ];
      final ids = [for (final c in chunks) blake2bKeyed(chunkKey, c.data)];
      expect(ids.map(bytesToHex).toList(), expected['chunkIds']);

      final plain = _segmentPlaintext([
        for (var i = 0; i < chunks.length; i++)
          (id: ids[i], type: chunks[i].type, data: chunks[i].data),
      ]);
      expect(
        bytesToHex(plain.sublist(0, 16 + 40 * chunks.length)),
        expected['header'],
      );
      expect(plain.length, expected['plaintextLength']);
      expect(bytesToHex(blake2b(plain)), expected['plaintextHash']);
      expect(_parseSegment(plain), isNull);

      final segmentBlob = await segmentBlobOnce();
      expect(segmentBlob.length, expected['blobLength']);
      expect(bytesToHex(blake2b(segmentBlob)), expected['blobHash']);
    });

    final minimal = _segmentPlaintext([
      (id: Uint8List(32), type: 1, data: Uint8List.fromList('x'.codeUnits)),
    ]);
    test('minimal', () {
      final info = segmentVectors['minimalSegment']! as Map<String, Object?>;
      expect(minimal.length, info['length']);
      expect(bytesToHex(blake2b(minimal)), info['hash']);
    });

    for (final c in segmentCases.where((c) => c != segmentCase)) {
      test(c['name'], () {
        final input = c['input']! as Map<String, Object?>;
        var data = Uint8List.fromList(minimal);
        if (input['patch'] case final Map<String, Object?> patch) {
          final bytes = hexToBytes(patch['bytes']! as String);
          data.setRange(
            patch['offset']! as int,
            (patch['offset']! as int) + bytes.length,
            bytes,
          );
        }
        if (input['truncate'] case final int length) {
          data = data.sublist(0, length);
        }
        expect(_parseSegment(data), (c['expected']! as Map)['error']);
      });
    }
  });

  group('merkle', () {
    for (final c in vectorCases(loadVectors('format/merkle.json'))) {
      test(c['name'], () {
        final body = patternBytes(
          (c['input']! as Map<String, Object?>)['bodyPattern']!
              as Map<String, Object?>,
        );
        expect(
          bytesToHex(_merkleRoot(body)),
          (c['expected']! as Map<String, Object?>)['root'],
        );
      });
    }
  });

  group('fragment', () {
    for (final c in vectorCases(loadVectors('format/fragment.json'))) {
      // Случаи verify-* и reject-* проверяет рабочий код (format_test.dart).
      if (!(c['input']! as Map<String, Object?>).containsKey('k')) continue;
      test(c['name'], () async {
        final segmentBlob = await segmentBlobOnce();
        final input = c['input']! as Map<String, Object?>;
        final expected = c['expected']! as Map<String, Object?>;
        final k = input['k']! as int;
        final n = input['n']! as int;
        final segmentId = hexToBytes(
          (segmentCase['input']! as Map<String, Object?>)['segmentId']!
              as String,
        );
        final perShard = (segmentBlob.length + k - 1) ~/ k;
        final shardSize = (perShard + 63) ~/ 64 * 64;
        expect(shardSize, expected['shardSize']);

        final padded = Uint8List(k * shardSize)..setAll(0, segmentBlob);
        final shards = [
          for (var i = 0; i < k; i++)
            Uint8List.sublistView(padded, i * shardSize, (i + 1) * shardSize),
          for (var i = k; i < n; i++) Uint8List(shardSize),
        ];
        ReedSolomon(k, n - k).encode(shards);

        final fragments = (expected['fragments']! as List<Object?>)
            .cast<Map<String, Object?>>();
        for (var index = 0; index < n; index++) {
          final body = shards[index];
          final root = _merkleRoot(body);
          final header = Uint8List(96)
            ..setAll(0, ascii.encode('FSFR'))
            ..setAll(4, [1, 1, k, n, index, 16, 0, 0])
            ..setAll(12, u32le(segmentBlob.length))
            ..setAll(16, u32le(shardSize))
            ..setAll(20, segmentId)
            ..setAll(52, root);
          expect(bytesToHex(header), fragments[index]['header']);
          expect(bytesToHex(root), fragments[index]['bodyRoot']);
          expect(bytesToHex(blake2b(body)), fragments[index]['bodyHash']);
          expect(bytesToHex(blake2b(header)), fragments[index]['fragmentId']);
        }
      });
    }
  });
}

/// Блоб сегмента из случая four-chunks в segment.json.
Future<Uint8List> _segmentBlob(Map<String, Object?> segmentCase) async {
  final input = segmentCase['input']! as Map<String, Object?>;
  final chunkKey = hexToBytes(input['chunkIdKey']! as String);
  final chunks = [
    for (final spec
        in (input['chunks']! as List<Object?>).cast<Map<String, Object?>>())
      (
        data: patternBytes(spec['dataPattern']! as Map<String, Object?>),
        type: spec['type']! as int,
      ),
  ];
  final plain = _segmentPlaintext([
    for (final c in chunks)
      (id: blake2bKeyed(chunkKey, c.data), type: c.type, data: c.data),
  ]);
  final segmentId = hexToBytes(input['segmentId']! as String);
  final segmentKey = await hkdf(
    hexToBytes(input['dataKey']! as String),
    Uint8List(0),
    [...ascii.encode('fs/v1/segment'), ...segmentId],
  );
  return await sealBlob(
    type: 1,
    objectId: segmentId,
    nonce: hexToBytes(input['nonce']! as String),
    key: segmentKey,
    plaintext: plain,
  );
}

/// Число как 16 шестнадцатеричных цифр без знака.
String _hex64(int value) =>
    (value >>> 32).toRadixString(16).padLeft(8, '0') +
    (value & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0');

List<int> _gear(List<int> key) => [
  for (var i = 0; i < 256; i++)
    ByteData.sublistView(blake2bKeyed(key, [...ascii.encode('fs/v1/gear'), i]))
        .getUint64(0, Endian.little),
];

/// FastCDC из data-format.md, раздел 2. В Dart `int` — 64 бита с
/// переполнением, поэтому сдвиг и сложение работают по модулю 2^64.
int _cut(Uint8List data, int start, List<int> gear) {
  final length = data.length - start;
  if (length <= _min) return length;
  final n = length < _max ? length : _max;
  final normal = n < _normal ? n : _normal;
  var fp = 0;
  var i = _min;
  for (; i < normal; i++) {
    fp = (fp << 1) + gear[data[start + i]];
    if (fp & _maskS == 0) return i + 1;
  }
  for (; i < n; i++) {
    fp = (fp << 1) + gear[data[start + i]];
    if (fp & _maskL == 0) return i + 1;
  }
  return n;
}

Uint8List _segmentPlaintext(
  List<({Uint8List id, int type, Uint8List data})> chunks,
) {
  final dataLength = chunks.fold(0, (sum, c) => sum + c.data.length);
  final builder = BytesBuilder()
    ..add(ascii.encode('FSSG'))
    ..add([1, 0, 0, 0])
    ..add(u32le(chunks.length))
    ..add(u32le(dataLength));
  for (final c in chunks) {
    builder
      ..add(c.id)
      ..add([c.type, 0, 0, 0])
      ..add(u32le(c.data.length));
  }
  for (final c in chunks) {
    builder.add(c.data);
  }
  final padding = (65536 - builder.length % 65536) % 65536;
  builder.add(Uint8List(padding));
  return builder.toBytes();
}

/// Разбор открытого текста сегмента по data-format.md, раздел 3.
/// null — сегмент корректен, 'format' — ошибка формата.
String? _parseSegment(Uint8List s) {
  if (s.length < 16 || s.length % 65536 != 0 || s.length > 16 * 1024 * 1024) {
    return 'format';
  }
  if (ascii.decode(s.sublist(0, 4), allowInvalid: true) != 'FSSG') {
    return 'format';
  }
  if (s[4] != 1 || s[5] != 0 || s[6] != 0 || s[7] != 0) return 'format';
  final view = ByteData.sublistView(s);
  final count = view.getUint32(8, Endian.little);
  final dataLength = view.getUint32(12, Endian.little);
  if (count == 0) return 'format';
  final dataStart = 16 + 40 * count;
  if (dataStart + dataLength > s.length) return 'format';
  var sum = 0;
  for (var i = 0; i < count; i++) {
    final e = 16 + 40 * i;
    final type = s[e + 32];
    if (type != 1 && type != 2) return 'format';
    if (s[e + 33] != 0 || s[e + 34] != 0 || s[e + 35] != 0) return 'format';
    final length = view.getUint32(e + 36, Endian.little);
    if (length == 0) return 'format';
    sum += length;
  }
  if (sum != dataLength) return 'format';
  for (var i = dataStart + dataLength; i < s.length; i++) {
    if (s[i] != 0) return 'format';
  }
  return null;
}

/// Дерево Меркла по data-format.md, раздел 5 (RFC 6962, BLAKE2b-256).
Uint8List _merkleRoot(Uint8List body) {
  final leaves = [
    for (var i = 0; i < body.length; i += _block)
      blake2b([
        0,
        ...Uint8List.sublistView(
          body,
          i,
          i + _block < body.length ? i + _block : body.length,
        ),
      ]),
  ];
  Uint8List mth(List<Uint8List> nodes) {
    if (nodes.length == 1) return nodes.first;
    var j = 1;
    while (j * 2 < nodes.length) {
      j *= 2;
    }
    return blake2b([1, ...mth(nodes.sublist(0, j)), ...mth(nodes.sublist(j))]);
  }

  return mth(leaves);
}
