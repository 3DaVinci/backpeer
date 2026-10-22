import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:protocol/protocol.dart' as pb;
import 'package:test/test.dart';
import 'package:test_vectors/test_vectors.dart';

/// Приёмник чанков, как в конвейере: дедупликация по локальному индексу;
/// каждый новый чанк — отдельный «сегмент» (упаковка — задача 1.6.3).
final class _IndexSink implements ChunkSink {
  new(this.index);

  final LocalIndex index;
  final List<SegmentEntry> written = [];

  @override
  bool contains(ChunkId id) => index.findChunk(id) != null;

  @override
  Future<bool> add(ChunkId id, ChunkType type, Uint8List data) async {
    if (contains(id)) return false;
    final segment = SegmentEntry(
      segmentId: Uint8List.fromList(id.bytes.reversed.toList()),
      k: 2,
      n: 3,
      blobLength: data.length + 80,
      shardSize: shardSizeFor(data.length + 80, 2),
      fragmentIds: [for (var i = 0; i < 3; i++) Uint8List(32)..[0] = i],
      chunks: [
        SegmentChunk(
          chunkId: id,
          type: type.code,
          offset: 0,
          length: data.length,
        ),
      ],
    );
    index
      ..addSegment(segment)
      ..markSegmentStored(segment.segmentId);
    written.add(segment);
    return true;
  }
}

