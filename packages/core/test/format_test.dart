// Рабочий код форматов data-format.md, разделы 3–5, на векторах
// format/segment.json, merkle.json, fragment.json.

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:test/test.dart';
import 'package:test_vectors/test_vectors.dart';

void main() {
  late CryptoProvider crypto;
  setUpAll(() async => crypto = await SodiumCryptoProvider.load());

  Map<String, Object?> map(Object? v) => v! as Map<String, Object?>;
  String h(Uint8List data) => bytesToHex(crypto.blake2b256(data));

  final segmentVectors = loadVectors('format/segment.json');
  final fourChunks = vectorCases(segmentVectors)
      .firstWhere((c) => c['name'] == 'four-chunks');

  ({Uint8List plain, Uint8List blob, Uint8List segmentId}) buildFourChunks() {
    final input = map(fourChunks['input']);
    final hasher = ChunkIdHasher(
      crypto,
      SecretBytes(hexToBytes(input['chunkIdKey']! as String)),
    );
    final chunks = [
      for (final spec
          in (input['chunks']! as List).cast<Map<String, Object?>>())
        () {
          final data = patternBytes(map(spec['dataPattern']));
          return PackedChunk(
            id: hasher.of(data),
            type: ChunkType.fromCode(spec['type']! as int)!,
            data: data,
          );
        }(),
    ];
    final plain = SegmentPlaintext.encode(chunks);
    final segmentId = hexToBytes(input['segmentId']! as String);
    final segmentKey = crypto.hkdfSha256(
      ikm: SecretBytes(hexToBytes(input['dataKey']! as String)),
      salt: Uint8List(0),
      info: Uint8List.fromList([
        ...ascii.encode('fs/v1/segment'),
        ...segmentId,
      ]),
    );
    final blob = SegmentCipher.seal(
      crypto,
      segmentKey: segmentKey,
      segmentId: segmentId,
      plaintext: plain,
      nonce: hexToBytes(input['nonce']! as String),
    );
    expect(
      SegmentCipher.open(
        crypto,
        segmentKey: segmentKey,
        segmentId: segmentId,
        blob: blob,
      ),
      plain,
    );
    expect(
      () => SegmentCipher.open(
        crypto,
        segmentKey: segmentKey,
        segmentId: Uint8List(32),
        blob: blob,
      ),
      throwsA(isA<IntegrityException>()),
    );
    return (plain: plain, blob: blob, segmentId: segmentId);
  }

  group('segment', () {
    test('four-chunks', () {
      final expected = map(fourChunks['expected']);
      final built = buildFourChunks();
      final parsed = SegmentPlaintext.parse(built.plain);
      expect(parsed.map((c) => '${c.id}').toList(), expected['chunkIds']);
      expect(
        bytesToHex(built.plain.sublist(0, 16 + 40 * parsed.length)),
        expected['header'],
      );
      expect(built.plain.length, expected['plaintextLength']);
      expect(h(built.plain), expected['plaintextHash']);
      expect(built.blob.length, expected['blobLength']);
      expect(h(built.blob), expected['blobHash']);
    });

    final minimal = SegmentPlaintext.encode([
      PackedChunk(
        id: ChunkId(Uint8List(32)),
        type: ChunkType.file,
        data: Uint8List.fromList('x'.codeUnits),
      ),
    ]);
    test('minimal', () {
      final info = map(segmentVectors['minimalSegment']);
      expect(minimal.length, info['length']);
      expect(h(minimal), info['hash']);
      expect(SegmentPlaintext.parse(minimal).single.data, 'x'.codeUnits);
    });

    for (final c in vectorCases(segmentVectors)) {
      if (c == fourChunks) continue;
      test(c['name'], () {
        final input = map(c['input']);
        var data = Uint8List.fromList(minimal);
        if (input['patch'] case final Map<String, Object?> patch) {
          data.setAll(
            patch['offset']! as int,
            hexToBytes(patch['bytes']! as String),
          );
        }
        if (input['truncate'] case final int length) {
          data = data.sublist(0, length);
        }
        expect(map(c['expected'])['error'], 'format');
        expect(
          () => SegmentPlaintext.parse(data),
          throwsA(isA<DataFormatException>()),
        );
      });
    }

    test('fits и encode отвергают переполнение и повторы', () {
      expect(SegmentPlaintext.fits(1, 16 * 1024 * 1024 - 56), isTrue);
      expect(SegmentPlaintext.fits(1, 16 * 1024 * 1024 - 55), isFalse);
      final id = ChunkId(Uint8List(32));
      final chunk = PackedChunk(
        id: id,
        type: ChunkType.file,
        data: Uint8List(1),
      );
      expect(
        () => SegmentPlaintext.encode([chunk, chunk]),
        throwsArgumentError,
      );
      expect(() => SegmentPlaintext.encode([]), throwsArgumentError);
    });
  });

  group('merkle', () {
    for (final c in vectorCases(loadVectors('format/merkle.json'))) {
      test(c['name'], () {
        final body = patternBytes(map(map(c['input'])['bodyPattern']));
        expect(
          bytesToHex(merkleRoot(crypto, body)),
          map(c['expected'])['root'],
        );
        // Те же векторы частями неровной длины, поперёк границ блоков.
        final builder = MerkleBuilder(crypto);
        for (var i = 0, step = 1; i < body.length; i += step, step *= 3) {
          builder.add(
            Uint8List.sublistView(
              body,
              i,
              i + step < body.length ? i + step : body.length,
            ),
          );
        }
        expect(bytesToHex(builder.finish()), map(c['expected'])['root']);
      });
    }

    test('MerkleBuilder: пустое тело и повторное завершение', () {
      expect(() => MerkleBuilder(crypto).finish(), throwsArgumentError);
      final b = MerkleBuilder(crypto)
        ..add([1])
        ..finish();
      expect(b.finish, throwsStateError);
      expect(() => b.add([2]), throwsStateError);
    });
  });

  group('fragment', () {
    final fragmentVectors = loadVectors('format/fragment.json');
    final minimalInfo = map(fragmentVectors['minimalFragment']);
    final minimal = hexToBytes(minimalInfo['bytes']! as String);

    for (final c in vectorCases(fragmentVectors)) {
      final input = map(c['input']);
      final expected = map(c['expected']);
      if (input.containsKey('k')) {
        test(c['name'], () {
          final built = buildFourChunks();
          final k = input['k']! as int;
          final n = input['n']! as int;
          final fragments = encodeFragments(
            crypto,
            blob: built.blob,
            segmentId: built.segmentId,
            k: k,
            n: n,
          );
          expect(fragments.first.header.shardSize, expected['shardSize']);
          final want = (expected['fragments']! as List)
              .cast<Map<String, Object?>>();
          for (var i = 0; i < n; i++) {
            final f = fragments[i];
            expect(bytesToHex(f.header.toBytes()), want[i]['header']);
            expect(bytesToHex(f.header.bodyRoot), want[i]['bodyRoot']);
            expect(h(f.body), want[i]['bodyHash']);
            final id = f.header.fragmentId(crypto);
            expect(bytesToHex(id), want[i]['fragmentId']);
            final parsed = Fragment.parse(f.toBytes())
              ..verify(crypto, expectedFragmentId: id);
            expect(parsed.header.index, i);
          }
        });
        continue;
      }
      test(c['name'], () {
        var data = Uint8List.fromList(minimal);
        if (input['patch'] case final Map<String, Object?> patch) {
          data.setAll(
            patch['offset']! as int,
            hexToBytes(patch['bytes']! as String),
          );
        }
        if (input['truncate'] case final int length) {
          data = data.sublist(0, length);
        }
        final expectedId = input['expectedFragmentId'] == null
            ? null
            : hexToBytes(input['expectedFragmentId']! as String);
        void check() =>
            Fragment.parse(data).verify(crypto, expectedFragmentId: expectedId);
        switch (expected['error']) {
          case 'format':
            expect(check, throwsA(isA<DataFormatException>()));
          case 'integrity':
            expect(check, throwsA(isA<IntegrityException>()));
          default:
            check();
            expect(
              bytesToHex(Fragment.parse(data).header.fragmentId(crypto)),
              minimalInfo['fragmentId'],
            );
        }
      });
    }
  });

  group('сегмент → фрагменты → сегмент', () {
    test('из любых k фрагментов, включая только чётность', () {
      final built = buildFourChunks();
      const k = 10;
      const n = 20;
      final fragments = encodeFragments(
        crypto,
        blob: built.blob,
        segmentId: built.segmentId,
        k: k,
        n: n,
      );
      final ids = {
        for (final f in fragments) f.header.index: f.header.fragmentId(crypto),
      };
      final random = Random(5);
      final subsets = [
        [for (var i = 0; i < k; i++) i],
        [for (var i = k; i < n; i++) i],
        for (var r = 0; r < 5; r++)
          (List.generate(n, (i) => i)..shuffle(random)).take(k).toList(),
      ];
      for (final subset in subsets) {
        final chosen = [
          for (final i in subset) Fragment.parse(fragments[i].toBytes()),
        ];
        final blob = decodeFragments(
          crypto,
          chosen,
          segmentId: built.segmentId,
          expectedFragmentIds: ids,
        );
        expect(h(blob), h(built.blob), reason: '$subset');
      }
    });

    test('чужой фрагмент и нехватка распознаются', () {
      final built = buildFourChunks();
      final a = encodeFragments(
        crypto,
        blob: built.blob,
        segmentId: built.segmentId,
        k: 2,
        n: 4,
      );
      final otherId = Uint8List(32)..[0] = 7;
      final b = encodeFragments(
        crypto,
        blob: built.blob,
        segmentId: otherId,
        k: 2,
        n: 4,
      );
      expect(
        () => decodeFragments(crypto, [a[0], b[1]], segmentId: built.segmentId),
        throwsA(isA<IntegrityException>()),
      );
      expect(
        () => decodeFragments(crypto, [a[0], a[0]], segmentId: built.segmentId),
        throwsA(isA<InsufficientShardsException>()),
      );
      // Подмена тела с сохранением заголовка.
      final forged = Fragment(
        a[1].header,
        Uint8List.fromList(a[1].body)..[0] ^= 1,
      );
      expect(
        () =>
            decodeFragments(crypto, [a[0], forged], segmentId: built.segmentId),
        throwsA(isA<IntegrityException>()),
      );
      // verified: дерево Меркла не пересчитывается, проверка сегмента
      // остаётся.
      expect(
        () => decodeFragments(
          crypto,
          [a[0], b[1]],
          segmentId: built.segmentId,
          verified: true,
        ),
        throwsA(isA<IntegrityException>()),
      );
      expect(
        decodeFragments(
          crypto,
          [a[0], a[1]],
          segmentId: built.segmentId,
          verified: true,
        ),
        built.blob,
      );
    });
  });
}
