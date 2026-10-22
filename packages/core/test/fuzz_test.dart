// Фаззинг разборщиков (задача 1.8.5, модель угроз Х-9): случайные и
// мутированные входы на основе правильных образцов. Разборщик либо
// принимает вход, либо бросает подтип CoreException — никаких RangeError,
// StateError и прочих необработанных исключений.
//
//   FS_FUZZ_RUNS=100000 FS_FUZZ_SEED=7 dart test test/fuzz_test.dart
//
// По умолчанию — 2000 входов на разборщик, seed 1. Упавший вход
// печатается вместе с seed и номером прогона.

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:fixnum/fixnum.dart';
import 'package:protocol/protocol.dart' as pb;
import 'package:test/test.dart';
import 'package:test_vectors/test_vectors.dart';

final Map<String, String> _env = Platform.environment;
final int _runs = int.parse(_env['FS_FUZZ_RUNS'] ?? '2000');
final int _seed = int.parse(_env['FS_FUZZ_SEED'] ?? '1');

/// Мутация правильного образца: переворот битов, замена байтов на
/// граничные значения, обрезка, удлинение, вставка и удаление участка,
/// перестановка участков; иногда — совсем случайный вход.
Uint8List mutate(Random r, Uint8List sample) {
  if (r.nextInt(20) == 0) {
    return Uint8List.fromList(
      List.generate(r.nextInt(sample.length * 2 + 2), (_) => r.nextInt(256)),
    );
  }
  var b = Uint8List.fromList(sample);
  final steps = 1 + r.nextInt(4);
  for (var s = 0; s < steps; s++) {
    if (b.isEmpty) b = Uint8List(1);
    switch (r.nextInt(8)) {
      case 0:
        b[r.nextInt(b.length)] ^= 1 << r.nextInt(8);
      case 1:
        const interesting = [0, 1, 0x7F, 0x80, 0xFF];
        b[r.nextInt(b.length)] = interesting[r.nextInt(interesting.length)];
      case 2:
        // Граничное 32-битное число по случайному смещению: длины и
        // счётчики в заголовках — u32le.
        if (b.length >= 4) {
          const values = [0, 1, 0x7FFFFFFF, 0x80000000, 0xFFFFFFFF, 65536];
          final at = r.nextInt(b.length - 3);
          final v = values[r.nextInt(values.length)];
          for (var i = 0; i < 4; i++) {
            b[at + i] = (v >> (8 * i)) & 0xFF;
          }
        }
      case 3:
        b = Uint8List.sublistView(b, 0, r.nextInt(b.length + 1));
      case 4:
        b = Uint8List.fromList([
          ...b,
          ...List.generate(1 + r.nextInt(64), (_) => r.nextInt(256)),
        ]);
      case 5:
        final at = r.nextInt(b.length + 1);
        b = Uint8List.fromList([
          ...b.sublist(0, at),
          ...List.generate(1 + r.nextInt(16), (_) => r.nextInt(256)),
          ...b.sublist(at),
        ]);
      case 6:
        final at = r.nextInt(b.length);
        final end = min(b.length, at + 1 + r.nextInt(16));
        b = Uint8List.fromList([...b.sublist(0, at), ...b.sublist(end)]);
      default:
        final a = r.nextInt(b.length);
        final c = r.nextInt(b.length);
        final len = min(16, min(b.length - a, b.length - c));
        b.setRange(c, c + len, Uint8List.fromList(b.sublist(a, a + len)));
    }
  }
  return b;
}

/// [_runs] мутаций каждого из [samples] через [target]. Допустимы только
/// успех и [CoreException]. Возвращает число отказов.
int fuzz(
  String name,
  List<Uint8List> samples,
  void Function(Uint8List input) target, {
  int? runs,
}) {
  final r = Random(_seed ^ name.hashCode);
  var rejected = 0;
  final total = runs ?? _runs;
  for (var i = 0; i < total; i++) {
    final input = mutate(r, samples[i % samples.length]);
    try {
      target(input);
    } on CoreException {
      rejected++;
    } on Object catch (e, st) {
      fail(
        '$name: seed $_seed, прогон $i, вход ${input.length} байт '
        '${toHex(input.take(256).toList())}…\n$e\n$st',
      );
    }
  }
  return rejected;
}

