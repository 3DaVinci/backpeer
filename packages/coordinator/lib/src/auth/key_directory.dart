import 'dart:typed_data';

import 'package:core/core.dart';

/// Вид ключа, которым подписан запрос (protocol.md, раздел 4.3).
enum KeyKind { account, device, node }

/// Что координатор знает о ключе.
final class KeyInfo {
  const new({
    required this.kind,
    required this.accountId,
    this.revoked = false,
  });

  final KeyKind kind;

  /// Учётная запись: сама (для [KeyKind.account]), владелец устройства или
  /// узла.
  final Uint8List accountId;

  /// Устройство отозвано или узел удалён.
  final bool revoked;
}

/// Источник сведений о ключах для проверки `FS-Auth`.
abstract interface class KeyDirectory {
  /// `null` — ключ неизвестен.
  Future<KeyInfo?> lookup(Uint8List publicKey);
}

/// Справочник в памяти — для тестов и заглушек.
final class InMemoryKeyDirectory implements KeyDirectory {
  final _keys = <String, KeyInfo>{};

  void put(Uint8List publicKey, KeyInfo info) =>
      _keys[bytesToHex(publicKey)] = info;

  @override
  Future<KeyInfo?> lookup(Uint8List publicKey) async =>
      _keys[bytesToHex(publicKey)];
}
