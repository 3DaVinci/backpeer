// Тесты свойств (задача 1.8.2): случайное дерево файлов → бэкап со
// случайными k и n → случайные потери и порча фрагментов (не больше n − k
// на сегмент) → восстановление совпадает с исходным. Иногда — потеря
// n − k + 1 у одного сегмента: восстановление обязано сообщить об ошибке.
//
//   dart test test/property_test.dart                       # 30 прогонов
//   FS_PROPERTY_RUNS=2000 dart test test/property_test.dart
//   FS_PROPERTY_SEED=1234 dart test test/property_test.dart # один прогон
//
// Упавший прогон печатает свой seed.

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:test/test.dart';

const _nameParts = [
  'a',
  'b',
  'файл',
  'with space',
  'data.bin',
  'ü',
  '中',
  'x.txt',
];

/// Случайное дерево в [root]; возвращает число созданных элементов.
int _populate(Random r, Directory root, {required int depth}) {
  var count = 0;
  final entries = r.nextInt(6);
  final used = <String>{};
  for (var i = 0; i < entries; i++) {
    final name = '${_nameParts[r.nextInt(_nameParts.length)]}-$i';
    if (!used.add(name)) continue;
    final path = '${root.path}/$name';
    final kind = r.nextInt(10);
    if (kind < 5) {
      final size = switch (r.nextInt(20)) {
        0 => 0,
        1 => 17 << 20, // больше сегмента — редко
        < 8 => r.nextInt(64),
        < 16 => r.nextInt(64 << 10),
        _ => (512 << 10) + r.nextInt(2 << 20),
      };
      final bytes = Uint8List(size);
      for (var j = 0; j < size; j += 4096) {
        bytes[j] = r.nextInt(256);
      }
      if (size > 0) bytes[size - 1] = r.nextInt(256);
      File(path).writeAsBytesSync(bytes);
      if (!Platform.isWindows && r.nextBool()) {
        Process.runSync('chmod', [
          ['600', '644', '755', '640'][r.nextInt(4)],
          path,
        ]);
      }
    } else if (kind < 8 && depth > 0) {
      Directory(path).createSync();
      count += _populate(r, Directory(path), depth: depth - 1);
    } else if (!Platform.isWindows) {
      Link(path).createSync(r.nextBool() ? 'missing-$i' : '../');
    } else {
      File(path).writeAsStringSync(name);
    }
    count++;
  }
  if (Platform.isLinux && r.nextInt(4) == 0) {
    final raw = Uint8List.fromList([
      ...utf8.encode('${root.path}/'),
      0xFF,
      0x80 + r.nextInt(64),
    ]);
    File.fromRawPath(raw).writeAsStringSync('raw');
    count++;
  }
  return count;
}

/// Дерево с метаданными для сравнения.
Map<String, Object> _describe(CryptoProvider crypto, String root) {
  final walker = TreeWalker();
  return {
    for (final item in walker.walk(TreeWalker.rootPath(root)))
      item.relative: (
        item.entry.kind,
        item.entry.kind == EntryKind.file ? item.entry.size : 0,
        item.entry.kind == EntryKind.symlink ? 0 : item.entry.mode,
        item.entry.mtimeNs,
        item.entry.kind == EntryKind.symlink
            ? utf8.decode(walker.readLink(item.path)!, allowMalformed: true)
            : '',
        item.entry.kind == EntryKind.file
            ? bytesToHex(
                crypto.blake2b256(
                  File.fromRawPath(item.path).readAsBytesSync(),
                ),
              )
            : '',
      ),
  };
}

