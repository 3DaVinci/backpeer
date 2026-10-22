// Замер конвейера бэкапа (1.6.3, 1.8.3): скорость по шагам и всего
// конвейера в AOT.
//
//   dart build cli -t bin/backup_bench.dart
//   .../bundle/bin/backup_bench <файл> [isolate]
//
// Фрагменты не сохраняются — только считаются.

import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';

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

Future<void> main(List<String> args) async {
  final file = File(args[0]);
  final workers = args.length > 1 ? int.parse(args[1]) : 2;
  final size = file.lengthSync();
  final crypto = await SodiumCryptoProvider.load();
  final keys = await AccountKeys.fromPhrase(
    RecoveryPhrase.fromEntropy(Uint8List(32)),
    crypto,
  );
  final cdc = FastCdc(GearTable.derive(crypto, keys.gearKey));
  final hasher = ChunkIdHasher(crypto, keys.chunkIdKey);

  double mbps(Stopwatch w) => size / 1e6 / (w.elapsedMicroseconds / 1e6);

  // 1. Чтение и FastCDC.
  var w = Stopwatch()..start();
  final chunks = <Uint8List>[];
  await for (final e in chunkFile(file, cdc)) {
    if (e is ChunkRead && chunks.length < 64) chunks.add(e.data);
  }
  stdout.writeln('чтение + FastCDC: ${mbps(w).toStringAsFixed(0)} МБ/с');

  // 2. chunk_id (BLAKE2b с ключом) по первым чанкам.
  w = Stopwatch()..start();
  var hashed = 0;
  for (final c in chunks) {
    hasher.of(c);
    hashed += c.length;
  }
  stdout.writeln(
    'chunk_id: ${(hashed / 1e6 / (w.elapsedMicroseconds / 1e6)).toStringAsFixed(0)} МБ/с',
  );

  // 3. Сегмент: шифрование + Reed–Solomon + Меркл, один поток.
  final plain = Uint8List(16 << 20);
  final encoder = InlineSegmentEncoder(crypto);
  w = Stopwatch()..start();
  const segments = 8;
  for (var i = 0; i < segments; i++) {
    final id = crypto.randomBytes(32);
    await encoder.encode(
      SegmentJob(
        segmentId: id,
        segmentKey: keys.segmentKey(id),
        plaintext: plain,
        k: 10,
        n: 20,
      ),
    );
  }
  stdout.writeln(
    'сегмент (шифрование + RS + Меркл), 1 поток: '
    '${(segments * plain.length / 1e6 / (w.elapsedMicroseconds / 1e6)).toStringAsFixed(0)} МБ/с',
  );

  // 4. Весь конвейер.
  final tmp = Directory.systemTemp.createTempSync('backup-bench-');
  final index = LocalIndex.open('${tmp.path}/index.db');
  final store = _Discard();
  final pool = await IsolateSegmentEncoder.start(workers);
  final baseline = ProcessInfo.currentRss;
  var peak = baseline;
  w = Stopwatch()..start();
  final result = await runBackup(
    crypto: crypto,
    keys: keys,
    index: index,
    fragments: store,
    objects: LocalObjectStore(Directory('${tmp.path}/objects')),
    paths: [file.parent.path],
    deviceId: Uint8List(32),
    encoder: pool,
    maxInFlight: workers,
    onProgress: (_) {
      final rss = ProcessInfo.currentRss;
      if (rss > peak) peak = rss;
    },
  );
  await pool.close();
  index.close();
  tmp.deleteSync(recursive: true);
  stdout.writeln(
    'конвейер, $workers isolate: ${mbps(w).toStringAsFixed(0)} МБ/с, '
    'сегментов ${result.segmentsStored}, '
    'рост RSS ${(peak - baseline) >> 20} МиБ',
  );
}
