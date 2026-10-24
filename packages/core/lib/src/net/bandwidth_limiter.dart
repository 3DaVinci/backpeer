import 'dart:async';
import 'dart:math';

import 'package:meta/meta.dart';

/// Предел скорости передачи («ведро токенов» с долгом): [acquire] берёт
/// байты сразу и, если ведро ушло в минус, ждёт, пока долг не погасится.
/// Параллельные передачи делят один предел: каждая следующая ждёт и за
/// долг предыдущих.
///
/// Ведро начинается пустым, а за время простоя набирает не больше
/// [burst] работы на текущем пределе (но не меньше [minBurstBytes]): на
/// длинной передаче средняя скорость совпадает с пределом с точностью до
/// одного такого запаса.
final class BandwidthLimiter {
  new(
    this.bytesPerSecond, {
    this.burst = defaultBurst,
    @visibleForTesting Duration Function()? elapsed,
  }) : _elapsed = elapsed ?? (Stopwatch()..start()).elapsedFunction;

  static const Duration defaultBurst = Duration(milliseconds: 100);

  /// Одна часть фрагмента с запасом: проходит без ожидания после паузы.
  static const int minBurstBytes = 64 * 1024;

  /// Предел, байт в секунду; 0 и меньше — без предела. Функция, потому
  /// что предел меняется по расписанию и из локального API.
  final int Function() bytesPerSecond;

  final Duration burst;
  final Duration Function() _elapsed;
  double _tokens = 0;
  int? _lastMicros;

  /// Разрешение передать [bytes] байт: завершается, когда их можно
  /// отправлять.
  Future<void> acquire(int bytes) {
    final rate = bytesPerSecond();
    final now = _elapsed().inMicroseconds;
    if (rate <= 0) {
      _lastMicros = null;
      _tokens = 0;
      return Future.value();
    }
    final capacity = max(
      rate * burst.inMicroseconds / Duration.microsecondsPerSecond,
      minBurstBytes.toDouble(),
    );
    if (_lastMicros case final last?) {
      _tokens = min(
        capacity,
        _tokens + (now - last) * rate / Duration.microsecondsPerSecond,
      );
    }
    _lastMicros = now;
    _tokens -= bytes;
    if (_tokens >= 0) return Future.value();
    return Future.delayed(
      Duration(
        microseconds: (-_tokens * Duration.microsecondsPerSecond / rate).ceil(),
      ),
    );
  }
}

extension on Stopwatch {
  Duration Function() get elapsedFunction =>
      () => elapsed;
}
