import 'dart:typed_data';

import 'package:core/core.dart';

/// Вид ключа, которым подписан запрос (protocol.md, раздел 4.3). Ключи
/// relay — не в базе, а в настройках (`relay.servers`, [RelayKeyDirectory]).
enum KeyKind { account, device, node, relay }

/// Что координатор знает о ключе.
final class KeyInfo {
  const new({
    required this.kind,
    required this.accountId,
    this.revoked = false,
    this.blocked = false,
  });

  final KeyKind kind;

  /// Учётная запись: сама (для [KeyKind.account]), владелец устройства или
  /// узла; у relay пусто.
  final Uint8List accountId;

  /// Устройство отозвано или узел удалён.
  final bool revoked;

  /// Учётная запись заблокирована оператором (`coordinator admin account
  /// block`): любой подписанный запрос её ключей — `PERMISSION_DENIED`.
  final bool blocked;
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

/// Ключи relay из настроек поверх справочника [inner]: отчёты relay
/// (`ReportRelayUsage`) подписаны ими.
final class RelayKeyDirectory implements KeyDirectory {
  new(this.inner, Iterable<Uint8List> relayKeys)
    : _relays = {for (final k in relayKeys) bytesToHex(k)};

  final KeyDirectory inner;
  final Set<String> _relays;

  static final _noAccount = Uint8List(0);

  @override
  Future<KeyInfo?> lookup(Uint8List publicKey) async {
    if (_relays.contains(bytesToHex(publicKey))) {
      return KeyInfo(kind: KeyKind.relay, accountId: _noAccount);
    }
    return await inner.lookup(publicKey);
  }
}
