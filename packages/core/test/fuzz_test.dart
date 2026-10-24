// Фаззинг разборщиков (задача 1.8.5, модель угроз Х-9): случайные и
// мутированные входы на основе правильных образцов. Разборщик либо
// принимает вход, либо бросает подтип CoreException — никаких RangeError,
// StateError и прочих необработанных исключений.
//
//   FS_FUZZ_RUNS=100000 FS_FUZZ_SEED=7 dart test test/fuzz_test.dart
//
// По умолчанию — 2000 входов на разборщик, seed 1. Упавший вход
// печатается вместе с seed и номером прогона.

import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:fixnum/fixnum.dart';
import 'package:protocol/protocol.dart' as pb;
import 'package:test/test.dart';
import 'package:test_vectors/test_vectors.dart';

import 'support/fuzz.dart';

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
    fuzz('segment', [plain], SegmentPlaintext.parse, runs: fuzzRuns ~/ 4);
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
      runs: fuzzRuns ~/ 4,
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
