// Обе реализации CryptoProvider на векторах RFC (crypto/primitives.json) и
// на векторах спецификации crypto.md (bip39-seed, key-hierarchy, chunk-id,
// blob, key-bundle).

import 'dart:convert';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:test/test.dart';
import 'package:test_vectors/test_vectors.dart';

void main() {
  final providers = <String, Future<CryptoProvider> Function()>{
    'libsodium': SodiumCryptoProvider.load,
    'dart': () async => DartCryptoProvider(),
  };
  for (final MapEntry(key: name, value: create) in providers.entries) {
    group(name, () {
      late CryptoProvider provider;
      setUpAll(() async => provider = await create());
      CryptoProvider crypto() => provider;
      _primitives(crypto);
      _specVectors(crypto);
      _contract(crypto);
    });
  }

  test('libsodium и dart дают одинаковые байты на случайных входах', () async {
    final sodium = await SodiumCryptoProvider.load();
    final dart = DartCryptoProvider();
    for (var i = 0; i < 20; i++) {
      final key = SecretBytes(sodium.randomBytes(32));
      final nonce = sodium.randomBytes(24);
      final data = sodium.randomBytes(i * 977);
      final aad = sodium.randomBytes(i);
      final a = sodium.aeadEncrypt(
        key: key,
        nonce: nonce,
        plaintext: data,
        aad: aad,
      );
      expect(
        dart.aeadEncrypt(key: key, nonce: nonce, plaintext: data, aad: aad),
        a,
      );
      expect(
        dart.aeadDecrypt(key: key, nonce: nonce, ciphertext: a, aad: aad),
        data,
      );
      expect(
        dart.blake2b256(data, key: key),
        sodium.blake2b256(data, key: key),
      );
      final pair = await sodium.ed25519FromSeed(key);
      final signature = await sodium.ed25519Sign(pair, data);
      expect(await dart.ed25519Sign(pair, data), signature);
      // Подготовленный ключ подписывает так же.
      for (final provider in [dart, sodium]) {
        final signer = await provider.ed25519Signer(pair);
        expect(signer.publicKey, pair.publicKey);
        expect(await signer.sign(data), signature);
        signer.dispose();
      }
      expect(
        pair.seed.isDisposed,
        isFalse,
        reason: 'пара остаётся у владельца',
      );
    }
  });
}

Map<String, Object?> _map(Object? value) => value! as Map<String, Object?>;
Uint8List _hex(Object? value) => hexToBytes(value! as String);

