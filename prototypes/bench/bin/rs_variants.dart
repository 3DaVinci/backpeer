// Замер 1.4.4: варианты внутреннего цикла Reed–Solomon и параллельность по
// isolate с передачей буферов без копирования.
//
//   dart build cli -t bin/rs_variants.dart   # замер только в AOT
//
// Все варианты считают outputs[j] = Σ rows[j][c] · inputs[c] над GF(2^8) и
// сверяются с вариантом A.

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:core/src/erasure/galois8.dart';

const int _segment = 16 * 1024 * 1024;

typedef _Kernel = void Function(
  List<Uint8List> rows,
  List<Uint8List> inputs,
  List<Uint8List> outputs,
  int length,
);

Future<void> main() async {
  stdout
    ..writeln('# ${Platform.version}')
    ..writeln('# Сегмент 16 МиБ, ядер: ${Platform.numberOfProcessors}')
    ..writeln(
      '| k | n | A: байты, МБ/с | B: u64, МБ/с | C: u64 + блоки, МБ/с |',
    )
    ..writeln('|---|---|---|---|---|');
  for (final (k, n) in const [(10, 16), (10, 20), (20, 40)]) {
    final m = n - k;
    final rows = _parityRows(k, n);
    final length = ((_segment + k - 1) ~/ k + 63) & ~63;
    final random = Random(1);
    final inputs = [
      for (var i = 0; i < k; i++)
        Uint8List.fromList(List.generate(length, (_) => random.nextInt(256))),
    ];
    final reference = [for (var j = 0; j < m; j++) Uint8List(length)];
    _byteKernel(rows, inputs, reference, length);
    final results = <String>[];
    for (final kernel in [_byteKernel, _wordKernel, _blockedWordKernel]) {
      final outputs = [for (var j = 0; j < m; j++) Uint8List(length)];
      kernel(rows, inputs, outputs, length);
      for (var j = 0; j < m; j++) {
        if (!_equal(outputs[j], reference[j])) {
          throw StateError('Вариант расходится с A');
        }
      }
      results.add(_throughput(kernel, rows, inputs, outputs, length));
    }
    stdout.writeln('| $k | $n | ${results.join(' | ')} |');
  }

  stdout
    ..writeln()
    ..writeln('| Isolate | k = 10, n = 20: кодирование сегментов, МБ/с |')
    ..writeln('|---|---|');
  for (final workers in {1, 2, 4, Platform.numberOfProcessors}) {
    stdout.writeln('| $workers | ${await _pool(workers)} |');
  }
}

String _throughput(
  _Kernel kernel,
  List<Uint8List> rows,
  List<Uint8List> inputs,
  List<Uint8List> outputs,
  int length,
) {
  final watch = Stopwatch()..start();
  var runs = 0;
  while (watch.elapsedMilliseconds < 2000) {
    kernel(rows, inputs, outputs, length);
    runs++;
  }
  final mbps = runs * _segment / 1e6 / (watch.elapsedMicroseconds / 1e6);
  return mbps.toStringAsFixed(1);
}

/// Строки чётности матрицы кодирования (как в ReedSolomon): кодируем
/// единичные векторы и читаем коэффициенты.
List<Uint8List> _parityRows(int k, int n) {
  final rs = ReedSolomon(k, n - k);
  final shards = [for (var i = 0; i < n; i++) Uint8List(k)];
  for (var c = 0; c < k; c++) {
    shards[c][c] = 1;
  }
  rs.encode(shards);
  return [for (var j = k; j < n; j++) Uint8List.fromList(shards[j])];
}

