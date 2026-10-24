import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:core/src/crypto/crypto_provider.dart';
import 'package:core/src/crypto/kdf.dart' as kdf;
import 'package:core/src/crypto/secret_bytes.dart';
import 'package:core/src/errors.dart';
import 'package:cryptography/cryptography.dart' as c;
import 'package:cryptography/dart.dart' as c;
import 'package:hashlib/hashlib.dart' as hashlib;

/// Запасной [CryptoProvider] на чистом Dart (пакеты `cryptography` и
/// `hashlib`). В 30 раз медленнее libsodium на AEAD (docs/benchmarks.md),
/// зато не требует нативной библиотеки.
final class DartCryptoProvider implements CryptoProvider {
  new() : _random = Random.secure();

  final Random _random;

  static const _aead = c.DartXchacha20.poly1305Aead();
  static const _chacha = c.DartChacha20.poly1305Aead();
  static final _ed25519 = c.DartEd25519();
  static const _x25519 = c.DartX25519();

  @override
  Uint8List aeadEncrypt({
    required SecretBytes key,
    required Uint8List nonce,
    required Uint8List plaintext,
    required Uint8List aad,
  }) {
    _checkLength(key.length, CryptoProvider.keyLength, 'key');
    _checkLength(nonce.length, CryptoProvider.aeadNonceLength, 'nonce');
    final box = _aead.encryptSync(
      plaintext,
      secretKey: c.SecretKeyData(key.bytes),
      nonce: nonce,
      aad: aad,
    );
    final tag = box.mac.bytes;
    return Uint8List(box.cipherText.length + tag.length)
      ..setAll(0, box.cipherText)
      ..setAll(box.cipherText.length, tag);
  }

  @override
  Uint8List? aeadDecrypt({
    required SecretBytes key,
    required Uint8List nonce,
    required Uint8List ciphertext,
    required Uint8List aad,
  }) {
    _checkLength(key.length, CryptoProvider.keyLength, 'key');
    _checkLength(nonce.length, CryptoProvider.aeadNonceLength, 'nonce');
    const tagLength = CryptoProvider.aeadTagLength;
    if (ciphertext.length < tagLength) return null;
    final split = ciphertext.length - tagLength;
    try {
      final plain = _aead.decryptSync(
        c.SecretBox(
          Uint8List.sublistView(ciphertext, 0, split),
          nonce: nonce,
          mac: c.Mac(Uint8List.sublistView(ciphertext, split)),
        ),
        secretKey: c.SecretKeyData(key.bytes),
        aad: aad,
      );
      return plain is Uint8List ? plain : Uint8List.fromList(plain);
    } on c.SecretBoxAuthenticationError {
      return null;
    }
  }

  @override
  Uint8List chacha20Poly1305Encrypt({
    required SecretBytes key,
    required Uint8List nonce,
    required Uint8List plaintext,
    required Uint8List aad,
  }) {
    _checkLength(key.length, CryptoProvider.keyLength, 'key');
    _checkLength(nonce.length, CryptoProvider.chachaNonceLength, 'nonce');
    final box = _chacha.encryptSync(
      plaintext,
      secretKey: c.SecretKeyData(key.bytes),
      nonce: nonce,
      aad: aad,
    );
    final tag = box.mac.bytes;
    return Uint8List(box.cipherText.length + tag.length)
      ..setAll(0, box.cipherText)
      ..setAll(box.cipherText.length, tag);
  }

  @override
  Uint8List? chacha20Poly1305Decrypt({
    required SecretBytes key,
    required Uint8List nonce,
    required Uint8List ciphertext,
    required Uint8List aad,
  }) {
    _checkLength(key.length, CryptoProvider.keyLength, 'key');
    _checkLength(nonce.length, CryptoProvider.chachaNonceLength, 'nonce');
    const tagLength = CryptoProvider.aeadTagLength;
    if (ciphertext.length < tagLength) return null;
    final split = ciphertext.length - tagLength;
    try {
      final plain = _chacha.decryptSync(
        c.SecretBox(
          Uint8List.sublistView(ciphertext, 0, split),
          nonce: nonce,
          mac: c.Mac(Uint8List.sublistView(ciphertext, split)),
        ),
        secretKey: c.SecretKeyData(key.bytes),
        aad: aad,
      );
      return plain is Uint8List ? plain : Uint8List.fromList(plain);
    } on c.SecretBoxAuthenticationError {
      return null;
    }
  }

  @override
  Uint8List blake2b512(Uint8List data) =>
      hashlib.blake2b512.convert(data).bytes;

  @override
  Uint8List blake2b256(Uint8List data, {SecretBytes? key}) {
    if (key == null) return hashlib.blake2b256.convert(data).bytes;
    _checkLength(key.length, CryptoProvider.keyLength, 'key');
    return hashlib.blake2b256.mac.by(key.bytes).convert(data).bytes;
  }

