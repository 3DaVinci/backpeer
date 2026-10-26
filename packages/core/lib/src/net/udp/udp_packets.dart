import 'dart:io';
import 'dart:typed_data';

/// Форматы датаграмм UDP (protocol.md, разделы 3.5 и 4.11). Первый байт —
/// вид пакета; числа — big-endian. Датаграмма, которая не разбирается,
/// пропускается без ответа.
abstract final class UdpPackets {
  /// Запрос к своднику: какой внешний адрес у отправителя.
  static const bindingRequest = 0x01;

  /// Ответ сводника.
  static const bindingResponse = 0x02;

  /// Пробивание NAT при сведении узлов.
  static const punch = 0x03;

  /// Пакеты потока (раздел 3.5).
  static const syn = 0x10;
  static const data = 0x11;
  static const state = 0x12;
  static const fin = 0x13;
  static const reset = 0x14;

  /// Версия форматов UDP.
  static const version = 1;

  /// Длина запроса к своднику. Ответ не длиннее запроса: сводник не
  /// усиливает поток, направленный на чужой адрес.
  static const bindingRequestLength = 64;

  /// Длина номера запроса к своднику.
  static const transactionIdLength = 12;

  /// Длина подтверждения адреса от сводника: `u32be` время выдачи в
  /// секундах и 16 байт MAC.
  static const bindingTokenLength = 20;

  /// Длина номера сведения.
  static const punchIdLength = 16;

  /// Флаг пакета [punch]: ответ на пакет собеседника.
  static const punchReply = 0x01;

  static Uint8List encodeBindingRequest(Uint8List transactionId) {
    _checkLength(transactionId, transactionIdLength, 'transactionId');
    return Uint8List(bindingRequestLength)
      ..[0] = bindingRequest
      ..[1] = version
      ..setRange(2, 2 + transactionIdLength, transactionId);
  }

  /// Номер запроса из запроса к своднику или `null`, если это не он.
  static Uint8List? decodeBindingRequest(Uint8List d) {
    if (d.length < bindingRequestLength ||
        d[0] != bindingRequest ||
        d[1] != version) {
      return null;
    }
    return Uint8List.fromList(d.sublist(2, 2 + transactionIdLength));
  }

  static Uint8List encodeBindingResponse(BindingResponse r) {
    final raw = r.address.rawAddress;
    _checkLength(r.transactionId, transactionIdLength, 'transactionId');
    _checkLength(r.token, bindingTokenLength, 'token');
    const a = 2 + transactionIdLength + 3;
    final b = a + raw.length;
    return Uint8List(b + bindingTokenLength)
      ..[0] = bindingResponse
      ..[1] = version
      ..setRange(2, 2 + transactionIdLength, r.transactionId)
      ..[a - 3] = r.port >> 8
      ..[a - 2] = r.port & 0xff
      ..[a - 1] = raw.length
      ..setRange(a, b, raw)
      ..setRange(b, b + bindingTokenLength, r.token);
  }

  static BindingResponse? decodeBindingResponse(Uint8List d) {
    if (d.length < 2 + transactionIdLength + 3 ||
        d[0] != bindingResponse ||
        d[1] != version) {
      return null;
    }
    var o = 2;
    final tx = Uint8List.fromList(d.sublist(o, o += transactionIdLength));
    final port = d[o] << 8 | d[o + 1];
    o += 2;
    final len = d[o++];
    if ((len != 4 && len != 16) ||
        d.length != o + len + bindingTokenLength ||
        port == 0) {
      return null;
    }
    final address = InternetAddress.fromRawAddress(d.sublist(o, o += len));
    return BindingResponse(
      transactionId: tx,
      address: address,
      port: port,
      token: Uint8List.fromList(d.sublist(o)),
    );
  }

  static Uint8List encodePunch(Uint8List punchId, {bool reply = false}) {
    _checkLength(punchId, punchIdLength, 'punchId');
    return Uint8List(2 + punchIdLength)
      ..[0] = punch
      ..[1] = reply ? punchReply : 0
      ..setRange(2, 2 + punchIdLength, punchId);
  }

  /// `(номер сведения, ответ ли)` или `null`.
  static (Uint8List, bool)? decodePunch(Uint8List d) {
    if (d.length != 2 + punchIdLength || d[0] != punch) return null;
    return (Uint8List.sublistView(d, 2), d[1] & punchReply != 0);
  }

