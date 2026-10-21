import 'dart:typed_data';

import 'package:core/src/crypto/secret_bytes.dart';
import 'package:hashlib/hashlib.dart' as hashlib;

// HKDF-SHA256 и PBKDF2-HMAC-SHA512 на чистом Dart (пакет hashlib). Общие для
// обеих реализаций CryptoProvider: libsodium через пакет sodium не даёт
// HKDF с двоичным info (контекст — строка) и HMAC-SHA512 (только
// HMAC-SHA512-256). Входы короткие, скорость не важна.

/// HKDF-SHA256 по RFC 5869.
SecretBytes hkdfSha256({
  required SecretBytes ikm,
  required Uint8List salt,
  required Uint8List info,
  required int length,
}) {
  const hashLength = 32;
  if (length < 1 || length > 255 * hashLength) {
    throw RangeError.range(length, 1, 255 * hashLength, 'length');
  }
  final prk = hashlib.sha256.hmac
      .by(salt.isEmpty ? Uint8List(hashLength) : salt)
      .convert(ikm.bytes)
      .bytes;
  final mac = hashlib.sha256.hmac.by(prk);
  final okm = Uint8List(length);
  var previous = Uint8List(0);
  for (var i = 0, offset = 0; offset < length; i++) {
    final block = mac.convert([...previous, ...info, i + 1]).bytes;
    final take = length - offset < hashLength ? length - offset : hashLength;
    okm.setRange(offset, offset + take, block);
    offset += take;
    previous.fillRange(0, previous.length, 0);
    previous = Uint8List.fromList(block);
    block.fillRange(0, block.length, 0);
  }
  previous.fillRange(0, previous.length, 0);
  prk.fillRange(0, prk.length, 0);
  return SecretBytes.adopt(okm);
}

/// PBKDF2-HMAC-SHA512 (RFC 8018), как в BIP39.
SecretBytes pbkdf2HmacSha512({
  required Uint8List password,
  required Uint8List salt,
  required int iterations,
  required int length,
}) {
  if (iterations < 1) {
    throw RangeError.range(iterations, 1, null, 'iterations');
  }
  if (length < 1) throw RangeError.range(length, 1, null, 'length');
  final digest = hashlib
      .PBKDF2(hashlib.sha512.hmac, iterations, salt: salt, keyLength: length)
      .convert(password);
  return SecretBytes.adopt(digest.bytes);
}
