import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:test/test.dart';
import 'package:test_vectors/test_vectors.dart';

/// Обёртка хранилища: считает записи и может отменить бэкап после
/// заданного числа записанных фрагментов.
final class _Recording implements FragmentStore {
  new(this.inner);

  final FragmentStore inner;
  final List<Uint8List> segmentsPut = [];
  int puts = 0;
  int? cancelAfter;
  CancellationToken? token;

  @override
  List<String> get nodes => inner.nodes;

  @override
  Future<Uint8List> put(
    String node,
    Uint8List fragment, {
    Uint8List? expectedFragmentId,
  }) async {
    final id = await inner.put(
      node,
      fragment,
      expectedFragmentId: expectedFragmentId,
    );
    puts++;
    final segmentId = Fragment.parse(fragment).header.segmentId;
    if (!segmentsPut.any((s) => bytesToHex(s) == bytesToHex(segmentId))) {
      segmentsPut.add(segmentId);
    }
    if (cancelAfter != null && puts >= cancelAfter!) token?.cancel();
    return id;
  }

  @override
  Future<Uint8List> get(String node, Uint8List fragmentId) =>
      inner.get(node, fragmentId);

  @override
  Future<List<bool>> has(String node, List<Uint8List> fragmentIds) =>
      inner.has(node, fragmentIds);

  @override
  Future<void> delete(String node, Uint8List fragmentId) =>
      inner.delete(node, fragmentId);
}

/// Обёртка хранилища с задержкой записи: пока узлы «думают», обход уже
/// прочитал файлы — на этом и видно, что доля считается по сделанному.
final class _Slow implements FragmentStore {
  new(this.inner, this.delay);

  final FragmentStore inner;
  final Duration delay;

  @override
  List<String> get nodes => inner.nodes;

  @override
  Future<Uint8List> put(
    String node,
    Uint8List fragment, {
    Uint8List? expectedFragmentId,
  }) async {
    await Future<void>.delayed(delay);
    return await inner.put(
      node,
      fragment,
      expectedFragmentId: expectedFragmentId,
    );
  }

  @override
  Future<Uint8List> get(String node, Uint8List fragmentId) =>
      inner.get(node, fragmentId);

  @override
  Future<List<bool>> has(String node, List<Uint8List> fragmentIds) =>
      inner.has(node, fragmentIds);

  @override
  Future<void> delete(String node, Uint8List fragmentId) =>
      inner.delete(node, fragmentId);
}

