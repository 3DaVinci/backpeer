import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:core/src/crypto/crypto_provider.dart';
import 'package:core/src/crypto/kdf.dart' as kdf;
import 'package:core/src/crypto/secret_bytes.dart';
import 'package:core/src/errors.dart';
import 'package:ffi/ffi.dart';
import 'package:sodium/sodium.ffi.dart' show LibSodiumFFI;
import 'package:sodium/sodium_sumo.dart';

/// [CryptoProvider] на libsodium через FFI (пакет `sodium`, решение 0.5.1).
/// libsodium собирает build hook пакета при сборке: нужен компилятор C
/// (docs/ci.md). HKDF и PBKDF2 — на чистом Dart (`kdf.dart`).
///
/// Результаты пакета `sodium` — внешние буферы `sodium_malloc`, которые
/// освобождает финализатор при сборке мусора. Наружу они не отдаются:
/// результат копируется в обычный `Uint8List` ([_own]). Так время жизни
/// нативной памяти не зависит от того, как код дальше держит байты
/// (представления, isolate). Поводом стало падение SIGSEGV в
/// `SegmentReader.segment` при нагрузочном замере 1.8.3; цена — одна копия
/// сегмента (16 МиБ — единицы миллисекунд).
final class SodiumCryptoProvider implements CryptoProvider {
  new _(this._sodium);

  /// Загружает libsodium. Ошибка загрузки — исключение пакета `sodium`;
  /// вызывающий может перейти на `DartCryptoProvider`.
  static Future<SodiumCryptoProvider> load() async =>
      SodiumCryptoProvider._(await SodiumSumoInit.init());

  final SodiumSumo _sodium;

  /// Версия libsodium, например `1.0.20`.
  String get libraryVersion => _sodium.version.toString();

  @override
  Uint8List aeadEncrypt({
    required SecretBytes key,
    required Uint8List nonce,
    required Uint8List plaintext,
    required Uint8List aad,
  }) {
    _checkLength(key.length, CryptoProvider.keyLength, 'key');
    _checkLength(nonce.length, CryptoProvider.aeadNonceLength, 'nonce');
    return _withKey(
      key,
      (k) => _own(
        _sodium.crypto.aeadXChaCha20Poly1305IETF.encrypt(
          message: plaintext,
          nonce: nonce,
          key: k,
          additionalData: aad,
        ),
      ),
    );
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
    if (ciphertext.length < CryptoProvider.aeadTagLength) return null;
    return _withKey(key, (k) {
      try {
        return _own(
          _sodium.crypto.aeadXChaCha20Poly1305IETF.decrypt(
            cipherText: ciphertext,
            nonce: nonce,
            key: k,
            additionalData: aad,
          ),
        );
      } on SodiumException {
        return null;
      }
    });
  }

  // ChaCha20-Poly1305 IETF в высокоуровневом API пакета `sodium` нет
  // (только исходная конструкция с nonce 8 байт), поэтому — прямой вызов
  // привязок FFI того же пакета, с той же собранной libsodium.
  static const _ffi = LibSodiumFFI();

  @override
  Uint8List chacha20Poly1305Encrypt({
    required SecretBytes key,
    required Uint8List nonce,
    required Uint8List plaintext,
    required Uint8List aad,
  }) {
    _checkLength(key.length, CryptoProvider.keyLength, 'key');
    _checkLength(nonce.length, CryptoProvider.chachaNonceLength, 'nonce');
    return _ietf(key, nonce, aad, plaintext, (k, n, a, input, out) {
      final outLength = calloc<UnsignedLongLong>();
      try {
        final rc = _ffi.crypto_aead_chacha20poly1305_ietf_encrypt(
          out,
          outLength,
          input,
          plaintext.length,
          a,
          aad.length,
          nullptr,
          n,
          k,
        );
        if (rc != 0) throw StateError('chacha20poly1305: код $rc');
        return outLength.value;
      } finally {
        calloc.free(outLength);
      }
    }, plaintext.length + CryptoProvider.aeadTagLength)!;
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
    if (ciphertext.length < CryptoProvider.aeadTagLength) return null;
    return _ietf(key, nonce, aad, ciphertext, (k, n, a, input, out) {
      final outLength = calloc<UnsignedLongLong>();
      try {
        final rc = _ffi.crypto_aead_chacha20poly1305_ietf_decrypt(
          out,
          outLength,
          nullptr,
          input,
          ciphertext.length,
          a,
          aad.length,
          n,
          k,
        );
        return rc == 0 ? outLength.value : null;
      } finally {
        calloc.free(outLength);
      }
    }, ciphertext.length - CryptoProvider.aeadTagLength);
  }

