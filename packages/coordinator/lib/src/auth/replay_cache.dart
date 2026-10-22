import 'dart:collection';
import 'dart:typed_data';

/// Принятые подписи запросов, пока их время в окне (protocol.md,
/// раздел 4.2, шаг 5). Живёт в памяти процесса: координатор MVP — один
/// процесс. При нескольких процессах понадобится общее хранилище.
final class ReplayCache {
  new({
    required this.capacity,
    this.sweepInterval = const Duration(seconds: 10),
  });

  /// Предел числа подписей. Его достигают только при нагрузке выше
  /// ограничения частоты; тогда новые запросы отклоняются, а не вытесняют
  /// старые подписи (иначе вытесненную можно было бы повторить).
  final int capacity;

  final Duration sweepInterval;

  final _expiry = HashMap<String, int>();
  int _lastSweepMs = 0;

  int get length => _expiry.length;

  /// Запоминает подпись до [expiresAtMs]. `false` — такая подпись уже была.
  /// Бросает [ReplayCacheFullException], если места нет.
  bool remember(
    Uint8List signature, {
    required int expiresAtMs,
    required int nowMs,
  }) {
    if (nowMs - _lastSweepMs >= sweepInterval.inMilliseconds ||
        _expiry.length >= capacity) {
      _sweep(nowMs);
    }
    final key = String.fromCharCodes(signature);
    final known = _expiry[key];
    if (known != null && known >= nowMs) return false;
    if (known == null && _expiry.length >= capacity) {
      throw const ReplayCacheFullException();
    }
    _expiry[key] = expiresAtMs;
    return true;
  }

  void _sweep(int nowMs) {
    _lastSweepMs = nowMs;
    _expiry.removeWhere((_, expires) => expires < nowMs);
  }
}

final class ReplayCacheFullException implements Exception {
  const new();
}
