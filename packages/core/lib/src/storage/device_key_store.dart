import 'dart:io';
import 'dart:typed_data';

import 'package:core/src/crypto/account_keys.dart';
import 'package:core/src/crypto/crypto_provider.dart';
import 'package:core/src/crypto/device_keys.dart';
import 'package:core/src/crypto/encrypted_blob.dart';
import 'package:core/src/crypto/key_bundle.dart';
import 'package:core/src/crypto/recovery_phrase.dart';
import 'package:core/src/crypto/secret_bytes.dart';
import 'package:core/src/errors.dart';
import 'package:core/src/storage/private_file.dart';
import 'package:core/src/util/bytes.dart';

/// Локальное хранилище ключей устройства (crypto.md, разделы 4, 4.1, 4.2):
/// KeyBundle с копией мастер-ключа под паролем в [file] и, если задана,
/// локальная копия фразы восстановления в `<file>.phrase` под тем же
/// `KEK`, и ключи устройства в `<file>.device` (блоб типа 6, crypto.md,
/// раздел 3.4). Файлы доступны только владельцу и пишутся атомарно.
final class DeviceKeyStore {
  new(this.file, this._crypto, {this.params = const Argon2Params()});

  final File file;
  final CryptoProvider _crypto;

  /// Параметры Argon2id для новых KeyBundle (создание, смена пароля).
  final Argon2Params params;

  File get phraseFile => File('${file.path}.phrase');

  File get deviceFile => File('${file.path}.device');

  bool get exists => file.existsSync();

  /// Сохраняет ключи под паролем; с [phrase] — и копию фразы для
  /// `show-phrase`, с [device] — ключи устройства. Существующее хранилище
  /// не перезаписывает.
  Future<void> create(
    AccountKeys keys,
    String password, {
    RecoveryPhrase? phrase,
    DeviceKeys? device,
  }) async {
    if (exists) {
      throw StorageException(
        location: file.path,
        problem: StorageProblem.io,
        operation: 'create',
        cause: 'хранилище ключей уже существует',
      );
    }
    await _write(keys, password, phrase, device);
  }

  /// Ключи учётной записи по паролю. Неверный пароль —
  /// [IntegrityException], отсутствующий файл — [StorageException].
  Future<AccountKeys> unlock(String password) async =>
      await _read().unlock(_crypto, password);

  bool get hasPhrase => phraseFile.existsSync();

  bool get hasDevice => deviceFile.existsSync();

  /// Ключи учётной записи и, если есть, ключи устройства — одним выводом
  /// `KEK`. Неверный пароль — [IntegrityException].
  Future<(AccountKeys, DeviceKeys?)> unlockWithDevice(String password) async {
    final bundle = _read();
    final derived = await bundle.deriveKeys(_crypto, password);
    try {
      final keys = await bundle.unlockWith(_crypto, derived);
      if (!hasDevice) return (keys, null);
      try {
        return (keys, await _openDevice(derived.kek, bundle.accountId));
      } on Object {
        keys.dispose();
        rethrow;
      }
    } finally {
      derived.dispose();
    }
  }

  Future<DeviceKeys> _openDevice(SecretBytes kek, Uint8List accountId) async {
    final secret = SecretBytes.adopt(
      EncryptedBlob.open(
        _crypto,
        _readBytes(deviceFile),
        key: kek,
        expectedType: BlobType.localDeviceKeys,
        expectedObjectId: accountId,
      ),
    );
    try {
      if (secret.length != DeviceKeys.secretLength) {
        throw const DataFormatException(
          object: 'device-keys',
          problem: FormatProblem.invalidField,
          detail: 'нужно 64 байта',
        );
      }
      return await DeviceKeys.fromSecret(_crypto, secret);
    } finally {
      secret.dispose();
    }
  }

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

  /// Перешифровывает копию мастер-ключа (фразы и ключей устройства, если
  /// есть) новым паролем, с новой солью и текущими [params]. Ключи учётной
  /// записи и устройства не меняются.
  Future<void> changePassword(String oldPassword, String newPassword) async {
    final (keys, device) = await unlockWithDevice(oldPassword);
    final phrase = hasPhrase ? await unlockPhrase(oldPassword) : null;
    try {
      await _write(keys, newPassword, phrase, device);
    } finally {
      keys.dispose();
      device?.dispose();
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
    DeviceKeys? device,
  ) async {
    final (bundle, derived) = await KeyBundle.createDerived(
      _crypto,
      keys: keys,
      password: password,
      params: params,
    );
    try {
      // Сначала фраза и ключи устройства: если запись KeyBundle потом
      // упадёт, старый KeyBundle не сможет открыть новые копии, но и не
      // потеряется.
      if (device != null) {
        final secret = device.toSecret();
        try {
          _writeFile(
            deviceFile,
            EncryptedBlob.seal(
              _crypto,
              type: BlobType.localDeviceKeys,
              objectId: keys.accountId,
              key: derived.kek,
              plaintext: secret.bytes,
            ),
          );
        } finally {
          secret.dispose();
        }
      }
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
