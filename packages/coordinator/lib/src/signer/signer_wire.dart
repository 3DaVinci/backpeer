import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:protocol/protocol.dart' as pb;

/// Обмен веб-сервера с подписантом по Unix-сокету (`docs/ops/coordinator.md`,
/// раздел «Подписант»). Не часть публичного протокола: обе стороны — один
/// пакет одной версии.
///
/// Кадр: `u32be длина || тело`, длина от 1 до [maxFrameLength].
///
/// Запрос: `u8 версия = 1 || u8 n || n × (u16be длина || FragmentTicket)`,
/// n от 0 до [maxBatch]; n = 0 — запрос открытого ключа подписанта (ответ
/// без подписей).
///
/// Ответ: `u8 0 || ключ подписанта (32) || n × подпись (64)` — подписи в
/// порядке талонов; или `u8 код ErrorCode || u32be retry_after_ms ||
/// u8 номер талона` (255 — ошибка не в талоне). Ошибка в одном талоне
/// отклоняет весь запрос.
abstract final class SignerWire {
  static const version = 1;
  static const maxBatch = 64;
  static const int maxFrameLength =
      2 + maxBatch * (2 + FragmentTickets.maxEncodedLength);
  static const noIndex = 255;
  static const keyLength = 32;
  static const int signatureLength = CryptoProvider.ed25519SignatureLength;

  static Uint8List frame(Uint8List body) {
    final out = Uint8List(4 + body.length);
    ByteData.sublistView(out).setUint32(0, body.length);
    out.setAll(4, body);
    return out;
  }

  static Uint8List encodeRequest(List<Uint8List> tickets) {
    if (tickets.length > maxBatch) {
      throw ArgumentError('талонов ${tickets.length}, нужно 0…$maxBatch');
    }
    final b = BytesBuilder(copy: false)
      ..addByte(version)
      ..addByte(tickets.length);
    for (final t in tickets) {
      if (t.length > FragmentTickets.maxEncodedLength) {
        throw ArgumentError('талон ${t.length} байт');
      }
      b
        ..addByte(t.length >> 8)
        ..addByte(t.length & 0xFF)
        ..add(t);
    }
    return b.takeBytes();
  }

  /// Тела талонов из запроса; `null` — запрос не по формату.
  static List<Uint8List>? decodeRequest(Uint8List body) {
    if (body.length < 2 || body[0] != version) return null;
    final count = body[1];
    if (count > maxBatch) return null;
    final view = ByteData.sublistView(body);
    final tickets = <Uint8List>[];
    var offset = 2;
    for (var i = 0; i < count; i++) {
      if (offset + 2 > body.length) return null;
      final length = view.getUint16(offset);
      offset += 2;
      if (offset + length > body.length) return null;
      tickets.add(Uint8List.sublistView(body, offset, offset + length));
      offset += length;
    }
    return offset == body.length ? tickets : null;
  }

  static Uint8List encodeSigned(Uint8List signer, List<Uint8List> signatures) {
    final b = BytesBuilder(copy: false)
      ..addByte(0)
      ..add(signer);
    signatures.forEach(b.add);
    return b.takeBytes();
  }

  static Uint8List encodeError(
    pb.ErrorCode code, {
    Duration? retryAfter,
    int index = noIndex,
  }) {
    final out = Uint8List(6)..[0] = code.value;
    ByteData.sublistView(out)
        .setUint32(1, retryAfter?.inMilliseconds.clamp(0, 0xFFFFFFFF) ?? 0);
    out[5] = index;
    return out;
  }
}

/// Ответ подписанта, разобранный клиентом.
sealed class SignerReply {
  const new();

  /// `null` — ответ не по формату для [count] талонов.
  static SignerReply? decode(Uint8List body, int count) {
    if (body.isEmpty) return null;
    if (body[0] == 0) {
      const head = 1 + SignerWire.keyLength;
      if (body.length != head + count * SignerWire.signatureLength) {
        return null;
      }
      return SignerSigned(Uint8List.fromList(body.sublist(1, head)), [
        for (var i = 0; i < count; i++)
          Uint8List.fromList(
            body.sublist(
              head + i * SignerWire.signatureLength,
              head + (i + 1) * SignerWire.signatureLength,
            ),
          ),
      ]);
    }
    if (body.length != 6) return null;
    final code = pb.ErrorCode.valueOf(body[0]);
    if (code == null) return null;
    final retryMs = ByteData.sublistView(body).getUint32(1);
    return SignerRefused(
      code,
      retryAfter: retryMs == 0 ? null : Duration(milliseconds: retryMs),
      index: body[5] == SignerWire.noIndex ? null : body[5],
    );
  }
}

final class SignerSigned extends SignerReply {
  const new(this.signer, this.signatures);

  final Uint8List signer;
  final List<Uint8List> signatures;
}

final class SignerRefused extends SignerReply {
  const new(this.code, {this.retryAfter, this.index});

  final pb.ErrorCode code;
  final Duration? retryAfter;

  /// Какой талон отклонён.
  final int? index;
}

/// Собирает кадры `u32be длина || тело` из кусков потока.
final class FrameReader {
  Uint8List _pending = Uint8List(0);

  void add(Uint8List chunk) {
    _pending = _pending.isEmpty
        ? chunk
        : (BytesBuilder(copy: false)
                ..add(_pending)
                ..add(chunk))
              .takeBytes();
  }

  /// Следующий целый кадр или `null`. Длина вне 1…[maxLength] —
  /// [FormatException]: поток дальше не разобрать.
  Uint8List? next({int maxLength = SignerWire.maxFrameLength}) {
    if (_pending.length < 4) return null;
    final length = ByteData.sublistView(_pending).getUint32(0);
    if (length == 0 || length > maxLength) {
      throw const FormatException('длина кадра');
    }
    if (_pending.length < 4 + length) return null;
    final frame = Uint8List.sublistView(_pending, 4, 4 + length);
    _pending = Uint8List.sublistView(_pending, 4 + length);
    return frame;
  }
}
