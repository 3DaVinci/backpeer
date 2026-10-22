import 'dart:collection';
import 'dart:math' as math;

/// Ограничение частоты «ведром токенов» по строковому ключу (IP-адрес или
/// ключ подписи, protocol.md, раздел 4.5). Ведро вмещает [burst] запросов
/// и пополняется со скоростью [perSecond].
final class RateLimiter {
  new({
    required this.perSecond,
    required this.burst,
    this.maxKeys = 100000,
    DateTime Function()? clock,
  }) : assert(perSecond > 0 && burst >= 1, 'неверные пределы'),
       _clock = clock ?? DateTime.now;

  final double perSecond;
  final int burst;

  /// Сколько вёдер держать в памяти. Полные (давно не тронутые) вёдра
  /// удаляются: их состояние совпадает с новым ведром.
  final int maxKeys;

  final DateTime Function() _clock;
  final _buckets = HashMap<String, _Bucket>();
  int _lastSweepUs = 0;

  int get trackedKeys => _buckets.length;

  /// `null` — запрос разрешён ([cost] токенов списано); иначе — через
  /// сколько появятся токены. [cost] не больше [burst].
  Duration? take(String key, {int cost = 1}) {
    if (cost < 1 || cost > burst) {
      throw ArgumentError.value(cost, 'cost', 'вне 1…$burst');
    }
    final nowUs = _clock().microsecondsSinceEpoch;
    _maybeSweep(nowUs);
    var bucket = _buckets[key];
    if (bucket == null) {
      if (_buckets.length >= maxKeys) {
        // Таблица заполнена активными ключами: новым отказываем, пока
        // вёдра не наполнятся.
        return const Duration(seconds: 1);
      }
      bucket = _buckets[key] = _Bucket(burst.toDouble(), nowUs);
    }
    bucket.refill(nowUs, perSecond, burst);
    if (bucket.tokens >= cost) {
      bucket.tokens -= cost;
      return null;
    }
    final waitUs = ((cost - bucket.tokens) / perSecond * 1e6).ceil();
    return Duration(microseconds: math.max(waitUs, 1000));
  }

  void _maybeSweep(int nowUs) {
    // Ведро наполняется целиком за burst / perSecond секунд.
    final fullAfterUs = (burst / perSecond * 1e6).ceil();
    // Заполненную таблицу чистим чаще, но не чаще раза в секунду: обход
    // всех вёдер на каждый запрос стал бы уязвимостью сам по себе.
    final intervalUs = _buckets.length >= maxKeys
        ? 1000000
        : math.max(fullAfterUs, 1000000);
    if (nowUs - _lastSweepUs < intervalUs) return;
    _lastSweepUs = nowUs;
    _buckets.removeWhere((_, b) => nowUs - b.updatedUs >= fullAfterUs);
  }
}

final class _Bucket {
  new(this.tokens, this.updatedUs);

  double tokens;
  int updatedUs;

  void refill(int nowUs, double perSecond, int burst) {
    if (nowUs > updatedUs) {
      tokens = math.min(
        burst.toDouble(),
        tokens + (nowUs - updatedUs) / 1e6 * perSecond,
      );
      updatedUs = nowUs;
    }
  }
}
