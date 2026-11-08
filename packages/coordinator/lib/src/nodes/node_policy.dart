/// Настройки реестра узлов.
final class NodePolicy {
  const new({
    this.minCapacityBytes = 10 * 1000 * 1000 * 1000,
    this.maxPerAccount = 20,
    this.heartbeatInterval = const Duration(minutes: 5),
    this.checkPrivateAddresses = false,
    this.reachabilityTimeout = const Duration(seconds: 5),
    this.maxReachabilityChecks = 64,
  });

  /// Минимум места у хранителя (`mvp-scope.md`: 10 ГБ).
  final int minCapacityBytes;

  /// Действующих узлов на учётную запись владельца.
  final int maxPerAccount;

  /// Период heartbeat, который координатор сообщает узлу.
  final Duration heartbeatInterval;

  /// Проверять достижимость узлов с частных, loopback- и link-local
  /// адресов (`CheckReachability`, задача 3.5.1). Только для стендов, где
  /// узлы и координатор в одной сети: в бою узел с частного адреса
  /// направлял бы соединения координатора во внутреннюю сеть.
  final bool checkPrivateAddresses;

  /// Сколько ждать соединения и второго сообщения Noise от узла.
  final Duration reachabilityTimeout;

  /// Одновременных проверок портов на весь координатор; сверх —
  /// `UNAVAILABLE`.
  final int maxReachabilityChecks;

  /// Узел в сети, если последний heartbeat не старше трёх периодов.
  Duration get onlineWindow => heartbeatInterval * 3;
}
