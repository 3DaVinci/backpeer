// Нагрузочный набор (1.8.3): бэкап и восстановление через папки-«узлы»
// на диске, повторный бэкап без изменений, скорость шагов восстановления.
//
//   dart build cli -t bin/load_bench.dart
//   .../bundle/bin/load_bench <рабочий каталог> large [ГиБ] [isolate]
//   .../bundle/bin/load_bench <рабочий каталог> small [файлов] [isolate]
//
// large — файлы по 1 ГиБ случайных данных, small — файлы от 1 до 16 КиБ
// по 100 штук в каталоге. Набор данных создаётся один раз и переиспользуется;
// фрагменты и восстановленные файлы удаляются после замера. Нужно места:
// данные × 4 (данные, фрагменты × 2, восстановленная копия).

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:core/core.dart';

Future<void> main(List<String> args) async {
  final work = Directory(args[0])..createSync(recursive: true);
  final mode = args[1];
  final workers = args.length > 3 ? int.parse(args[3]) : 2;
  final data = Directory('${work.path}/data-$mode');
  if (mode == 'large') {
    _makeLarge(data, args.length > 2 ? int.parse(args[2]) : 10);
  } else if (mode == 'small') {
    _makeSmall(data, args.length > 2 ? int.parse(args[2]) : 100000);
  } else {
    throw ArgumentError('режим: large или small');
  }
  final size = _sizeOf(data);
  stdout.writeln(
    'набор $mode: ${(size / (1 << 20)).toStringAsFixed(0)} МиБ, '
    'isolate: $workers',
  );

  final crypto = await SodiumCryptoProvider.load();
  final keys = await AccountKeys.fromPhrase(
    RecoveryPhrase.fromEntropy(Uint8List(32)),
    crypto,
  );
  final run = Directory('${work.path}/run')..createSync();
  try {
    final index = LocalIndex.open('${run.path}/index.db');
    final fragments = LocalFolderStore(
      Directory('${run.path}/nodes'),
      crypto,
      nodeCount: 20,
    );
    final objects = LocalObjectStore(Directory('${run.path}/objects'));
    final rss = _RssWatch();

    // 1. Первый бэкап.
    final pool = await IsolateSegmentEncoder.start(workers);
    var w = Stopwatch()..start();
    rss.start();
    final first = await runBackup(
      crypto: crypto,
      keys: keys,
      index: index,
      fragments: fragments,
      objects: objects,
      paths: [data.absolute.path],
      deviceId: Uint8List(32),
      encoder: pool,
      maxInFlight: workers,
    );
    _report('бэкап', size, w, rss.stop());
    stdout.writeln(
      '  файлов ${first.stats.files}, сегментов ${first.segmentsStored}, '
      'фрагменты ${_sizeOf(Directory('${run.path}/nodes')) >> 20} МиБ',
    );

    // 2. Повторный бэкап без изменений.
    w = Stopwatch()..start();
    rss.start();
    final second = await runBackup(
      crypto: crypto,
      keys: keys,
      index: index,
      fragments: fragments,
      objects: objects,
      paths: [data.absolute.path],
      deviceId: Uint8List(32),
      encoder: pool,
      maxInFlight: workers,
    );
    await pool.close();
    _report('повторный бэкап', size, w, rss.stop());
    stdout.writeln(
      '  прочитано ${second.stats.bytesRead} байт, '
      'новых сегментов ${second.segmentsStored}',
    );

    // 3. Восстановление.
    final target = Directory('${run.path}/restored');
    w = Stopwatch()..start();
    rss.start();
    final restored = await runRestore(
      crypto: crypto,
      keys: keys,
      index: index,
      fragments: fragments,
      objects: objects,
      snapshotId: Uint8List.fromList(first.snapshot.snapshotId),
      target: target,
    );
    _report('восстановление', size, w, rss.stop());
    stdout.writeln(
      '  файлов ${restored.files}, сегментов ${restored.segmentsFetched}, '
      'ошибок ${restored.errors.length}',
    );
    if (!restored.isComplete || restored.bytes != size) {
      throw StateError('восстановление неполное');
    }
    target.deleteSync(recursive: true);

    // 4. Шаги восстановления на первых сегментах.
    await _restoreSteps(crypto, keys, index, fragments);
    index.close();
  } finally {
    run.deleteSync(recursive: true);
  }
  // Что-то из пакетов держит цикл событий после замера.
  exit(0);
}

