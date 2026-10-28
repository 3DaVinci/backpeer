import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Событие системы, на которое отвечает агент (задача 5.6.3).
enum SystemEvent {
  /// Компьютер засыпает (сон, гибернация).
  sleep,

  /// Проснулся: таймеры расписания отстали, соединения порваны.
  wake,

  /// Сеть снова есть (подключение или смена сети).
  networkUp,
}

/// Задержка сна, пока агент останавливает бэкап; [release] — можно спать.
abstract interface class SleepInhibit {
  Future<void> release();
}

/// Сон, пробуждение и сеть (задача 5.6.3).
///
/// - Linux: сигналы `PrepareForSleep` у systemd-logind и `StateChanged`
///   у NetworkManager по системной шине (`gdbus monitor`); задержка сна —
///   `systemd-inhibit --mode=delay` (logind ждёт до `InhibitDelayMaxSec`,
///   по умолчанию 5 с).
/// - Все ОС: скачок часов — местное время ушло вперёд сильнее монотонного
///   (оно во сне не идёт): так видно пробуждение и без logind.
abstract interface class SystemEvents {
  /// `FS_AGENT_SYSTEM_EVENTS=none` — без событий (тесты).
  factory forPlatform([Map<String, String>? environment]) {
    final env = environment ?? Platform.environment;
    if (env['FS_AGENT_SYSTEM_EVENTS'] == 'none') return NoSystemEvents();
    return PlatformSystemEvents(logind: Platform.isLinux);
  }

  /// Для журнала: `logind`, `clock`, `none`.
  String get name;

  Stream<SystemEvent> get events;

  /// Задержать сон, пока идёт бэкап; `null` — нечем.
  Future<SleepInhibit?> inhibitSleep(String why);

  Future<void> close();
}

final class NoSystemEvents implements SystemEvents {
  final _events = StreamController<SystemEvent>.broadcast();

  @override
  String get name => 'none';

  @override
  Stream<SystemEvent> get events => _events.stream;

  @override
  Future<SleepInhibit?> inhibitSleep(String why) async => null;

  @override
  Future<void> close() => _events.close();
}

/// Для тестов: события шлёт тест ([emit]), задержки сна считаются.
final class FakeSystemEvents implements SystemEvents {
  final _events = StreamController<SystemEvent>.broadcast(sync: true);
  int inhibits = 0;
  int released = 0;

  void emit(SystemEvent event) => _events.add(event);

  @override
  String get name => 'fake';

  @override
  Stream<SystemEvent> get events => _events.stream;

  @override
  Future<SleepInhibit?> inhibitSleep(String why) async {
    inhibits++;
    return _FakeInhibit(this);
  }

  @override
  Future<void> close() => _events.close();
}

final class _FakeInhibit implements SleepInhibit {
  new(this._owner);

  final FakeSystemEvents _owner;
  bool _done = false;

  @override
  Future<void> release() async {
    if (_done) return;
    _done = true;
    _owner.released++;
  }
}

/// Разбор строк `gdbus monitor` (вынесен для тестов).
SystemEvent? parseMonitorLine(String line) {
  if (line.contains('.PrepareForSleep (true,)')) return SystemEvent.sleep;
  if (line.contains('.PrepareForSleep (false,)')) return SystemEvent.wake;
  // NM_STATE_CONNECTED_GLOBAL = 70.
  if (line.contains('NetworkManager.StateChanged (uint32 70,)')) {
    return SystemEvent.networkUp;
  }
  return null;
}

final class PlatformSystemEvents implements SystemEvents {
  new({
    required this.logind,
    this.clockCheck = const Duration(seconds: 15),
    this.clockJump = const Duration(seconds: 30),
  }) {
    _clock = Timer.periodic(clockCheck, (_) => _checkClock());
    if (logind) {
      unawaited(_monitor('org.freedesktop.login1', '/org/freedesktop/login1'));
      unawaited(
        _monitor(
          'org.freedesktop.NetworkManager',
          '/org/freedesktop/NetworkManager',
        ),
      );
    }
  }

  final bool logind;
  final Duration clockCheck;

  /// Насколько местное время должно уйти вперёд монотонного, чтобы
  /// считать это сном (а не подстройкой часов по NTP).
  final Duration clockJump;

  final _events = StreamController<SystemEvent>.broadcast();
  final _processes = <Process>[];
  final _mono = Stopwatch()..start();
  late final Timer _clock;
  DateTime _wall = DateTime.now();
  Duration _monoAt = Duration.zero;
  DateTime? _lastWake;
  bool _logindSeen = false;
  bool _closed = false;

  @override
  String get name => _logindSeen ? 'logind' : 'clock';

  @override
  Stream<SystemEvent> get events => _events.stream;

  void _emit(SystemEvent event) {
    if (_closed) return;
    if (event == SystemEvent.wake) {
      // logind и часы сообщат об одном пробуждении — одно событие.
      final last = _lastWake;
      final now = DateTime.now();
      if (last != null && now.difference(last) < const Duration(minutes: 1)) {
        return;
      }
      _lastWake = now;
    }
    _events.add(event);
  }

  void _checkClock() {
    final wall = DateTime.now();
    final mono = _mono.elapsed;
    final drift = wall.difference(_wall) - (mono - _monoAt);
    _wall = wall;
    _monoAt = mono;
    if (drift > clockJump) _emit(SystemEvent.wake);
  }

  Future<void> _monitor(String dest, String path) async {
    final Process process;
    try {
      process = await Process.start('gdbus', [
        'monitor',
        '--system',
        '--dest',
        dest,
        '--object-path',
        path,
      ]);
    } on ProcessException {
      return;
    }
    if (_closed) {
      process.kill();
      return;
    }
    _processes.add(process);
    unawaited(process.stderr.drain<void>());
    await process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .forEach((line) {
          final event = parseMonitorLine(line);
          if (event == null) return;
          if (event != SystemEvent.networkUp) _logindSeen = true;
          _emit(event);
        });
  }

  @override
  Future<SleepInhibit?> inhibitSleep(String why) async {
    if (!logind) return null;
    try {
      final process = await Process.start('systemd-inhibit', [
        '--what=sleep',
        '--mode=delay',
        '--who=Backpeer',
        '--why=$why',
        // Ждёт конца ввода: закрыли stdin или агент упал — задержка снята,
        // осиротевших процессов не остаётся.
        'cat',
      ]);
      unawaited(process.stdout.drain<void>());
      unawaited(process.stderr.drain<void>());
      return _ProcessInhibit(process);
    } on ProcessException {
      return null;
    }
  }

  @override
  Future<void> close() async {
    _closed = true;
    _clock.cancel();
    for (final p in _processes) {
      p.kill();
    }
    await _events.close();
  }
}

final class _ProcessInhibit implements SleepInhibit {
  new(this._process);

  final Process _process;

  bool _done = false;

  @override
  Future<void> release() async {
    if (_done) return;
    _done = true;
    // `systemd-inhibit` снимает задержку, когда завершается его команда.
    await _process.stdin.close();
    await _process.exitCode.timeout(
      const Duration(seconds: 2),
      onTimeout: () {
        _process.kill();
        return -1;
      },
    );
  }
}
