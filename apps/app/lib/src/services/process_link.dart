import 'dart:async';

import 'package:daemon_kit/daemon_kit.dart';
import 'package:flutter/foundation.dart';

/// Связь с фоновым процессом.
enum LinkState {
  /// Подключаемся (первый раз или после разрыва).
  connecting,

  /// Подключены, [BackgroundProcess.status] свежий.
  connected,

  /// Процесс не запущен или не отвечает; пробуем снова.
  unavailable,
}

/// Фоновый процесс для экранов: состояние связи, последний `status`,
/// вызовы методов и события. Экраны зависят только от этого интерфейса —
/// в тестах его заменяет подделка.
abstract interface class BackgroundProcess implements Listenable {
  LinkState get state;

  /// Последний ответ `status`; `null` — ещё не было связи. После разрыва
  /// остаётся последним известным.
  Map<String, Object?>? get status;

  /// Почему нет связи — для подсказки.
  String? get problem;

  /// Вызов метода локального API; нет связи — [ControlException]
  /// `unavailable`.
  Future<Map<String, Object?>> call(
    String method, [
    Map<String, Object?> params,
    Duration timeout,
  ]);

  /// События процесса, на которые подписана связь.
  Stream<ControlEvent> get events;
}

/// Связь с локальным API фонового процесса ([ControlClient]): держит
/// соединение, после разрыва (процесс перезапущен, обновлён, упал)
/// переподключается с нарастающей паузой, подписывается на события и
/// обновляет [status] по событию `status` или опросом раз в [poll].
final class ProcessLink extends ChangeNotifier implements BackgroundProcess {
  new({
    required this.connect,
    this.subscribe,
    this.poll,
    this.retry = const Duration(milliseconds: 500),
    this.maxRetry = const Duration(seconds: 10),
  });

  /// Подключение; процесса нет — [ControlException] `unavailable`.
  final Future<ControlClient> Function() connect;

  /// На какие события подписаться (пусто — на все); `null` — без
  /// подписки (у `node` событий нет).
  final List<String>? subscribe;

  /// Как часто запрашивать `status`; `null` — только по событию `status`.
  final Duration? poll;
  final Duration retry;
  final Duration maxRetry;

  final _events = StreamController<ControlEvent>.broadcast();
  ControlClient? _client;
  Timer? _timer;
  Duration _delay = Duration.zero;
  bool _started = false;
  bool _disposed = false;

  @override
  LinkState state = LinkState.connecting;

  @override
  Map<String, Object?>? status;

  @override
  String? problem;

  @override
  Stream<ControlEvent> get events => _events.stream;

  void start() {
    if (_started) return;
    _started = true;
    unawaited(_open());
  }

  Future<void> _open() async {
    if (_disposed) return;
    try {
      final client = await connect();
      if (_disposed) {
        await client.close();
        return;
      }
      _client = client;
      client.events.listen(_onEvent);
      unawaited(client.done.then((_) => _lost(client)));
      if (subscribe case final names?) await client.subscribe(names);
      status = await client.call('status');
      state = LinkState.connected;
      problem = null;
      _delay = Duration.zero;
      if (poll case final interval?) {
        _timer = Timer.periodic(interval, (_) => unawaited(_refresh()));
      }
      notifyListeners();
    } on ControlException catch (e) {
      _fail(e.message);
    }
  }

  void _onEvent(ControlEvent event) {
    if (event.name == 'status') {
      status = event.data;
      notifyListeners();
    }
    _events.add(event);
  }

  Future<void> _refresh() async {
    final client = _client;
    if (client == null || client.isClosed) return;
    try {
      status = await client.call('status');
      notifyListeners();
    } on ControlException catch (e) {
      // Соединение могло остаться открытым, а процесс — замолчать
      // (завис, застрял на блокирующем вызове): тогда разрыва не будет, и
      // [_lost] не сработает. Считаем это потерей связи и переподключаемся
      // — так приложение замечает молчащий процесс и восстанавливается.
      _fail(e.message);
    }
  }

  void _lost(ControlClient client) {
    if (!identical(client, _client)) return;
    _fail('соединение закрыто');
  }

  void _fail(String reason) {
    _timer?.cancel();
    _timer = null;
    final client = _client;
    _client = null;
    if (client != null) unawaited(client.close());
    if (_disposed) return;
    state = LinkState.unavailable;
    problem = reason;
    notifyListeners();
    _delay = _delay == Duration.zero
        ? retry
        : (_delay * 2 > maxRetry ? maxRetry : _delay * 2);
    _timer = Timer(_delay, () {
      state = LinkState.connecting;
      notifyListeners();
      unawaited(_open());
    });
  }

  @override
  Future<Map<String, Object?>> call(
    String method, [
    Map<String, Object?> params = const {},
    Duration timeout = const Duration(seconds: 10),
  ]) async {
    final client = _client;
    if (client == null || client.isClosed) {
      throw ControlException('unavailable', problem ?? 'нет связи');
    }
    final result = await client.call(method, params, timeout);
    if (method != 'status') unawaited(_refresh());
    return result;
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    unawaited(_client?.close());
    unawaited(_events.close());
    super.dispose();
  }
}
