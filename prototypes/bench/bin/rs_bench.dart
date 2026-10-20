// Замер 0.5.3: скорость Reed–Solomon (core/ReedSolomon) на сегменте 16 МиБ.
// Скорость считается по объёму данных сегмента (не по объёму фрагментов).
//
//   dart build cli -t bin/rs_bench.dart && build/cli/.../bundle/bin/rs_bench

import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:core/core.dart';

const int _segmentSize = 16 * 1024 * 1024;
const List<(int, int)> _configs = [
  (10, 16),
  (10, 20),
  (10, 30),
  (20, 40),
  (32, 64),
];

Future<void> main() async {
  final cores = Platform.numberOfProcessors;
  stdout
    ..writeln('# ${Platform.version}')
    ..writeln('# Сегмент ${_segmentSize >> 20} МиБ, ядер: $cores')
    ..writeln(
      '| k | n | Кодирование, 1 поток, МБ/с | Восстановление, 1 поток, МБ/с '
      '| Кодирование, $cores isolate, МБ/с |',
    )
    ..writeln('|---|---|---|---|---|');
  for (final (k, n) in _configs) {
    final encode = _encodeThroughput(k, n);
    final decode = _reconstructThroughput(k, n);
    final parallel = await _parallelEncode(k, n, cores);
    stdout.writeln(
      '| $k | $n | ${encode.toStringAsFixed(1)} | '
      '${decode.toStringAsFixed(1)} | ${parallel.toStringAsFixed(1)} |',
    );
  }
}

List<Uint8List> _shards(int k, int n) {
  final shardSize = (_segmentSize + k - 1) ~/ k;
  return [
    for (var i = 0; i < n; i++)
      Uint8List(shardSize)..fillRange(0, shardSize, i < k ? i * 37 + 1 : 0),
  ];
}

double _encodeThroughput(int k, int n) {
  final rs = ReedSolomon(k, n - k);
  final shards = _shards(k, n);
  rs.encode(shards); // прогрев
  final watch = Stopwatch()..start();
  var runs = 0;
  while (watch.elapsedMilliseconds < 2000) {
    rs.encode(shards);
    runs++;
  }
  return runs * _segmentSize / 1e6 / (watch.elapsedMicroseconds / 1e6);
}

/// Худший случай: потеряны min(k, n − k) фрагментов данных.
double _reconstructThroughput(int k, int n) {
  final rs = ReedSolomon(k, n - k);
  final full = _shards(k, n);
  rs.encode(full);
  final lost = k < n - k ? k : n - k;
  final watch = Stopwatch();
  var runs = 0;
  while (watch.elapsedMilliseconds < 2000) {
    final shards = <Uint8List?>[...full];
    for (var i = 0; i < lost; i++) {
      shards[i] = null;
    }
    watch.start();
    rs.reconstruct(shards);
    watch.stop();
    runs++;
  }
  return runs * _segmentSize / 1e6 / (watch.elapsedMicroseconds / 1e6);
}

/// Каждый isolate кодирует свои сегменты; итог — суммарная скорость.
Future<double> _parallelEncode(int k, int n, int isolates) async {
  final watch = Stopwatch()..start();
  final runs = await Future.wait([
    for (var i = 0; i < isolates; i++)
      Isolate.run(() {
        final rs = ReedSolomon(k, n - k);
        final shards = _shards(k, n);
        final local = Stopwatch()..start();
        var count = 0;
        while (local.elapsedMilliseconds < 3000) {
          rs.encode(shards);
          count++;
        }
        return count;
      }),
  ]);
  final total = runs.fold(0, (a, b) => a + b);
  return total * _segmentSize / 1e6 / (watch.elapsedMicroseconds / 1e6);
}
