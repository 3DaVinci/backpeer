import 'dart:typed_data';

import 'package:core/src/crypto/secret_bytes.dart';

/// Параметры Argon2id v1.3 (docs/spec/crypto.md, раздел 4). Значения по
/// умолчанию — из замера 0.5.2.
final class Argon2Params {
  const new({
    this.memoryKiB = 262144,
    this.iterations = 3,
    this.parallelism = 1,
  });

  /// `m`, КиБ.
  final int memoryKiB;

  /// `t`.
  final int iterations;

  /// `p`. libsodium поддерживает только 1.
  final int parallelism;

  @override
  String toString() =>
      'Argon2Params(m=$memoryKiB КиБ, t=$iterations, p=$parallelism)';
}

/// Пара ключей Ed25519. Закрытый ключ хранится как 32-байтный seed
/// (RFC 8032, раздел 5.1.5), как его выводит docs/spec/crypto.md.
final class Ed25519KeyPair {
  const new({required this.seed, required this.publicKey});

  final SecretBytes seed;

  /// 32 байта.
  final Uint8List publicKey;
}

/// Пара ключей X25519 (RFC 7748).
final class X25519KeyPair {
  const new({required this.secretKey, required this.publicKey});

  /// 32 байта.
  final SecretBytes secretKey;

  /// 32 байта.
  final Uint8List publicKey;
}

/// Криптографические примитивы из docs/spec/crypto.md, раздел 2 (ADR-003).
/// Основная реализация — libsodium через FFI, запасная — пакеты
/// `cryptography` и `hashlib`, позже возможна Rust. Все реализации дают
/// одинаковые байты на векторах `test-vectors/crypto/`.
///
/// Операции над объёмом данных бэкапа (AEAD, BLAKE2b) и над короткими
/// входами (HKDF, случайные байты) синхронные: они дешёвые или упираются
/// в скорость памяти. Медленные (Argon2id, PBKDF2) и асимметричные
/// (Ed25519, X25519) возвращают [Future]: реализация может вынести их в
/// isolate или опираться на асинхронную библиотеку.
///
/// Неверная длина ключа, nonce или подписи — [ArgumentError]: это ошибка
/// программы, а не данных.
abstract interface class CryptoProvider {
  static const int keyLength = 32;
  static const int aeadNonceLength = 24;
  static const int aeadTagLength = 16;
  static const int hashLength = 32;
  static const int ed25519SignatureLength = 64;

  /// XChaCha20-Poly1305 (IETF): возвращает шифротекст с тегом в конце,
  /// длина `plaintext.length + 16`.
  Uint8List aeadEncrypt({
    required SecretBytes key,
    required Uint8List nonce,
    required Uint8List plaintext,
    required Uint8List aad,
  });

  /// Обратная к [aeadEncrypt]. Неверный тег — `null`; частично
  /// расшифрованные данные не возвращаются.
  Uint8List? aeadDecrypt({
    required SecretBytes key,
    required Uint8List nonce,
    required Uint8List ciphertext,
    required Uint8List aad,
  });

  /// BLAKE2b-256 (RFC 7693); с [key] — ключевой режим, ключ 32 байта.
  Uint8List blake2b256(Uint8List data, {SecretBytes? key});

  /// HKDF-SHA256 (RFC 5869). Пустая [salt] равносильна 32 нулевым байтам.
  SecretBytes hkdfSha256({
    required SecretBytes ikm,
    required Uint8List salt,
    required Uint8List info,
    int length = keyLength,
  });

  /// PBKDF2-HMAC-SHA512 — вывод seed из фразы BIP39.
  Future<SecretBytes> pbkdf2HmacSha512({
    required Uint8List password,
    required Uint8List salt,
    required int iterations,
    required int length,
  });

  /// Argon2id v1.3 (RFC 9106). [password] — уже нормализованный NFKC
  /// пароль в UTF-8.
  Future<SecretBytes> argon2id({
    required Uint8List password,
    required Uint8List salt,
    Argon2Params params = const Argon2Params(),
    int length = keyLength,
  });

  /// Пара Ed25519 из 32-байтного seed.
  Future<Ed25519KeyPair> ed25519FromSeed(SecretBytes seed);

  /// Подпись Ed25519, 64 байта. Контекст подписи (crypto.md, раздел 3.5)
  /// добавляет вызывающий.
  Future<Uint8List> ed25519Sign(Ed25519KeyPair keyPair, Uint8List message);

  Future<bool> ed25519Verify({
    required Uint8List publicKey,
    required Uint8List message,
    required Uint8List signature,
  });

  /// Пара X25519 из 32 байтов закрытого ключа.
  Future<X25519KeyPair> x25519FromSecret(SecretBytes secretKey);

  /// Общий секрет X25519. Открытый ключ малого порядка (нулевой общий
  /// секрет) — `DataFormatException`: ключ пришёл от собеседника, это
  /// ошибка данных.
  Future<SecretBytes> x25519({
    required SecretBytes secretKey,
    required Uint8List publicKey,
  });

  /// Байты из криптостойкого ГПСЧ операционной системы.
  Uint8List randomBytes(int length);
}
