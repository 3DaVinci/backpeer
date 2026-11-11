import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:test/test.dart';
import 'package:test_vectors/test_vectors.dart';

typedef _Setup = ({
  LocalIndex index,
  LocalFolderStore nodes,
  LocalObjectStore objects,
});

void main() {
  late CryptoProvider crypto;
  late AccountKeys keys;
  setUpAll(() async {
    crypto = await SodiumCryptoProvider.load();
    keys = await AccountKeys.fromPhrase(
      RecoveryPhrase.fromEntropy(Uint8List(32)..[5] = 1),
      crypto,
    );
  });

  late Directory dir;
  late Directory data;
  late _Setup s;
  late BackupResult backup;
  setUp(() async {
    dir = Directory.systemTemp.createTempSync('fs-restore-');
    data = Directory('${dir.path}/data')..createSync();
    File('${data.path}/a.bin').writeAsBytesSync(splitmix64Bytes(1, 18 << 20));
    File('${data.path}/empty').createSync();
    Directory('${data.path}/empty-dir').createSync();
    File('${data.path}/sub/deep/z.txt')
      ..createSync(recursive: true)
      ..writeAsStringSync('глубоко');
    File('${data.path}/sub/run.sh').writeAsStringSync('#!/bin/sh\n');
    if (!Platform.isWindows) {
      Process.runSync('chmod', ['755', '${data.path}/sub/run.sh']);
      Process.runSync('chmod', ['640', '${data.path}/a.bin']);
      Process.runSync('chmod', ['750', '${data.path}/sub/deep']);
      Link('${data.path}/link').createSync('sub/deep/z.txt');
      Link('${data.path}/dangling').createSync('nowhere');
    }
    if (Platform.isLinux) {
      final name = Uint8List.fromList([
        ...utf8.encode('${data.path}/'),
        0xFF,
        0x41,
      ]);
      File.fromRawPath(name).writeAsStringSync('raw');
    }
    s = (
      index: LocalIndex.open('${dir.path}/index.db'),
      nodes: LocalFolderStore(
        Directory('${dir.path}/nodes'),
        crypto,
        nodeCount: 20,
      ),
      objects: LocalObjectStore(Directory('${dir.path}/objects')),
    );
    backup = await runBackup(
      crypto: crypto,
      keys: keys,
      index: s.index,
      fragments: s.nodes,
      objects: s.objects,
      paths: [data.path],
      deviceId: Uint8List(32),
    );
  });
  tearDown(() {
    s.index.close();
    dir.deleteSync(recursive: true);
  });

  Future<RestoreResult> restore(
    Directory target, {
    List<String> paths = const [],
    bool overwrite = false,
    ExistingFiles? existing,
    bool originalLocation = false,
    LocalIndex? index,
    FragmentStore? fragments,
    void Function(RestoreProgress)? onProgress,
  }) => runRestore(
    crypto: crypto,
    keys: keys,
    index: index ?? s.index,
    fragments: fragments ?? s.nodes,
    objects: s.objects,
    snapshotId: Uint8List.fromList(backup.snapshot.snapshotId),
    target: originalLocation ? null : target,
    originalLocation: originalLocation,
    paths: paths,
    overwrite: overwrite,
    existing: existing,
    onProgress: onProgress,
  );

  Directory restoredRoot(Directory target) =>
      Directory('${target.path}${data.path}');

  /// Дерево с метаданными для сравнения: путь → (вид, размер, права,
  /// mtime, цель ссылки, хэш содержимого).
  Map<String, Object> snapshotOf(Directory root) {
    final walker = TreeWalker();
    final out = <String, Object>{};
    for (final item in walker.walk(TreeWalker.rootPath(root.path))) {
      final e = item.entry;
      out[item.relative] = (
        e.kind,
        e.kind == EntryKind.file ? e.size : 0,
        e.mode,
        e.mtimeNs,
        e.kind == EntryKind.symlink
            ? utf8.decode(walker.readLink(item.path)!)
            : '',
        e.kind == EntryKind.file
            ? bytesToHex(
                crypto.blake2b256(
                  File.fromRawPath(item.path).readAsBytesSync(),
                ),
              )
            : '',
      );
    }
    return out;
  }

  test('полный снимок: файлы и метаданные совпадают побайтно', () async {
    final target = Directory('${dir.path}/out');
    final result = await restore(target);
    expect(result.errors, isEmpty);
    expect(result.files, Platform.isLinux ? 5 : 4);
    final original = snapshotOf(data);
    final restored = snapshotOf(restoredRoot(target));
    expect(restored.keys, unorderedEquals(original.keys));
    for (final key in original.keys) {
      expect(restored[key], original[key], reason: key);
    }
  });

  test('выбранный путь: восстанавливается только он', () async {
    final target = Directory('${dir.path}/out');
    final result = await restore(target, paths: ['${data.path}/sub/deep']);
    expect(result.errors, isEmpty);
    final root = restoredRoot(target);
    expect(File('${root.path}/sub/deep/z.txt').readAsStringSync(), 'глубоко');
    expect(File('${root.path}/a.bin').existsSync(), isFalse);
    expect(File('${root.path}/sub/run.sh').existsSync(), isFalse);
    expect(result.files, 1);
  });

  test('без перезаписи по умолчанию, с overwrite — перезапись', () async {
    final target = Directory('${dir.path}/out');
    await restore(target);
    final file = File('${restoredRoot(target).path}/sub/deep/z.txt')
      ..writeAsStringSync('правка');
    final again = await restore(target);
    expect(again.skippedExisting, isNotEmpty);
    expect(again.files, 0);
    expect(file.readAsStringSync(), 'правка');
    final forced = await restore(target, overwrite: true);
    expect(forced.errors, isEmpty);
    expect(file.readAsStringSync(), 'глубоко');
  });

  test('выбранный путь: объём считается заранее', () async {
    final target = Directory('${dir.path}/out');
    final seen = <int?>[];
    await restore(
      target,
      paths: ['${data.path}/sub', '${data.path}/empty'],
      onProgress: (p) => seen.add(p.totalBytes),
    );
    final expected =
        File('${data.path}/sub/deep/z.txt').lengthSync() +
        File('${data.path}/sub/run.sh').lengthSync();
    expect(seen.last, expected);
  });

  test('keepBoth: существующий остаётся, восстановленный — рядом', () async {
    final target = Directory('${dir.path}/out');
    final paths = ['${data.path}/sub/deep/z.txt'];
    await restore(target, paths: paths);
    final deep = '${restoredRoot(target).path}/sub/deep';
    File('$deep/z.txt').writeAsStringSync('правка');
    final first = await restore(
      target,
      paths: paths,
      existing: ExistingFiles.keepBoth,
    );
    expect(first.files, 1);
    expect(first.renamed.single.$2, '$deep/z (restored).txt');
    final second = await restore(
      target,
      paths: paths,
      existing: ExistingFiles.keepBoth,
    );
    expect(second.renamed.single.$2, '$deep/z (restored 2).txt');
    expect(File('$deep/z.txt').readAsStringSync(), 'правка');
    expect(File('$deep/z (restored).txt').readAsStringSync(), 'глубоко');
    expect(File('$deep/z (restored 2).txt').readAsStringSync(), 'глубоко');
  });

  test('на исходное место: удалённый файл возвращается', () async {
    final file = File('${data.path}/sub/deep/z.txt');
    final mtime = file.statSync().modified;
    file.deleteSync();
    File('${data.path}/sub/run.sh').writeAsStringSync('правка');
    final result = await restore(
      Directory('${dir.path}/unused'),
      originalLocation: true,
      paths: ['${data.path}/sub'],
    );
    expect(result.errors, isEmpty);
    expect(file.readAsStringSync(), 'глубоко');
    expect(file.statSync().modified, mtime);
    // Существующий без политики не тронут.
    expect(File('${data.path}/sub/run.sh').readAsStringSync(), 'правка');
    expect(result.skippedExisting.single, endsWith('run.sh'));
    expect(Directory('${dir.path}/unused').existsSync(), isFalse);
  });

  test('потеряны любые n − k узлов — восстановление проходит', () async {
    for (var i = 0; i < 10; i++) {
      Directory('${dir.path}/nodes/node-${(i * 2).toString().padLeft(2, '0')}')
          .deleteSync(recursive: true);
    }
    final target = Directory('${dir.path}/out');
    final result = await restore(target);
    expect(result.errors, isEmpty);
    expect(
      File('${restoredRoot(target).path}/a.bin').readAsBytesSync(),
      File('${data.path}/a.bin').readAsBytesSync(),
    );
  });

  test('потеряно больше n − k узлов — снимок не читается', () async {
    for (var i = 0; i < 11; i++) {
      Directory('${dir.path}/nodes/node-${i.toString().padLeft(2, '0')}')
          .deleteSync(recursive: true);
    }
    await expectLater(
      restore(Directory('${dir.path}/out')),
      throwsA(isA<InsufficientShardsException>()),
    );
  });

  test('недоступны сегменты с данными — ошибки по файлам', () async {
    var damaged = 0;
    for (final id in s.index.storedSegments()) {
      final entry = s.index.segment(id)!;
      if (entry.chunks.any((c) => c.type == ChunkType.tree.code)) continue;
      for (final f in s.index.fragments(id).take(11)) {
        await s.nodes.delete(f.node!, f.fragmentId);
      }
      damaged++;
    }
    expect(damaged, greaterThan(0), reason: 'a.bin занимает свой сегмент');
    final target = Directory('${dir.path}/out');
    final result = await restore(target);
    expect(result.errors.map((e) => e.$1), contains(endsWith('a.bin')));
    expect(result.isComplete, isFalse);
    expect(File('${restoredRoot(target).path}/a.bin').existsSync(), isFalse);
    expect(
      Directory('${restoredRoot(target).path}/empty-dir').existsSync(),
      isTrue,
    );
  });

  test(
    'новое устройство: индекс из объектов-индексов, узлы неизвестны',
    () async {
      final fresh = LocalIndex.inMemory();
      await recoverIndex(
        crypto: crypto,
        manifestKey: keys.manifestKey,
        store: s.objects,
        index: fresh,
      );
      final target = Directory('${dir.path}/out');
      final result = await restore(target, index: fresh);
      expect(result.errors, isEmpty);
      expect(snapshotOf(restoredRoot(target)), snapshotOf(data));
      fresh.close();
    },
  );

  group('verify', () {
    Future<VerifyReport> verify({bool full = false}) => runVerify(
      crypto: crypto,
      keys: keys,
      index: s.index,
      fragments: s.nodes,
      full: full,
    );

    test('всё на месте', () async {
      for (final full in [false, true]) {
        final report = await verify(full: full);
        expect(report.isHealthy, isTrue);
        expect(report.segments, backup.segmentsStored);
        expect(report.fragments, backup.segmentsStored * 20);
      }
    });

    test('недостающие фрагменты, сегмент в риске и невосстановимый', () async {
      final segmentId = s.index.storedSegments().first;
      final placed = s.index.fragments(segmentId);
      for (final f in placed.take(4)) {
        await s.nodes.delete(f.node!, f.fragmentId);
      }
      var report = await verify();
      expect(report.problems, hasLength(4));
      expect(report.atRisk, hasLength(1), reason: 'живых 16 = порог ремонта');
      expect(report.unrecoverable, isEmpty);

      for (final f in placed.skip(4).take(7)) {
        await s.nodes.delete(f.node!, f.fragmentId);
      }
      report = await verify();
      expect(report.unrecoverable, hasLength(1));
    });

    test('порчу видит только полный режим', () async {
      final segmentId = s.index.storedSegments().first;
      final f = s.index.fragments(segmentId)[3];
      s.nodes.corruptStored(f.node!, f.fragmentId);
      expect((await verify()).isHealthy, isTrue);
      final report = await verify(full: true);
      expect(report.problems.single.index, 3);
      expect(report.problems.single.error, isA<IntegrityException>());
      expect(report.unrecoverable, isEmpty);
    });

    test('недоступные узлы — неполная проверка, а не потеря данных', () async {
      final offline = LocalFolderStore(
        Directory('${dir.path}/nodes'),
        crypto,
        nodeCount: 20,
        faults: FaultPlan(
          unavailableNodes: {
            for (var i = 0; i < 20; i++) 'node-${i.toString().padLeft(2, '0')}',
          },
        ),
      );
      for (final full in [false, true]) {
        final report = await runVerify(
          crypto: crypto,
          keys: keys,
          index: s.index,
          fragments: offline,
          full: full,
        );
        expect(
          report.problems,
          isEmpty,
          reason: 'недоступность узла — не ошибка фрагмента',
        );
        expect(report.unrecoverable, isEmpty);
        expect(report.unchecked, hasLength(backup.segmentsStored));
        expect(report.uncheckedFragments, backup.segmentsStored * 20);
        expect(report.isHealthy, isFalse, reason: 'проверка неполная');
      }
    });

    test(
      'потерянные и недоступные: невосстановим, если не хватает и их',
      () async {
        final segmentId = s.index.storedSegments().first;
        final placed = s.index.fragments(segmentId);
        // 13 фрагментов потеряны, 2 узла из оставшихся 7 не отвечают:
        // подтверждённых 5, неизвестных 2, вместе меньше k = 10.
        for (final f in placed.take(13)) {
          await s.nodes.delete(f.node!, f.fragmentId);
        }
        final offline = LocalFolderStore(
          Directory('${dir.path}/nodes'),
          crypto,
          nodeCount: 20,
          faults: FaultPlan(
            unavailableNodes: {placed[13].node!, placed[14].node!},
          ),
        );
        final report = await runVerify(
          crypto: crypto,
          keys: keys,
          index: s.index,
          fragments: offline,
        );
        expect(report.unchecked, isEmpty);
        expect(report.unrecoverable, hasLength(1));
        expect(
          (report.unrecoverable.single.$2 as InsufficientShardsException)
              .available,
          5,
        );
      },
    );
  });
}
