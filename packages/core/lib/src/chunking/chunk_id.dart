import 'dart:typed_data';

import 'package:core/src/crypto/crypto_provider.dart';
import 'package:core/src/crypto/secret_bytes.dart';
import 'package:core/src/util/bytes.dart';
import 'package:meta/meta.dart';

/// Идентификатор чанка: `H_{K_chunk_id}(открытый текст чанка)`, 32 байта
/// (crypto.md, раздел 6). Ключевой хэш не даёт хранителю и координатору
/// проверить, есть ли у пользователя известный файл.
@immutable
final class ChunkId {
  /// Из 32 байт (копируются), например из индекса.
  factory(List<int> bytes) {
    if (bytes.length != length) {
      throw ArgumentError('chunk_id — $length байта, получено ${bytes.length}');
    }
    return ChunkId._(Uint8List.fromList(bytes));
  }

  const new _(this._bytes);

  static const int length = 32;

  final Uint8List _bytes;

  /// Копия байтов.
  Uint8List get bytes => Uint8List.fromList(_bytes);

  @override
  bool operator ==(Object other) {
    if (other is! ChunkId) return false;
    for (var i = 0; i < length; i++) {
      if (_bytes[i] != other._bytes[i]) return false;
    }
    return true;
  }

  /// Первые 8 байт: значение — криптографический хэш, распределено
  /// равномерно.
  @override
  int get hashCode =>
      ByteData.sublistView(_bytes, 0, 8).getInt64(0, Endian.little);

  @override
  String toString() => bytesToHex(_bytes);
}

/// Вычисляет [ChunkId] ключом `K_chunk_id` учётной записи.
final class ChunkIdHasher {
  new(this._crypto, this._key) {
    if (_key.length != CryptoProvider.keyLength) {
      throw ArgumentError('K_chunk_id — ${CryptoProvider.keyLength} байта');
    }
  }

  final CryptoProvider _crypto;
  final SecretBytes _key;

  ChunkId of(Uint8List chunk) =>
      ChunkId._(_crypto.blake2b256(chunk, key: _key));
}
