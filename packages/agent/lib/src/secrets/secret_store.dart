import 'dart:io';

import 'package:agent/src/secrets/libsecret_store.dart';

/// Хранилище секретов ОС (ADR-010): на Linux — Secret Service (GNOME
/// Keyring, KWallet) через libsecret; Keychain на macOS и Credential
/// Manager на Windows — задача 5.1.5.
///
/// Секрет — короткая строка (ключ агента в base64), запись находится по
/// [key]: у каждого каталога программы своя.
abstract interface class SecretStore {
  /// Хранилище этой ОС; недоступно — [UnavailableSecretStore].
  static SecretStore forPlatform() {
    if (Platform.isLinux) {
      return LibsecretStore.open() ??
          const UnavailableSecretStore('libsecret не найдена');
    }
    return UnavailableSecretStore(
      'хранилище ключей ${Platform.operatingSystem} пока не поддержано',
    );
  }

  /// Имя для состояния и журнала: `secret-service`, `memory`, `none`.
  String get name;

  /// Секрет по [key]; записи нет — `null`. Хранилище недоступно или
  /// закрыто — [SecretStoreException].
  Future<String?> read(String key);

  /// Сохраняет [secret] под [key] с подписью [label] для пользователя
  /// (её видно в «Паролях и ключах»).
  Future<void> write(String key, String label, String secret);

  /// Удаляет запись; записи нет — не ошибка.
  Future<void> delete(String key);
}

/// Хранилище недоступно, закрыто или отказало.
final class SecretStoreException implements Exception {
  const new(this.message);

  final String message;

  @override
  String toString() => 'SecretStoreException: $message';
}

/// Хранилища нет: агент работает только после ввода пароля.
final class UnavailableSecretStore implements SecretStore {
  const new(this.reason);

  final String reason;

  @override
  String get name => 'none';

  @override
  Future<String?> read(String key) async => throw SecretStoreException(reason);

  @override
  Future<void> write(String key, String label, String secret) async =>
      throw SecretStoreException(reason);

  @override
  Future<void> delete(String key) async {}
}

/// В памяти — для тестов.
final class MemorySecretStore implements SecretStore {
  final Map<String, String> secrets = {};

  /// Имитировать закрытое хранилище.
  bool locked = false;

  @override
  String get name => 'memory';

  @override
  Future<String?> read(String key) async {
    if (locked) throw const SecretStoreException('хранилище закрыто');
    return secrets[key];
  }

  @override
  Future<void> write(String key, String label, String secret) async {
    if (locked) throw const SecretStoreException('хранилище закрыто');
    secrets[key] = secret;
  }

  @override
  Future<void> delete(String key) async => secrets.remove(key);
}
