// Простая сборка мусора (задача 2.7.4; manifest.md, раздел 7): после
// удаления снимка ненужные сегменты уходят из индексов и с узлов, нужные
// остаются, оставшийся снимок восстанавливается.

import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:test/test.dart';
import 'package:test_vectors/test_vectors.dart';

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
  late LocalIndex index;
  late LocalFolderStore nodes;
  late LocalObjectStore objects;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('fs-gc-');
    index = LocalIndex.open('${dir.path}/index.db');
    nodes = LocalFolderStore(
      Directory('${dir.path}/nodes'),
      crypto,
      nodeCount: 6,
    );
    objects = LocalObjectStore(Directory('${dir.path}/objects'));
  });
  tearDown(() {
    index.close();
    dir.deleteSync(recursive: true);
  });

  final params = DurabilityParameters(k: 2, n: 4, repairThreshold: 3);

  Future<BackupResult> backup(Directory data) => runBackup(
    crypto: crypto,
    keys: keys,
    index: index,
    fragments: nodes,
    objects: objects,
    paths: [data.path],
    deviceId: deviceId,
    params: params,
  );

  Future<GarbageReport> gc({bool dryRun = false, LocalIndex? on}) =>
      collectGarbage(
        crypto: crypto,
        keys: keys,
        index: on ?? index,
        fragments: nodes,
        objects: objects,
        releaser: LocalSegmentReleaser(on ?? index, nodes),
        dryRun: dryRun,
      );

  int nodeBytes() =>
      Directory('${dir.path}/nodes')
          .listSync(recursive: true)
          .whereType<File>()
          .fold(0, (sum, f) => sum + f.lengthSync());

  SnapshotCatalog catalog([LocalIndex? on]) => SnapshotCatalog(
    crypto: crypto,
    manifestKey: keys.manifestKey,
    store: objects,
    index: on ?? index,
  );

  test('после удаления снимка и сборки мусора место уменьшается', () async {
    final a = Directory('${dir.path}/a')..createSync();
    final b = Directory('${dir.path}/b')..createSync();
    File('${a.path}/big.bin').writeAsBytesSync(splitmix64Bytes(1, 3 << 20));
    File('${b.path}/other.bin').writeAsBytesSync(splitmix64Bytes(2, 2 << 20));
    final first = await backup(a);
    final second = await backup(b);
    final before = nodeBytes();
    final segmentsBefore = index.storedSegments().length;

    // Ничего не удалено — мусора нет.
    var report = await gc();
    expect(report.segmentsDeleted, 0);
    expect(report.snapshots, 2);
    expect(nodeBytes(), before);

    await catalog().forget(Uint8List.fromList(first.snapshot.snapshotId));
    final dry = await gc(dryRun: true);
    expect(dry.segmentsDeleted, greaterThan(0));
    expect(nodeBytes(), before, reason: 'пробный запуск ничего не удаляет');

    report = await gc();
    expect(report.segmentsDeleted, dry.segmentsDeleted);
    expect(report.fragmentsDeleted, report.segmentsDeleted * params.n);
    expect(report.fragmentErrors, isEmpty);
    expect(report.indexesRewritten, greaterThan(0));
    expect(nodeBytes(), before - report.bytesFreed);
    expect(nodeBytes(), lessThan(before));
    expect(
      index.storedSegments().length,
      segmentsBefore - report.segmentsDeleted,
    );

    // Индексы на «координаторе» больше не ссылаются на удалённое: новое
    // устройство восстанавливает только живые сегменты.
    final fresh = LocalIndex.inMemory();
    final recovered = await recoverIndex(
      crypto: crypto,
      manifestKey: keys.manifestKey,
      store: objects,
      index: fresh,
    );
    expect(recovered.unreadable, isEmpty);
    expect(fresh.storedSegments().length, report.segmentsLive);

    // Оставшийся снимок восстанавливается целиком.
    final target = Directory('${dir.path}/restored');
    final restored = await runRestore(
      crypto: crypto,
      keys: keys,
      index: fresh,
      fragments: nodes,
      objects: objects,
      snapshotId: Uint8List.fromList(second.snapshot.snapshotId),
      target: target,
    );
    expect(restored.errors, isEmpty);
    expect(
      File('${target.path}${b.path}/other.bin').readAsBytesSync(),
      splitmix64Bytes(2, 2 << 20),
    );
    fresh.close();

    // Повторная сборка — ничего нового.
    expect((await gc()).segmentsDeleted, 0);
  });

  test('общие чанки удерживают сегмент', () async {
    final a = Directory('${dir.path}/a')..createSync();
    File('${a.path}/same.bin').writeAsBytesSync(splitmix64Bytes(3, 1 << 20));
    final first = await backup(a);
    File('${a.path}/extra.bin').writeAsBytesSync(splitmix64Bytes(4, 1 << 20));
    await backup(a);
    await catalog().forget(Uint8List.fromList(first.snapshot.snapshotId));
    final before = index.storedSegments().length;
    final report = await gc();
    // Данные first целиком входят во второй снимок; уйти может только
    // сегмент с деревом первого снимка, если он отдельный.
    expect(index.storedSegments().length, before - report.segmentsDeleted);
    final target = Directory('${dir.path}/r');
    final listing = await catalog().list();
    final restored = await runRestore(
      crypto: crypto,
      keys: keys,
      index: index,
      fragments: nodes,
      objects: objects,
      snapshotId: Uint8List.fromList(listing.snapshots.single.snapshotId),
      target: target,
    );
    expect(restored.errors, isEmpty);
    expect(
      File('${target.path}${a.path}/same.bin').readAsBytesSync(),
      splitmix64Bytes(3, 1 << 20),
    );
  });

  test('откат списка снимков останавливает сборку', () async {
    final a = Directory('${dir.path}/a')..createSync();
    File('${a.path}/x.bin').writeAsBytesSync(splitmix64Bytes(5, 1 << 20));
    final first = await backup(a);
    // «Координатор» спрятал снимок: удалён в обход каталога.
    await objects.delete(
      ObjectKind.snapshot,
      Uint8List.fromList(first.snapshot.snapshotId),
    );
    await expectLater(gc(), throwsA(isA<PreconditionException>()));
    expect(index.storedSegments(), isNotEmpty);
  });
}
