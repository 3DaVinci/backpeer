// Ключи координатора и проверка подписанных талонов (задача 2.2.2,
// protocol.md, раздел 5.1).

import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:fixnum/fixnum.dart';
import 'package:protocol/protocol.dart' as pb;
import 'package:test/test.dart';

void main() {
  late CryptoProvider crypto;
  late Ed25519KeyPair oldKey;
  late Ed25519KeyPair newKey;

  setUpAll(() async {
    crypto = await SodiumCryptoProvider.load();
    oldKey = await crypto.ed25519FromSeed(SecretBytes(Uint8List(32)..[0] = 1));
    newKey = await crypto.ed25519FromSeed(SecretBytes(Uint8List(32)..[0] = 2));
  });

  pb.FragmentTicket ticket() => pb.FragmentTicket(
    operation: pb.TicketOperation.TICKET_OPERATION_GET,
    nodeId: Uint8List(32)..[0] = 9,
    deviceSign: Uint8List(32)..[0] = 8,
    fragmentId: Uint8List(32)..[0] = 7,
    fragmentSize: 4096,
    expiresAtUnixMs: Int64(1792713600000),
    ticketId: Uint8List(16)..[0] = 6,
  );

  Future<pb.Signed> signed(Ed25519KeyPair key) =>
      SignedMessages.sign(crypto, key, 'ticket', ticket());

  test('при ротации талон нового ключа принимается списком из двух', () async {
    final both = CoordinatorKeySet([oldKey.publicKey, newKey.publicKey]);
    final onlyOld = CoordinatorKeySet([oldKey.publicKey]);
    for (final key in [oldKey, newKey]) {
      expect(
        await FragmentTickets.open(crypto, await signed(key), both),
        ticket(),
      );
    }
    await expectLater(
      FragmentTickets.open(crypto, await signed(newKey), onlyOld),
      throwsA(isA<IntegrityException>()),
      reason: 'клиент без обновления не знает нового ключа',
    );
  });

  test('подделка: чужая подпись, другой контекст, изменённое тело', () async {
    final trusted = CoordinatorKeySet([oldKey.publicKey]);
    final good = await signed(oldKey);
    final forged = pb.Signed(
      body: good.body,
      signer: oldKey.publicKey,
      signature: (await signed(newKey)).signature,
    );
    final otherContext = await SignedMessages.sign(
      crypto,
      oldKey,
      'device-cert',
      ticket(),
    );
    final tampered = good.deepCopy()..body = ([...good.body]..[3] ^= 1);
    for (final s in [forged, otherContext, tampered]) {
      await expectLater(
        FragmentTickets.open(crypto, s, trusted),
        throwsA(isA<IntegrityException>()),
      );
    }
  });

  test('неверный талон под верной подписью — ошибка формата', () async {
    final bad = await SignedMessages.sign(
      crypto,
      oldKey,
      'ticket',
      ticket()..ticketId = Uint8List(3),
    );
    await expectLater(
      FragmentTickets.open(crypto, bad, CoordinatorKeySet([oldKey.publicKey])),
      throwsA(isA<DataFormatException>()),
    );
  });

  test('идентификатор ключа и разбор списка', () {
    final id = CoordinatorKeySet.keyId(crypto, oldKey.publicKey);
    expect(id, hasLength(16));
    expect(id, bytesToHex(crypto.blake2b256(oldKey.publicKey).sublist(0, 8)));
    final set = CoordinatorKeySet.fromHex([bytesToHex(oldKey.publicKey)]);
    expect(set.trusts(oldKey.publicKey), isTrue);
    expect(set.trusts(newKey.publicKey), isFalse);
    expect(() => CoordinatorKeySet([Uint8List(31)]), throwsArgumentError);
    expect(CoordinatorKeySet.builtIn.isEmpty, builtInCoordinatorKeys.isEmpty);
  });
}
