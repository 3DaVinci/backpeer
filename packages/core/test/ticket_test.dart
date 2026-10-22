// Правила талона FragmentTicket (protocol.md, раздел 5). Векторы талонов
// с подписью — задача 2.7.2.

import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:fixnum/fixnum.dart';
import 'package:protocol/protocol.dart' as pb;
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 10, 23, 12);

  pb.FragmentTicket ticket() => pb.FragmentTicket(
    operation: pb.TicketOperation.TICKET_OPERATION_PUT,
    nodeId: Uint8List(32)..fillRange(0, 32, 1),
    deviceSign: Uint8List(32)..fillRange(0, 32, 2),
    fragmentId: Uint8List(32)..fillRange(0, 32, 3),
    fragmentSize: 1677824,
    expiresAtUnixMs: Int64(
      now.add(const Duration(minutes: 30)).millisecondsSinceEpoch,
    ),
    ticketId: Uint8List(16)..fillRange(0, 16, 4),
  );

  Matcher formatError(String detail) => isA<DataFormatException>()
      .having((e) => e.object, 'object', 'fragment-ticket')
      .having((e) => e.detail, 'detail', contains(detail));

  test('правильный талон разбирается', () {
    final body = ticket().writeToBuffer();
    expect(body.length, lessThanOrEqualTo(FragmentTickets.maxEncodedLength));
    final parsed = FragmentTickets.parse(body);
    expect(parsed, ticket());
  });

  test('поля проверяются', () {
    final cases = <String, void Function(pb.FragmentTicket)>{
      'operation': (t) => t.clearOperation(),
      'node_id': (t) => t.nodeId = Uint8List(31),
      'device_sign': (t) => t.deviceSign = Uint8List(33),
      'fragment_id': (t) => t.clearFragmentId(),
      'ticket_id': (t) => t.ticketId = Uint8List(32),
      'fragment_size = 96': (t) => t.fragmentSize = 96,
      'fragment_size = 16781313': (t) =>
          t.fragmentSize = FragmentTickets.maxFragmentSize + 1,
      'expires_at': (t) => t.clearExpiresAtUnixMs(),
    };
    for (final MapEntry(key: detail, value: spoil) in cases.entries) {
      final t = ticket();
      spoil(t);
      expect(
        () => FragmentTickets.parse(t.writeToBuffer()),
        throwsA(formatError(detail)),
        reason: detail,
      );
    }
  });

  test('предельный размер фрагмента допустим', () {
    final t = ticket()..fragmentSize = FragmentTickets.maxFragmentSize;
    expect(FragmentTickets.parse(t.writeToBuffer()).fragmentSize, 16781312);
  });

  test('неканоническое тело отклоняется', () {
    final body = ticket().writeToBuffer();
    // Неизвестное поле 15 (varint 1).
    final extra = Uint8List.fromList([...body, 0x78, 0x01]);
    expect(
      () => FragmentTickets.parse(extra),
      throwsA(formatError('неканоническая')),
    );
    // Неизвестное значение enum operation.
    final unknownOp = Uint8List.fromList([0x08, 0x07, ...body.sublist(2)]);
    expect(body.sublist(0, 2), [0x08, 0x01]);
    expect(
      () => FragmentTickets.parse(unknownOp),
      throwsA(formatError('неканоническая')),
    );
    // Те же поля в обратном порядке.
    final reordered = Uint8List.fromList([...body.sublist(2), 0x08, 0x01]);
    expect(
      () => FragmentTickets.parse(reordered),
      throwsA(formatError('неканоническая')),
    );
  });

  test('мусор и длинное тело — ошибка формата', () {
    expect(
      () => FragmentTickets.parse(Uint8List.fromList([0xFF, 0xFF, 0xFF])),
      throwsA(isA<DataFormatException>()),
    );
    expect(
      () => FragmentTickets.parse(Uint8List(257)),
      throwsA(formatError('257 байт')),
    );
  });

  group('срок', () {
    TicketTimeProblem? at(Duration expiresIn, {Duration? skew}) =>
        FragmentTickets.checkTime(
          ticket()
            ..expiresAtUnixMs = Int64(
              now.add(expiresIn).millisecondsSinceEpoch,
            ),
          now,
          skew: skew ?? FragmentTickets.clockSkew,
        );

    test('без допуска (подписант)', () {
      expect(at(const Duration(minutes: 1), skew: Duration.zero), isNull);
      expect(at(const Duration(hours: 1), skew: Duration.zero), isNull);
      expect(
        at(const Duration(hours: 1, milliseconds: 1), skew: Duration.zero),
        TicketTimeProblem.tooLong,
      );
      expect(at(Duration.zero, skew: Duration.zero), TicketTimeProblem.expired);
    });

    test('с допуском 5 минут (узел)', () {
      expect(at(const Duration(minutes: -4)), isNull);
      expect(at(const Duration(minutes: -5)), TicketTimeProblem.expired);
      expect(at(const Duration(minutes: 65)), isNull);
      expect(
        at(const Duration(minutes: 65, milliseconds: 1)),
        TicketTimeProblem.tooLong,
      );
    });
  });
}
