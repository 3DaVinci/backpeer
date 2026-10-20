import 'dart:typed_data';

import 'package:core/src/erasure/erasure_coder.dart';
import 'package:core/src/erasure/galois8.dart';

/// Reed–Solomon на GF(2^8), побайтно совместимый с reed-solomon-erasure 6.x.
///
/// Матрица кодирования: матрица Вандермонда n × k (`v[r][c] = r^c`),
/// умноженная справа на обратную к своей верхней квадратной части k × k.
/// Верхние k строк результата — единичная матрица (систематический код),
/// нижние n − k задают фрагменты чётности.
final class ReedSolomon implements ErasureCoder {
  new(this.dataShards, this.parityShards)
    : totalShards = dataShards + parityShards {
    if (dataShards < 1 || parityShards < 1 || totalShards > 256) {
      throw ArgumentError(
        'Нужно 1 ≤ k, 1 ≤ n − k, n ≤ 256; получено k=$dataShards, '
        'n=$totalShards',
      );
    }
    final vandermonde = _Matrix(totalShards, dataShards);
    for (var r = 0; r < totalShards; r++) {
      for (var c = 0; c < dataShards; c++) {
        vandermonde.set(r, c, Galois8.pow(r, c));
      }
    }
    final top = vandermonde.subMatrix(0, dataShards);
    _matrix = vandermonde.times(top.inverse());
  }

  @override
  final int dataShards;

  @override
  final int parityShards;

  @override
  final int totalShards;

  late final _Matrix _matrix;

  @override
  void encode(List<Uint8List> shards) {
    _checkShards(shards);
    final inputs = shards.sublist(0, dataShards);
    final outputs = shards.sublist(dataShards);
    final rows = [
      for (var p = 0; p < parityShards; p++) _matrix.row(dataShards + p),
    ];
    _codeSomeShards(rows, inputs, outputs, shards.first.length);
  }

  @override
  void reconstruct(List<Uint8List?> shards) {
    if (shards.length != totalShards) {
      throw ArgumentError('Ожидалось $totalShards фрагментов');
    }
    final present = <int>[];
    int? length;
    for (var i = 0; i < totalShards; i++) {
      final shard = shards[i];
      if (shard == null) continue;
      length ??= shard.length;
      if (shard.length != length) {
        throw ArgumentError('Фрагменты разной длины');
      }
      present.add(i);
    }
    if (present.length == totalShards) return;
    if (present.length < dataShards || length == null) {
      throw StateError(
        'Недостаточно фрагментов: ${present.length} из нужных $dataShards',
      );
    }

    // Как в эталоне: берём первые k имеющихся фрагментов по порядку
    // номеров, обращаем соответствующие строки матрицы кодирования
    // и получаем недостающие фрагменты данных.
    final used = present.sublist(0, dataShards);
    final sub = _Matrix(dataShards, dataShards);
    for (var r = 0; r < dataShards; r++) {
      for (var c = 0; c < dataShards; c++) {
        sub.set(r, c, _matrix.get(used[r], c));
      }
    }
    final decode = sub.inverse();
    final inputs = [for (final i in used) shards[i]!];

    final missingData = [
      for (var i = 0; i < dataShards; i++)
        if (shards[i] == null) i,
    ];
    if (missingData.isNotEmpty) {
      final outputs = [for (final _ in missingData) Uint8List(length)];
      _codeSomeShards(
        [for (final i in missingData) decode.row(i)],
        inputs,
        outputs,
        length,
      );
      for (var j = 0; j < missingData.length; j++) {
        shards[missingData[j]] = outputs[j];
      }
    }

    final missingParity = [
      for (var i = dataShards; i < totalShards; i++)
        if (shards[i] == null) i,
    ];
    if (missingParity.isNotEmpty) {
      final data = [for (var i = 0; i < dataShards; i++) shards[i]!];
      final outputs = [for (final _ in missingParity) Uint8List(length)];
      _codeSomeShards(
        [for (final i in missingParity) _matrix.row(i)],
        data,
        outputs,
        length,
      );
      for (var j = 0; j < missingParity.length; j++) {
        shards[missingParity[j]] = outputs[j];
      }
    }
  }