  /// Копирует аргументы в нативную память, вызывает [call] и забирает
  /// [outCapacity] байт результата. Копия ключа затирается.
  static Uint8List? _ietf(
    SecretBytes key,
    Uint8List nonce,
    Uint8List aad,
    Uint8List input,
    int? Function(
      Pointer<UnsignedChar> key,
      Pointer<UnsignedChar> nonce,
      Pointer<UnsignedChar> aad,
      Pointer<UnsignedChar> input,
      Pointer<UnsignedChar> out,
    )
    call,
    int outCapacity,
  ) => using((arena) {
    Pointer<UnsignedChar> copy(Uint8List bytes) {
      // Пустой буфер — ненулевой указатель: libsodium его не читает.
      final p = arena<Uint8>(bytes.isEmpty ? 1 : bytes.length);
      p.asTypedList(bytes.length).setAll(0, bytes);
      return p.cast();
    }

    final k = arena<Uint8>(CryptoProvider.keyLength);
    try {
      k.asTypedList(CryptoProvider.keyLength).setAll(0, key.bytes);
      final out = arena<Uint8>(outCapacity == 0 ? 1 : outCapacity);
      final length = call(
        k.cast(),
        copy(nonce),
        copy(aad),
        copy(input),
        out.cast(),
      );
      return length == null
          ? null
          : Uint8List.fromList(out.asTypedList(length));
    } finally {
      k
          .asTypedList(CryptoProvider.keyLength)
          .fillRange(0, CryptoProvider.keyLength, 0);
    }
  });

  @override
  Uint8List blake2b512(Uint8List data) => _own(
    _sodium.crypto.genericHash(
      message: data,
      outLen: CryptoProvider.blake2b512Length,
    ),
  );

  @override
  Uint8List blake2b256(Uint8List data, {SecretBytes? key}) {
    final hash = _sodium.crypto.genericHash;
    if (key == null) {
      return _own(hash(message: data, outLen: CryptoProvider.hashLength));
    }
    _checkLength(key.length, CryptoProvider.keyLength, 'key');
    return _withKey(
      key,
      (k) =>
          _own(hash(message: data, outLen: CryptoProvider.hashLength, key: k)),
    );
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
    if (params.parallelism != 1) {
      throw ArgumentError.value(
        params.parallelism,
        'params.parallelism',
        'libsodium поддерживает только p = 1',
      );
    }
    _checkLength(salt.length, 16, 'salt');
    // Сотни миллисекунд и 256 МиБ памяти — в отдельном isolate, чтобы не
    // останавливать цикл событий (прогресс CLI, интерфейс).
    final memoryKiB = params.memoryKiB;
    final iterations = params.iterations;
    final out = await Isolate.run(
      () => _argon2idInIsolate(password, salt, memoryKiB, iterations, length),
    );
    return SecretBytes.adopt(out);
  }

  @override
  Future<Ed25519KeyPair> ed25519FromSeed(SecretBytes seed) async {
    _checkLength(seed.length, 32, 'seed');
    final pair = _withKey(seed, _sodium.crypto.sign.seedKeyPair);
    pair.secretKey.dispose();
    return Ed25519KeyPair(
      seed: SecretBytes(seed.bytes),
      publicKey: _own(pair.publicKey),
    );
  }

  @override
  Future<Ed25519Signer> ed25519Signer(Ed25519KeyPair keyPair) async =>
      _SodiumSigner(
        _sodium,
        _withKey(keyPair.seed, _sodium.crypto.sign.seedKeyPair).secretKey,
        Uint8List.fromList(keyPair.publicKey),
      );

