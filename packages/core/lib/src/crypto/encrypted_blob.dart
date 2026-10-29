import 'dart:typed_data';

import 'package:core/src/crypto/crypto_provider.dart';
import 'package:core/src/crypto/secret_bytes.dart';
import 'package:core/src/errors.dart';
import 'package:core/src/util/bytes.dart';

/// Тип объекта в зашифрованном блобе (crypto.md, раздел 5).
enum BlobType {
  segment(1),
  snapshot(2),
  indexObject(3),
  keyBundle(4),

  /// Локальная копия фразы восстановления (crypto.md, раздел 4.2); на
  /// координатор не отправляется.
  localPhrase(5),

  /// Локальные ключи устройства (crypto.md, раздел 3.4); на координатор не
  /// отправляются.
  localDeviceKeys(6),

  /// Ключи для фоновой работы агента бэкапа под ключом из хранилища ОС
  /// (crypto.md, раздел 4.5); только локальные.
  localAgentKeys(7);

  new(this.code);

  final int code;

  static BlobType? fromCode(int code) {
    for (final t in values) {
      if (t.code == code) return t;
    }
    return null;
  }
}

/// Открытый заголовок блоба: 64 байта.
///
/// | Смещение | Размер | Поле |
/// |---|---|---|
/// | 0 | 4 | `FSEB` |
/// | 4 | 1 | версия = 1 |
/// | 5 | 1 | тип |
/// | 6 | 2 | резерв, нули |
/// | 8 | 32 | идентификатор объекта |
/// | 40 | 24 | nonce |
///
/// AAD — байты 0..39.
final class BlobHeader {
  const new({required this.type, required this.objectId, required this.nonce});

  /// Разбор заголовка без расшифровки. Ошибки — [DataFormatException].
  factory parse(Uint8List blob) {
    if (blob.length < EncryptedBlob.minLength) {
      throw DataFormatException(
        object: _object,
        problem: FormatProblem.truncated,
        detail:
            '${blob.length} байт, нужно не меньше ${EncryptedBlob.minLength}',
      );
    }
    final r = ByteReader(blob);
    if (!constantTimeEquals(r.bytes(4), _magic)) {
      throw const DataFormatException(
        object: _object,
        problem: FormatProblem.badMagic,
        offset: 0,
      );
    }
    final version = r.u8();
    if (version != EncryptedBlob.version) {
      throw DataFormatException(
        object: _object,
        problem: FormatProblem.unsupportedVersion,
        detail: 'версия $version',
        offset: 4,
      );
    }
    final code = r.u8();
    final type = BlobType.fromCode(code);
    if (type == null) {
      throw DataFormatException(
        object: _object,
        problem: FormatProblem.unknownType,
        detail: 'тип $code',
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
    return BlobHeader(
      type: type,
      objectId: Uint8List.fromList(r.bytes(EncryptedBlob.objectIdLength)),
      nonce: Uint8List.fromList(r.bytes(CryptoProvider.aeadNonceLength)),
    );
  }

  final BlobType type;

  /// 32 байта.
  final Uint8List objectId;

  /// 24 байта.
  final Uint8List nonce;

  /// Байты 0..39 — AAD.
  Uint8List get aad =>
      (ByteWriter(EncryptedBlob.aadLength)
            ..bytes(_magic)
            ..u8(EncryptedBlob.version)
            ..u8(type.code)
            ..u16le(0)
            ..bytes(objectId))
          .toBytes();
}

/// Зашифрованный блоб: единый формат сегментов, снимков, индексов и копии
/// мастер-ключа (crypto.md, раздел 5).
abstract final class EncryptedBlob {
  static const int version = 1;
  static const int objectIdLength = 32;
  static const int aadLength = 40;
  static const int headerLength = 64;

  /// Заголовок и тег Poly1305.
  static const int overhead = headerLength + CryptoProvider.aeadTagLength;
  static const int minLength = overhead;

  /// Шифрует [plaintext]. [nonce] по умолчанию случайный; фиксированный —
  /// только для тестовых векторов.
  static Uint8List seal(
    CryptoProvider crypto, {
    required BlobType type,
    required Uint8List objectId,
    required SecretBytes key,
    required Uint8List plaintext,
    Uint8List? nonce,
  }) {
    if (objectId.length != objectIdLength) {
      throw ArgumentError('objectId — $objectIdLength байта');
    }
    final header = BlobHeader(
      type: type,
      objectId: objectId,
      nonce: nonce ?? crypto.randomBytes(CryptoProvider.aeadNonceLength),
    );
    final body = crypto.aeadEncrypt(
      key: key,
      nonce: header.nonce,
      plaintext: plaintext,
      aad: header.aad,
    );
    return Uint8List(headerLength + body.length)
      ..setAll(0, header.aad)
      ..setAll(aadLength, header.nonce)
      ..setAll(headerLength, body);
  }

  /// Разбирает и расшифровывает блоб. Битый заголовок —
  /// [DataFormatException] (расшифровка не выполняется), неверный тег —
  /// [IntegrityException].
  ///
  /// [expectedType] и [expectedObjectId] защищают от подмены целого блоба
  /// другим, тоже подлинным: тип не тот — [DataFormatException],
  /// идентификатор не тот — [IntegrityException].
  static Uint8List open(
    CryptoProvider crypto,
    Uint8List blob, {
    required SecretBytes key,
    BlobType? expectedType,
    Uint8List? expectedObjectId,
  }) {
    final header = BlobHeader.parse(blob);
    if (expectedType != null && header.type != expectedType) {
      throw DataFormatException(
        object: _object,
        problem: FormatProblem.unknownType,
        detail: 'ожидался ${expectedType.name}, получен ${header.type.name}',
        offset: 5,
      );
    }
    if (expectedObjectId != null &&
        !constantTimeEquals(header.objectId, expectedObjectId)) {
      throw IntegrityException(
        object: _object,
        check: IntegrityCheck.objectId,
        objectId: header.objectId,
      );
    }
    final plaintext = crypto.aeadDecrypt(
      key: key,
      nonce: header.nonce,
      ciphertext: Uint8List.sublistView(blob, headerLength),
      aad: Uint8List.sublistView(blob, 0, aadLength),
    );
    if (plaintext == null) {
      throw IntegrityException(
        object: _object,
        check: IntegrityCheck.aeadTag,
        objectId: header.objectId,
      );
    }
    return plaintext;
  }
}

const _object = 'blob';
final _magic = Uint8List.fromList('FSEB'.codeUnits);
