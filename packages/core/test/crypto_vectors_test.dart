// Проверка векторов docs/spec/crypto.md второй, независимой реализацией
// на чистом Dart (пакеты cryptography и hashlib). Векторы получены
// эталоном на Python и libsodium (tool/crypto_vectors.py). Рабочая
// реализация CryptoProvider появится в этапе 1 (1.2.1) и будет проверяться
// этими же векторами.

import 'dart:convert';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:hashlib/hashlib.dart' as hashlib;
import 'package:test/test.dart';

import 'support/reference.dart';
import 'support/vectors.dart';

void main() {
  group('bip39-seed', () {
    for (final c in vectorCases(loadVectors('crypto/bip39-seed.json'))) {
      test(c['name'], () async {
        final input = c['input']! as Map<String, Object?>;
        final expected = c['expected']! as Map<String, Object?>;
        final seed = await _bip39Seed(
          input['mnemonic']! as String,
          input['passphrase']! as String,
        );
        expect(bytesToHex(seed), expected['seed']);
      });
    }
  });

  group('key-hierarchy', () {
    for (final c in vectorCases(loadVectors('crypto/key-hierarchy.json'))) {
      test(c['name'], () async {
        final input = c['input']! as Map<String, Object?>;
        final expected = c['expected']! as Map<String, Object?>;
        final seed = await _bip39Seed(input['mnemonic']! as String, '');
        expect(bytesToHex(seed), expected['seed']);

        final mk = await hkdf(
          seed,
          ascii.encode('fs/v1/master-salt'),
          ascii.encode('fs/v1/master'),
        );
        expect(bytesToHex(mk), expected['masterKey']);

        Future<Uint8List> derive(String label) =>
            hkdf(mk, Uint8List(0), ascii.encode(label));
        final data = await derive('fs/v1/data');
        expect(
          bytesToHex(await derive('fs/v1/manifest')),
          expected['manifestKey'],
        );
        expect(bytesToHex(data), expected['dataKey']);
        expect(
          bytesToHex(await derive('fs/v1/chunk-id')),
          expected['chunkIdKey'],
        );
        expect(
          bytesToHex(await derive('fs/v1/chunk-gear')),
          expected['gearKey'],
        );
        final signSeed = await derive('fs/v1/account-sign');
        expect(bytesToHex(signSeed), expected['accountSignSeed']);

        final segmentKey = await hkdf(data, Uint8List(0), [
          ...ascii.encode('fs/v1/segment'),
          ...hexToBytes(input['segmentId']! as String),
        ]);
        expect(bytesToHex(segmentKey), expected['segmentKey']);

        final keyPair = await DartEd25519().newKeyPairFromSeed(signSeed);
        final publicKey = await keyPair.extractPublicKey();
        expect(bytesToHex(publicKey.bytes), expected['accountPublicKey']);
      });
    }
  });

  group('blob', () {
    for (final c in vectorCases(loadVectors('crypto/blob.json'))) {
      final input = c['input']! as Map<String, Object?>;
      final expected = c['expected']! as Map<String, Object?>;
      final key = hexToBytes(input['key']! as String);

      if (expected.containsKey('error')) {
        test(c['name'], () async {
          final blob = hexToBytes(input['blob']! as String);
          expect(await _openBlob(key, blob), expected['error']);
        });
        continue;
      }

      test(c['name'], () async {
        final plaintext = input.containsKey('plaintextPattern')
            ? patternBytes(input['plaintextPattern']! as Map<String, Object?>)
            : hexToBytes(input['plaintext']! as String);
        final blob = await sealBlob(
          type: input['type']! as int,
          objectId: hexToBytes(input['objectId']! as String),
          nonce: hexToBytes(input['nonce']! as String),
          key: key,
          plaintext: plaintext,
        );
        expect(bytesToHex(blob), expected['blob']);
        expect(await _openBlob(key, blob), 'ok');
      });
    }
  });

  group('chunk-id', () {
    for (final c in vectorCases(loadVectors('crypto/chunk-id.json'))) {
      test(c['name'], () {
        final input = c['input']! as Map<String, Object?>;
        final expected = c['expected']! as Map<String, Object?>;
        final data = patternBytes(
          input['dataPattern']! as Map<String, Object?>,
        );
        final key = hexToBytes(input['chunkIdKey']! as String);
        final id = hashlib.blake2b256.mac.by(key).convert(data).bytes;
        expect(bytesToHex(id), expected['chunkId']);
      });
    }
  });

  group('key-bundle', () {
    for (final c in vectorCases(loadVectors('crypto/key-bundle.json'))) {
      test(c['name'], () async {
        final input = c['input']! as Map<String, Object?>;
        final expected = c['expected']! as Map<String, Object?>;
        // Нормализация NFKC проверяется по ожидаемому значению: в Dart нет
        // встроенной нормализации Unicode, её добавит этап 1 (1.2.5).
        final password = hexToBytes(expected['passwordNfkcUtf8']! as String);
        if (input['password'] == 'correct horse battery staple') {
          expect(password, utf8.encode(input['password']! as String));
        }
        final salt = hexToBytes(input['salt']! as String);
        final m = input['m']! as int;
        final t = input['t']! as int;
        final pk = hashlib.Argon2(
          salt: salt,
          hashLength: 32,
          iterations: t,
          parallelism: input['p']! as int,
          memorySizeKB: m,
        ).convert(password).bytes;
        expect(bytesToHex(pk), expected['pk']);

        final kek = await hkdf(pk, Uint8List(0), ascii.encode('fs/v1/kek'));
        final auth = await hkdf(pk, Uint8List(0), ascii.encode('fs/v1/auth'));
        expect(bytesToHex(kek), expected['kek']);
        expect(bytesToHex(auth), expected['auth']);

        final header = BytesBuilder()
          ..add(ascii.encode('FSKB'))
          ..add([1, 1, 0, 0])
          ..add(u32le(m))
          ..add(u32le(t))
          ..add(u32le(input['p']! as int))
          ..add(salt);
        final inner = await sealBlob(
          type: 4,
          objectId: hexToBytes(input['accountPublicKey']! as String),
          nonce: hexToBytes(input['nonce']! as String),
          key: kek,
          plaintext: hexToBytes(input['masterKey']! as String),
        );
        expect(
          bytesToHex([...header.toBytes(), ...inner]),
          expected['keyBundle'],
        );
      });
    }
  });
}

