import 'dart:typed_data';

import 'package:core/src/crypto/crypto_provider.dart';
import 'package:core/src/crypto/signed_message.dart';
import 'package:core/src/errors.dart';
import 'package:core/src/format/coordinator_keys.dart';
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

/// Почему узел отклоняет талон ([FragmentTickets.authorize]).
enum TicketRejection {
  /// Подписавший не входит во вшитый список ключей координатора.
  untrusted,

  /// Подпись не сходится.
  signature,

  /// Поля или каноническая сериализация.
  format,
  expired,
  tooLong,

  /// Талон на другую операцию, другой узел, другое устройство или другой
  /// фрагмент.
  mismatch,
}

/// Талон не разрешает операцию.
final class TicketRejectedException implements Exception {
  const new(this.reason, [this.detail]);

  final TicketRejection reason;
  final String? detail;

  @override
  String toString() {
    final suffix = detail == null ? '' : ': $detail';
    return 'TicketRejectedException(${reason.name}$suffix)';
  }
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

  /// Каноническое тело талона не длиннее: до четырёх ключей и
  /// идентификаторы с тегами и длинами, числа в varint — около 190 байт.
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

  /// Проверяет подписанный талон: подписавший входит в [trusted]
  /// (protocol.md, раздел 5.1), подпись верна, поля по [parse]. Чужой ключ
  /// или неверная подпись — [IntegrityException], поля — [DataFormatException].
  /// Срок, узел и устройство проверяет вызывающий ([checkTime]).
  static Future<pb.FragmentTicket> open(
    CryptoProvider crypto,
    pb.Signed signed,
    CoordinatorKeySet trusted,
  ) async {
    if (!trusted.trusts(signed.signer)) {
      throw const IntegrityException(
        object: 'fragment-ticket',
        check: IntegrityCheck.signature,
      );
    }
    return await SignedMessages.open(
      crypto,
      signed,
      context: signingContext,
      object: 'fragment-ticket',
      parse: (body) => parse(Uint8List.fromList(body)),
    );
  }

  /// Полная проверка талона узлом перед операцией (protocol.md, раздел 5):
  /// подпись ключом из [trusted], поля, срок на момент [now] с допуском
  /// [clockSkew], операция, этот узел [nodeId], собеседник по Noise
  /// [deviceSign], фрагмент [fragmentId] и, если известен, его размер
  /// [fragmentSize] (для PUT — после приёма). Повторное использование
  /// `ticket_id` узел проверяет сам: это его состояние. Отказ —
  /// [TicketRejectedException].
  static Future<pb.FragmentTicket> authorize(
    CryptoProvider crypto,
    pb.Signed signed,
    CoordinatorKeySet trusted, {
    required DateTime now,
    required pb.TicketOperation operation,
    required List<int> nodeId,
    required List<int> deviceSign,
    required List<int> fragmentId,
    int? fragmentSize,
  }) async {
    if (!trusted.trusts(signed.signer)) {
      throw const TicketRejectedException(TicketRejection.untrusted);
    }
    final pb.FragmentTicket ticket;
    try {
      ticket = await open(crypto, signed, trusted);
    } on IntegrityException {
      throw const TicketRejectedException(TicketRejection.signature);
    } on DataFormatException catch (e) {
      throw TicketRejectedException(TicketRejection.format, e.detail);
    }
    switch (checkTime(ticket, now)) {
      case TicketTimeProblem.expired:
        throw const TicketRejectedException(TicketRejection.expired);
      case TicketTimeProblem.tooLong:
        throw const TicketRejectedException(TicketRejection.tooLong);
      case null:
    }
    String? mismatch;
    if (ticket.operation != operation) {
      mismatch = 'operation';
    } else if (!constantTimeEquals(ticket.nodeId, nodeId)) {
      mismatch = 'node_id';
    } else if (!constantTimeEquals(ticket.deviceSign, deviceSign)) {
      mismatch = 'device_sign';
    } else if (!constantTimeEquals(ticket.fragmentId, fragmentId)) {
      mismatch = 'fragment_id';
    } else if (fragmentSize != null && ticket.fragmentSize != fragmentSize) {
      mismatch = 'fragment_size';
    }
    if (mismatch != null) {
      throw TicketRejectedException(TicketRejection.mismatch, mismatch);
    }
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
    // Владелец фрагмента — только у PUT узла-исполнителя ремонта
    // (protocol.md, раздел 4.14).
    if (ticket.ownerAccount.isNotEmpty) {
      if (ticket.operation != pb.TicketOperation.TICKET_OPERATION_PUT) {
        throw _error(FormatProblem.invalidField, 'owner_account не у PUT');
      }
      _length('owner_account', ticket.ownerAccount, keyLength);
    }
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
