/// Настройки размещения фрагментов и талонов (protocol.md, раздел 5).
final class PlacementPolicy {
  const new({
    this.minAvailability = 0.6,
    this.probation = const Duration(hours: 72),
    this.maxProbationShare = 0.25,
    this.ticketLifetime = const Duration(minutes: 30),
    this.distinctSubnets = true,
    this.candidatesCache = const Duration(seconds: 1),
  });

  /// Порог доступности хранителя (`mvp-scope.md`).
  final double minAvailability;

  /// Испытательный срок узла после регистрации (модель угроз, С-6).
  final Duration probation;

  /// Доля фрагментов сегмента, которую могут получить узлы на
  /// испытательном сроке: при 0,25 и n = 20 — не больше 5.
  final double maxProbationShare;

  /// Срок жизни талонов: не больше часа (`FragmentTickets.maxLifetime`) и
  /// не больше предела подписанта.
  final Duration ticketLifetime;

  /// Подсети узлов сегмента различны. Выключается только на локальном
  /// стенде, где все узлы-заглушки приходят с одного адреса
  /// (`docs/ops/coordinator.md`, раздел «Docker»); координатор тогда
  /// предупреждает в журнале при запуске.
  final bool distinctSubnets;

  /// Сколько живёт кэш узлов в сети для размещения (`NodeService`):
  /// новые узлы, heartbeat и исключение узла видны с этой задержкой.
  final Duration candidatesCache;

  /// Узлов на испытательном сроке в сегменте из [n] фрагментов.
  int maxProbation(int n) => (n * maxProbationShare).floor();
}
