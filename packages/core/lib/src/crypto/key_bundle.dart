import 'dart:convert';
import 'dart:typed_data';

import 'package:core/src/crypto/account_keys.dart';
import 'package:core/src/crypto/crypto_provider.dart';
import 'package:core/src/crypto/encrypted_blob.dart';
import 'package:core/src/crypto/secret_bytes.dart';
import 'package:core/src/errors.dart';
import 'package:core/src/util/bytes.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

/// Пароль в байтах для Argon2id: NFKC, затем UTF-8 (crypto.md, раздел 4).
Uint8List normalizePassword(String password) =>
    utf8.encode(unorm.nfkc(password));

/// Ключи из пароля: `PK` = Argon2id, `KEK` и `AUTH` из него через HKDF.
final class PasswordKeys {
  new _(this.kek, this.auth);

  static Future<PasswordKeys> derive(
    CryptoProvider crypto, {
    required String password,
    required Uint8List salt,
    required Argon2Params params,
  }) async {
    final pk = await crypto.argon2id(
      password: normalizePassword(password),
      salt: salt,
      params: params,
    );
    SecretBytes sub(String label) => crypto.hkdfSha256(
      ikm: pk,
      salt: Uint8List(0),
      info: ascii.encode(label),
    );
    try {
      return PasswordKeys._(sub('fs/v1/kek'), sub('fs/v1/auth'));
    } finally {
      pk.dispose();
    }
  }

  /// Шифрует копию мастер-ключа; не покидает устройство.
  final SecretBytes kek;

  /// Для входа на координатор (этап 2).
  final SecretBytes auth;

  void dispose() {
    kek.dispose();
    auth.dispose();
  }
}

/// Копия мастер-ключа под паролем (crypto.md, раздел 4.1).
///
/// | Смещение | Размер | Поле |
/// |---|---|---|
/// | 0 | 4 | `FSKB` |
/// | 4 | 1 | версия = 1 |
/// | 5 | 1 | KDF: 1 = Argon2id v1.3 |
/// | 6 | 2 | резерв, нули |
/// | 8 | 12 | `m` (КиБ), `t`, `p`, `u32le` |
/// | 20 | 16 | соль |
/// | 36 | 112 | блоб `key-bundle` с 32 байтами MK |
final class KeyBundle {
  const new _({required this.params, required this.salt, required this.blob});

  /// Разбор без расшифровки. Ошибки — [DataFormatException].
  ///
  /// Параметры Argon2id ограничены сверху: KeyBundle может прийти с
  /// координатора, и подложенные огромные `m` или `t` не должны занять
  /// всю память или время устройства.
  factory parse(Uint8List bytes) {
    if (bytes.length != length) {
      throw DataFormatException(
        object: _object,
        problem: bytes.length < length
            ? FormatProblem.truncated
            : FormatProblem.tooLarge,
        detail: '${bytes.length} байт, нужно $length',
      );
    }
    final r = ByteReader(bytes);
    if (!constantTimeEquals(r.bytes(4), _magic)) {
      throw const DataFormatException(
        object: _object,
        problem: FormatProblem.badMagic,
        offset: 0,
      );
    }
    final version = r.u8();
    if (version != 1) {
      throw DataFormatException(
        object: _object,
        problem: FormatProblem.unsupportedVersion,
        detail: 'версия $version',
        offset: 4,
      );
    }
    final kdf = r.u8();
    if (kdf != _kdfArgon2id) {
      throw DataFormatException(
        object: _object,
        problem: FormatProblem.unknownType,
        detail: 'KDF $kdf',
        offset: 5,
      );
    }
    if (r.u16le() != 0) {
      throw const DataFormatException(
        object: _object,
        problem: FormatProblem.reservedNotZero,
        offset: 6,
      );
    }
    final params = Argon2Params(
      memoryKiB: r.u32le(),
      iterations: r.u32le(),
      parallelism: r.u32le(),
    );
    _checkParams(params);
    final salt = Uint8List.fromList(r.bytes(saltLength));
    final blob = Uint8List.fromList(r.bytes(r.remaining));
    final header = BlobHeader.parse(blob);
    if (header.type != BlobType.keyBundle) {
      throw DataFormatException(
        object: _object,
        problem: FormatProblem.unknownType,
        detail: 'вложенный блоб типа ${header.type.name}',
        offset: 36 + 5,
      );
    }
    return KeyBundle._(params: params, salt: salt, blob: blob);
  }

  static const int saltLength = 16;
  static const int length =
      36 + EncryptedBlob.overhead + CryptoProvider.keyLength;

  /// Пределы параметров при разборе: от минимума libsodium до 4 ГиБ и
  /// 64 проходов.
  static const int minMemoryKiB = 8;
  static const int maxMemoryKiB = 4 * 1024 * 1024;
  static const int maxIterations = 64;

  final Argon2Params params;
  final Uint8List salt;

