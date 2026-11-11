import 'dart:io';

import 'package:agent/agent.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  late CryptoProvider crypto;
  late Directory dir;
  late AccountKeys keys;
  late DeviceKeys device;

  setUpAll(() async => crypto = await SodiumCryptoProvider.load());
  setUp(() async {
    dir = Directory.systemTemp.createTempSync('fs-agent-keys-');
    keys = await AccountKeys.fromMasterKey(
      SecretBytes(crypto.randomBytes(32)),
      crypto,
    );
    device = await DeviceKeys.generate(crypto);
  });
  tearDown(() {
    keys.dispose();
    device.dispose();
    dir.deleteSync(recursive: true);
  });

  AgentKeyVault vault(SecretStore store, [String entry = '/home/a']) =>
      AgentKeyVault(
        file: File('${dir.path}/keys.agent'),
        crypto: crypto,
        secrets: store,
        entry: entry,
      );

  test('сохранить и открыть без пароля: те же ключи', () async {
    final store = MemorySecretStore();
    final v = vault(store);
    expect(await v.open(), isNull);
    await v.remember(keys, device);
    expect(store.secrets.keys, ['/home/a']);
    if (!Platform.isWindows) {
      expect(v.file.statSync().mode & 511, 384); // 0600
    }
    final material = (await v.open())!;
    expect(material.accountId, keys.accountId);
    final (k, d) = await material.open(crypto);
    expect(k.masterKey.bytes, keys.masterKey.bytes);
    expect(k.accountId, keys.accountId);
    expect(d!.sign.publicKey, device.sign.publicKey);
    expect(d.dh.publicKey, device.dh.publicKey);
    k.dispose();
    d.dispose();
    material.dispose();
  });

  test('без ключей устройства', () async {
    final v = vault(MemorySecretStore());
    await v.remember(keys, null);
    final material = (await v.open())!;
    expect(material.hasDevice, isFalse);
    material.dispose();
  });

  test('запись в хранилище заменена или удалена — null; файл без записи '
      'бесполезен', () async {
    final store = MemorySecretStore();
    final v = vault(store);
    await v.remember(keys, device);
    final old = store.secrets['/home/a']!;
    // Другой каталог программы — своя запись.
    expect(await vault(store, '/home/b').open(), isNull);
    store.secrets['/home/a'] = 'не base64!';
    expect(await v.open(), isNull);
    // Ключ правильной длины, но другой.
    store.secrets['/home/a'] = old.replaceRange(0, 4, 'AAAA');
    expect(await v.open(), isNull);
    store.secrets.remove('/home/a');
    expect(await v.open(), isNull);
  });

  test('хранилище закрыто или недоступно — SecretStoreException', () async {
    final store = MemorySecretStore();
    final v = vault(store);
    await v.remember(keys, device);
    store.locked = true;
    await expectLater(v.open(), throwsA(isA<SecretStoreException>()));
    await expectLater(
      vault(const UnavailableSecretStore('нет')).remember(keys, device),
      throwsA(isA<SecretStoreException>()),
    );
  });

  test('забыть: запись и файл удалены', () async {
    final store = MemorySecretStore();
    final v = vault(store);
    await v.remember(keys, device);
    await v.forget();
    expect(store.secrets, isEmpty);
    expect(v.exists, isFalse);
    expect(await v.open(), isNull);
  });

  test(
    'Secret Service по-настоящему (FS_TEST_SECRET_SERVICE=1)',
    () async {
      final store = LibsecretStore.open();
      expect(store, isNotNull, reason: 'нет libsecret');
      final entry = '/tmp/fs-agent-test-$pid';
      final v = vault(store!, entry);
      try {
        await v.remember(keys, device);
        final material = (await v.open())!;
        expect(material.accountId, keys.accountId);
        material.dispose();
        expect(await store.read(entry), isNotNull);
      } finally {
        await v.forget();
      }
      expect(await store.read(entry), isNull);
    },
    skip: Platform.environment['FS_TEST_SECRET_SERVICE'] == '1'
        ? false
        : 'FS_TEST_SECRET_SERVICE не задан (нужен сеанс с Secret Service)',
  );

  test(
    'Keychain по-настоящему (FS_TEST_KEYCHAIN=1)',
    () async {
      final store = KeychainStore.open();
      expect(store, isNotNull, reason: 'нет Security.framework');
      final entry = '/tmp/fs-agent-test-$pid';
      final v = vault(store!, entry);
      try {
        await v.remember(keys, device);
        final material = (await v.open())!;
        expect(material.accountId, keys.accountId);
        material.dispose();
        expect(await store.read(entry), isNotNull);
        // Повторная запись обновляет ту же запись, а не заводит вторую.
        await v.remember(keys, null);
        expect((await v.open())!.hasDevice, isFalse);
      } finally {
        await v.forget();
      }
      expect(await store.read(entry), isNull);
    },
    skip: !Platform.isMacOS
        ? 'нужен macOS'
        : Platform.environment['FS_TEST_KEYCHAIN'] == '1'
        ? false
        : 'FS_TEST_KEYCHAIN не задан (нужен сеанс с Keychain)',
  );

  test(
    'диспетчер учётных данных по-настоящему '
    '(FS_TEST_CREDENTIAL_MANAGER=1)',
    () async {
      final store = CredentialStore.open();
      expect(store, isNotNull, reason: 'нет advapi32');
      const entry = r'C:\fs-agent-test';
      final v = vault(store!, entry);
      try {
        await v.remember(keys, device);
        final material = (await v.open())!;
        expect(material.accountId, keys.accountId);
        material.dispose();
        expect(await store.read(entry), isNotNull);
        // Повторная запись обновляет ту же учётную запись.
        await v.remember(keys, null);
        expect((await v.open())!.hasDevice, isFalse);
      } finally {
        await v.forget();
      }
      expect(await store.read(entry), isNull);
    },
    skip: !Platform.isWindows
        ? 'нужен Windows'
        : Platform.environment['FS_TEST_CREDENTIAL_MANAGER'] == '1'
        ? false
        : 'FS_TEST_CREDENTIAL_MANAGER не задан (нужен вход пользователя)',
  );
}
