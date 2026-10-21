import 'dart:convert';
import 'dart:typed_data';

import 'package:core/src/crypto/crypto_provider.dart';
import 'package:core/src/crypto/recovery_phrase.dart';
import 'package:core/src/crypto/secret_bytes.dart';

/// Ключи учётной записи по docs/spec/crypto.md, раздел 3: мастер-ключ и
/// производные от него. Все секреты — [SecretBytes]; [toString] их не
/// показывает, [dispose] затирает.
final class AccountKeys {
  new _({
    required this._crypto,
    required this.masterKey,
    required this.manifestKey,
    required this.dataKey,
    required this.chunkIdKey,
    required this.gearKey,
    required this.accountSign,
  });

  /// Ключи из фразы восстановления: фраза → seed → мастер-ключ.
  static Future<AccountKeys> fromPhrase(
    RecoveryPhrase phrase,
    CryptoProvider crypto,
  ) async {
    final seed = await phrase.seed(crypto);
    try {
      final masterKey = crypto.hkdfSha256(
        ikm: seed,
        salt: _label('fs/v1/master-salt'),
        info: _label('fs/v1/master'),
      );
      return await fromMasterKey(masterKey, crypto);
    } finally {
      seed.dispose();
    }
  }

  /// Ключи из мастер-ключа (например, расшифрованного из KeyBundle).
  /// [masterKey] переходит во владение результата.
  static Future<AccountKeys> fromMasterKey(
    SecretBytes masterKey,
    CryptoProvider crypto,
  ) async {
    if (masterKey.length != CryptoProvider.keyLength) {
      throw ArgumentError('Мастер-ключ — ${CryptoProvider.keyLength} байта');
    }
    SecretBytes derive(String label) => crypto.hkdfSha256(
      ikm: masterKey,
      salt: Uint8List(0),
      info: _label(label),
    );
    final signSeed = derive('fs/v1/account-sign');
    final accountSign = await crypto.ed25519FromSeed(signSeed);
    signSeed.dispose();
    return AccountKeys._(
      crypto: crypto,
      masterKey: masterKey,
      manifestKey: derive('fs/v1/manifest'),
      dataKey: derive('fs/v1/data'),
      chunkIdKey: derive('fs/v1/chunk-id'),
      gearKey: derive('fs/v1/chunk-gear'),
      accountSign: accountSign,
    );
  }

  final CryptoProvider _crypto;

  /// `MK`.
  final SecretBytes masterKey;

  /// `K_manifest`: AEAD снимков и индексов.
  final SecretBytes manifestKey;

  /// `K_data`: корень ключей сегментов.
  final SecretBytes dataKey;

  /// `K_chunk_id`: ключ BLAKE2b идентификаторов чанков.
  final SecretBytes chunkIdKey;

  /// `K_gear`: ключ таблицы gear FastCDC.
  final SecretBytes gearKey;

  /// Ключ подписи учётной записи (Ed25519, seed `account_sign_seed`).
  final Ed25519KeyPair accountSign;

  /// Идентификатор учётной записи — открытый ключ [accountSign].
  Uint8List get accountId => accountSign.publicKey;

  /// `K_seg(segment_id)`; [segmentId] — 32 байта.
  SecretBytes segmentKey(Uint8List segmentId) {
    if (segmentId.length != 32) {
      throw ArgumentError(
        'segment_id — 32 байта, получено ${segmentId.length}',
      );
    }
    final prefix = _label('fs/v1/segment');
    return _crypto.hkdfSha256(
      ikm: dataKey,
      salt: Uint8List(0),
      info: Uint8List(prefix.length + 32)
        ..setAll(0, prefix)
        ..setAll(prefix.length, segmentId),
    );
  }

  void dispose() {
    for (final key in [
      masterKey,
      manifestKey,
      dataKey,
      chunkIdKey,
      gearKey,
      accountSign.seed,
    ]) {
      key.dispose();
    }
  }

  @override
  String toString() => 'AccountKeys(…)';
}

Uint8List _label(String label) => ascii.encode(label);