Future<Uint8List> _bip39Seed(String mnemonic, String passphrase) async {
  // Слова английского словаря и пустая passphrase — ASCII, для них NFKD
  // ничего не меняет.
  final key =
      await DartPbkdf2(
        macAlgorithm: Hmac.sha512(),
        iterations: 2048,
        bits: 512,
      ).deriveKey(
        secretKey: SecretKey(utf8.encode(mnemonic)),
        nonce: utf8.encode('mnemonic$passphrase'),
      );
  return Uint8List.fromList(await key.extractBytes());
}

/// Эталонный разбор блоба по crypto.md, раздел 5. Возвращает 'ok',
/// 'format' или 'integrity'.
Future<String> _openBlob(List<int> key, Uint8List blob) async {
  if (blob.length < 80) return 'format';
  if (ascii.decode(blob.sublist(0, 4), allowInvalid: true) != 'FSEB') {
    return 'format';
  }
  if (blob[4] != 1) return 'format';
  if (blob[5] < 1 || blob[5] > 4) return 'format';
  if (blob[6] != 0 || blob[7] != 0) return 'format';
  try {
    await const DartXchacha20.poly1305Aead().decrypt(
      SecretBox(
        blob.sublist(64, blob.length - 16),
        nonce: blob.sublist(40, 64),
        mac: Mac(blob.sublist(blob.length - 16)),
      ),
      secretKey: SecretKey(key),
      aad: blob.sublist(0, 40),
    );
    return 'ok';
  } on SecretBoxAuthenticationError {
    return 'integrity';
  }
}
