import 'dart:typed_data';

import 'package:core/src/crypto/crypto_provider.dart';
import 'package:core/src/util/bytes.dart';

/// Открытые ключи координатора, вшитые в приложение (protocol.md,
/// раздел 5.1): hex, по одному на ключ, с идентификатором в комментарии.
/// При ротации здесь два ключа (`docs/ops/coordinator.md`, раздел
/// «Ротация ключа»).
///
/// Пусто, пока нет тестового координатора (задача 2.9.4): клиенту и узлу
/// тестового стенда список задаётся настройкой.
const List<String> builtInCoordinatorKeys = [];

/// Список ключей координатора, которым доверяют клиент и узел.
final class CoordinatorKeySet {
  new(Iterable<Uint8List> keys)
    : _keys = {
        for (final k in keys)
          if (k.length == CryptoProvider.keyLength)
            bytesToHex(k)
          else
            throw ArgumentError('ключ координатора — 32 байта'),
      };

  /// Из hex-строк (вшитый список, настройки).
  factory fromHex(Iterable<String> keys) =>
      CoordinatorKeySet([for (final k in keys) hexToBytes(k)]);

  /// Вшитый список [builtInCoordinatorKeys].
  static final CoordinatorKeySet builtIn = CoordinatorKeySet.fromHex(
    builtInCoordinatorKeys,
  );

  final Set<String> _keys;

  bool get isEmpty => _keys.isEmpty;

  bool trusts(List<int> publicKey) => _keys.contains(bytesToHex(publicKey));

  /// Идентификатор ключа: первые 8 байт `H(ключ)` в hex — для журналов и
  /// процедур ротации.
  static String keyId(CryptoProvider crypto, List<int> publicKey) => bytesToHex(
    crypto.blake2b256(Uint8List.fromList(publicKey)).sublist(0, 8),
  );
}
