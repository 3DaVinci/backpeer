import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:core/src/crypto/bip39_english.dart';
import 'package:core/src/crypto/recovery_phrase.dart';
import 'package:hashlib/hashlib.dart' as hashlib;
import 'package:test/test.dart';
import 'package:test_vectors/test_vectors.dart';

void main() {
  late CryptoProvider crypto;
  setUpAll(() async => crypto = await SodiumCryptoProvider.load());

  test('словарь совпадает с официальным english.txt', () {
    final file = utf8.encode('${bip39English.join('\n')}\n');
    expect(
      hashlib.sha256.convert(file).hex(),
      '2f5eed53a4727b4bf8880d8f3f199efc90e58503646d9ff8eff3a2ed3b24dbda',
    );
  });

  group('bip39-mnemonic', () {
    for (final c in vectorCases(loadVectors('crypto/bip39-mnemonic.json'))) {
      final input = c['input']! as Map<String, Object?>;
      final expected = c['expected']! as Map<String, Object?>;
      test(c['name'], () async {
        if (input.containsKey('entropy')) {
          final entropy = hexToBytes(input['entropy']! as String);
          final mnemonic = entropyToMnemonic(entropy);
          expect(mnemonic.join(' '), expected['mnemonic']);
          expect(bytesToHex(mnemonicToEntropy(mnemonic)), input['entropy']);
          final seed = await bip39Seed(
            crypto,
            mnemonic.join(' '),
            passphrase: 'TREZOR',
          );
          expect(bytesToHex(seed.bytes), expected['seedTrezor']);
          return;
        }
        final text = input['phrase']! as String;
        switch (expected['error']) {
          case 'format':
            expect(
              () => RecoveryPhrase.parse(text),
              throwsA(isA<DataFormatException>()),
            );
          case 'integrity':
            expect(
              () => RecoveryPhrase.parse(text),
              throwsA(
                isA<IntegrityException>().having(
                  (e) => e.check,
                  'check',
                  IntegrityCheck.checksum,
                ),
              ),
            );
          default:
            final phrase = RecoveryPhrase.parse(text);
            expect(bytesToHex(phrase.entropy.bytes), expected['entropy']);
            expect(
              RecoveryPhrase.parse(phrase.phrase).entropy.bytes,
              phrase.entropy.bytes,
            );
        }
      });
    }
  });

  group('bip39-seed (passphrase TREZOR)', () {
    for (final c in vectorCases(loadVectors('crypto/bip39-seed.json'))) {
      test(c['name'], () async {
        final input = c['input']! as Map<String, Object?>;
        final phrase = RecoveryPhrase.parse(input['mnemonic']! as String);
        expect(bytesToHex(phrase.entropy.bytes), input['entropy']);
        final seed = await bip39Seed(
          crypto,
          phrase.phrase,
          passphrase: input['passphrase']! as String,
        );
        expect(
          bytesToHex(seed.bytes),
          (c['expected']! as Map<String, Object?>)['seed'],
        );
      });
    }
  });

  test('seed фразы — по key-hierarchy.json (пустая passphrase)', () async {
    for (final c in vectorCases(loadVectors('crypto/key-hierarchy.json'))) {
      final input = c['input']! as Map<String, Object?>;
      final phrase = RecoveryPhrase.parse(input['mnemonic']! as String);
      final seed = await phrase.seed(crypto);
      expect(
        bytesToHex(seed.bytes),
        (c['expected']! as Map<String, Object?>)['seed'],
      );
    }
  });

  test('generate: 24 слова, разбираются обратно', () {
    final phrase = RecoveryPhrase.generate(crypto);
    expect(phrase.words, hasLength(24));
    final again = RecoveryPhrase.parse(phrase.phrase);
    expect(again.entropy.bytes, phrase.entropy.bytes);
    expect(RecoveryPhrase.generate(crypto).phrase, isNot(phrase.phrase));
  });

  test('toString и ошибки не раскрывают слова', () {
    final phrase = RecoveryPhrase.fromEntropy(Uint8List(32));
    expect(phrase.toString(), isNot(contains('abandon')));
    try {
      RecoveryPhrase.parse('${'abandon ' * 23}secretwordx');
      fail('ожидалась ошибка');
    } on DataFormatException catch (e) {
      expect(e.message, isNot(contains('secretwordx')));
      expect(e.message, contains('№24'));
    }
  });

  test('dispose затирает энтропию', () {
    final phrase = RecoveryPhrase.fromEntropy(
      Uint8List.fromList(List.filled(32, 7)),
    );
    final entropy = phrase.entropy;
    phrase.dispose();
    expect(entropy.isDisposed, isTrue);
    expect(() => phrase.words, throwsStateError);
  });

  test('fromEntropy проверяет длину', () {
    expect(
      () => RecoveryPhrase.fromEntropy(Uint8List(16)),
      throwsArgumentError,
    );
  });

  test('копия словаря в tool/ совпадает с кодом', () {
    var dir = Directory.current.absolute;
    while (!File('${dir.path}/tool/bip39-english.txt').existsSync()) {
      dir = dir.parent;
    }
    final lines = File('${dir.path}/tool/bip39-english.txt').readAsLinesSync();
    expect(lines, bip39English);
  });
}
