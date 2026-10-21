import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:test/test.dart';
import 'package:test_vectors/test_vectors.dart';

void main() {
  late CryptoProvider crypto;
  setUpAll(() async => crypto = await SodiumCryptoProvider.load());

  group('key-hierarchy', () {
    for (final c in vectorCases(loadVectors('crypto/key-hierarchy.json'))) {
      test(c['name'], () async {
        final input = c['input']! as Map<String, Object?>;
        final expected = c['expected']! as Map<String, Object?>;
        final phrase = RecoveryPhrase.parse(input['mnemonic']! as String);
        expect(bytesToHex(phrase.entropy.bytes), input['entropy']);
        final keys = await AccountKeys.fromPhrase(phrase, crypto);
        String hex(SecretBytes key) => bytesToHex(key.bytes);
        expect(hex(keys.masterKey), expected['masterKey']);
        expect(hex(keys.manifestKey), expected['manifestKey']);
        expect(hex(keys.dataKey), expected['dataKey']);
        expect(hex(keys.chunkIdKey), expected['chunkIdKey']);
        expect(hex(keys.gearKey), expected['gearKey']);
        expect(hex(keys.accountSign.seed), expected['accountSignSeed']);
        expect(bytesToHex(keys.accountId), expected['accountPublicKey']);
        final segmentId = hexToBytes(input['segmentId']! as String);
        expect(hex(keys.segmentKey(segmentId)), expected['segmentKey']);
      });
    }
  });

  test('fromMasterKey даёт те же ключи, что fromPhrase', () async {
    final phrase = RecoveryPhrase.generate(crypto);
    final a = await AccountKeys.fromPhrase(phrase, crypto);
    final b = await AccountKeys.fromMasterKey(
      SecretBytes(a.masterKey.bytes),
      crypto,
    );
    expect(b.chunkIdKey.bytes, a.chunkIdKey.bytes);
    expect(b.accountId, a.accountId);
  });

  test('ключи не выводятся в toString, dispose затирает', () async {
    final keys = await AccountKeys.fromPhrase(
      RecoveryPhrase.fromEntropy(Uint8List(32)),
      crypto,
    );
    final hex = bytesToHex(keys.masterKey.bytes);
    expect('$keys', isNot(contains(hex)));
    expect('${keys.masterKey}', isNot(contains(hex)));
    keys.dispose();
    expect(keys.masterKey.isDisposed, isTrue);
    expect(keys.accountSign.seed.isDisposed, isTrue);
    expect(() => keys.gearKey.bytes, throwsStateError);
  });

  test('segmentKey проверяет длину идентификатора', () async {
    final keys = await AccountKeys.fromPhrase(
      RecoveryPhrase.fromEntropy(Uint8List(32)),
      crypto,
    );
    expect(() => keys.segmentKey(Uint8List(16)), throwsArgumentError);
  });
}
