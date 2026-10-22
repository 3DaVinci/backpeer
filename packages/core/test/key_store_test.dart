import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:test/test.dart';
import 'package:test_vectors/test_vectors.dart';

const _fast = Argon2Params(memoryKiB: 1024, iterations: 1);

void main() {
  late CryptoProvider crypto;
  setUpAll(() async => crypto = await SodiumCryptoProvider.load());

  group('nfkc', () {
    for (final c in vectorCases(loadVectors('crypto/nfkc.json'))) {
      test(c['name'], () {
        final input = c['input']! as Map<String, Object?>;
        final expected = c['expected']! as Map<String, Object?>;
        expect(
          bytesToHex(normalizePassword(input['text']! as String)),
          expected['nfkcUtf8'],
        );
      });
    }
  });

  group('key-bundle', () {
    for (final c in vectorCases(loadVectors('crypto/key-bundle.json'))) {
      test(c['name'], () async {
        final input = c['input']! as Map<String, Object?>;
        final expected = c['expected']! as Map<String, Object?>;
        final password = input['password']! as String;
        expect(
          bytesToHex(normalizePassword(password)),
          expected['passwordNfkcUtf8'],
        );
        final keys = await AccountKeys.fromMasterKey(
          SecretBytes(hexToBytes(input['masterKey']! as String)),
          crypto,
        );
        expect(bytesToHex(keys.accountId), input['accountPublicKey']);
        final params = Argon2Params(
          memoryKiB: input['m']! as int,
          iterations: input['t']! as int,
          parallelism: input['p']! as int,
        );
        final bundle = await KeyBundle.create(
          crypto,
          keys: keys,
          password: password,
          params: params,
          salt: hexToBytes(input['salt']! as String),
          nonce: hexToBytes(input['nonce']! as String),
        );
        expect(bytesToHex(bundle.toBytes()), expected['keyBundle']);

        final parsed = KeyBundle.parse(
          hexToBytes(expected['keyBundle']! as String),
        );
        expect(parsed.params.memoryKiB, params.memoryKiB);
        expect(bytesToHex(parsed.accountId), input['accountPublicKey']);
        final unlocked = await parsed.unlock(crypto, password);
        expect(bytesToHex(unlocked.masterKey.bytes), input['masterKey']);
        await expectLater(
          parsed.unlock(crypto, '${password}x'),
          throwsA(isA<IntegrityException>()),
        );

        final derived = await PasswordKeys.derive(
          crypto,
          password: password,
          salt: parsed.salt,
          params: params,
        );
        expect(bytesToHex(derived.kek.bytes), expected['kek']);
        expect(bytesToHex(derived.auth.bytes), expected['auth']);
      });
    }
  });

  group('разбор KeyBundle отвергает', () {
    late Uint8List valid;
    setUpAll(() async {
      final keys = await AccountKeys.fromPhrase(
        RecoveryPhrase.fromEntropy(Uint8List(32)),
        crypto,
      );
      valid = (await KeyBundle.create(
        crypto,
        keys: keys,
        password: 'pw',
        params: _fast,
      )).toBytes();
    });

    Uint8List patched(void Function(ByteData view) patch) {
      final copy = Uint8List.fromList(valid);
      patch(ByteData.sublistView(copy));
      return copy;
    }

    final cases = <String, void Function(ByteData)>{
      'неверный magic': (v) => v.setUint8(0, 0x58),
      'неизвестная версия': (v) => v.setUint8(4, 2),
      'неизвестный KDF': (v) => v.setUint8(5, 2),
      'ненулевой резерв': (v) => v.setUint8(7, 1),
      'огромный m': (v) => v.setUint32(8, 0xFFFFFFFF, Endian.little),
      'нулевой t': (v) => v.setUint32(12, 0, Endian.little),
      'p = 2': (v) => v.setUint32(16, 2, Endian.little),
      'вложенный блоб другого типа': (v) => v.setUint8(36 + 5, 2),
    };
    for (final MapEntry(key: name, value: patch) in cases.entries) {
      test(name, () {
        expect(
          () => KeyBundle.parse(patched(patch)),
          throwsA(isA<DataFormatException>()),
        );
      });
    }

    test('неверная длина', () {
      expect(
        () => KeyBundle.parse(Uint8List.sublistView(valid, 1)),
        throwsA(isA<DataFormatException>()),
      );
      expect(
        () => KeyBundle.parse(Uint8List.fromList([...valid, 0])),
        throwsA(isA<DataFormatException>()),
      );
    });
  });

  group('DeviceKeyStore', () {
    late Directory dir;
    late AccountKeys keys;
    setUp(() async {
      dir = Directory.systemTemp.createTempSync('fs-keys-');
      keys = await AccountKeys.fromPhrase(
        RecoveryPhrase.generate(crypto),
        crypto,
      );
    });
    tearDown(() => dir.deleteSync(recursive: true));

    DeviceKeyStore open() => DeviceKeyStore(
      File('${dir.path}/keys/device.key'),
      crypto,
      params: _fast,
    );

    test('создание и открытие новым экземпляром', () async {
      await open().create(keys, 'пароль ﬁ');
      final again = await open().unlock('пароль fi'); // та же NFKC
      expect(again.masterKey.bytes, keys.masterKey.bytes);
      expect(dir.listSync(recursive: true).whereType<File>(), hasLength(1));
    });

    test('права файла 0600', () async {
      final store = open();
      await store.create(keys, 'pw');
      expect(store.file.statSync().mode & 0x1FF, 0x180);
    }, testOn: '!windows');

    test('неверный пароль — IntegrityException', () async {
      await open().create(keys, 'right');
      await expectLater(
        open().unlock('wrong'),
        throwsA(isA<IntegrityException>()),
      );
    });

    test('смена пароля', () async {
      final store = open();
      await store.create(keys, 'old');
      final before = KeyBundle.parse(store.file.readAsBytesSync());
      await store.changePassword('old', 'new');
      final after = KeyBundle.parse(store.file.readAsBytesSync());
      expect(after.salt, isNot(before.salt));
      expect((await store.unlock('new')).masterKey.bytes, keys.masterKey.bytes);
      await expectLater(
        store.unlock('old'),
        throwsA(isA<IntegrityException>()),
      );
      await expectLater(
        store.changePassword('old', 'x'),
        throwsA(isA<IntegrityException>()),
      );
    });

    test('повторное создание и отсутствующий файл', () async {
      final store = open();
      await expectLater(
        store.unlock('pw'),
        throwsA(
          isA<StorageException>().having(
            (e) => e.problem,
            'problem',
            StorageProblem.notFound,
          ),
        ),
      );
      await store.create(keys, 'pw');
      await expectLater(
        store.create(keys, 'pw'),
        throwsA(isA<StorageException>()),
      );
    });

    test('фраза по паролю, переживает смену пароля', () async {
      final phrase = RecoveryPhrase.generate(crypto);
      final phraseKeys = await AccountKeys.fromPhrase(phrase, crypto);
      final store = open();
      await store.create(phraseKeys, 'old', phrase: phrase);
      expect(store.hasPhrase, isTrue);
      expect((await store.unlockPhrase('old')).phrase, phrase.phrase);
      await expectLater(
        store.unlockPhrase('wrong'),
        throwsA(isA<IntegrityException>()),
      );
      await store.changePassword('old', 'new');
      expect((await store.unlockPhrase('new')).phrase, phrase.phrase);
      if (!Platform.isWindows) {
        expect(store.phraseFile.statSync().mode & 0x1FF, 0x180);
      }
    });

    test('чужая фраза рядом с KeyBundle распознаётся', () async {
      final store = open();
      await store.create(keys, 'pw', phrase: RecoveryPhrase.generate(crypto));
      await expectLater(
        store.unlockPhrase('pw'),
        throwsA(isA<IntegrityException>()),
      );
    });

    test('повреждённый файл — ошибка формата', () async {
      final store = open();
      await store.create(keys, 'pw');
      store.file.writeAsBytesSync([1, 2, 3]);
      await expectLater(
        store.unlock('pw'),
        throwsA(isA<DataFormatException>()),
      );
    });
  });
}
