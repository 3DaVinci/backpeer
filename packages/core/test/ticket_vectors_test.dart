// Векторы талонов test-vectors/protocol/ticket.json (protocol.md, раздел 5;
// генератор tool/protocol_vectors.py): проверка так, как её делает узел.

import 'package:core/core.dart';
import 'package:protocol/protocol.dart' as pb;
import 'package:test/test.dart';
import 'package:test_vectors/test_vectors.dart';

void main() {
  final cases = vectorCases(loadVectors('protocol/ticket.json'));
  late CryptoProvider crypto;
  setUpAll(() async => crypto = await SodiumCryptoProvider.load());

  for (final c in cases) {
    final input = c['input']! as Map<String, Object?>;
    final expected = c['expected']! as Map<String, Object?>;
    test(c['name'], () async {
      final signedJson = input['signed']! as Map<String, Object?>;
      final signed = pb.Signed(
        body: hexToBytes(signedJson['body']! as String),
        signer: hexToBytes(signedJson['signer']! as String),
        signature: hexToBytes(signedJson['signature']! as String),
      );
      final trusted = CoordinatorKeySet.fromHex([
        for (final k in input['trustedKeys']! as List<Object?>) k! as String,
      ]);
      final now = DateTime.fromMillisecondsSinceEpoch(
        input['nowUnixMs']! as int,
        isUtc: true,
      );
      Future<pb.FragmentTicket> authorize(pb.FragmentTicket t) =>
          FragmentTickets.authorize(
            crypto,
            signed,
            trusted,
            now: now,
            operation: t.operation,
            nodeId: t.nodeId,
            deviceSign: t.deviceSign,
            fragmentId: t.fragmentId,
            fragmentSize: t.fragmentSize,
          );

      final error = expected['error'] as String?;
      if (error == null) {
        final ticket = await FragmentTickets.open(crypto, signed, trusted);
        expect(ticket.operation.value, expected['operation']);
        expect(bytesToHex(ticket.nodeId), expected['nodeId']);
        expect(bytesToHex(ticket.deviceSign), expected['deviceSign']);
        expect(bytesToHex(ticket.fragmentId), expected['fragmentId']);
        expect(ticket.fragmentSize, expected['fragmentSize']);
        expect(ticket.expiresAtUnixMs.toInt(), expected['expiresAtUnixMs']);
        expect(bytesToHex(ticket.ticketId), expected['ticketId']);
        expect(await authorize(ticket), ticket);
        // Узел-заглушка: талон чужого узла или другой операции не годится.
        await expectLater(
          FragmentTickets.authorize(
            crypto,
            signed,
            trusted,
            now: now,
            operation: ticket.operation,
            nodeId: List.filled(32, 0x99),
            deviceSign: ticket.deviceSign,
            fragmentId: ticket.fragmentId,
          ),
          throwsA(
            isA<TicketRejectedException>().having(
              (e) => e.reason,
              'reason',
              TicketRejection.mismatch,
            ),
          ),
        );
        return;
      }
      final reason = switch (error) {
        'untrusted' => TicketRejection.untrusted,
        'signature' => TicketRejection.signature,
        'format' => TicketRejection.format,
        'expired' => TicketRejection.expired,
        'too-long' => TicketRejection.tooLong,
        _ => throw StateError('неизвестная ошибка $error'),
      };
      // Поля для сверки с операцией: из тела, если разбирается.
      pb.FragmentTicket fields;
      try {
        fields = pb.FragmentTicket.fromBuffer(signed.body);
      } on Object {
        fields = pb.FragmentTicket();
      }
      await expectLater(
        authorize(fields),
        throwsA(
          isA<TicketRejectedException>().having(
            (e) => e.reason,
            'reason',
            reason,
          ),
        ),
      );
    });
  }
}
