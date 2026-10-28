// Восстановление с ожиданием (задача 3.9.3; durability.md, раздел 3):
// отложенные файлы докачиваются, когда узлы выходят в сеть; прогресс и
// оценка времени; запас запросов на медленные узлы.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:test/test.dart';
import 'package:test_vectors/test_vectors.dart';

/// Узлы, которые не в сети или отвечают с задержкой.
final class _Flaky implements FragmentStore {
  new(this.inner);

  final FragmentStore inner;
  final Set<String> offline = {};

  /// Фрагменты, которых «нет в сети», как будто их узлы выключены.
  final Set<String> missing = {};
  final Map<String, Duration> slow = {};
  final List<String> gets = [];

  @override
  List<String> get nodes => inner.nodes;

  void _check(String node, Uint8List? fragmentId) {
    if (offline.contains(node) ||
        (fragmentId != null && missing.contains(bytesToHex(fragmentId)))) {
      throw StorageException(
        location: node,
        problem: StorageProblem.unavailable,
        operation: 'get',
      );
    }
  }

  @override
  Future<Uint8List> get(String node, Uint8List fragmentId) async {
    gets.add(node);
    final delay = slow[node];
    if (delay != null) await Future<void>.delayed(delay);
    _check(node, fragmentId);
    return await inner.get(node, fragmentId);
  }

  @override
  Future<List<bool>> has(String node, List<Uint8List> fragmentIds) async {
    _check(node, null);
    return await inner.has(node, fragmentIds);
  }

  @override
  Future<Uint8List> put(
    String node,
    Uint8List fragment, {
    Uint8List? expectedFragmentId,
  }) => inner.put(node, fragment, expectedFragmentId: expectedFragmentId);

  @override
  Future<void> delete(String node, Uint8List fragmentId) =>
      inner.delete(node, fragmentId);
}

