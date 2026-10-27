import 'dart:typed_data';

import 'package:core/core.dart';

/// Relay из настроек координатора (`relay.servers`): имя, адрес для
/// клиентов и узлов и открытый ключ, которым relay подписывает отчёты.
final class RelayServerInfo {
  const new({
    required this.name,
    required this.endpoint,
    required this.publicKey,
  });

  /// Из строки `<имя> <хост:порт> <ключ hex>`; ошибка —
  /// [FormatException].
  factory parse(String line) {
    final parts = line.trim().split(RegExp(r'\s+'));
    if (parts.length != 3) {
      throw const FormatException('ожидается «имя хост:порт ключ»');
    }
    final [name, endpoint, key] = parts;
    if (!RelayWire.relayName.hasMatch(name)) {
      throw FormatException('имя relay «$name»: a–z, 0–9, «.», «-»');
    }
    if (splitHostPort(endpoint) == null) {
      throw FormatException('адрес relay «$endpoint»: хост:порт');
    }
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(key)) {
      throw const FormatException('ключ relay — 64 hex-символа');
    }
    return RelayServerInfo(
      name: name,
      endpoint: endpoint,
      publicKey: hexToBytes(key),
    );
  }

  final String name;

  /// `хост:порт` для TCP.
  final String endpoint;
  final Uint8List publicKey;
}

/// Настройки relay на координаторе (задачи 3.8.2, 3.8.3;
/// `docs/ops/coordinator.md`, раздел «Relay»).
final class RelayPolicy {
  const new({
    this.servers = const [],
    this.passKeyFile,
    this.passLifetime = const Duration(minutes: 60),
    this.passBytes = 1 << 30,
    this.accountBytesPerDay = 10 << 30,
    this.reportInterval = const Duration(seconds: 60),
    this.perMinute = 60,
    this.burst = 30,
  });

  final List<RelayServerInfo> servers;

  /// Файл ключа пропусков (Ed25519, права 0600); его открытый ключ —
  /// в `pass_keys` каждого relay.
  final String? passKeyFile;

  /// Срок пропуска: узел продлевает LISTEN заранее, клиент берёт
  /// CONNECT под ближайшие соединения.
  final Duration passLifetime;

  /// Предел байт на один пропуск CONNECT.
  final int passBytes;

  /// Предел байт через relay на учётную запись за сутки UTC.
  final int accountBytesPerDay;

  /// Период отчётов relay (`ReportRelayUsageResponse.next_report_ms`).
  final Duration reportInterval;

  /// Пропусков в минуту на ключ и запас.
  final int perMinute;
  final int burst;

  bool get enabled => servers.isNotEmpty && passKeyFile != null;

  RelayServerInfo? byName(String name) {
    for (final s in servers) {
      if (s.name == name) return s;
    }
    return null;
  }

  RelayServerInfo? byKey(List<int> publicKey) {
    for (final s in servers) {
      if (constantTimeEquals(s.publicKey, publicKey)) return s;
    }
    return null;
  }
}