  @override
  SecretBytes hkdfSha256({
    required SecretBytes ikm,
    required Uint8List salt,
    required Uint8List info,
    int length = CryptoProvider.keyLength,
  }) => kdf.hkdfSha256(ikm: ikm, salt: salt, info: info, length: length);

  @override
  Future<SecretBytes> pbkdf2HmacSha512({
    required Uint8List password,
    required Uint8List salt,
    required int iterations,
    required int length,
  }) async => kdf.pbkdf2HmacSha512(
    password: password,
    salt: salt,
    iterations: iterations,
    length: length,
  );

  @override
  Future<SecretBytes> argon2id({
    required Uint8List password,
    required Uint8List salt,
    Argon2Params params = const Argon2Params(),
    int length = CryptoProvider.keyLength,
  }) async {
    final m = params.memoryKiB;
    final t = params.iterations;
    final p = params.parallelism;
    final out = await Isolate.run(
      () => hashlib.Argon2(
        salt: salt,
        hashLength: length,
        iterations: t,
        parallelism: p,
        memorySizeKB: m,
      ).convert(password).bytes,
    );
    return SecretBytes.adopt(out);
  }

  @override
  Future<Ed25519KeyPair> ed25519FromSeed(SecretBytes seed) async {
    _checkLength(seed.length, 32, 'seed');
    final pair = await _ed25519.newKeyPairFromSeed(seed.bytes);
    final public = await pair.extractPublicKey();
    return Ed25519KeyPair(
      seed: SecretBytes(seed.bytes),
      publicKey: Uint8List.fromList(public.bytes),
    );
  }

  @override
  Future<Uint8List> ed25519Sign(
    Ed25519KeyPair keyPair,
    Uint8List message,
  ) async {
    final pair = await _ed25519.newKeyPairFromSeed(keyPair.seed.bytes);
    final signature = await _ed25519.sign(message, keyPair: pair);
    return Uint8List.fromList(signature.bytes);
  }

  @override
  Future<Ed25519Signer> ed25519Signer(Ed25519KeyPair keyPair) async =>
      _DartSigner(
        this,
        Ed25519KeyPair(
          seed: SecretBytes(keyPair.seed.bytes),
          publicKey: keyPair.publicKey,
        ),
      );

  @override
  Future<bool> ed25519Verify({
    required Uint8List publicKey,
    required Uint8List message,
    required Uint8List signature,
  }) async {
    _checkLength(publicKey.length, 32, 'publicKey');
    if (signature.length != CryptoProvider.ed25519SignatureLength) {
      return false;
    }
    return await _ed25519.verify(
      message,
      signature: c.Signature(
        signature,
        publicKey: c.SimplePublicKey(publicKey, type: c.KeyPairType.ed25519),
      ),
    );
  }

  @override
  Future<X25519KeyPair> x25519FromSecret(SecretBytes secretKey) async {
    _checkLength(secretKey.length, 32, 'secretKey');
    final pair = await _x25519.newKeyPairFromSeed(secretKey.bytes);
    final public = await pair.extractPublicKey();
    return X25519KeyPair(
      secretKey: SecretBytes(secretKey.bytes),
      publicKey: Uint8List.fromList(public.bytes),
    );
  }

  @override
  Future<SecretBytes> x25519({
    required SecretBytes secretKey,
    required Uint8List publicKey,
  }) async {
    _checkLength(secretKey.length, 32, 'secretKey');
    _checkLength(publicKey.length, 32, 'publicKey');
    final pair = await _x25519.newKeyPairFromSeed(secretKey.bytes);
    final shared = await _x25519.sharedSecretKey(
      keyPair: pair,
      remotePublicKey: c.SimplePublicKey(publicKey, type: c.KeyPairType.x25519),
    );
    final bytes = Uint8List.fromList(await shared.extractBytes());
    // Как в libsodium: нулевой общий секрет означает точку малого порядка.
    if (bytes.every((b) => b == 0)) {
      throw const DataFormatException(
        object: 'x25519-public-key',
        problem: FormatProblem.invalidField,
        detail: 'точка малого порядка',
      );
    }
    return SecretBytes.adopt(bytes);
  }

  @override
  Uint8List randomBytes(int length) {
    RangeError.checkNotNegative(length, 'length');
    final out = Uint8List(length);
    for (var i = 0; i < length; i++) {
      out[i] = _random.nextInt(256);
    }
    return out;
  }
}

void _checkLength(int actual, int expected, String name) {
  if (actual != expected) {
    throw ArgumentError('$name: нужно $expected байт, получено $actual');
  }
}

final class _DartSigner implements Ed25519Signer {
  new(this._crypto, this._key);

  final DartCryptoProvider _crypto;
  final Ed25519KeyPair _key;

  @override
  Uint8List get publicKey => _key.publicKey;

  @override
  Future<Uint8List> sign(Uint8List message) =>
      _crypto.ed25519Sign(_key, message);

  @override
  void dispose() => _key.seed.dispose();
}
