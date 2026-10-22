import 'dart:typed_data';

import 'package:core/src/errors.dart';
import 'package:core/src/format/fragment.dart';
import 'package:core/src/snapshot/manifest_objects.dart';
import 'package:core/src/util/bytes.dart';
import 'package:protocol/protocol.dart' as pb;

/// Почему срок талона не годится (protocol.md, раздел 5).
enum TicketTimeProblem {
  /// `expires_at` в прошлом (с учётом допуска на часы).
  expired,

  /// `expires_at` дальше [FragmentTickets.maxLifetime] от текущего времени.
  tooLong,
}

/// Правила талона `FragmentTicket` (protocol.md, раздел 5): общие для
/// подписанта координатора и узла.
abstract final class FragmentTickets {
  /// Контекст подписи талона (protocol.md, раздел 6).
  static const signingContext = 'ticket';

  /// Наибольший срок жизни талона.
  static const maxLifetime = Duration(hours: 1);

  /// Допуск на расхождение часов при проверке срока узлом.
  static const clockSkew = Duration(minutes: 5);

  /// `fragment_size`: от заголовка плюс байт до сегмента целиком при
  /// k = 1 с заголовками.
  static const int minFragmentSize = FragmentHeader.length + 1;
  static const int maxFragmentSize = 16 * 1024 * 1024 + 4096;

  static const keyLength = 32;
  static const fragmentIdLength = 32;
  static const ticketIdLength = 16;

  /// Каноническое тело талона не длиннее: три ключа и идентификаторы с
  /// тегами и длинами, числа в varint — около 150 байт.
  static const maxEncodedLength = 256;

  /// Разбирает тело талона и проверяет поля и каноничность. Ошибки —
  /// [DataFormatException] (`object: fragment-ticket`). Срок проверяет
  /// [checkTime].
  static pb.FragmentTicket parse(Uint8List body) {
    if (body.length > maxEncodedLength) {
      throw _error(FormatProblem.tooLarge, '${body.length} байт');
    }
    final ticket = ManifestObjects.parseMessage(
      'fragment-ticket',
      () => pb.FragmentTicket.fromBuffer(body),
    );
    // Неизвестные поля и значения enum разбор кладёт в unknownFields, а
    // запись возвращает обратно: проверяем их отдельно.
    if (ticket.unknownFields.isNotEmpty ||
        !constantTimeEquals(ticket.writeToBuffer(), body)) {
      throw _error(FormatProblem.invalidField, 'неканоническая сериализация');
    }
    check(ticket);
    return ticket;
  }

  /// Проверяет поля уже построенного талона (protocol.md, раздел 5).
  static void check(pb.FragmentTicket ticket) {
    if (ticket.operation == pb.TicketOperation.TICKET_OPERATION_UNSPECIFIED) {
      throw _error(FormatProblem.invalidField, 'operation не задана');
    }
    _length('node_id', ticket.nodeId, keyLength);
    _length('device_sign', ticket.deviceSign, keyLength);
    _length('fragment_id', ticket.fragmentId, fragmentIdLength);
    _length('ticket_id', ticket.ticketId, ticketIdLength);
    final size = ticket.fragmentSize;
    if (size < minFragmentSize || size > maxFragmentSize) {
      throw _error(FormatProblem.invalidField, 'fragment_size = $size');
    }
    if (ticket.expiresAtUnixMs <= 0) {
      throw _error(FormatProblem.invalidField, 'expires_at_unix_ms не задан');
    }
  }

  /// Срок талона относительно [now]: `null` — годится. [skew] — допуск на
  /// часы в обе стороны: узлу — [clockSkew], подписанту — ноль.
  /// [lifetime] — предел срока жизни, не больше [maxLifetime] (подписант
  /// может быть строже спецификации).
  static TicketTimeProblem? checkTime(
    pb.FragmentTicket ticket,
    DateTime now, {
    Duration skew = clockSkew,
    Duration lifetime = maxLifetime,
  }) {
    final expires = ticket.expiresAtUnixMs.toInt();
    final nowMs = now.millisecondsSinceEpoch;
    if (expires + skew.inMilliseconds <= nowMs) {
      return TicketTimeProblem.expired;
    }
    if (expires > nowMs + lifetime.inMilliseconds + skew.inMilliseconds) {
      return TicketTimeProblem.tooLong;
    }
    return null;
  }

  static void _length(String field, List<int> value, int expected) {
    if (value.length != expected) {
      throw _error(
        FormatProblem.invalidField,
        '$field: ${value.length} байт, нужно $expected',
      );
    }
  }

  static DataFormatException _error(FormatProblem problem, String detail) =>
      DataFormatException(
        object: 'fragment-ticket',
        problem: problem,
        detail: detail,
      );
}