/// Скорость шагов восстановления на первых 16 сегментах: чтение фрагментов
/// с диска, проверка фрагментов, Reed–Solomon (худший случай — потеряны
/// n − k фрагментов данных), расшифровка и проверка чанков.
Future<void> _restoreSteps(
  CryptoProvider crypto,
  AccountKeys keys,
  LocalIndex index,
  LocalFolderStore store,
) async {
  final segments = index.storedSegments().take(16).toList();
  final read = Stopwatch();
  final verify = Stopwatch();
  final decode = Stopwatch();
  final open = Stopwatch();
  var bytes = 0;
  for (final id in segments) {
    final entries = index.fragments(id);
    final k = index.segment(id)!.k;
    // Фрагменты чётности и сколько нужно данных: худший случай для RS.
    final chosen = [
      ...entries.where((f) => f.number >= k),
      ...entries.where((f) => f.number < k),
    ].take(k);
    read.start();
    final raw = [
      for (final f in chosen) await store.get(f.node!, f.fragmentId),
    ];
    read.stop();
    verify.start();
    final parsed = [
      for (var i = 0; i < raw.length; i++)
        Fragment.parse(raw[i])..verify(crypto),
    ];
    verify.stop();
    decode.start();
    final blob = decodeFragments(crypto, parsed, segmentId: id, verified: true);
    decode.stop();
    open.start();
    final segmentKey = keys.segmentKey(id);
    final plain = SegmentCipher.open(
      crypto,
      segmentKey: segmentKey,
      segmentId: id,
      blob: blob,
    );
    segmentKey.dispose();
    final hasher = ChunkIdHasher(crypto, keys.chunkIdKey);
    for (final c in SegmentPlaintext.parse(plain)) {
      hasher.of(c.data);
    }
    open.stop();
    bytes += plain.length;
  }
  String mbps(Stopwatch s) =>
      (bytes / 1e6 / (s.elapsedMicroseconds / 1e6)).toStringAsFixed(0);
  stdout
    ..writeln(
      'шаги восстановления (${segments.length} сегментов, МБ/с данных):',
    )
    ..writeln('  чтение k фрагментов: ${mbps(read)}')
    ..writeln('  проверка фрагментов (Меркл): ${mbps(verify)}')
    ..writeln(
      '  Reed–Solomon (потеряны n − k фрагментов данных): ${mbps(decode)}',
    )
    ..writeln('  расшифровка и проверка чанков: ${mbps(open)}');
}

void _report(String what, int size, Stopwatch w, int rssGrowth) {
  final s = w.elapsedMilliseconds / 1000;
  stdout.writeln(
    '$what: ${s.toStringAsFixed(1)} с, '
    '${(size / 1e6 / s).toStringAsFixed(0)} МБ/с, '
    'рост RSS ${rssGrowth >> 20} МиБ',
  );
}

final class _RssWatch {
  Timer? _timer;
  int _baseline = 0;
  int _peak = 0;

  void start() {
    _baseline = _peak = ProcessInfo.currentRss;
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      final rss = ProcessInfo.currentRss;
      if (rss > _peak) _peak = rss;
    });
  }

  int stop() {
    _timer?.cancel();
    final rss = ProcessInfo.currentRss;
    if (rss > _peak) _peak = rss;
    return _peak - _baseline;
  }
}

void _makeLarge(Directory dir, int gib) {
  final done = File('${dir.path}.done');
  if (done.existsSync()) return;
  dir.createSync(recursive: true);
  final random = Random(1);
  final block = Uint8List(64 << 20);
  final words = Uint32List.view(block.buffer);
  for (var f = 0; f < gib; f++) {
    final file = File('${dir.path}/big-$f.bin').openSync(mode: FileMode.write);
    for (var b = 0; b < 16; b++) {
      for (var i = 0; i < words.length; i++) {
        words[i] = random.nextInt(1 << 32);
      }
      file.writeFromSync(block);
    }
    file.closeSync();
  }
  done.writeAsStringSync('$gib');
}

void _makeSmall(Directory dir, int count) {
  final done = File('${dir.path}.done');
  if (done.existsSync()) return;
  dir.createSync(recursive: true);
  final random = Random(2);
  for (var i = 0; i < count; i++) {
    final sub = Directory('${dir.path}/d${i ~/ 100}');
    if (i % 100 == 0) sub.createSync();
    final bytes = Uint8List(1024 + random.nextInt(15 * 1024));
    for (var j = 0; j < bytes.length; j++) {
      bytes[j] = random.nextInt(256);
    }
    File('${sub.path}/f$i.txt').writeAsBytesSync(bytes);
  }
  done.writeAsStringSync('$count');
}

int _sizeOf(Directory dir) {
  var total = 0;
  for (final e in dir.listSync(recursive: true, followLinks: false)) {
    if (e is File) total += e.lengthSync();
  }
  return total;
}
