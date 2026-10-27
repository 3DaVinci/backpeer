/// Настройки размещения фрагментов и талонов (protocol.md, раздел 5).
final class PlacementPolicy {
  const new({
    this.minAvailability = 0.6,
    this.probation = const Duration(hours: 72),
    this.maxProbationShare = 0.25,
    this.probationMaxBytes = 10 * 1000 * 1000 * 1000,
    this.minReputation = 0.05,
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

  /// Сколько байт фрагментов узел может получить за испытательный срок:
  /// новый узел сначала получает небольшую долю фрагментов (задача
  /// 4.2.2), 10 ГБ — десятая часть минимальной ёмкости хранителя.
  final int probationMaxBytes;

  /// Порог репутации (`Reputation`, `docs/spec/reputation.md`): узел с
  /// меньшей новых фрагментов не получает.
  final double minReputation;

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

  /// Узлов на испытательном сроке в сегменте из [n] фрагментов, из них
  /// [k] — данные: новые узлы получают только чётность (задача 4.2.2),
  /// поэтому их не больше n − k.
  int maxProbation(int n, [int k = 0]) {
    final share = (n * maxProbationShare).floor();
    return share < n - k ? share : n - k;
  }
}
