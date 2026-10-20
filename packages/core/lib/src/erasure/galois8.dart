import 'dart:typed_data';

/// Арифметика поля GF(2^8) с порождающим многочленом
/// x^8 + x^4 + x^3 + x^2 + 1 (0x11D) и образующим элементом 2 —
/// как в reed-solomon-erasure (galois_8) и Backblaze JavaReedSolomon.
abstract final class Galois8 {
  static final Uint8List _exp = _buildExp();
  static final Uint8List _log = _buildLog();

  /// Таблица умножения 256 × 256: `mulTable[a * 256 + b] == a * b`.
  static final Uint8List mulTable = _buildMulTable();

  static Uint8List _buildExp() {
    final exp = Uint8List(510);
    var x = 1;
    for (var i = 0; i < 255; i++) {
      exp[i] = x;
      exp[i + 255] = x;
      x <<= 1;
      if (x & 0x100 != 0) x ^= 0x11D;
    }
    return exp;
  }

  static Uint8List _buildLog() {
    final log = Uint8List(256);
    for (var i = 0; i < 255; i++) {
      log[_exp[i]] = i;
    }
    return log;
  }

  static Uint8List _buildMulTable() {
    final table = Uint8List(256 * 256);
    for (var a = 1; a < 256; a++) {
      for (var b = 1; b < 256; b++) {
        table[a * 256 + b] = _exp[_log[a] + _log[b]];
      }
    }
    return table;
  }

  static int mul(int a, int b) => mulTable[a * 256 + b];

  static int div(int a, int b) {
    if (b == 0) throw ArgumentError('Деление на ноль в GF(256)');
    if (a == 0) return 0;
    return _exp[(_log[a] - _log[b] + 255) % 255];
  }

  /// a в степени n.
  static int pow(int a, int n) {
    if (n == 0) return 1;
    if (a == 0) return 0;
    return _exp[(_log[a] * n) % 255];
  }
}