void main() {
  late CryptoProvider crypto;
  late AccountKeys keys;
  setUpAll(() async {
    crypto = await SodiumCryptoProvider.load();
    keys = await AccountKeys.fromPhrase(
      RecoveryPhrase.fromEntropy(Uint8List(32)..[7] = 3),
      crypto,
    );
  });

  late Directory dir;
  late Directory data;
  late LocalIndex index;
  late _Flaky nodes;
  late LocalObjectStore objects;
  late BackupResult backup;
  setUp(() async {
    dir = Directory.systemTemp.createTempSync('fs-restore-wait-');
    data = Directory('${dir.path}/data')..createSync();
    File('${data.path}/big.bin').writeAsBytesSync(splitmix64Bytes(9, 20 << 20));
    File('${data.path}/sub/small.txt')
      ..createSync(recursive: true)
      ..writeAsStringSync('маленький');
    index = LocalIndex.open('${dir.path}/index.db');
    nodes = _Flaky(
      LocalFolderStore(Directory('${dir.path}/nodes'), crypto, nodeCount: 20),
    );
    objects = LocalObjectStore(Directory('${dir.path}/objects'));
    backup = await runBackup(
      crypto: crypto,
      keys: keys,
      index: index,
      fragments: nodes,
      objects: objects,
      paths: [data.path],
      deviceId: Uint8List(32),
    );
  });
  tearDown(() {
    index.close();
    dir.deleteSync(recursive: true);
  });

  Future<RestoreResult> restore(
    Directory target, {
    RestoreWait wait = RestoreWait.none,
    void Function(RestoreProgress)? onProgress,
  }) => runRestore(
    crypto: crypto,
    keys: keys,
    index: index,
    fragments: nodes,
    objects: objects,
    snapshotId: Uint8List.fromList(backup.snapshot.snapshotId),
    target: target,
    wait: wait,
    onProgress: onProgress,
    progressInterval: const Duration(milliseconds: 50),
  );

  File restored(Directory target, String name) =>
      File('${target.path}${data.path}/$name');

  /// Первый сегмент с данными большого файла.
  Uint8List bigSegment() {
    final segments = index.storedSegments();
    return segments.firstWhere(
      (s) => index.segment(s)!.chunks.length == 1,
      orElse: () => segments.first,
    );
  }

  void hideSegment(Uint8List segmentId) => nodes.missing.addAll([
    for (final f in index.fragments(segmentId)) bytesToHex(f.fragmentId),
  ]);

  test('узлы выходят в сеть позже — восстановление завершается само', () async {
    // 11 узлов из 20 не в сети: ни одного сегмента не собрать, даже
    // корневое дерево.
    nodes.offline.addAll(nodes.nodes.take(11));
    final progress = <RestoreProgress>[];
    final target = Directory('${dir.path}/out');
    final pending = restore(
      target,
      wait: const RestoreWait(
        maxWait: Duration(seconds: 30),
        retryInterval: Duration(milliseconds: 200),
      ),
      onProgress: progress.add,
    );
    await Future<void>.delayed(const Duration(milliseconds: 800));
    expect(progress.last.nextRetry, isNotNull, reason: 'ждёт узлы');
    expect(progress.last.waitLeft, isNotNull);
    expect(progress.last.eta, isNull);
    nodes.offline.clear();
    final result = await pending;
    expect(result.isComplete, isTrue, reason: '${result.errors}');
    expect(
      restored(target, 'big.bin').readAsBytesSync(),
      File('${data.path}/big.bin').readAsBytesSync(),
    );
    expect(progress.last.bytes, progress.last.totalBytes);
    expect(progress.last.waitingFiles, 0);
  });

  test('доступное восстанавливается сразу, недостающее — докачивается, '
      'метаданные каталогов — после', () async {
    final hidden = bigSegment();
    hideSegment(hidden);
    final target = Directory('${dir.path}/out');
    var sawPartial = false;
    RestoreProgress? waiting;
    final pending = restore(
      target,
      wait: const RestoreWait(
        maxWait: Duration(seconds: 30),
        retryInterval: Duration(milliseconds: 200),
      ),
      onProgress: (p) {
        if (p.waitingFiles > 0 && p.files > 0) {
          sawPartial = true;
          waiting = p;
        }
      },
    );
    for (var i = 0; i < 100 && !sawPartial; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(sawPartial, isTrue, reason: 'маленький файл не ждёт большой');
    expect(restored(target, 'sub/small.txt').readAsStringSync(), 'маленький');
    expect(restored(target, 'big.bin').existsSync(), isFalse);
    // Видно, чего ждём: путь отложенного файла и причина.
    expect(waiting!.waitingPaths.single, endsWith('big.bin'));
    expect(waiting!.waitingReason, isNotEmpty);
    expect(waiting!.waitLeft, isNotNull);
    nodes.missing.clear();
    final result = await pending;
    expect(result.isComplete, isTrue, reason: '${result.errors}');
    expect(result.files, 2);
    expect(
      restored(target, 'big.bin').readAsBytesSync(),
      File('${data.path}/big.bin').readAsBytesSync(),
    );
    // Каталог данных получил mtime из снимка уже после докачки.
    expect(
      Directory('${target.path}${data.path}').statSync().modified,
      data.statSync().modified,
    );
  });

  test('ожидание вышло — ошибки по отложенным файлам', () async {
    hideSegment(bigSegment());
    final result = await restore(
      Directory('${dir.path}/out'),
      wait: const RestoreWait(
        maxWait: Duration(milliseconds: 500),
        retryInterval: Duration(milliseconds: 100),
      ),
    );
    expect(result.files, 1);
    expect(result.errors.single.$1, endsWith('big.bin'));
    expect(result.errors.single.$2, contains('фрагментов'));
  });

  test('без ожидания — ошибка сразу', () async {
    hideSegment(bigSegment());
    final watch = Stopwatch()..start();
    final result = await restore(Directory('${dir.path}/out'));
    expect(result.errors, hasLength(1));
    expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
  });

  test('оценка времени по скорости', () {
    const p = RestoreProgress(
      files: 1,
      bytes: 100,
      totalBytes: 300,
      segmentsFetched: 1,
      waitingFiles: 0,
      nextRetry: null,
      waitLeft: null,
      elapsed: Duration(seconds: 2),
    );
    expect(p.rate, 50);
    expect(p.eta, const Duration(seconds: 4));
  });

  group('запас на медленные', () {
    late Uint8List segment;
    late Stopwatch watch;
    setUp(() {
      segment = bigSegment();
      final first = index.fragments(segment).first.node!;
      nodes.slow[first] = const Duration(seconds: 3);
      watch = Stopwatch()..start();
    });

    SegmentReader reader({int spare = 2}) => SegmentReader(
      crypto: crypto,
      keys: keys,
      index: index,
      store: nodes,
      spare: spare,
    );

    test('медленный узел не задерживает сегмент', () async {
      final r = reader();
      await r.fetchBlob(segment);
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
      expect(nodes.gets, hasLength(11), reason: 'k и один запасной');
    });

    test('без запаса — ждёт медленный', () async {
      await reader(spare: 0).fetchBlob(segment);
      expect(watch.elapsed, greaterThanOrEqualTo(const Duration(seconds: 3)));
      expect(nodes.gets, hasLength(10));
    });

    test('неудачный запрос сразу заменяется следующим', () async {
      nodes.slow.clear();
      nodes.offline.add(index.fragments(segment)[3].node!);
      await reader(spare: 0).fetchBlob(segment);
      expect(nodes.gets, hasLength(11));
    });
  });
}