void main() {
  late CryptoProvider crypto;
  final key = SecretBytes(Uint8List(32)..[0] = 5);
  Uint8List id(int b) => Uint8List(32)..[0] = b;
  setUpAll(() async => crypto = await SodiumCryptoProvider.load());

  Uint8List blob(int length) => EncryptedBlob.seal(
    crypto,
    type: BlobType.segment,
    objectId: id(1),
    key: key,
    plaintext: splitmix64Bytes(length, length),
  );

  test('заголовок блоба', () {
    final rejected = fuzz('blob-header', [
      blob(0),
      blob(100),
    ], BlobHeader.parse);
    expect(rejected, greaterThan(0));
  });

  test('блоб: разбор и расшифровка', () {
    fuzz('blob-open', [
      blob(0),
      blob(1000),
    ], (b) => EncryptedBlob.open(crypto, b, key: key));
  });

  test('открытый текст сегмента', () {
    final plain = SegmentPlaintext.encode([
      for (var i = 0; i < 5; i++)
        PackedChunk(
          id: ChunkId(id(10 + i)),
          type: i.isEven ? ChunkType.file : ChunkType.tree,
          data: splitmix64Bytes(i, 100 + 1000 * i),
        ),
    ]);
    // Мутации полного сегмента 64 КиБ медленные; случайные правки
    // заголовка и оглавления — на усечённых образцах тоже.
    fuzz('segment', [plain], SegmentPlaintext.parse, runs: _runs ~/ 4);
    fuzz(
      'segment-head',
      [Uint8List.sublistView(plain, 0, 512)],
      (b) => SegmentPlaintext.parse(
        Uint8List(SegmentPlaintext.alignment)..setAll(0, b.take(65536)),
      ),
    );
  });

  test('заголовок фрагмента и фрагмент', () {
    final fragments = encodeFragments(
      crypto,
      blob: blob(3000),
      segmentId: id(1),
      k: 3,
      n: 5,
    );
    final samples = [for (final f in fragments.take(2)) f.toBytes()];
    fuzz('fragment-header', samples, FragmentHeader.parse);
    fuzz('fragment', samples, (b) => Fragment.parse(b).verify(crypto));
    fuzz('fragment-decode', samples, (b) {
      final f = Fragment.parse(b);
      decodeFragments(crypto, [
        f,
        ...fragments.skip(2).take(2),
      ], segmentId: id(1));
    });
  });

  test('KeyBundle', () {
    final samples = [
      for (final c in vectorCases(loadVectors('crypto/key-bundle.json')))
        fromHex(
          (c['expected']! as Map<String, Object?>)['keyBundle']! as String,
        ),
    ];
    fuzz('key-bundle', samples, (b) {
      final bundle = KeyBundle.parse(b);
      // Пределы Argon2id проверены разбором: память не больше 4 ГиБ.
      expect(
        bundle.params.memoryKiB,
        lessThanOrEqualTo(KeyBundle.maxMemoryKiB),
      );
      expect(
        bundle.params.iterations,
        lessThanOrEqualTo(KeyBundle.maxIterations),
      );
    });
  });

  test('фраза восстановления', () {
    final phrase = RecoveryPhrase.fromEntropy(id(7)).words.join(' ');
    fuzz('phrase', [
      Uint8List.fromList(phrase.codeUnits),
    ], (b) => RecoveryPhrase.parse(String.fromCharCodes(b)));
  });

  // Объекты манифеста за AEAD: подделать их без ключа нельзя, поэтому
  // мутируется открытый текст и запечатывается правильным ключом — так
  // проверяется разбор Protobuf и проверки после него.
  Uint8List sealRaw(BlobType type, Uint8List objectId, Uint8List plain) =>
      EncryptedBlob.seal(
        crypto,
        type: type,
        objectId: objectId,
        key: key,
        plaintext: plain,
      );

  test('объект снимка', () {
    final snapshot = pb.Snapshot(
      formatVersion: 1,
      snapshotId: id(1),
      sequence: Int64(3),
      parentSnapshotId: id(2),
      createdAtUnixMs: Int64(1792000000000),
      hostname: 'хост',
      deviceId: id(3),
      paths: ['/home/u', '/srv'],
      rootTree: [id(4), id(5)],
      tags: ['a'],
      stats: pb.SnapshotStats(files: Int64(10), bytes: Int64(1 << 40)),
    );
    fuzz(
      'snapshot',
      [snapshot.writeToBuffer()],
      (b) => ManifestObjects.openSnapshot(
        crypto,
        key,
        sealRaw(BlobType.snapshot, id(1), b),
      ),
    );
    fuzz(
      'snapshot-blob',
      [ManifestObjects.sealSnapshot(crypto, key, snapshot)],
      (b) => ManifestObjects.openSnapshot(crypto, key, b),
      runs: _runs ~/ 4,
    );
  });

  test('объект индекса и записи сегментов', () {
    final index = pb.Index(
      formatVersion: 1,
      indexId: id(1),
      segments: [
        pb.SegmentRecord(
          segmentId: id(2),
          k: 2,
          n: 4,
          blobLength: 3000,
          shardSize: 1536,
          fragmentIds: [id(3), id(4), id(5), id(6)],
          chunks: [
            pb.ChunkEntry(
              chunkId: id(7),
              type: pb.ChunkType.CHUNK_TYPE_CONTENT,
              offset: 16 + 40,
              length: 100,
            ),
          ],
        ),
      ],
      supersedes: [id(8)],
    );
    fuzz('index', [index.writeToBuffer()], (b) {
      final parsed = ManifestObjects.openIndex(
        crypto,
        key,
        sealRaw(BlobType.indexObject, id(1), b),
      );
      parsed.segments.forEach(segmentEntry);
    });
  });

  test('дерево каталога (Protobuf)', () {
    final tree = pb.Tree(
      nodes: [
        pb.Node(
          name: [0x61],
          type: pb.NodeType.NODE_TYPE_FILE,
          size: Int64(5),
          content: [id(1)],
          mode: 420,
        ),
        pb.Node(
          name: [0xFF, 0xFE],
          type: pb.NodeType.NODE_TYPE_SYMLINK,
          symlinkTarget: [0x2F],
        ),
      ],
    );
    // Тот же разбор, что у деревьев при восстановлении.
    fuzz(
      'tree',
      [tree.writeToBuffer()],
      (b) => ManifestObjects.parseMessage('tree', () => pb.Tree.fromBuffer(b)),
    );
  });
}
