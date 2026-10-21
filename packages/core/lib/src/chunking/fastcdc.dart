import 'dart:convert';
import 'dart:typed_data';

import 'package:core/src/crypto/crypto_provider.dart';
import 'package:core/src/crypto/secret_bytes.dart';

/// Таблица gear FastCDC, своя для каждой учётной записи
/// (data-format.md, раздел 2):
/// `gear[i] = u64le(первые 8 байт H_{K_gear}("fs/v1/gear" || u8(i)))`.
final class GearTable {
  new _(this._values);

  factory derive(CryptoProvider crypto, SecretBytes gearKey) {
    final values = Uint64List(256);
    final input = Uint8List(_label.length + 1)..setAll(0, _label);
    for (var i = 0; i < 256; i++) {
      input[_label.length] = i;
      final hash = crypto.blake2b256(input, key: gearKey);
      values[i] = ByteData.sublistView(hash).getUint64(0, Endian.little);
    }
    return GearTable._(values);
  }

  final Uint64List _values;

  int operator [](int byte) => _values[byte];

  static final Uint8List _label = ascii.encode('fs/v1/gear');
}

/// FastCDC с нормализацией второго уровня (data-format.md, раздел 2).
/// Отпечаток `fp` — u64 в 64-битном int Dart VM (сдвиг и сложение по
/// модулю 2^64); JavaScript не поддерживается.
/// Параметры фиксированы спецификацией: любая реализация обязана резать
/// одинаково, иначе дедупликация сломается при переходе.
final class FastCdc {
  new(this._gear);

  static const int minSize = 512 * 1024;
  static const int normalSize = 1024 * 1024;
  static const int maxSize = 8 * 1024 * 1024;
  static const int maskS = 0xFFFFFC0000000000;
  static const int maskL = 0xFFFFC00000000000;

  final GearTable _gear;

  /// Длина следующего чанка в `data[start..end)`; `end` по умолчанию —
  /// конец буфера. Для потоковой нарезки в окне должно быть не меньше
  /// [maxSize] байт либо весь остаток файла: иначе граница зависит от
  /// размера буфера.
  int cut(Uint8List data, [int start = 0, int? end]) {
    final stop = RangeError.checkValidRange(start, end, data.length);
    final length = stop - start;
    if (length <= minSize) return length;
    final n = length < maxSize ? length : maxSize;
    final normal = n < normalSize ? n : normalSize;
    final gear = _gear._values;
    var fp = 0;
    var i = minSize;
    for (; i < normal; i++) {
      fp = (fp << 1) + gear[data[start + i]];
      if (fp & maskS == 0) return i + 1;
    }
    for (; i < n; i++) {
      fp = (fp << 1) + gear[data[start + i]];
      if (fp & maskL == 0) return i + 1;
    }
    return n;
  }

  /// Длины чанков целого буфера. Пустой буфер не даёт ни одного чанка.
  List<int> chunkLengths(Uint8List data) {
    final out = <int>[];
    for (var pos = 0; pos < data.length;) {
      final size = cut(data, pos);
      out.add(size);
      pos += size;
    }
    return out;
  }
}
