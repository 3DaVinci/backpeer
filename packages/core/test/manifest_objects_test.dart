import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:fixnum/fixnum.dart';
import 'package:protocol/protocol.dart' as pb;
import 'package:test/test.dart';
import 'package:test_vectors/test_vectors.dart';

void main() {
  late CryptoProvider crypto;
  final key = SecretBytes(Uint8List(32)..[0] = 9);
  setUpAll(() async => crypto = await SodiumCryptoProvider.load());

  Uint8List id(int b) => Uint8List(32)..[0] = b;

  pb.Snapshot snapshot() => pb.Snapshot(
    formatVersion: 1,
    snapshotId: id(1),
    sequence: Int64(7),
    parentSnapshotId: id(2),
    createdAtUnixMs: Int64(1792000000000),
    hostname: 'host',
    deviceId: id(3),
    paths: ['/home/u'],
    rootTree: [id(4)],
    stats: pb.SnapshotStats(files: Int64(10)),
  );

  group('manifest/encoding.json: байты сохраняются через блоб', () {
    for (final c in vectorCases(loadVectors('manifest/encoding.json'))) {
      final type = (c['input']! as Map<String, Object?>)['messageType'];
      if (type == 'fs.v1.Tree') continue; // деревья — чанки, не блобы
      test(c['name'], () {
        final bytes = hexToBytes(
          (c['expected']! as Map<String, Object?>)['bytes']! as String,
        );
        if (type == 'fs.v1.Snapshot') {
          final s = pb.Snapshot.fromBuffer(bytes);
          final blob = ManifestObjects.sealSnapshot(crypto, key, s);
          final back = ManifestObjects.openSnapshot(crypto, key, blob);
          expect(back.writeToBuffer(), bytes);
        } else {
          final i = pb.Index.fromBuffer(bytes);
          final blob = ManifestObjects.sealIndex(crypto, key, i);
          final back = ManifestObjects.openIndex(crypto, key, blob);
          expect(back.writeToBuffer(), bytes);
        }
      });
    }
  });

  group('снимок', () {
    test('туда и обратно, ожидаемый идентификатор', () {
      final blob = ManifestObjects.sealSnapshot(crypto, key, snapshot());
      expect(BlobHeader.parse(blob).type, BlobType.snapshot);
      final back = ManifestObjects.openSnapshot(
        crypto,
        key,
        blob,
        expectedId: id(1),
      );
      expect(back.sequence.toInt(), 7);
      expect(
        () =>
            ManifestObjects.openSnapshot(crypto, key, blob, expectedId: id(9)),
        throwsA(isA<IntegrityException>()),
      );
      expect(
        () => ManifestObjects.openIndex(crypto, key, blob),
        throwsA(isA<DataFormatException>()),
      );
    });

    test('неизвестная версия формата — format', () {
      final blob = ManifestObjects.sealSnapshot(
        crypto,
        key,
        snapshot()..formatVersion = 2,
      );
      expect(
        () => ManifestObjects.openSnapshot(crypto, key, blob),
        throwsA(isA<DataFormatException>()),
      );
    });

    test('идентификатор внутри не совпадает с блобом — integrity', () {
      final s = snapshot();
      final blob = EncryptedBlob.seal(
        crypto,
        type: BlobType.snapshot,
        objectId: id(5),
        key: key,
        plaintext: s.writeToBuffer(),
      );
      expect(
        () => ManifestObjects.openSnapshot(crypto, key, blob),
        throwsA(isA<IntegrityException>()),
      );
    });

    test('мусор вместо Protobuf — format', () {
      final blob = EncryptedBlob.seal(
        crypto,
        type: BlobType.snapshot,
        objectId: id(1),
        key: key,
        plaintext: Uint8List.fromList([0xFF, 0xFF, 0xFF]),
      );
      expect(
        () => ManifestObjects.openSnapshot(crypto, key, blob),
        throwsA(isA<DataFormatException>()),
      );
    });
  });

  group('IndexBuilder', () {
    pb.SegmentRecord record(int i) => pb.SegmentRecord(
      segmentId: id(i & 0xFF)..[1] = i >> 8,
      k: 10,
      n: 20,
      blobLength: 16 << 20,
      shardSize: 1 << 20,
      fragmentIds: [for (var f = 0; f < 20; f++) id(f)],
      chunks: [
        for (var c = 0; c < 14; c++)
          pb.ChunkEntry(
            chunkId: id(c),
            type: pb.ChunkType.CHUNK_TYPE_CONTENT,
            offset: c * 1000,
            length: 1000,
          ),
      ],
    );

    test('режет индексы по 4 МиБ и ничего не теряет', () {
      var next = 0;
      final builder = IndexBuilder(() => id(200)..[1] = next++);
      const count = 6000;
      for (var i = 0; i < count; i++) {
        builder.add(record(i));
      }
      final indexes = builder.finish();
      expect(indexes.length, greaterThan(1));
      var total = 0;
      for (final index in indexes) {
        final length = index.writeToBuffer().length;
        expect(length, lessThanOrEqualTo(maxIndexLength));
        total += index.segments.length;
        final blob = ManifestObjects.sealIndex(crypto, key, index);
        expect(
          ManifestObjects.openIndex(crypto, key, blob).segments.length,
          index.segments.length,
        );
      }
      expect(total, count);
      // Все индексы, кроме последнего, заполнены почти до предела.
      expect(
        indexes.first.writeToBuffer().length,
        greaterThan(maxIndexLength - 2000),
      );
      expect(builder.finish(), isEmpty);
    });

    test('малый предел', () {
      final builder = IndexBuilder(() => id(1), limit: 3000);
      for (var i = 0; i < 5; i++) {
        builder.add(record(i));
      }
      final indexes = builder.finish();
      for (final index in indexes) {
        expect(index.writeToBuffer().length, lessThanOrEqualTo(3000));
      }
      expect(indexes.fold(0, (s, i) => s + i.segments.length), 5);
    });
  });

  group('защита от отката', () {
    test('предупреждения и номер следующего снимка', () {
      final listed = [(id: id(1), sequence: 5), (id: id(2), sequence: 6)];
      expect(
        checkRollback(listed, knownMaxSequence: 6, lastOwnSnapshot: id(2)),
        isEmpty,
      );
      expect(
        checkRollback(listed, knownMaxSequence: 8, lastOwnSnapshot: id(2)),
        [RollbackWarning.sequenceRegressed],
      );
      expect(
        checkRollback(
          listed.sublist(0, 1),
          knownMaxSequence: 5,
          lastOwnSnapshot: id(2),
        ),
        [RollbackWarning.lastSnapshotMissing],
      );
      expect(nextSequence(listed, 3), 7);
      expect(nextSequence(listed, 9), 10);
      expect(nextSequence(const [], 0), 1);
    });

    test('состояние в локальном индексе переживает перезапуск', () {
      final dir = Directory.systemTemp.createTempSync('fs-state-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/index.db';
      final index = LocalIndex.open(path);
      expect(index.maxSequence, 0);
      expect(index.lastOwnSnapshot, isNull);
      index
        ..recordOwnSnapshot(id(1), 4)
        ..observeSequence(3)
        ..observeSequence(9)
        ..close();
      final again = LocalIndex.open(path);
      expect(again.maxSequence, 9);
      expect(again.lastOwnSnapshot, id(1));
      expect(again.schemaVersion, 2);
      again.close();
    });
  });
}
