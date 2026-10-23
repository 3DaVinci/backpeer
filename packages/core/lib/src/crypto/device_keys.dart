import 'dart:typed_data';

import 'package:core/src/crypto/crypto_provider.dart';
import 'package:core/src/crypto/secret_bytes.dart';

/// Ключи устройства (crypto.md, раздел 3.4): `device_sign` (Ed25519) —
/// подпись запросов к координатору, `device_dh` (X25519) — статический
/// ключ транспорта Noise. Случайные, создаются при установке; хранятся
/// локально под паролем (`DeviceKeyStore`, блоб типа 6).
final class DeviceKeys {
  const new _(this.sign, this.dh);

  /// Длина сериализованных закрытых ключей: seed Ed25519 и ключ X25519.
  static const secretLength = 64;

  static Future<DeviceKeys> generate(CryptoProvider crypto) async {
    final secret = SecretBytes(crypto.randomBytes(secretLength));
    try {
      return await fromSecret(crypto, secret);
    } finally {
      secret.dispose();
    }
  }

  /// Ключи из [secret] (64 байта: seed `device_sign`, закрытый
  /// `device_dh`); [secret] остаётся у вызывающего.
  static Future<DeviceKeys> fromSecret(
    CryptoProvider crypto,
    SecretBytes secret,
  ) async {
    if (secret.length != secretLength) {
      throw ArgumentError('ключи устройства — $secretLength байта');
    }
    final signSeed = SecretBytes(secret.bytes.sublist(0, 32));
    final dhSecret = SecretBytes(secret.bytes.sublist(32));
    try {
      return DeviceKeys._(
        await crypto.ed25519FromSeed(signSeed),
        await crypto.x25519FromSecret(dhSecret),
      );
    } finally {
      signSeed.dispose();
      dhSecret.dispose();
    }
  }

  final Ed25519KeyPair sign;
  final X25519KeyPair dh;

  /// Идентификатор устройства для координатора — открытый `device_sign`.
  Uint8List get deviceId => sign.publicKey;

  /// Закрытые ключи для хранения; затирает вызывающий.
  SecretBytes toSecret() => SecretBytes(
    Uint8List(secretLength)
      ..setAll(0, sign.seed.bytes)
      ..setAll(32, dh.secretKey.bytes),
  );

  void dispose() {
    sign.seed.dispose();
    dh.secretKey.dispose();
  }

  @override
  String toString() => 'DeviceKeys(…)';
}