void _primitives(CryptoProvider Function() provider) {
  group('primitives', () {
    for (final c in vectorCases(loadVectors('crypto/primitives.json'))) {
      final input = _map(c['input']);
      final expected = _map(c['expected']);
      test(c['name'], () async {
        switch (input['primitive']) {
          case 'xchacha20poly1305':
            final key = SecretBytes(_hex(input['key']));
            final nonce = _hex(input['nonce']);
            final aad = _hex(input['aad']);
            if (expected['error'] == 'integrity') {
              expect(
                provider().aeadDecrypt(
                  key: key,
                  nonce: nonce,
                  ciphertext: _hex(input['ciphertext']),
                  aad: aad,
                ),
                isNull,
              );
              return;
            }
            final plaintext = _hex(input['plaintext']);
            final ciphertext = provider().aeadEncrypt(
              key: key,
              nonce: nonce,
              plaintext: plaintext,
              aad: aad,
            );
            expect(bytesToHex(ciphertext), expected['ciphertext']);
            expect(
              provider().aeadDecrypt(
                key: key,
                nonce: nonce,
                ciphertext: ciphertext,
                aad: aad,
              ),
              plaintext,
            );
          case 'blake2b256':
            final key = input['key'];
            final digest = provider().blake2b256(
              _hex(input['data']),
              key: key == null ? null : SecretBytes(_hex(key)),
            );
            expect(bytesToHex(digest), expected['digest']);
          case 'hkdf-sha256':
            final okm = provider().hkdfSha256(
              ikm: SecretBytes(_hex(input['ikm'])),
              salt: _hex(input['salt']),
              info: _hex(input['info']),
              length: input['length']! as int,
            );
            expect(bytesToHex(okm.bytes), expected['okm']);
          case 'ed25519':
            final pair = await provider().ed25519FromSeed(
              SecretBytes(_hex(input['seed'])),
            );
            expect(bytesToHex(pair.publicKey), expected['publicKey']);
            final message = _hex(input['message']);
            final signature = await provider().ed25519Sign(pair, message);
            expect(bytesToHex(signature), expected['signature']);
            expect(
              await provider().ed25519Verify(
                publicKey: pair.publicKey,
                message: message,
                signature: signature,
              ),
              isTrue,
            );
            final forged = Uint8List.fromList([...message, 0]);
            expect(
              await provider().ed25519Verify(
                publicKey: pair.publicKey,
                message: forged,
                signature: signature,
              ),
              isFalse,
            );
          case 'x25519':
            Future<SecretBytes> run() => provider().x25519(
              secretKey: SecretBytes(_hex(input['secretKey'])),
              publicKey: _hex(input['publicKey']),
            );
            if (expected['error'] == 'format') {
              await expectLater(run, throwsA(isA<DataFormatException>()));
              return;
            }
            expect(bytesToHex((await run()).bytes), expected['sharedSecret']);
          case 'x25519-exchange':
            final alice = await provider().x25519FromSecret(
              SecretBytes(_hex(input['aliceSecretKey'])),
            );
            final bob = await provider().x25519FromSecret(
              SecretBytes(_hex(input['bobSecretKey'])),
            );
            expect(bytesToHex(alice.publicKey), expected['alicePublicKey']);
            expect(bytesToHex(bob.publicKey), expected['bobPublicKey']);
            final k1 = await provider().x25519(
              secretKey: alice.secretKey,
              publicKey: bob.publicKey,
            );
            final k2 = await provider().x25519(
              secretKey: bob.secretKey,
              publicKey: alice.publicKey,
            );
            expect(bytesToHex(k1.bytes), expected['sharedSecret']);
            expect(k2.bytes, k1.bytes);
          default:
            fail('Неизвестный примитив ${input['primitive']}');
        }
      });
    }
  });
}