  static void _checkLength(Uint8List b, int length, String name) {
    if (b.length != length) {
      throw ArgumentError.value(b.length, name, 'нужно $length байт');
    }
  }
}

/// Ответ сводника: внешний адрес отправителя запроса и подтверждение
/// этого адреса для координатора.
final class BindingResponse {
  const new({
    required this.transactionId,
    required this.address,
    required this.port,
    required this.token,
  });

  final Uint8List transactionId;
  final InternetAddress address;
  final int port;
  final Uint8List token;
}

/// Пакет потока поверх UDP (protocol.md, раздел 3.5):
///
/// ```text
/// вид (1) || conn_id (4) || seq (4) || ack (4) || ts (4) || ts_diff (4)
///   || wnd (4) || sack_len (1) || sack (sack_len) || данные
/// ```
final class StreamPacket {
  new({
    required this.type,
    required this.connectionId,
    required this.seq,
    required this.ack,
    required this.timestamp,
    required this.timestampDiff,
    required this.window,
    Uint8List? sack,
    Uint8List? payload,
  }) : sack = sack ?? _empty,
       payload = payload ?? _empty;

  static final _empty = Uint8List(0);

  /// Длина заголовка без битовой карты SACK.
  static const headerLength = 26;

  /// Наибольшая битовая карта SACK: 256 пакетов за подтверждённым.
  static const maxSackBytes = 32;

  /// Наибольшие данные в пакете: датаграмма не длиннее 1232 байт (1280
  /// минимального MTU IPv6 минус заголовки IP и UDP) с любой картой SACK.
  static const maxPayload = 1152;

  final int type;
  final int connectionId;

  /// Младшие 32 бита номера пакета.
  final int seq;

  /// Младшие 32 бита наибольшего номера, принятого по порядку.
  final int ack;

  /// Время отправки, микросекунды по часам отправителя (младшие 32 бита).
  final int timestamp;

  /// Задержка последнего принятого пакета собеседника: время приёма
  /// минус его [timestamp] (по модулю 2^32).
  final int timestampDiff;

  /// Сколько байт ещё готов принять отправитель.
  final int window;

  /// Бит `i` байта `j` (с младшего) — принят пакет `ack + 2 + 8j + i`.
  final Uint8List sack;
  final Uint8List payload;

  static bool isStreamType(int type) => type >= 0x10 && type <= 0x14;

  Uint8List encode() {
    final out = Uint8List(headerLength + sack.length + payload.length);
    ByteData.sublistView(out)
      ..setUint8(0, type)
      ..setUint32(1, connectionId)
      ..setUint32(5, seq & 0xffffffff)
      ..setUint32(9, ack & 0xffffffff)
      ..setUint32(13, timestamp & 0xffffffff)
      ..setUint32(17, timestampDiff & 0xffffffff)
      ..setUint32(21, window)
      ..setUint8(25, sack.length);
    out
      ..setRange(headerLength, headerLength + sack.length, sack)
      ..setRange(headerLength + sack.length, out.length, payload);
    return out;
  }

  static StreamPacket? decode(Uint8List d) {
    if (d.length < headerLength || !isStreamType(d[0])) return null;
    final b = ByteData.sublistView(d);
    final sackLength = d[25];
    if (sackLength > maxSackBytes || d.length < headerLength + sackLength) {
      return null;
    }
    final payloadStart = headerLength + sackLength;
    if (d.length - payloadStart > maxPayload) return null;
    return StreamPacket(
      type: d[0],
      connectionId: b.getUint32(1),
      seq: b.getUint32(5),
      ack: b.getUint32(9),
      timestamp: b.getUint32(13),
      timestampDiff: b.getUint32(17),
      window: b.getUint32(21),
      sack: Uint8List.sublistView(d, headerLength, payloadStart),
      payload: Uint8List.sublistView(d, payloadStart),
    );
  }
}

/// Восстанавливает 64-битный номер по младшим 32 битам [low]: ближайший
/// к [reference].
int expandSequence(int low, int reference) {
  const span = 1 << 32;
  final base = reference & ~(span - 1);
  var candidate = base | low;
  if (candidate - reference > span ~/ 2) {
    candidate -= span;
  } else if (reference - candidate > span ~/ 2) {
    candidate += span;
  }
  return candidate;
}