  /// Вложенный блоб типа 4; идентификатор объекта — идентификатор
  /// учётной записи.
  final Uint8List blob;

  /// Идентификатор учётной записи из заголовка вложенного блоба.
  Uint8List get accountId => BlobHeader.parse(blob).objectId;

  /// Новый KeyBundle с копией мастер-ключа [keys] под [password]. Соль и
  /// nonce случайные; фиксированные — только для тестовых векторов.
  static Future<KeyBundle> create(
    CryptoProvider crypto, {
    required AccountKeys keys,
    required String password,
    Argon2Params params = const Argon2Params(),
    Uint8List? salt,
    Uint8List? nonce,
  }) async {
    final (bundle, derived) = await createDerived(
      crypto,
      keys: keys,
      password: password,
      params: params,
      salt: salt,
      nonce: nonce,
    );
    derived.dispose();
    return bundle;
  }

  /// Как [create], но отдаёт и ключи из пароля — чтобы зашифровать тем же
  /// `KEK` локальную копию фразы (crypto.md, раздел 4.2) без второго
  /// Argon2id. Вызывающий уничтожает ключи.
  static Future<(KeyBundle, PasswordKeys)> createDerived(
    CryptoProvider crypto, {
    required AccountKeys keys,
    required String password,
    Argon2Params params = const Argon2Params(),
    Uint8List? salt,
    Uint8List? nonce,
  }) async {
    _checkParams(params);
    final s = salt ?? crypto.randomBytes(saltLength);
    if (s.length != saltLength) throw ArgumentError('Соль — $saltLength байт');
    final derived = await PasswordKeys.derive(
      crypto,
      password: password,
      salt: s,
      params: params,
    );
    final blob = EncryptedBlob.seal(
      crypto,
      type: BlobType.keyBundle,
      objectId: keys.accountId,
      key: derived.kek,
      plaintext: keys.masterKey.bytes,
      nonce: nonce,
    );
    return (KeyBundle._(params: params, salt: s, blob: blob), derived);
  }

  /// Ключи из пароля по соли и параметрам этого KeyBundle.
  Future<PasswordKeys> deriveKeys(CryptoProvider crypto, String password) =>
      PasswordKeys.derive(
        crypto,
        password: password,
        salt: salt,
        params: params,
      );

  /// Расшифровывает мастер-ключ и восстанавливает ключи учётной записи.
  /// Неверный пароль — [IntegrityException] (тег AEAD). Мастер-ключ,
  /// который не соответствует идентификатору учётной записи в заголовке, —
  /// тоже [IntegrityException].
  Future<AccountKeys> unlock(CryptoProvider crypto, String password) async {
    final derived = await deriveKeys(crypto, password);
    try {
      return await unlockWith(crypto, derived);
    } finally {
      derived.dispose();
    }
  }

  /// Как [unlock], но с уже выведенными из пароля ключами.
  Future<AccountKeys> unlockWith(
    CryptoProvider crypto,
    PasswordKeys derived,
  ) async {
    final Uint8List masterKey;
    try {
      masterKey = EncryptedBlob.open(
        crypto,
        blob,
        key: derived.kek,
        expectedType: BlobType.keyBundle,
      );
    } on IntegrityException {
      throw const IntegrityException(
        object: _object,
        check: IntegrityCheck.aeadTag,
      );
    }
    if (masterKey.length != CryptoProvider.keyLength) {
      masterKey.fillRange(0, masterKey.length, 0);
      throw const DataFormatException(
        object: _object,
        problem: FormatProblem.invalidField,
        detail: 'длина мастер-ключа',
      );
    }
    final keys = await AccountKeys.fromMasterKey(
      SecretBytes.adopt(masterKey),
      crypto,
    );
    if (!constantTimeEquals(keys.accountId, accountId)) {
      keys.dispose();
      throw IntegrityException(
        object: _object,
        check: IntegrityCheck.objectId,
        objectId: accountId,
      );
    }
    return keys;
  }

  Uint8List toBytes() =>
      (ByteWriter(length)
            ..bytes(_magic)
            ..u8(1)
            ..u8(_kdfArgon2id)
            ..u16le(0)
            ..u32le(params.memoryKiB)
            ..u32le(params.iterations)
            ..u32le(params.parallelism)
            ..bytes(salt)
            ..bytes(blob))
          .toBytes();

  static void _checkParams(Argon2Params p) {
    if (p.memoryKiB < minMemoryKiB ||
        p.memoryKiB > maxMemoryKiB ||
        p.iterations < 1 ||
        p.iterations > maxIterations ||
        p.parallelism != 1) {
      throw DataFormatException(
        object: _object,
        problem: FormatProblem.invalidField,
        detail: '$p',
        offset: 8,
      );
    }
  }
}

const _object = 'key-bundle';
const _kdfArgon2id = 1;
final _magic = Uint8List.fromList('FSKB'.codeUnits);
