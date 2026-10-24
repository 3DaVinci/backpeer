import 'dart:collection';
import 'dart:typed_data';

import 'package:core/src/errors.dart';
import 'package:core/src/net/noise.dart';

/// Кадры канала Noise (protocol.md, раздел 3.3).
///
/// - Транспортный кадр: `u16be длина || сообщение Noise`, длина до 65 535.
/// - Кадр приложения: `u32be длина || PeerMessage` в потоке расшифрованных
///   транспортных кадров, длина до 1 МиБ. Отправитель нарезает его на куски
///   по [maxPlaintext] байт, по куску на транспортный кадр; получатель не
///   опирается на границы кадров.
/// - Смена ключей: после каждых [rekeyInterval] транспортных сообщений в
///   направлении обе стороны вызывают `Rekey()` шифра этого направления.
abstract final class NoiseFrames {
  static const int maxTransportMessage = Noise.maxMessageLength;

  /// Открытый текст одного транспортного кадра: 65 535 − 16.
  static const int maxPlaintext = maxTransportMessage - Noise.tagLength;

  static const int maxAppMessage = 1 << 20;

  static const int rekeyInterval = 65536;

  /// Транспортный кадр из сообщения Noise.
  static Uint8List frame(Uint8List message) {
    if (message.length > maxTransportMessage) {
      throw ArgumentError('сообщение Noise длиннее 65 535 байт');
    }
    return Uint8List(2 + message.length)
      ..buffer.asByteData().setUint16(0, message.length)
      ..setAll(2, message);
  }
}

/// Очередь байт: куски добавляются в конец, читаются с начала без
/// склейки всего буфера.
final class _ByteQueue {
  final Queue<Uint8List> _chunks = Queue();
  int _offset = 0;
  int _length = 0;

  int get length => _length;

  void add(Uint8List chunk) {
    if (chunk.isEmpty) return;
    _chunks.add(chunk);
    _length += chunk.length;
  }

  /// [n] байт с начала; вызывающий проверил [length].
  Uint8List take(int n) {
    final out = Uint8List(n);
    var filled = 0;
    while (filled < n) {
      final head = _chunks.first;
      final available = head.length - _offset;
      final count = available < n - filled ? available : n - filled;
      out.setRange(filled, filled + count, head, _offset);
      filled += count;
      _offset += count;
      if (_offset == head.length) {
        _chunks.removeFirst();
        _offset = 0;
      }
    }
    _length -= n;
    return out;
  }

  /// Беззнаковое big-endian из [width] первых байт, без извлечения.
  int peekUint(int width) {
    var value = 0;
    var seen = 0;
    var offset = _offset;
    for (final chunk in _chunks) {
      for (var i = offset; i < chunk.length && seen < width; i++, seen++) {
        value = (value << 8) | chunk[i];
      }
      if (seen == width) break;
      offset = 0;
    }
    return value;
  }
}

/// Разбор потока на транспортные кадры: принимает куски любого размера,
/// отдаёт сообщения Noise целиком.
final class TransportFrameDecoder {
  final _ByteQueue _buffer = _ByteQueue();

  /// В буфере начатый, но не дочитанный кадр.
  bool get hasPartial => _buffer.length > 0;

  List<Uint8List> add(Uint8List chunk) {
    _buffer.add(chunk);
    final out = <Uint8List>[];
    while (_buffer.length >= 2) {
      final length = _buffer.peekUint(2);
      if (_buffer.length < 2 + length) break;
      _buffer.take(2);
      out.add(_buffer.take(length));
    }
    return out;
  }
}

/// Отправляющая половина канала после рукопожатия.
final class ChannelEncoder {
  new(this._cipher, {this.rekeyInterval = NoiseFrames.rekeyInterval}) {
    if (rekeyInterval <= 0) throw ArgumentError.value(rekeyInterval);
  }

  final NoiseCipherState _cipher;
  final int rekeyInterval;
  static final _empty = Uint8List(0);

  /// Транспортные кадры с сообщением приложения [message].
  Uint8List encode(Uint8List message) {
    if (message.length > NoiseFrames.maxAppMessage) {
      throw ArgumentError('сообщение приложения длиннее 1 МиБ');
    }
    final data = Uint8List(4 + message.length)
      ..buffer.asByteData().setUint32(0, message.length)
      ..setAll(4, message);
    final out = BytesBuilder(copy: false);
    for (var i = 0; i < data.length; i += NoiseFrames.maxPlaintext) {
      final end = i + NoiseFrames.maxPlaintext < data.length
          ? i + NoiseFrames.maxPlaintext
          : data.length;
      out.add(
        NoiseFrames.frame(
          _cipher.encrypt(_empty, Uint8List.sublistView(data, i, end)),
        ),
      );
      if (_cipher.nonce % rekeyInterval == 0) _cipher.rekey();
    }
    return out.takeBytes();
  }

  void dispose() => _cipher.dispose();
}

/// Принимающая половина канала: расшифровывает транспортные кадры и
/// собирает из них сообщения приложения.
final class ChannelDecoder {
  new(this._cipher, {this.rekeyInterval = NoiseFrames.rekeyInterval}) {
    if (rekeyInterval <= 0) throw ArgumentError.value(rekeyInterval);
  }

  final NoiseCipherState _cipher;
  final int rekeyInterval;
  final _ByteQueue _plain = _ByteQueue();
  static final _empty = Uint8List(0);

  /// Начатое сообщение приложения не дочитано.
  bool get hasPartial => _plain.length > 0;

  /// Сообщения приложения, которые завершило транспортное сообщение
  /// [message]. Кадр короче тега и длина сообщения больше 1 МиБ —
  /// [DataFormatException], неверный тег (подмена, перестановка, обрыв) —
  /// [IntegrityException].
  List<Uint8List> add(Uint8List message) {
    if (message.length < Noise.tagLength) {
      throw DataFormatException(
        object: 'noise-frame',
        problem: FormatProblem.truncated,
        detail: 'транспортный кадр ${message.length} байт короче тега',
      );
    }
    final plain = _cipher.decrypt(_empty, message);
    if (plain == null) {
      throw const IntegrityException(
        object: 'noise-frame',
        check: IntegrityCheck.aeadTag,
      );
    }
    if (_cipher.nonce % rekeyInterval == 0) _cipher.rekey();
    _plain.add(plain);
    final out = <Uint8List>[];
    while (_plain.length >= 4) {
      final length = _plain.peekUint(4);
      if (length > NoiseFrames.maxAppMessage) {
        throw DataFormatException(
          object: 'peer-message',
          problem: FormatProblem.tooLarge,
          detail: '$length байт',
        );
      }
      if (_plain.length < 4 + length) break;
      _plain.take(4);
      out.add(_plain.take(length));
    }
    return out;
  }

  void dispose() => _cipher.dispose();
}