  @override
  Future<Uint8List> ed25519Sign(
    Ed25519KeyPair keyPair,
    Uint8List message,
  ) async {
    final pair = _withKey(keyPair.seed, _sodium.crypto.sign.seedKeyPair);
    try {
      return _own(
        _sodium.crypto.sign.detached(
          message: message,
          secretKey: pair.secretKey,
        ),
      );
    } finally {
      pair.secretKey.dispose();
    }
  }

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
    return _sodium.crypto.sign.verifyDetached(
      message: message,
      signature: signature,
      publicKey: publicKey,
    );
  }

  @override
  Future<X25519KeyPair> x25519FromSecret(SecretBytes secretKey) async {
    _checkLength(secretKey.length, 32, 'secretKey');
    final public = _withKey(
      secretKey,
      (k) => _sodium.crypto.scalarmult.base(n: k),
    );
    return X25519KeyPair(
      secretKey: SecretBytes(secretKey.bytes),
      publicKey: _own(public),
    );
  }

  @override
  Future<SecretBytes> x25519({
    required SecretBytes secretKey,
    required Uint8List publicKey,
  }) async {
    _checkLength(secretKey.length, 32, 'secretKey');
    _checkLength(publicKey.length, 32, 'publicKey');
    return _withKey<SecretBytes>(secretKey, (k) {
      final SecureKey shared;
      try {
        shared = _sodium.crypto.scalarmult(n: k, p: publicKey);
      } on SodiumException {
        throw _lowOrderPoint;
      }
      try {
        return SecretBytes.adopt(shared.extractBytes());
      } finally {
        shared.dispose();
      }
    });
  }

  @override
  Uint8List randomBytes(int length) {
    RangeError.checkNotNegative(length, 'length');
    return length == 0 ? Uint8List(0) : _own(_sodium.randombytes.buf(length));
  }

  /// Копия результата `sodium` в обычной памяти Dart (см. описание класса).
  static Uint8List _own(Uint8List native) => Uint8List.fromList(native);

  /// Временный [SecureKey] (защищённая память libsodium) на время вызова.
  T _withKey<T>(SecretBytes key, T Function(SecureKey key) body) {
    final secure = SecureKey.fromList(_sodium, key.bytes);
    try {
      return body(secure);
    } finally {
      secure.dispose();
    }
  }
}

Future<Uint8List> _argon2idInIsolate(
  Uint8List password,
  Uint8List salt,
  int memoryKiB,
  int iterations,
  int length,
) async {
  final sodium = await SodiumSumoInit.init();
  final key = sodium.crypto.pwhash.callRaw(
    outLen: length,
    password: Int8List.sublistView(password),
    salt: salt,
    opsLimit: iterations,
    memLimit: memoryKiB * 1024,
    alg: CryptoPwhashAlgorithm.argon2id13,
  );
  try {
    return key.extractBytes();
  } finally {
    key.dispose();
  }
}

const _lowOrderPoint = DataFormatException(
  object: 'x25519-public-key',
  problem: FormatProblem.invalidField,
  detail: 'точка малого порядка',
);

void _checkLength(int actual, int expected, String name) {
  if (actual != expected) {
    throw ArgumentError('$name: нужно $expected байт, получено $actual');
  }
}

/// Закрытый ключ Ed25519 в защищённой памяти libsodium на всё время жизни:
/// без выделения защищённой памяти и вывода ключа из seed на каждую
/// подпись (в 7 раз быстрее, нагрузочный тест 2.9.3).
final class _SodiumSigner implements Ed25519Signer {
  new(this._sodium, this._secretKey, this.publicKey);

  final Sodium _sodium;
  final SecureKey _secretKey;

  @override
  final Uint8List publicKey;

  @override
  Future<Uint8List> sign(Uint8List message) async => Uint8List.fromList(
    _sodium.crypto.sign.detached(message: message, secretKey: _secretKey),
  );

  @override
  void dispose() => _secretKey.dispose();
}