  void _checkShards(List<Uint8List> shards) {
    if (shards.length != totalShards) {
      throw ArgumentError('Ожидалось $totalShards фрагментов');
    }
    final length = shards.first.length;
    for (final shard in shards) {
      if (shard.length != length) {
        throw ArgumentError('Фрагменты разной длины');
      }
    }
  }

  /// `outputs[j] = Σ rows[j][c] · inputs[c]` над GF(2^8), побайтно.
  ///
  /// Для каждого коэффициента берётся своя строка таблицы умножения
  /// (256 байт), цикл развёрнут на 8 байт.
  static void _codeSomeShards(
    List<Uint8List> rows,
    List<Uint8List> inputs,
    List<Uint8List> outputs,
    int length,
  ) {
    final table = Galois8.mulTable;
    final tail = length - length % 8;
    for (var j = 0; j < outputs.length; j++) {
      final out = outputs[j];
      final row = rows[j];
      for (var c = 0; c < inputs.length; c++) {
        final input = inputs[c];
        final mul = Uint8List.sublistView(
          table,
          row[c] * 256,
          row[c] * 256 + 256,
        );
        if (c == 0) {
          var i = 0;
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
          var i = 0;
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
}

/// Квадратная или прямоугольная матрица над GF(2^8).
final class _Matrix {
  new(this.rows, this.columns) : _data = Uint8List(rows * columns);

  final int rows;
  final int columns;
  final Uint8List _data;

  int get(int r, int c) => _data[r * columns + c];

  void set(int r, int c, int value) => _data[r * columns + c] = value;

  Uint8List row(int r) =>
      Uint8List.sublistView(_data, r * columns, (r + 1) * columns);

  _Matrix subMatrix(int rowStart, int rowEnd) {
    final result = _Matrix(rowEnd - rowStart, columns);
    result._data.setRange(0, result._data.length, _data, rowStart * columns);
    return result;
  }

  _Matrix times(_Matrix other) {
    final result = _Matrix(rows, other.columns);
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < other.columns; c++) {
        var value = 0;
        for (var i = 0; i < columns; i++) {
          value ^= Galois8.mul(get(r, i), other.get(i, c));
        }
        result._data[r * result.columns + c] = value;
      }
    }
    return result;
  }

  /// Обращение методом Гаусса–Жордана.
  _Matrix inverse() {
    if (rows != columns) throw StateError('Матрица не квадратная');
    final n = rows;
    final work = _Matrix(n, 2 * n);
    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        work._data[r * 2 * n + c] = get(r, c);
      }
      work._data[r * 2 * n + n + r] = 1;
    }
    for (var r = 0; r < n; r++) {
      if (work.get(r, r) == 0) {
        final swap = [
          for (var below = r + 1; below < n; below++)
            if (work.get(below, r) != 0) below,
        ];
        if (swap.isEmpty) throw StateError('Вырожденная матрица');
        work._swapRows(r, swap.first);
      }
      final pivot = work.get(r, r);
      if (pivot != 1) {
        for (var c = 0; c < 2 * n; c++) {
          work._data[r * 2 * n + c] = Galois8.div(work.get(r, c), pivot);
        }
      }
      for (var other = 0; other < n; other++) {
        if (other == r) continue;
        final factor = work.get(other, r);
        if (factor == 0) continue;
        for (var c = 0; c < 2 * n; c++) {
          work._data[other * 2 * n + c] ^= Galois8.mul(factor, work.get(r, c));
        }
      }
    }
    final result = _Matrix(n, n);
    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        result._data[r * n + c] = work.get(r, n + c);
      }
    }
    return result;
  }

  void _swapRows(int a, int b) {
    for (var c = 0; c < columns; c++) {
      final tmp = _data[a * columns + c];
      _data[a * columns + c] = _data[b * columns + c];
      _data[b * columns + c] = tmp;
    }
  }
}
