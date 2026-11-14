import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:test/test.dart';

/// Планировщик, который сначала ставит фрагменты на узлы, не принимающие
/// талон (их нет в хранилище), а с [healthyFrom]-й попытки — на настоящие
/// узлы: так выглядит отказ узла и переразмещение сегмента (protocol.md,
/// раздел 5.2).
final class _Placer implements SegmentPlacer {
  new(this.store, {this.healthyFrom = 2});

  final LocalFolderStore store;
  final int healthyFrom;

  int allocations = 0;
  int commits = 0;

  @override
  Future<List<FragmentTarget?>> allocate(SegmentAllocation segment) async {
    allocations++;
    if (allocations < healthyFrom) {
      return [
        for (var i = 0; i < segment.n; i++)
          FragmentTarget(index: i, node: 'no-such-node-$i'),
      ];
    }
    final nodes = placeFragments(segment.segmentId, store.nodes, segment.n);
    return [
      for (var i = 0; i < segment.n; i++)
        FragmentTarget(index: i, node: nodes[i]),
    ];
  }

  @override
  Future<void> commit(Uint8List segmentId, List<int> storedIndexes) async {
    commits++;
  }
}

void main() {
  late CryptoProvider crypto;
  late AccountKeys keys;
  final deviceId = Uint8List(32)..[0] = 0x11;
  late Directory dir;
  late Directory data;

  setUpAll(() async {
    crypto = await SodiumCryptoProvider.load();
    keys = await AccountKeys.fromPhrase(
      RecoveryPhrase.fromEntropy(Uint8List(32)),
      crypto,
    );
  });
  setUp(() {
    dir = Directory.systemTemp.createTempSync('fs-realloc-');
    data = Directory('${dir.path}/data')..createSync();
    File('${data.path}/note.txt').writeAsStringSync('заново');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  ({LocalIndex index, _Placer placer, Future<BackupResult> run}) start({
    int healthyFrom = 2,
  }) {
    final nodes = LocalFolderStore(
      Directory('${dir.path}/nodes'),
      crypto,
      nodeCount: 20,
    );
    final index = LocalIndex.open('${dir.path}/index.db');
    final placer = _Placer(nodes, healthyFrom: healthyFrom);
    final run = runBackup(
      crypto: crypto,
      keys: keys,
      index: index,
      fragments: nodes,
      objects: LocalObjectStore(Directory('${dir.path}/objects')),
      placer: placer,
      paths: [data.path],
      deviceId: deviceId,
    );
    return (index: index, placer: placer, run: run);
  }

  test('узел не принял фрагменты — сегмент размещается заново, бэкап '
      'проходит', () async {
    final b = start();
    final result = await b.run;
    expect(b.placer.allocations, 2, reason: 'первое размещение отказало');
    expect(b.placer.commits, 1);
    expect(result.segmentsStored, 1);
    final segments = b.index.storedSegments();
    expect(segments, hasLength(1));
    expect(b.index.pendingSegments(), isEmpty);
    final fragments = b.index.fragments(segments.single);
    expect(fragments.map((f) => f.node).toSet(), hasLength(20));
    expect(fragments.every((f) => f.node != null), isTrue);
  });

  test('все попытки размещения неудачны — бэкап падает, сегмент не '
      'подтверждён', () async {
    final b = start(healthyFrom: 99);
    await expectLater(
      b.run,
      throwsA(
        isA<InsufficientShardsException>().having(
          (e) => e.available,
          'available',
          0,
        ),
      ),
    );
    expect(b.placer.allocations, 2, reason: 'по умолчанию две попытки');
    expect(b.placer.commits, 0);
    expect(b.index.pendingSegments(), hasLength(1));
    expect(b.index.storedSegments(), isEmpty);
  });
}
