import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:fixnum/fixnum.dart';
import 'package:protocol/protocol.dart' as pb;
import 'package:test/test.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('fs-catalog-'));
  tearDown(() => dir.deleteSync(recursive: true));

  group('SnapshotCatalog', () {
    late CryptoProvider crypto;
    late SnapshotCatalog catalog;
    late LocalIndex index;
    final key = SecretBytes(Uint8List(32)..[0] = 3);
    setUp(() async {
      crypto = await SodiumCryptoProvider.load();
      index = LocalIndex.inMemory();
      catalog = SnapshotCatalog(
        crypto: crypto,
        manifestKey: key,
        store: LocalObjectStore(dir),
        index: index,
      );
    });
    tearDown(() => index.close());

    pb.Snapshot snapshot(int b, int sequence, [int? parent]) => pb.Snapshot(
      formatVersion: 1,
      snapshotId: Uint8List(32)..[0] = b,
      sequence: Int64(sequence),
      parentSnapshotId: parent == null ? null : (Uint8List(32)..[0] = parent),
      paths: ['/data'],
      rootTree: [Uint8List(32)],
    );

    test(
      'список по sequence, удалённый не виден, остальные открываются',
      () async {
        await catalog.save(snapshot(0xA1, 1));
        await catalog.save(snapshot(0xB2, 2, 0xA1));
        await catalog.save(snapshot(0xC3, 3, 0xB2));
        var listing = await catalog.list();
        expect(listing.snapshots.map((s) => s.sequence.toInt()), [1, 2, 3]);
        expect(listing.warnings, isEmpty);

        await catalog.forget((await catalog.matching('b2')).single);
        listing = await catalog.list();
        expect(listing.snapshots.map((s) => s.snapshotId[0]), [0xA1, 0xC3]);
        expect(listing.warnings, isEmpty);
        for (final s in listing.snapshots) {
          expect((await catalog.get(Uint8List.fromList(s.snapshotId))).paths, [
            '/data',
          ]);
        }
      },
    );

    test('удаление последнего снимка устройства — не откат', () async {
      await catalog.save(snapshot(0xA1, 1));
      await catalog.save(snapshot(0xB2, 2, 0xA1));
      await catalog.forget(Uint8List(32)..[0] = 0xB2);
      expect(index.lastOwnSnapshot?[0], 0xA1);
      expect(index.maxSequence, 1);
      expect((await catalog.list()).warnings, isEmpty);
      await catalog.forget(Uint8List(32)..[0] = 0xA1);
      expect(index.lastOwnSnapshot, isNull);
    });

    test('подмена списка старым — предупреждение', () async {
      await catalog.save(snapshot(0xA1, 1));
      final store = LocalObjectStore(dir);
      final oldBlob = await store.get(
        ObjectKind.snapshot,
        Uint8List(32)..[0] = 0xA1,
      );
      await catalog.save(snapshot(0xB2, 2, 0xA1));
      // Координатор прячет новый снимок.
      await store.delete(ObjectKind.snapshot, Uint8List(32)..[0] = 0xB2);
      await store.put(
        ObjectKind.snapshot,
        Uint8List(32)..[0] = 0xA1,
        oldBlob,
        sequence: 1,
      );
      final listing = await catalog.list();
      expect(listing.warnings, [
        RollbackWarning.sequenceRegressed,
        RollbackWarning.lastSnapshotMissing,
      ]);
    });

    test(
      'чужой или повреждённый объект — в unreadable, остальные видны',
      () async {
        await catalog.save(snapshot(0xA1, 1));
        final store = LocalObjectStore(dir);
        await store.put(
          ObjectKind.snapshot,
          Uint8List(32)..[0] = 0xEE,
          Uint8List(100),
          sequence: 2,
        );
        final listing = await catalog.list();
        expect(listing.snapshots, hasLength(1));
        expect(listing.unreadable.single.$2, isA<DataFormatException>());
      },
    );

    test('matching: префикс, неоднозначность, неизвестный', () async {
      await catalog.save(snapshot(0xA1, 1));
      await catalog.save(snapshot(0xA2, 2));
      expect(await catalog.matching('a'), hasLength(2));
      expect((await catalog.matching('A100')).single[0], 0xA1);
      expect(await catalog.matching('ffff'), isEmpty);
      expect(await catalog.matching('xyz'), isEmpty);
    });
  });
}
