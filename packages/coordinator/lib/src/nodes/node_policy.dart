/// Настройки реестра узлов.
final class NodePolicy {
  const new({
    this.minCapacityBytes = 100 * 1000 * 1000 * 1000,
    this.maxPerAccount = 20,
    this.heartbeatInterval = const Duration(minutes: 5),
  });

  /// Минимум места у хранителя (`mvp-scope.md`: 100 ГБ).
  final int minCapacityBytes;

  /// Действующих узлов на учётную запись владельца.
  final int maxPerAccount;

  /// Период heartbeat, который координатор сообщает узлу.
  final Duration heartbeatInterval;

  /// Узел в сети, если последний heartbeat не старше трёх периодов.
  Duration get onlineWindow => heartbeatInterval * 3;
}
