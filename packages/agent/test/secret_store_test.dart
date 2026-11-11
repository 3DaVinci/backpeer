import 'dart:io';

import 'package:agent/agent.dart';
import 'package:test/test.dart';

void main() {
  test('хранилище для этой ОС: имя системы, без падения', () {
    final store = SecretStore.forPlatform();
    if (Platform.isLinux) {
      // Без libsecret (сервер без рабочего стола) — запасной вариант.
      expect(store.name, anyOf('secret-service', 'none'));
    } else if (Platform.isMacOS) {
      expect(store.name, 'keychain');
    } else if (Platform.isWindows) {
      expect(store.name, 'credential-manager');
    } else {
      expect(store.name, 'none');
    }
  });

  test('чужое хранилище на этой ОС не загружается, а не падает', () {
    // Библиотеки другой ОС не найдены: `open()` возвращает null, а не
    // бросает — агент тогда работает только после ввода пароля.
    expect(KeychainStore.open(), Platform.isMacOS ? isNotNull : isNull);
    expect(CredentialStore.open(), Platform.isWindows ? isNotNull : isNull);
  });

  test('имя записи в диспетчере учётных данных', () {
    expect(
      CredentialStore.target(r'C:\Users\a\backpeer'),
      r'Backpeer: C:\Users\a\backpeer',
    );
  });
}
