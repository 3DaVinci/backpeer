import 'dart:io';

/// Проброс порта на роутере (задача 3.5.2).
final class PortMapping {
  const new({
    required this.method,
    required this.internalPort,
    required this.externalPort,
    required this.lifetime,
    required this.createdAt,
    this.externalAddress,
  });

  /// `upnp`, `pcp` или `nat-pmp`.
  final String method;
  final int internalPort;
  final int externalPort;

  /// Внешний адрес роутера, если он его сообщил: частный — двойной NAT
  /// или NAT провайдера, и проброс узлу не поможет.
  final InternetAddress? externalAddress;

  /// Срок аренды; [Duration.zero] — бессрочно (UPnP-роутеры, которые не
  /// умеют аренду со сроком).
  final Duration lifetime;
  final DateTime createdAt;

  Map<String, Object?> toJson() => {
    'method': method,
    'internalPort': internalPort,
    'externalPort': externalPort,
    'externalAddress': externalAddress?.address,
    'lifetimeSeconds': lifetime.inSeconds,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };
}

/// Протокол проброса: UPnP IGD или PCP с откатом на NAT-PMP.
abstract interface class PortMappingProtocol {
  /// Для журнала и [PortMapping.method].
  String get name;

  /// Пробрасывает внешний TCP-порт [externalPort] (пожелание: роутер
  /// может дать другой) на свой порт [internalPort] на [lifetime].
  /// Повторный вызов с теми же портами продлевает аренду. Неудача —
  /// [PortMappingException].
  Future<PortMapping> map({
    required int internalPort,
    required int externalPort,
    required Duration lifetime,
  });

  /// Снимает проброс; ошибки — [PortMappingException].
  Future<void> unmap(PortMapping mapping);

  /// Закрывает сокеты и HTTP-клиент.
  void close();
}

/// Проброс не удался. [unsupported] — на этой сети протокола нет
/// (никто не ответил), а не отказ роутера.
final class PortMappingException implements Exception {
  const new(this.message, {this.unsupported = false, this.conflict = false});

  final String message;
  final bool unsupported;

  /// Внешний порт занят другим пробросом: стоит попросить другой.
  final bool conflict;

  @override
  String toString() => 'PortMappingException: $message';
}