void main() {
  final env = Platform.environment;
  final single = int.tryParse(env['FS_PROPERTY_SEED'] ?? '');
  final runs = int.tryParse(env['FS_PROPERTY_RUNS'] ?? '') ?? 30;
  final seeds = single != null
      ? [single]
      : [for (var i = 0; i < runs; i++) 1000 + i];

  late CryptoProvider crypto;
  late AccountKeys keys;
  setUpAll(() async {
    crypto = await SodiumCryptoProvider.load();
    keys = await AccountKeys.fromPhrase(
      RecoveryPhrase.fromEntropy(Uint8List(32)..[0] = 42),
      crypto,
    );
  });

  test('случайные деревья и потери: ${seeds.length} прогонов', () async {
    var restoredRuns = 0;
    var failureRuns = 0;
    var segments = 0;
    for (final seed in seeds) {
      try {
        final outcome = await _run(seed, crypto, keys);
        segments += outcome.segments;
        if (outcome.expectedFailure) {
          failureRuns++;
        } else {
          restoredRuns++;
        }
      } on Object catch (e, stack) {
        fail(
          'seed $seed: $e\n$stack\nПовторить: FS_PROPERTY_SEED=$seed dart test test/property_test.dart',
        );
      }
    }
    stdout.writeln(
      'прогонов ${seeds.length}: восстановлено $restoredRuns, '
      'ожидаемых отказов $failureRuns, сегментов $segments',
    );
  }, timeout: Timeout(Duration(seconds: 60 + seeds.length * 2)));
}

Future<({bool expectedFailure, int segments})> _run(
  int seed,
  CryptoProvider crypto,
  AccountKeys keys,
) async {
  final r = Random(seed);
  final dir = Directory.systemTemp.createTempSync('fs-prop-');
  final index = LocalIndex.inMemory();
  try {
    final data = Directory('${dir.path}/data')..createSync();
    _populate(r, data, depth: 3);

    final k = 1 + r.nextInt(6);
    final n = k + 1 + r.nextInt(5);
    final t = k + r.nextInt(n - k);
    final params = DurabilityParameters(k: k, n: n, repairThreshold: t);
    final nodes = LocalFolderStore(
      Directory('${dir.path}/nodes'),
      crypto,
      nodeCount: n + r.nextInt(3),
    );
    final objects = LocalObjectStore(Directory('${dir.path}/objects'));
    final backup = await runBackup(
      crypto: crypto,
      keys: keys,
      index: index,
      fragments: nodes,
      objects: objects,
      paths: [data.path],
      deviceId: Uint8List(32),
      params: params,
    );
    expect(backup.report.skipped, isEmpty);

    // Потери и порча: у каждого сегмента не больше n − k.
    final ids = index.storedSegments();
    final breakOne = ids.isNotEmpty && r.nextInt(8) == 0;
    final broken = breakOne ? r.nextInt(ids.length) : -1;
    for (var s = 0; s < ids.length; s++) {
      final placed = index.fragments(ids[s])..shuffle(r);
      final losses = s == broken ? n - k + 1 : r.nextInt(n - k + 1);
      for (final f in placed.take(losses)) {
        if (r.nextBool()) {
          await nodes.delete(f.node!, f.fragmentId);
        } else {
          nodes.corruptStored(
            f.node!,
            f.fragmentId,
            offset: 96 + r.nextInt(1 << 16),
          );
        }
      }
    }

    final target = Directory('${dir.path}/out');
    Future<RestoreResult> restore() => runRestore(
      crypto: crypto,
      keys: keys,
      index: index,
      fragments: nodes,
      objects: objects,
      snapshotId: Uint8List.fromList(backup.snapshot.snapshotId),
      target: target,
    );
    if (breakOne) {
      try {
        final result = await restore();
        expect(
          result.isComplete,
          isFalse,
          reason: 'потеря n − k + 1 не замечена',
        );
      } on InsufficientShardsException {
        // Сломан сегмент с корневым деревом — снимок не читается целиком.
      }
      return (expectedFailure: true, segments: ids.length);
    }
    final result = await restore();
    expect(result.errors, isEmpty);
    expect(result.skippedExisting, isEmpty);
    final copy = '${target.path}${data.path}';
    expect(_describe(crypto, copy), _describe(crypto, data.path));
    return (expectedFailure: false, segments: ids.length);
  } finally {
    index.close();
    dir.deleteSync(recursive: true);
  }
}