bool _equal(Uint8List a, Uint8List b) {
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// A: текущая реализация — побайтно, развёртка на 8.
void _byteKernel(
  List<Uint8List> rows,
  List<Uint8List> inputs,
  List<Uint8List> outputs,
  int length,
) {
  final table = Galois8.mulTable;
  final tail = length - length % 8;
  for (var j = 0; j < outputs.length; j++) {
    final out = outputs[j];
    for (var c = 0; c < inputs.length; c++) {
      final input = inputs[c];
      final base = rows[j][c] * 256;
      final mul = Uint8List.sublistView(table, base, base + 256);
      var i = 0;
      if (c == 0) {
        for (; i < tail; i += 8) {
          out[i] = mul[input[i]];
          out[i + 1] = mul[input[i + 1]];
          out[i + 2] = mul[input[i + 2]];
          out[i + 3] = mul[input[i + 3]];
          out[i + 4] = mul[input[i + 4]];
          out[i + 5] = mul[input[i + 5]];
          out[i + 6] = mul[input[i + 6]];
          out[i + 7] = mul[input[i + 7]];
        }
        for (; i < length; i++) {
          out[i] = mul[input[i]];
        }
      } else {
        for (; i < tail; i += 8) {
          out[i] ^= mul[input[i]];
          out[i + 1] ^= mul[input[i + 1]];
          out[i + 2] ^= mul[input[i + 2]];
          out[i + 3] ^= mul[input[i + 3]];
          out[i + 4] ^= mul[input[i + 4]];
          out[i + 5] ^= mul[input[i + 5]];
          out[i + 6] ^= mul[input[i + 6]];
          out[i + 7] ^= mul[input[i + 7]];
        }
        for (; i < length; i++) {
          out[i] ^= mul[input[i]];
        }
      }
    }
  }
}

/// B: вход читается словами u64, результат собирается и пишется словом.
void _wordKernel(
  List<Uint8List> rows,
  List<Uint8List> inputs,
  List<Uint8List> outputs,
  int length,
) => _words(rows, inputs, outputs, 0, length ~/ 8);

/// C: как B, но блоками по 64 КиБ: на блок все входы и выходы в кеше.
void _blockedWordKernel(
  List<Uint8List> rows,
  List<Uint8List> inputs,
  List<Uint8List> outputs,
  int length,
) {
  const block = 65536 ~/ 8;
  final words = length ~/ 8;
  for (var start = 0; start < words; start += block) {
    _words(rows, inputs, outputs, start, min(start + block, words));
  }
}

void _words(
  List<Uint8List> rows,
  List<Uint8List> inputs,
  List<Uint8List> outputs,
  int from,
  int to,
) {
  final table = Galois8.mulTable;
  final in64 = [for (final input in inputs) input.buffer.asUint64List()];
  for (var j = 0; j < outputs.length; j++) {
    final out = outputs[j].buffer.asUint64List();
    for (var c = 0; c < inputs.length; c++) {
      final input = in64[c];
      final base = rows[j][c] * 256;
      final mul = Uint8List.sublistView(table, base, base + 256);
      if (c == 0) {
        for (var i = from; i < to; i++) {
          final x = input[i];
          out[i] =
              mul[x & 0xFF] |
              (mul[(x >>> 8) & 0xFF] << 8) |
              (mul[(x >>> 16) & 0xFF] << 16) |
              (mul[(x >>> 24) & 0xFF] << 24) |
              (mul[(x >>> 32) & 0xFF] << 32) |
              (mul[(x >>> 40) & 0xFF] << 40) |
              (mul[(x >>> 48) & 0xFF] << 48) |
              (mul[x >>> 56] << 56);
        }
      } else {
        for (var i = from; i < to; i++) {
          final x = input[i];
          out[i] ^=
              mul[x & 0xFF] |
              (mul[(x >>> 8) & 0xFF] << 8) |
              (mul[(x >>> 16) & 0xFF] << 16) |
              (mul[(x >>> 24) & 0xFF] << 24) |
              (mul[(x >>> 32) & 0xFF] << 32) |
              (mul[(x >>> 40) & 0xFF] << 40) |
              (mul[(x >>> 48) & 0xFF] << 48) |
              (mul[x >>> 56] << 56);
        }
      }
    }
  }
}

/// Пул isolate: главный поток раздаёт сегменты, isolate кодирует и
/// возвращает фрагменты чётности; буферы передаются через
/// TransferableTypedData без копирования.
Future<String> _pool(int workers) async {
  const k = 10;
  const shardSize = ((_segment + k - 1) ~/ k + 63) & ~63;
  final random = Random(2);
  final segment = Uint8List.fromList(
    List.generate(_segment, (_) => random.nextInt(256)),
  );
  final ports = <SendPort>[];
  final replies = ReceivePort();
  final queue = StreamIterator(replies);
  for (var w = 0; w < workers; w++) {
    await Isolate.spawn(_worker, replies.sendPort);
    await queue.moveNext();
    ports.add(queue.current as SendPort);
  }
  final watch = Stopwatch()..start();
  var done = 0;
  var sent = 0;
  void send(int worker) {
    // Копия сегмента имитирует новый сегмент от упаковщика.
    final copy = Uint8List(shardSize * k)..setAll(0, segment);
    ports[worker].send((
      worker,
      TransferableTypedData.fromList([copy]),
      shardSize,
    ));
    sent++;
  }

  for (var w = 0; w < workers; w++) {
    send(w);
  }
  while (watch.elapsedMilliseconds < 3000 || done < sent) {
    await queue.moveNext();
    final (worker, parity) = queue.current as (int, TransferableTypedData);
    parity.materialize();
    done++;
    if (watch.elapsedMilliseconds < 3000) send(worker);
  }
  final mbps = done * _segment / 1e6 / (watch.elapsedMicroseconds / 1e6);
  for (final port in ports) {
    port.send(null);
  }
  replies.close();
  return mbps.toStringAsFixed(1);
}

void _worker(SendPort replies) {
  const k = 10;
  const n = 20;
  final rs = ReedSolomon(k, n - k);
  final inbox = ReceivePort();
  replies.send(inbox.sendPort);
  inbox.listen((message) {
    if (message == null) {
      inbox.close();
      return;
    }
    final (worker, data, shardSize) =
        message as (int, TransferableTypedData, int);
    final buffer = data.materialize();
    final parity = Uint8List(shardSize * (n - k)).buffer;
    final shards = [
      for (var i = 0; i < k; i++) buffer.asUint8List(i * shardSize, shardSize),
      for (var j = 0; j < n - k; j++)
        parity.asUint8List(j * shardSize, shardSize),
    ];
    rs.encode(shards);
    replies.send((
      worker,
      TransferableTypedData.fromList([parity.asUint8List()]),
    ));
  });
}