void main() {
  late CryptoProvider crypto;
  late AccountKeys keys;
  final deviceId = Uint8List(32)..[0] = 0xDE;
  setUpAll(() async {
    crypto = await SodiumCryptoProvider.load();
    keys = await AccountKeys.fromPhrase(
      RecoveryPhrase.fromEntropy(Uint8List(32)),
      crypto,
    );
  });

  late Directory dir;
  late Directory data;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('fs-backup-');
    data = Directory('${dir.path}/data')..createSync();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  void populate({int megabytes = 6}) {
    for (var i = 0; i < megabytes; i++) {
      File('${data.path}/f$i.bin')
          .writeAsBytesSync(splitmix64Bytes(100 + i, 1 << 20));
    }
    File('${data.path}/sub/note.txt')
      ..createSync(recursive: true)
      ..writeAsStringSync('note');
  }

  ({LocalIndex index, LocalFolderStore nodes, LocalObjectStore objects}) setup(
    String name, {
    FaultPlan faults = FaultPlan.none,
  }) => (
    index: LocalIndex.open('${dir.path}/$name/index.db'),
    nodes: LocalFolderStore(
      Directory('${dir.path}/$name/nodes'),
      crypto,
      nodeCount: 20,
      faults: faults,
    ),
    objects: LocalObjectStore(Directory('${dir.path}/$name/objects')),
  );

  Future<BackupResult> backup(
    ({LocalIndex index, LocalFolderStore nodes, LocalObjectStore objects}) s, {
    FragmentStore? fragments,
    CancellationToken? cancel,
    SegmentEncoder? encoder,
    List<BackupProgress>? progress,
  }) => runBackup(
    crypto: crypto,
    keys: keys,
    index: s.index,
    fragments: fragments ?? s.nodes,
    objects: s.objects,
    paths: [data.path],
    deviceId: deviceId,
    cancel: cancel,
    encoder: encoder,
    onProgress: progress?.add,
    progressInterval: const Duration(milliseconds: 1),
  );

  /// Сегмент собирается из любых k фрагментов с узлов, расшифровывается и
  /// разбирается; идентификаторы чанков совпадают с индексом.
  Future<void> checkSegment(
    ({LocalIndex index, LocalFolderStore nodes, LocalObjectStore objects}) s,
    Uint8List segmentId,
  ) async {
    final entry = s.index.segment(segmentId)!;
    final fragments = <Fragment>[];
    for (final f in s.index.fragments(segmentId).reversed) {
      if (f.node == null) continue;
      fragments.add(Fragment.parse(await s.nodes.get(f.node!, f.fragmentId)));
      if (fragments.length == entry.k) break;
    }
    final blob = decodeFragments(crypto, fragments, segmentId: segmentId);
    final plain = SegmentCipher.open(
      crypto,
      segmentKey: keys.segmentKey(segmentId),
      segmentId: segmentId,
      blob: blob,
    );
    final chunks = SegmentPlaintext.parse(plain);
    final hasher = ChunkIdHasher(crypto, keys.chunkIdKey);
    expect(chunks.map((c) => c.id), entry.chunks.map((c) => c.chunkId));
    for (final c in chunks) {
      expect(hasher.of(c.data), c.id);
    }
  }

  test('полный бэкап: сегменты на узлах, индексы, снимок', () async {
    populate();
    final s = setup('a');
    final progress = <BackupProgress>[];
    final result = await backup(s, progress: progress);
    expect(result.segmentsStored, greaterThan(0));
    expect(result.stats.files, 7);
    expect(s.index.pendingSegments(), isEmpty);
    expect(s.index.segmentsNotInIndex(), isEmpty);
    expect(progress.last.segmentsStored, result.segmentsStored);
    expect(progress.last.bytesRead, (6 << 20) + 4);

    final listing = await SnapshotCatalog(
      crypto: crypto,
      manifestKey: keys.manifestKey,
      store: s.objects,
      index: s.index,
    ).list();
    expect(listing.snapshots.single.snapshotId, result.snapshot.snapshotId);

    final recovered = LocalIndex.inMemory();
    final report = await recoverIndex(
      crypto: crypto,
      manifestKey: keys.manifestKey,
      store: s.objects,
      index: recovered,
    );
    expect(report.segmentsAdded, result.segmentsStored);
    expect(recovered.chunkCount, s.index.chunkCount);

    final segmentIds = [
      for (final o in await s.objects.list(ObjectKind.indexObject))
        for (final r in ManifestObjects.openIndex(
          crypto,
          keys.manifestKey,
          await s.objects.get(ObjectKind.indexObject, o.id),
        ).segments)
          Uint8List.fromList(r.segmentId),
    ];
    expect(segmentIds, hasLength(result.segmentsStored));
    for (final id in segmentIds) {
      final placed = s.index.fragments(id);
      expect(
        placed.map((f) => f.node).toSet(),
        hasLength(20),
        reason: 'по фрагменту на узел',
      );
      await checkSegment(s, id);
    }
    s.index.close();
  });

  test('второй бэкап без изменений: ничего не читает и не пишет', () async {
    populate();
    final s = setup('a');
    final first = await backup(s);
    final second = await backup(s);
    expect(second.stats.filesRead, 0);
    expect(second.segmentsStored, 0);
    expect(second.snapshot.rootTree, first.snapshot.rootTree);
    expect(second.snapshot.parentSnapshotId, first.snapshot.snapshotId);
    expect(
      second.snapshot.sequence.toInt(),
      first.snapshot.sequence.toInt() + 1,
    );
    s.index.close();
  });

  test('3 недоступных узла из 20 — бэкап проходит, 4 — нет', () async {
    populate(megabytes: 1);
    final ok = setup(
      'ok',
      faults: const FaultPlan(
        unavailableNodes: {'node-01', 'node-05', 'node-09'},
      ),
    );
    final result = await backup(ok);
    expect(ok.index.segmentsNotInIndex(), isEmpty);
    expect(result.segmentsStored, greaterThan(0));
    ok.index.close();

    final bad = setup(
      'bad',
      faults: const FaultPlan(
        unavailableNodes: {'node-01', 'node-05', 'node-09', 'node-13'},
      ),
    );
    await expectLater(backup(bad), throwsA(isA<InsufficientShardsException>()));
    expect(await bad.objects.list(ObjectKind.snapshot), isEmpty);
    bad.index.close();
  });

  test(
    'прерванный и продолженный бэкап = непрерывный; готовое не отправляется',
    () async {
      populate(megabytes: 40);
      final whole = setup('whole');
      final reference = await backup(whole);
      expect(reference.segmentsStored, greaterThanOrEqualTo(3));
      whole.index.close();

      final s = setup('resume');
      final first = _Recording(s.nodes)
        ..token = CancellationToken()
        ..cancelAfter = 20 * 2; // два сегмента записаны целиком
      await expectLater(
        backup(s, fragments: first, cancel: first.token),
        throwsA(isA<CancelledException>()),
      );
      expect(await s.objects.list(ObjectKind.snapshot), isEmpty);
      // Индексы не записаны до отмены, поэтому все сохранённые сегменты —
      // среди «не в индексе».
      final storedBefore = {
        for (final e in s.index.segmentsNotInIndex()) bytesToHex(e.segmentId),
      };
      expect(storedBefore, isNotEmpty);
      expect(
        storedBefore.length,
        lessThan(reference.segmentsStored),
        reason: 'прервано на середине',
      );

      final second = _Recording(s.nodes);
      final resumed = await backup(s, fragments: second);
      expect(resumed.snapshot.rootTree, reference.snapshot.rootTree);
      final resent = second.segmentsPut
          .map(bytesToHex)
          .toSet()
          .intersection(storedBefore);
      expect(
        resent,
        isEmpty,
        reason: 'сохранённые сегменты не отправлены повторно',
      );
      expect(
        s.index.segmentsNotInIndex(),
        isEmpty,
        reason: 'сегменты первого запуска попали в индексы',
      );

      final recovered = LocalIndex.inMemory();
      await recoverIndex(
        crypto: crypto,
        manifestKey: keys.manifestKey,
        store: s.objects,
        index: recovered,
      );
      expect(recovered.chunkCount, s.index.chunkCount);
      s.index.close();
    },
  );

  test(
    'сбой записи: недописанный сегмент отбрасывается следующим бэкапом',
    () async {
      populate(megabytes: 2);
      final dbPath = '${dir.path}/crash/index.db';
      final failing = (
        index: LocalIndex.open(dbPath),
        nodes: LocalFolderStore(
          Directory('${dir.path}/crash/nodes'),
          crypto,
          nodeCount: 20,
          faults: const FaultPlan(failWriteRate: 1),
        ),
        objects: LocalObjectStore(Directory('${dir.path}/crash/objects')),
      );
      await expectLater(
        backup(failing),
        throwsA(isA<InsufficientShardsException>()),
      );
      expect(failing.index.pendingSegments(), isNotEmpty);
      failing.index.close();

      final healthy = (
        index: LocalIndex.open(dbPath),
        nodes: LocalFolderStore(
          Directory('${dir.path}/crash/nodes'),
          crypto,
          nodeCount: 20,
        ),
        objects: failing.objects,
      );
      final result = await backup(healthy);
      expect(result.discardedSegments, greaterThan(0));
      expect(healthy.index.pendingSegments(), isEmpty);
      expect(
        result.stats.newChunks,
        greaterThan(0),
        reason: 'чанки отброшенных сегментов упакованы заново',
      );
      healthy.index.close();
    },
  );

  test('прогресс: доля по сделанному, а не по обходу', () async {
    populate(megabytes: 4);
    final s = setup('slow');
    final progress = <BackupProgress>[];
    final result = await backup(
      s,
      fragments: _Slow(s.nodes, const Duration(milliseconds: 40)),
      progress: progress,
    );
    expect(result.stats.files, 5);
    // Обход уходит вперёд: пока сегменты ждут узлов, сделано меньше, чем
    // прочитано, — полоса не должна стоять целой.
    expect(
      progress.any((p) => p.doneBytes < p.bytes),
      isTrue,
      reason: 'есть точка, где часть прочитанного ещё не сохранена',
    );
    expect(
      progress.every((p) => p.doneBytes <= p.bytes),
      isTrue,
      reason: 'сделано не больше обработанного',
    );
    expect(progress.last.doneBytes, progress.last.bytes);
    s.index.close();
  });

  test('прогресс: неизменённые файлы сделаны сразу', () async {
    populate(megabytes: 4);
    final s = setup('cached');
    await backup(s);
    final progress = <BackupProgress>[];
    final result = await backup(
      s,
      fragments: _Slow(s.nodes, const Duration(milliseconds: 40)),
      progress: progress,
    );
    expect(result.stats.newChunks, 0);
    expect(progress.last.doneBytes, progress.last.bytes);
    expect(progress.last.doneBytes, result.stats.bytes);
    s.index.close();
  });

  test('пул isolate даёт тот же снимок, что кодирование в потоке', () async {
    populate(megabytes: 20);
    final inline = setup('inline');
    final a = await backup(inline);
    inline.index.close();
    final pool = await IsolateSegmentEncoder.start(2);
    addTearDown(pool.close);
    final isolated = setup('pool');
    final b = await backup(isolated, encoder: pool);
    expect(b.snapshot.rootTree, a.snapshot.rootTree);
    expect(b.segmentsStored, a.segmentsStored);
    expect(isolated.index.segmentsNotInIndex(), isEmpty);
    final seg = (await recoverIndex(
      crypto: crypto,
      manifestKey: keys.manifestKey,
      store: isolated.objects,
      index: LocalIndex.inMemory(),
    )).segmentsAdded;
    expect(seg, b.segmentsStored);
    isolated.index.close();
  });
}
