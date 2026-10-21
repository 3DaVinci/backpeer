import 'dart:io';

import 'package:core/src/crypto/account_keys.dart';
import 'package:core/src/crypto/crypto_provider.dart';
import 'package:core/src/crypto/key_bundle.dart';
import 'package:core/src/errors.dart';
import 'package:core/src/storage/private_file.dart';

/// Локальное хранилище ключей устройства: KeyBundle с копией мастер-ключа
/// под паролем в одном файле (crypto.md, раздел 4). Файл доступен только
/// владельцу и пишется атомарно. Копия на координаторе — этап 2.
final class DeviceKeyStore {
  new(this.file, this._crypto, {this.params = const Argon2Params()});

  final File file;
  final CryptoProvider _crypto;

  /// Параметры Argon2id для новых KeyBundle (создание, смена пароля).
  final Argon2Params params;

  bool get exists => file.existsSync();

  /// Сохраняет ключи под паролем. Существующий файл не перезаписывает.
  Future<void> create(AccountKeys keys, String password) async {
    if (exists) {
      throw StorageException(
        location: file.path,
        problem: StorageProblem.io,
        operation: 'create',
        cause: 'хранилище ключей уже существует',
      );
    }
    await _write(keys, password);
  }

  /// Ключи учётной записи по паролю. Неверный пароль —
  /// [IntegrityException], отсутствующий файл — [StorageException].
  Future<AccountKeys> unlock(String password) async =>
      await _read().unlock(_crypto, password);

  /// Перешифровывает копию мастер-ключа новым паролем, с новой солью и
  /// текущими [params]. Ключи учётной записи не меняются.
  Future<void> changePassword(String oldPassword, String newPassword) async {
    final keys = await unlock(oldPassword);
    try {
      await _write(keys, newPassword);
    } finally {
      keys.dispose();
    }
  }

  KeyBundle _read() {
    try {
      return KeyBundle.parse(file.readAsBytesSync());
    } on PathNotFoundException catch (e) {
      throw StorageException(
        location: file.path,
        problem: StorageProblem.notFound,
        operation: 'read',
        cause: e.osError?.message,
      );
    } on FileSystemException catch (e) {
      throw StorageException(
        location: file.path,
        problem: StorageProblem.io,
        operation: 'read',
        cause: e.osError?.message ?? e.message,
      );
    }
  }

  Future<void> _write(AccountKeys keys, String password) async {
    final bundle = await KeyBundle.create(
      _crypto,
      keys: keys,
      password: password,
      params: params,
    );
    try {
      writePrivateFileAtomic(file, bundle.toBytes());
    } on FileSystemException catch (e) {
      throw StorageException(
        location: file.path,
        problem: StorageProblem.io,
        operation: 'write',
        cause: e.osError?.message ?? e.message,
      );
    }
  }
}
