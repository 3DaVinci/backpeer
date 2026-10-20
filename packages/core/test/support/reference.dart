// Эталонные функции для проверки векторов в тестах: независимая от будущего
// кода core реализация примитивов из docs/spec/ на пакетах cryptography и
// hashlib.

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:hashlib/hashlib.dart' as hashlib;

/// BLAKE2b-256 без ключа.
Uint8List blake2b(List<int> data) =>
    Uint8List.fromList(hashlib.blake2b256.convert(data).bytes);

/// BLAKE2b-256 с ключом.
Uint8List blake2bKeyed(List<int> key, List<int> data) =>
    Uint8List.fromList(hashlib.blake2b256.mac.by(key).convert(data).bytes);

Future<Uint8List> hkdf(List<int> ikm, List<int> salt, List<int> info) async {
  final key = await DartHkdf(
    hmac: Hmac.sha256(),
    outputLength: 32,
  ).deriveKey(secretKey: SecretKey(ikm), nonce: salt, info: info);
  return Uint8List.fromList(await key.extractBytes());
}

List<int> u32le(int value) =>
    (ByteData(4)..setUint32(0, value, Endian.little)).buffer.asUint8List();

Future<Uint8List> sealBlob({
  required int type,
  required List<int> objectId,
  required List<int> nonce,
  required List<int> key,
  required List<int> plaintext,
}) async {
  final header = Uint8List.fromList([
    ...ascii.encode('FSEB'),
    1,
    type,
    0,
    0,
    ...objectId,
  ]);
  final box = await const DartXchacha20.poly1305Aead().encrypt(
    plaintext,
    secretKey: SecretKey(key),
    nonce: nonce,
    aad: header,
  );
  return Uint8List.fromList([
    ...header,
    ...nonce,
    ...box.cipherText,
    ...box.mac.bytes,
  ]);
}
