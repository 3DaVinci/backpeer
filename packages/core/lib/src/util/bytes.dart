import 'dart:typed_data';

/// Последовательная запись байтов форматов из docs/spec/: целые
/// little-endian (`u16le`, `u32le`, `u64le`, crypto.md, раздел 1) и
/// big-endian (кадры протокола, protocol.md), varint, сырые байты.
///
/// u64 хранится в 64-битном int Dart VM: значения от 2^63 выглядят
/// отрицательными, но биты сохраняются. JavaScript не поддерживается.
final class ByteWriter {
  new([int initialCapacity = 64])
    : _buffer = Uint8List(initialCapacity < 8 ? 8 : initialCapacity);

  Uint8List _buffer;
  int _length = 0;

  int get length => _length;

  void u8(int value) {
    _checkRange(value, 0xFF);
    _reserve(1);
    _buffer[_length++] = value;
  }

  void u16le(int value) => _uint(value, 2, Endian.little);
  void u32le(int value) => _uint(value, 4, Endian.little);
  void u64le(int value) => _uint(value, 8, Endian.little);
  void u16be(int value) => _uint(value, 2, Endian.big);
  void u32be(int value) => _uint(value, 4, Endian.big);
  void u64be(int value) => _uint(value, 8, Endian.big);

  /// Беззнаковый varint (LEB128, как в Protobuf). Значение трактуется как
  /// 64-битное беззнаковое.
  void varint(int value) {
    var v = value;
    while (v & ~0x7F != 0) {
      _reserve(1);
      _buffer[_length++] = (v & 0x7F) | 0x80;
      v >>>= 7;
    }
    _reserve(1);
    _buffer[_length++] = v;
  }

  void bytes(List<int> data) {
    _reserve(data.length);
    _buffer.setRange(_length, _length + data.length, data);
    _length += data.length;
  }

  /// [count] нулевых байтов (выравнивание, зарезервированные поля).
  void zeros(int count) {
    RangeError.checkNotNegative(count, 'count');
    _reserve(count);
    _buffer.fillRange(_length, _length + count, 0);
    _length += count;
  }

  /// Копия записанных байтов.
  Uint8List toBytes() => Uint8List.fromList(_buffer.sublist(0, _length));

  void _uint(int value, int width, Endian endian) {
    if (width < 8) _checkRange(value, (1 << (8 * width)) - 1);
    _reserve(width);
    final view = ByteData.sublistView(_buffer, _length, _length + width);
    switch (width) {
      case 2:
        view.setUint16(0, value, endian);
      case 4:
        view.setUint32(0, value, endian);
      default:
        view.setUint64(0, value, endian);
    }
    _length += width;
  }

  void _reserve(int extra) {
    final needed = _length + extra;
    if (needed <= _buffer.length) return;
    var capacity = _buffer.length * 2;
    while (capacity < needed) {
      capacity *= 2;
    }
    _buffer = Uint8List(capacity)..setRange(0, _length, _buffer);
  }

  static void _checkRange(int value, int max) {
    if (value < 0 || value > max) {
      throw RangeError.range(value, 0, max, 'value');
    }
  }
}

/// Последовательное чтение байтов с проверкой границ. Выход за конец
/// буфера — [RangeError]; разборщики форматов переводят его в свои ошибки.
final class ByteReader {
  new(Uint8List data) : _data = data, _view = ByteData.sublistView(data);

  final Uint8List _data;
  final ByteData _view;
  int _offset = 0;

  int get offset => _offset;
  int get remaining => _data.length - _offset;
  bool get isAtEnd => _offset == _data.length;

  int u8() => _data[_take(1)];
  int u16le() => _view.getUint16(_take(2), Endian.little);
  int u32le() => _view.getUint32(_take(4), Endian.little);
  int u64le() => _view.getUint64(_take(8), Endian.little);
  int u16be() => _view.getUint16(_take(2));
  int u32be() => _view.getUint32(_take(4));
  int u64be() => _view.getUint64(_take(8));

  /// Беззнаковый varint (LEB128), не длиннее 10 байтов. Неканоническая
  /// запись (лишние нулевые старшие группы) отвергается.
  int varint() {
    var result = 0;
    for (var i = 0; i < 10; i++) {
      final b = u8();
      if (i == 9 && b > 1) {
        throw const FormatException('varint больше 64 бит');
      }
      result |= (b & 0x7F) << (7 * i);
      if (b & 0x80 == 0) {
        if (b == 0 && i > 0) {
          throw const FormatException('Неканонический varint');
        }
        return result;
      }
    }
    throw const FormatException('varint длиннее 10 байтов');
  }

  /// Представление следующих [count] байтов без копирования.
  Uint8List bytes(int count) {
    final start = _take(count);
    return Uint8List.sublistView(_data, start, start + count);
  }

  void skip(int count) => _take(count);

  int _take(int count) {
    RangeError.checkNotNegative(count, 'count');
    if (count > remaining) {
      throw RangeError(
        'Нужно $count байт по смещению $_offset, осталось $remaining',
      );
    }
    final start = _offset;
    _offset += count;
    return start;
  }
}

const _hexDigits = '0123456789abcdef';

/// Байты в шестнадцатеричную строку в нижнем регистре.
String bytesToHex(List<int> bytes) {
  final out = StringBuffer();
  for (final b in bytes) {
    out
      ..write(_hexDigits[(b >> 4) & 0xF])
      ..write(_hexDigits[b & 0xF]);
  }
  return out.toString();
}

/// Шестнадцатеричная строка (любой регистр) в байты.
Uint8List hexToBytes(String hex) {
  if (hex.length.isOdd) {
    throw FormatException('Нечётная длина hex-строки', hex);
  }
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = (_nibble(hex, 2 * i) << 4) | _nibble(hex, 2 * i + 1);
  }
  return out;
}

int _nibble(String hex, int index) {
  final c = hex.codeUnitAt(index);
  if (c >= 0x30 && c <= 0x39) return c - 0x30;
  final lower = c | 0x20;
  if (lower >= 0x61 && lower <= 0x66) return lower - 0x61 + 10;
  throw FormatException('Недопустимый символ hex', hex, index);
}

/// Сравнение байтов за время, не зависящее от места первого различия
/// (для MAC и хэшей).
bool constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}
