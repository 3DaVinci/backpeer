import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

ChunkId _id(int b) => ChunkId(Uint8List(32)..[0] = b);

SegmentEntry _segment(int b, List<int> chunkBytes) => SegmentEntry(
  segmentId: Uint8List(32)..[31] = b,
  k: 2,
  n: 3,
  blobLength: 1000,
  shardSize: 512,
  fragmentIds: [for (var i = 0; i < 3; i++) Uint8List(32)..[0] = b * 10 + i],
  chunks: [
    for (var i = 0; i < chunkBytes.length; i++)
      SegmentChunk(
        chunkId: _id(chunkBytes[i]),
        type: 1,
        offset: i * 100,
        length: 100,
      ),
  ],
);

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('fs-index-'));
  tearDown(() => dir.deleteSync(recursive: true));
  String dbPath() => '${dir.path}/index/index.db';

  test('создание и миграция до последней версии', () {
    final index = LocalIndex.open(dbPath());
    expect(index.schemaVersion, LocalIndex.latestVersion);
    index.close();
    final again = LocalIndex.open(dbPath());
    expect(again.schemaVersion, LocalIndex.latestVersion);
    again.close();
  });

  test('база новее программы — ошибка формата', () {
    LocalIndex.open(dbPath()).close();
    sqlite3.open(dbPath())
      ..userVersion = LocalIndex.latestVersion + 1
      ..close();
    expect(
      () => LocalIndex.open(dbPath()),
      throwsA(
        isA<DataFormatException>().having(
          (e) => e.problem,
          'problem',
          FormatProblem.unsupportedVersion,
        ),
      ),
    );
  });

  test('не база SQLite — StorageException', () {
    File(dbPath())
      ..createSync(recursive: true)
      ..writeAsStringSync('not a database' * 100);
    expect(() => LocalIndex.open(dbPath()), throwsA(isA<StorageException>()));
  });

  test('сегменты, чанки и фрагменты', () {
    final index = LocalIndex.inMemory()
      ..addSegment(_segment(1, [1, 2]))
      ..addSegment(_segment(2, [2, 3]));
    expect(index.chunkCount, 3);
    final two = index.findChunk(_id(2))!;
    expect(two.segmentId[31], 1, reason: 'первое вхождение не перезаписано');
    expect(two.stored, isFalse);
    expect(index.findChunk(_id(9)), isNull);
    expect(index.pendingSegments().map((s) => s[31]), [1, 2]);

    final seg1 = _segment(1, const []).segmentId;
    index
      ..setFragmentNode(seg1, 0, 'node-a')
      ..markSegmentStored(seg1);
    expect(index.findChunk(_id(1))!.stored, isTrue);
    expect(index.pendingSegments().map((s) => s[31]), [2]);
    final fragments = index.fragments(seg1);
    expect(fragments.map((f) => f.node), ['node-a', null, null]);
    expect(fragments[2].fragmentId[0], 12);
    expect(
      () => index.markSegmentStored(Uint8List(32)),
      throwsA(isA<StorageException>()),
    );
  });

  test('транзакция откатывается при исключении', () {
    final index = LocalIndex.inMemory();
    expect(
      () => index.transaction(() {
        index.addSegment(_segment(1, [1]));
        throw StateError('сбой');
      }),
      throwsStateError,
    );
    expect(index.chunkCount, 0);
    expect(index.pendingSegments(), isEmpty);
  });

  test('кеш файлов', () {
    final index = LocalIndex.inMemory();
    final path = Uint8List.fromList([0x2F, 0x61, 0xFF]); // не UTF-8
    const stamp = FileStamp(size: 10, mtimeNs: 5, ctimeNs: 6, inode: 9);
    expect(index.cachedFile(path, stamp), isNull);
    index.putFile(path, stamp, [_id(1), _id(2)]);
    expect(index.cachedFile(path, stamp), [_id(1), _id(2)]);
    for (final changed in const [
      FileStamp(size: 11, mtimeNs: 5, ctimeNs: 6, inode: 9),
      FileStamp(size: 10, mtimeNs: 7, ctimeNs: 6, inode: 9),
      FileStamp(size: 10, mtimeNs: 5, ctimeNs: 8, inode: 9),
      FileStamp(size: 10, mtimeNs: 5, ctimeNs: 6, inode: 10),
    ]) {
      expect(index.cachedFile(path, changed), isNull);
    }
    index.putFile(path, stamp, const []);
    expect(index.cachedFile(path, stamp), isEmpty);
    index.removeFile(path);
    expect(index.cachedFile(path, stamp), isNull);
  });

  test('FileStamp из FileStat меняется при записи в файл', () {
    final file = File('${dir.path}/f')..writeAsStringSync('a');
    final before = FileStamp.fromStat(file.statSync());
    sleep(const Duration(milliseconds: 20));
    file.writeAsStringSync('b');
    final after = FileStamp.fromStat(file.statSync());
    expect(after.size, before.size);
    expect((
      after.mtimeNs,
      after.ctimeNs,
    ), isNot((before.mtimeNs, before.ctimeNs)));
  });

  test(
    'процесс убит посреди транзакции — база цела, изменений нет',
    () async {
      LocalIndex.open(dbPath())
        ..addSegment(_segment(1, [1]))
        ..close();
      final child = await Process.start(Platform.resolvedExecutable, [
        'run',
        'test/support/index_crash_writer.dart',
        dbPath(),
      ]);
      final ready = child.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .firstWhere((line) => line == 'ready');
      await ready.timeout(const Duration(minutes: 2));
      expect(child.kill(ProcessSignal.sigkill), isTrue);
      await child.exitCode;

      final reopened = LocalIndex.open(dbPath());
      expect(reopened.pendingSegments(), hasLength(1));
      expect(reopened.findChunk(_id(1)), isNotNull);
      reopened.close();
      final check = sqlite3.open(dbPath());
      expect(check.select('PRAGMA integrity_check').first.values.first, 'ok');
      check.close();
    },
    testOn: '!windows',
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