void main() {
  late CryptoProvider crypto;
  final key = SecretBytes(Uint8List(32)..[0] = 5);
  late Directory dir;
  setUpAll(() async => crypto = await SodiumCryptoProvider.load());
  setUp(() => dir = Directory.systemTemp.createTempSync('fs-recover-'));
  tearDown(() => dir.deleteSync(recursive: true));

  var nextId = 0;
  Uint8List newId() => Uint8List(32)
    ..[0] = 0x1D
    ..[1] = nextId++;

  Future<void> writeIndexes(
    ObjectStore store,
    List<SegmentEntry> segments, {
    int limit = maxIndexLength,
  }) async {
    final builder = IndexBuilder(newId, limit: limit);
    segments.map(segmentRecord).forEach(builder.add);
    for (final i in builder.finish()) {
      await store.put(
        ObjectKind.indexObject,
        Uint8List.fromList(i.indexId),
        ManifestObjects.sealIndex(crypto, key, i),
      );
    }
  }

  SegmentEntry segment(int b, List<int> chunks) => SegmentEntry(
    segmentId: Uint8List(32)..[31] = b,
    k: 2,
    n: 3,
    blobLength: 1000,
    shardSize: 512,
    fragmentIds: [for (var i = 0; i < 3; i++) Uint8List(32)..[0] = b * 10 + i],
    chunks: [
      for (var i = 0; i < chunks.length; i++)
        SegmentChunk(
          chunkId: ChunkId(Uint8List(32)..[0] = chunks[i]),
          type: 1 + i % 2,
          offset: i * 100,
          length: 100,
        ),
    ],
  );

  test('SegmentEntry ↔ SegmentRecord', () {
    final s = segment(1, [1, 2, 3]);
    final back = segmentEntry(
      pb.SegmentRecord.fromBuffer(segmentRecord(s).writeToBuffer()),
    );
    expect(back.segmentId, s.segmentId);
    expect(back.fragmentIds, s.fragmentIds);
    expect(
      back.chunks.map((c) => (c.chunkId, c.type, c.offset, c.length)),
      s.chunks.map((c) => (c.chunkId, c.type, c.offset, c.length)),
    );
    expect(
      () => segmentEntry(segmentRecord(s)..fragmentIds.removeLast()),
      throwsA(isA<DataFormatException>()),
    );
  });

  test('восстановление: все сегменты, supersedes, битые индексы', () async {
    final store = LocalObjectStore(dir);
    final segments = [
      for (var b = 1; b <= 40; b++) segment(b, [b, b + 100]),
    ];
    // Маленький предел — индексов несколько.
    await writeIndexes(store, segments, limit: 2000);
    // Старый индекс с лишним сегментом, заменённый новым.
    final old = pb.Index(
      formatVersion: 1,
      indexId: newId(),
      segments: [
        segmentRecord(segment(99, [250])),
      ],
    );
    await store.put(
      ObjectKind.indexObject,
      Uint8List.fromList(old.indexId),
      ManifestObjects.sealIndex(crypto, key, old),
    );
    final replacing = pb.Index(
      formatVersion: 1,
      indexId: newId(),
      supersedes: [old.indexId],
    );
    await store.put(
      ObjectKind.indexObject,
      Uint8List.fromList(replacing.indexId),
      ManifestObjects.sealIndex(crypto, key, replacing),
    );
    // Мусор.
    await store.put(ObjectKind.indexObject, newId(), Uint8List(90));

    final index = LocalIndex.inMemory();
    final report = await recoverIndex(
      crypto: crypto,
      manifestKey: key,
      store: store,
      index: index,
    );
    expect(report.segmentsAdded, 40);
    expect(report.indexesSuperseded, 1);
    expect(report.unreadable, hasLength(1));
    expect(report.indexesRead, greaterThan(2));
    expect(index.chunkCount, 80);
    expect(index.pendingSegments(), isEmpty);
    expect(index.findChunk(ChunkId(Uint8List(32)..[0] = 250)), isNull);
    final location = index.findChunk(ChunkId(Uint8List(32)..[0] = 107))!;
    expect(location.segmentId[31], 7);
    expect((location.type, location.offset, location.stored), (2, 100, true));
    expect(index.fragments(location.segmentId).map((f) => f.fragmentId[0]), [
      70,
      71,
      72,
    ]);

    final again = await recoverIndex(
      crypto: crypto,
      manifestKey: key,
      store: store,
      index: index,
    );
    expect((again.segmentsAdded, again.segmentsKnown), (0, 40));
    index.close();
  });

  test(
    'после потери базы следующий бэкап не загружает чанки повторно',
    () async {
      final data = Directory('${dir.path}/data')..createSync();
      File('${data.path}/big.bin')
          .writeAsBytesSync(splitmix64Bytes(3, 3 << 20));
      File('${data.path}/small.txt').writeAsStringSync('hello');
      final store = LocalObjectStore(Directory('${dir.path}/objects'));
      final cdc = FastCdc(GearTable.derive(crypto, SecretBytes(Uint8List(32))));
      final hasher = ChunkIdHasher(crypto, SecretBytes(Uint8List(32)..[0] = 1));

      Future<(TreeStats, _IndexSink)> backup(LocalIndex index) async {
        final sink = _IndexSink(index);
        final builder = TreeBuilder(
          walker: TreeWalker(),
          cdc: cdc,
          hasher: hasher,
          sink: sink,
          index: index,
        );
        await builder.buildRoot([data.path]);
        await writeIndexes(store, sink.written);
        return (builder.stats, sink);
      }

      final dbPath = '${dir.path}/db/index.db';
      final first = LocalIndex.open(dbPath);
      final (stats1, _) = await backup(first);
      expect(stats1.newChunks, greaterThan(3));
      first.close();
      for (final f in Directory('${dir.path}/db').listSync()) {
        f.deleteSync();
      }

      final fresh = LocalIndex.open(dbPath);
      final report = await recoverIndex(
        crypto: crypto,
        manifestKey: key,
        store: store,
        index: fresh,
      );
      expect(report.segmentsAdded, stats1.newChunks);
      final (stats2, _) = await backup(fresh);
      expect(stats2.filesRead, 2, reason: 'кеша файлов нет — файлы перечитаны');
      expect(stats2.newChunks, 0, reason: 'чанки уже сохранены');
      fresh.close();
    },
  );
}