void _specVectors(CryptoProvider Function() provider) {
  Future<SecretBytes> bip39Seed(String mnemonic, String passphrase) =>
      provider().pbkdf2HmacSha512(
        password: utf8.encode(mnemonic),
        salt: utf8.encode('mnemonic$passphrase'),
        iterations: 2048,
        length: 64,
      );
  SecretBytes derive(SecretBytes ikm, String salt, List<int> info) =>
      provider().hkdfSha256(
        ikm: ikm,
        salt: ascii.encode(salt),
        info: Uint8List.fromList(info),
      );

  group('bip39-seed', () {
    for (final c in vectorCases(loadVectors('crypto/bip39-seed.json'))) {
      test(c['name'], () async {
        final input = _map(c['input']);
        final seed = await bip39Seed(
          input['mnemonic']! as String,
          input['passphrase']! as String,
        );
        expect(bytesToHex(seed.bytes), _map(c['expected'])['seed']);
      });
    }
  });

  group('key-hierarchy', () {
    for (final c in vectorCases(loadVectors('crypto/key-hierarchy.json'))) {
      test(c['name'], () async {
        final input = _map(c['input']);
        final expected = _map(c['expected']);
        final seed = await bip39Seed(input['mnemonic']! as String, '');
        expect(bytesToHex(seed.bytes), expected['seed']);
        final mk = derive(
          seed,
          'fs/v1/master-salt',
          ascii.encode('fs/v1/master'),
        );
        expect(bytesToHex(mk.bytes), expected['masterKey']);
        String sub(String label) =>
            bytesToHex(derive(mk, '', ascii.encode(label)).bytes);
        expect(sub('fs/v1/manifest'), expected['manifestKey']);
        expect(sub('fs/v1/data'), expected['dataKey']);
        expect(sub('fs/v1/chunk-id'), expected['chunkIdKey']);
        expect(sub('fs/v1/chunk-gear'), expected['gearKey']);
        expect(sub('fs/v1/account-sign'), expected['accountSignSeed']);
        final data = derive(mk, '', ascii.encode('fs/v1/data'));
        final segmentKey = derive(data, '', [
          ...ascii.encode('fs/v1/segment'),
          ..._hex(input['segmentId']),
        ]);
        expect(bytesToHex(segmentKey.bytes), expected['segmentKey']);
        final account = await provider().ed25519FromSeed(
          derive(mk, '', ascii.encode('fs/v1/account-sign')),
        );
        expect(bytesToHex(account.publicKey), expected['accountPublicKey']);
      });
    }
  });

  group('chunk-id', () {
    for (final c in vectorCases(loadVectors('crypto/chunk-id.json'))) {
      test(c['name'], () {
        final input = _map(c['input']);
        final id = provider().blake2b256(
          patternBytes(_map(input['dataPattern'])),
          key: SecretBytes(_hex(input['chunkIdKey'])),
        );
        expect(bytesToHex(id), _map(c['expected'])['chunkId']);
      });
    }
  });

  // Только шифрование и расшифровка тела; разбор заголовка — задача 1.2.4.
  group('blob (AEAD)', () {
    for (final c in vectorCases(loadVectors('crypto/blob.json'))) {
      final expected = _map(c['expected']);
      if (expected.containsKey('error')) continue;
      test(c['name'], () {
        final input = _map(c['input']);
        final blob = _hex(expected['blob']);
        final header = Uint8List.sublistView(blob, 0, 40);
        final key = SecretBytes(_hex(input['key']));
        final nonce = _hex(input['nonce']);
        final plaintext = input.containsKey('plaintextPattern')
            ? patternBytes(_map(input['plaintextPattern']))
            : _hex(input['plaintext']);
        final body = provider().aeadEncrypt(
          key: key,
          nonce: nonce,
          plaintext: plaintext,
          aad: header,
        );
        expect(bytesToHex(body), bytesToHex(blob.sublist(64)));
        expect(
          provider().aeadDecrypt(
            key: key,
            nonce: nonce,
            ciphertext: body,
            aad: header,
          ),
          plaintext,
        );
      });
    }
  });

  group('key-bundle (Argon2id)', () {
    for (final c in vectorCases(loadVectors('crypto/key-bundle.json'))) {
      test(c['name'], () async {
        final input = _map(c['input']);
        final expected = _map(c['expected']);
        final pk = await provider().argon2id(
          password: _hex(expected['passwordNfkcUtf8']),
          salt: _hex(input['salt']),
          params: Argon2Params(
            memoryKiB: input['m']! as int,
            iterations: input['t']! as int,
            parallelism: input['p']! as int,
          ),
        );
        expect(bytesToHex(pk.bytes), expected['pk']);
        String sub(String label) =>
            bytesToHex(derive(pk, '', ascii.encode(label)).bytes);
        expect(sub('fs/v1/kek'), expected['kek']);
        expect(sub('fs/v1/auth'), expected['auth']);
      });
    }
  });
}

void _contract(CryptoProvider Function() provider) {
  group('контракт', () {
    final key = SecretBytes(Uint8List(32));
    final nonce = Uint8List(24);

    test('неверные длины ключа и nonce — ArgumentError', () {
      expect(
        () => provider().aeadEncrypt(
          key: SecretBytes(Uint8List(16)),
          nonce: nonce,
          plaintext: Uint8List(0),
          aad: Uint8List(0),
        ),
        throwsArgumentError,
      );
      expect(
        () => provider().aeadEncrypt(
          key: key,
          nonce: Uint8List(12),
          plaintext: Uint8List(0),
          aad: Uint8List(0),
        ),
        throwsArgumentError,
      );
      expect(
        () =>
            provider().blake2b256(Uint8List(0), key: SecretBytes(Uint8List(8))),
        throwsArgumentError,
      );
    });

    test('шифротекст короче тега — null', () {
      expect(
        provider().aeadDecrypt(
          key: key,
          nonce: nonce,
          ciphertext: Uint8List(15),
          aad: Uint8List(0),
        ),
        isNull,
      );
    });

    test('подпись неверной длины не проходит проверку', () async {
      final pair = await provider().ed25519FromSeed(key);
      expect(
        await provider().ed25519Verify(
          publicKey: pair.publicKey,
          message: Uint8List(0),
          signature: Uint8List(63),
        ),
        isFalse,
      );
    });

    test('randomBytes', () {
      expect(provider().randomBytes(0), isEmpty);
      final a = provider().randomBytes(32);
      expect(a.length, 32);
      expect(provider().randomBytes(32), isNot(a));
    });
  });
}
