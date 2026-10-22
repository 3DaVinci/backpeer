// Долгий тест памяти конвейера бэкапа (критерий 1.6.3: бэкап 10 ГиБ
// укладывается в заданный предел памяти).
//
//   FS_LARGE_TESTS=1 dart test test/backup_large_test.dart
//
// FS_BACKUP_GIB — размер (по умолчанию 10), FS_LARGE_DIR — каталог для
// файла данных на диске (по умолчанию ~/.cache/file_storage_tests: /tmp
// бывает в памяти). Фрагменты не сохраняются — только считаются.

import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:test/test.dart';
import 'package:test_vectors/test_vectors.dart';

final class _Discard implements FragmentStore {
  int bytes = 0;

  @override
  final List<String> nodes = [for (var i = 0; i < 20; i++) 'n$i'];

  @override
  Future<Uint8List> put(
    String node,
    Uint8List fragment, {
    Uint8List? expectedFragmentId,
  }) async {
    bytes += fragment.length;
    return expectedFragmentId ?? Uint8List(32);
  }

  @override
  Future<Uint8List> get(String node, Uint8List fragmentId) =>
      throw UnimplementedError();

  @override
  Future<List<bool>> has(String node, List<Uint8List> fragmentIds) async => [
    for (final _ in fragmentIds) false,
  ];

  @override
  Future<void> delete(String node, Uint8List fragmentId) async {}
}

void main() {
  final env = Platform.environment;
  final gib = int.parse(env['FS_BACKUP_GIB'] ?? '10');
  test(
    'бэкап $gib ГиБ: пиковая память в пределе',
    () async {
      final root = Directory(
        env['FS_LARGE_DIR'] ?? '${env['HOME']}/.cache/file_storage_tests',
      )..createSync(recursive: true);
      final dir = root.createTempSync('backup-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final data = Directory('${dir.path}/data')..createSync();
      final file = File('${data.path}/big.bin').openSync(mode: FileMode.write);
      const block = 64 << 20;
      for (var i = 0; i < gib * 16; i++) {
        file.writeFromSync(splitmix64Bytes(1000 + i, block));
      }
      file.closeSync();

      final crypto = await SodiumCryptoProvider.load();
      final keys = await AccountKeys.fromPhrase(
        RecoveryPhrase.fromEntropy(Uint8List(32)),
        crypto,
      );
      final index = LocalIndex.open('${dir.path}/index.db');
      final store = _Discard();
      final pool = await IsolateSegmentEncoder.start(2);
      final baseline = ProcessInfo.currentRss;
      var peak = baseline;
      final watch = Stopwatch()..start();
      final result = await runBackup(
        crypto: crypto,
        keys: keys,
        index: index,
        fragments: store,
        objects: LocalObjectStore(Directory('${dir.path}/objects')),
        paths: [data.path],
        deviceId: Uint8List(32),
        encoder: pool,
        onProgress: (_) {
          final rss = ProcessInfo.currentRss;
          if (rss > peak) peak = rss;
        },
      );
      await pool.close();
      index.close();
      final seconds = watch.elapsedMilliseconds / 1000;
      final growth = peak - baseline;
      stdout.writeln(
        '$gib ГиБ: ${seconds.toStringAsFixed(0)} с, '
        '${(result.stats.bytesRead / 1e6 / seconds).toStringAsFixed(0)} МБ/с, '
        'сегментов ${result.segmentsStored}, '
        'фрагментов ${store.bytes >> 30} ГиБ, '
        'рост RSS ${growth >> 20} МиБ (пик по выборкам раз в 250 мс)',
      );
      expect(result.stats.bytesRead, gib << 30);
      // Предел: 2 сегмента в работе (открытый текст, блоб, 20 фрагментов —
      // около 70 МиБ каждый), открытый сегмент 16 МиБ, окно чтения 16 МиБ,
      // плюс запас на сборку мусора.
      expect(growth, lessThan(512 << 20));
    },
    skip: env['FS_LARGE_TESTS'] == '1'
        ? false
        : 'долгий тест, включается FS_LARGE_TESTS=1',
    timeout: const Timeout(Duration(hours: 1)),
  );
}
