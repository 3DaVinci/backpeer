import 'dart:io';
import 'dart:typed_data';

import 'package:core/src/crypto/account_keys.dart';
import 'package:core/src/crypto/crypto_provider.dart';
import 'package:core/src/crypto/encrypted_blob.dart';
import 'package:core/src/crypto/key_bundle.dart';
import 'package:core/src/crypto/recovery_phrase.dart';
import 'package:core/src/errors.dart';
import 'package:core/src/storage/private_file.dart';
import 'package:core/src/util/bytes.dart';

/// Локальное хранилище ключей устройства (crypto.md, разделы 4, 4.1, 4.2):
/// KeyBundle с копией мастер-ключа под паролем в [file] и, если задана,
/// локальная копия фразы восстановления в `<file>.phrase` под тем же
/// `KEK`. Файлы доступны только владельцу и пишутся атомарно. Копия
/// KeyBundle на координаторе — этап 2.
final class DeviceKeyStore {
  new(this.file, this._crypto, {this.params = const Argon2Params()});

  final File file;
  final CryptoProvider _crypto;

  /// Параметры Argon2id для новых KeyBundle (создание, смена пароля).
  final Argon2Params params;

  File get phraseFile => File('${file.path}.phrase');

  bool get exists => file.existsSync();

  /// Сохраняет ключи под паролем; с [phrase] — и копию фразы для
  /// `show-phrase`. Существующее хранилище не перезаписывает.
  Future<void> create(
    AccountKeys keys,
    String password, {
    RecoveryPhrase? phrase,
  }) async {
    if (exists) {
      throw StorageException(
        location: file.path,
        problem: StorageProblem.io,
        operation: 'create',
        cause: 'хранилище ключей уже существует',
      );
    }
    await _write(keys, password, phrase);
  }

  /// Ключи учётной записи по паролю. Неверный пароль —
  /// [IntegrityException], отсутствующий файл — [StorageException].
  Future<AccountKeys> unlock(String password) async =>
      await _read().unlock(_crypto, password);

  bool get hasPhrase => phraseFile.existsSync();

  /// Фраза восстановления по паролю (модель угроз, У-2). Фраза
  /// проверяется: она обязана давать ту же учётную запись.
  Future<RecoveryPhrase> unlockPhrase(String password) async {
    final bundle = _read();
    final derived = await bundle.deriveKeys(_crypto, password);
    try {
      final keys = await bundle.unlockWith(_crypto, derived);
      keys.dispose();
      final blob = _readBytes(phraseFile);
      final entropy = EncryptedBlob.open(
        _crypto,
        blob,
        key: derived.kek,
        expectedType: BlobType.localPhrase,
        expectedObjectId: bundle.accountId,
      );
      final phrase = RecoveryPhrase.fromEntropy(entropy);
      entropy.fillRange(0, entropy.length, 0);
      final check = await AccountKeys.fromPhrase(phrase, _crypto);
      final same = constantTimeEquals(check.accountId, bundle.accountId);
      check.dispose();
      if (!same) {
        phrase.dispose();
        throw IntegrityException(
          object: 'recovery-phrase',
          check: IntegrityCheck.objectId,
          objectId: bundle.accountId,
        );
      }
      return phrase;
    } finally {
      derived.dispose();
    }
  }

  /// Перешифровывает копию мастер-ключа (и фразы, если есть) новым
  /// паролем, с новой солью и текущими [params]. Ключи учётной записи не
  /// меняются.
  Future<void> changePassword(String oldPassword, String newPassword) async {
    final keys = await unlock(oldPassword);
    final phrase = hasPhrase ? await unlockPhrase(oldPassword) : null;
    try {
      await _write(keys, newPassword, phrase);
    } finally {
      keys.dispose();
      phrase?.dispose();
    }
  }

  KeyBundle _read() => KeyBundle.parse(_readBytes(file));

  Uint8List _readBytes(File f) {
    try {
      return f.readAsBytesSync();
    } on PathNotFoundException catch (e) {
      throw StorageException(
        location: f.path,
        problem: StorageProblem.notFound,
        operation: 'read',
        cause: e.osError?.message,
      );
    } on FileSystemException catch (e) {
      throw StorageException(
        location: f.path,
        problem: StorageProblem.io,
        operation: 'read',
        cause: e.osError?.message ?? e.message,
      );
    }
  }

  Future<void> _write(
    AccountKeys keys,
    String password,
    RecoveryPhrase? phrase,
  ) async {
    final (bundle, derived) = await KeyBundle.createDerived(
      _crypto,
      keys: keys,
      password: password,
      params: params,
    );
    try {
      // Сначала фраза: если запись KeyBundle потом упадёт, старый KeyBundle
      // не сможет открыть новую фразу, но и не потеряется.
      if (phrase != null) {
        _writeFile(
          phraseFile,
          EncryptedBlob.seal(
            _crypto,
            type: BlobType.localPhrase,
            objectId: keys.accountId,
            key: derived.kek,
            plaintext: phrase.entropy.bytes,
          ),
        );
      }
      _writeFile(file, bundle.toBytes());
    } finally {
      derived.dispose();
    }
  }

  static void _writeFile(File f, Uint8List bytes) {
    try {
      writePrivateFileAtomic(f, bytes);
    } on FileSystemException catch (e) {
      throw StorageException(
        location: f.path,
        problem: StorageProblem.io,
        operation: 'write',
        cause: e.osError?.message ?? e.message,
      );
    }
  }
}
