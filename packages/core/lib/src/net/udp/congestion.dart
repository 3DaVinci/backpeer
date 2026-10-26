import 'dart:math' as math;

import 'package:core/src/net/udp/udp_packets.dart';

/// Управление перегрузкой потока поверх UDP: сколько байт может быть в
/// пути ([window]).
abstract interface class CongestionControl {
  /// Окно перегрузки, байт.
  int get window;

  /// Подтверждено [ackedBytes] новых байт. [flightBytes] — сколько было в
  /// пути до этого подтверждения; [delaySample] — задержка пакетов в одну
  /// сторону по измерению получателя, микросекунды по модулю 2^32 (со
  /// сдвигом часов, поэтому важны только разности); [rtt] — время до
  /// подтверждения, если измерено.
  void onAck({
    required int ackedBytes,
    required int flightBytes,
    int? delaySample,
    Duration? rtt,
  });

  /// Потеря пакета; вызывается не чаще раза за время в пути.
  void onLoss();

  /// Истёк таймаут повторной отправки.
  void onTimeout();

  /// Состояние для журнала и тестов.
  Map<String, Object?> toJson();
}

/// «Вежливое» управление перегрузкой в духе LEDBAT (RFC 6817) и LEDBAT++
/// (draft-irtf-iccrg-ledbat-plus-plus), как у uTP: окно растёт, пока
/// очередь на пути (задержка сверх наименьшей) меньше [target], и
/// сокращается, когда очередь её превышает. Обычный поток TCP — браузер,
/// видеозвонок — заполняет очередь роутера, и бэкап уступает ему канал;
/// сам бэкап держит очередь не длиннее [target].
///
/// - Медленный старт, пока очередь меньше трёх четвертей [target] и не было
///   потерь (LEDBAT++).
/// - Рост: `GAIN · off_target · MSS · acked / cwnd` (RFC 6817), не больше
///   двух пакетов сверх того, что было в пути.
/// - Очередь больше [target]: мультипликативное сокращение LEDBAT++ —
///   за время в пути окно уменьшается на `cwnd · (очередь / target − 1)`, но
///   не больше чем вдвое.
/// - Потеря — окно вдвое, таймаут — один пакет, как у TCP.
/// - Наименьшая задержка — минимум за 10 минут (по минутным корзинам),
///   текущая — минимум четырёх последних измерений.
final class Ledbat implements CongestionControl {
  new({
    this.target = const Duration(milliseconds: 100),
    this.gain = 1.0,
    this.maxWindow = 16 << 20,
    int Function()? clockMicros,
  }) : _clock = clockMicros ?? _monotonic,
       _window = 4.0 * _mss;

  final Duration target;
  final double gain;
  final int maxWindow;
  final int Function() _clock;

  static const int _mss = StreamPacket.maxPayload;
  static const int _minWindow = 2 * _mss;
  static const int _currentFilter = 4;
  static const int _baseHistory = 10;
  static const int _bucketMicros = 60 * 1000 * 1000;

  double _window;
  bool _slowStart = true;
  int? _reference;
  final List<int> _current = [];
  final List<int> _base = [];
  int _bucketStart = 0;

  /// Очередь на пути по последнему измерению, микросекунды.
  int queuingDelayMicros = 0;

  @override
  int get window => _window.round();

  bool get slowStart => _slowStart;

  @override
  void onAck({
    required int ackedBytes,
    required int flightBytes,
    int? delaySample,
    Duration? rtt,
  }) {
    if (delaySample != null) _addDelay(delaySample);
    final targetUs = target.inMicroseconds;
    final queued = queuingDelayMicros;
    double next;
    if (_slowStart) {
      if (queued > targetUs * 3 ~/ 4) {
        _slowStart = false;
        next = _window;
      } else {
        next = _window + ackedBytes;
      }
    } else if (queued <= targetUs) {
      final offTarget = (targetUs - queued) / targetUs;
      next = _window + gain * offTarget * _mss * ackedBytes / _window;
    } else {
      // За время в пути подтверждается около cwnd байт: доля этого
      // уменьшения на каждое подтверждение.
      final perRtt = math.max(
        gain * _mss - _window * (queued / targetUs - 1),
        -_window / 2,
      );
      next = _window + perRtt * ackedBytes / _window;
    }
    if (next > _window) {
      // Не растить окно, которое отправитель не заполняет (RFC 6817,
      // раздел 2.4.2).
      next = math.min(next, math.max(_window, flightBytes + 2.0 * _mss));
    }
    _window = next.clamp(_minWindow.toDouble(), maxWindow.toDouble());
  }

  void _addDelay(int sample) {
    // Отсчёты по модулю 2^32: приводим к числу рядом с первым.
    final ref = _reference ??= sample;
    final diff = ((sample - ref + 0x80000000) & 0xffffffff) - 0x80000000;
    final value = ref + diff;
    _current.add(value);
    if (_current.length > _currentFilter) _current.removeAt(0);
    final now = _clock();
    if (_base.isEmpty || now - _bucketStart >= _bucketMicros) {
      _base.add(value);
      _bucketStart = now;
      if (_base.length > _baseHistory) _base.removeAt(0);
    } else if (value < _base.last) {
      _base.last = value;
    }
    final base = _base.reduce(math.min);
    final current = _current.reduce(math.min);
    queuingDelayMicros = math.max(0, current - base);
  }

  @override
  void onLoss() {
    _slowStart = false;
    _window = math.max(_window / 2, _minWindow.toDouble());
  }

  @override
  void onTimeout() {
    _slowStart = false;
    _window = _mss.toDouble();
  }

  @override
  Map<String, Object?> toJson() => {
    'kind': 'ledbat',
    'window': window,
    'slowStart': _slowStart,
    'queuingDelayMs': queuingDelayMicros / 1000,
  };

  static final Stopwatch _watch = Stopwatch()..start();
  static int _monotonic() => _watch.elapsedMicroseconds;
}

/// Управление перегрузкой как у TCP Reno: медленный старт до порога, затем
/// окно растёт на пакет за время в пути, потеря — вдвое. В потоке не
/// используется: в тестах изображает обычный трафик пользователя, которому
/// [Ledbat] должен уступать.
final class Reno implements CongestionControl {
  new({this.maxWindow = 16 << 20});

  final int maxWindow;

  static const int _mss = StreamPacket.maxPayload;

  double _window = 4.0 * _mss;
  double _threshold = double.infinity;

  @override
  int get window => _window.round();

  @override
  void onAck({
    required int ackedBytes,
    required int flightBytes,
    int? delaySample,
    Duration? rtt,
  }) {
    final next = _window < _threshold
        ? _window + ackedBytes
        : _window + _mss * ackedBytes / _window;
    _window = math.min(next, maxWindow.toDouble());
  }

  @override
  void onLoss() {
    _threshold = math.max(_window / 2, 2.0 * _mss);
    _window = _threshold;
  }

  @override
  void onTimeout() {
    _threshold = math.max(_window / 2, 2.0 * _mss);
    _window = _mss.toDouble();
  }

  @override
  Map<String, Object?> toJson() => {'kind': 'reno', 'window': window};
}
