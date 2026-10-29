import 'dart:async';
import 'dart:io';

import 'package:daemon_kit/src/control_endpoint.dart';
import 'package:daemon_kit/src/control_wire.dart';

/// Событие фонового процесса из подписки ([ControlClient.subscribe]).
final class ControlEvent {
  const new(this.name, this.data);

  final String name;
  final Map<String, Object?> data;

  @override
  String toString() => 'ControlEvent($name)';
}

/// Клиент локального API фонового процесса: для `cli node …` и
/// приложения. Запросы по одному соединению, ответы по `id`; события
/// подписки — в [events].
final class ControlClient {
  new _(this._socket, this._process) {
    _subscription = _socket.listen(
      _onData,
      onError: (Object _) => _fail(),
      onDone: _fail,
    );
    // Ошибка записи (процесс сбросил соединение) приходит сюда.
    unawaited(_socket.done.then<void>((_) {}, onError: (Object _) => _fail()));
  }

  /// Подключается к процессу; его нет — [ControlException] с кодом
  /// `unavailable`.
  static Future<ControlClient> connect(
    ControlEndpoint endpoint, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final Socket socket;
    String? token;
    try {
      if (ControlEndpoint.usesUnixSocket) {
        socket = await Socket.connect(
          InternetAddress(endpoint.socketPath, type: InternetAddressType.unix),
          0,
          timeout: timeout,
        );
      } else {
        final (port, t) = endpoint.readToken();
        token = t;
        socket = await Socket.connect(
          InternetAddress.loopbackIPv4,
          port,
          timeout: timeout,
        );
      }
    } on SocketException {
      throw ControlException('unavailable', '${endpoint.process} не запущен');
    }
    final client = ControlClient._(socket, endpoint.process);
    if (token != null) {
      await client.call('auth', {'token': token}, timeout);
    }
    return client;
  }

  final Socket _socket;
  final String _process;
  late final StreamSubscription<List<int>> _subscription;
  final _reader = LineReader();
  final _pending = <int, Completer<Map<String, Object?>>>{};
  final _events = StreamController<ControlEvent>.broadcast();
  final _done = Completer<void>();
  var _nextId = 1;
  var _closed = false;

  /// События после [subscribe]; поток закрывается вместе с соединением.
  Stream<ControlEvent> get events => _events.stream;

  /// Завершается, когда соединение закрыто (процесс остановлен или
  /// перезапущен, [close]).
  Future<void> get done => _done.future;

  bool get isClosed => _closed;

  /// Вызов [method]; ошибка процесса — [ControlException].
  Future<Map<String, Object?>> call(
    String method, [
    Map<String, Object?> params = const {},
    Duration timeout = const Duration(seconds: 10),
  ]) {
    if (_closed) {
      throw const ControlException('unavailable', 'соединение закрыто');
    }
    final id = _nextId++;
    final completer = _pending[id] = Completer<Map<String, Object?>>();
    _socket.add(
      ControlWire.encode({'id': id, 'method': method, 'params': params}),
    );
    return completer.future.timeout(
      timeout,
      onTimeout: () {
        _pending.remove(id);
        throw ControlException('unavailable', '$_process не ответил');
      },
    );
  }

  /// Подписка на события [names] (пусто — на все); события приходят в
  /// [events].
  Future<void> subscribe([List<String> names = const []]) =>
      call('subscribe', {if (names.isNotEmpty) 'events': names});

  void _onData(List<int> chunk) {
    final List<Map<String, Object?>> messages;
    try {
      messages = _reader.add(chunk);
    } on FormatException {
      _fail();
      return;
    }
    for (final m in messages) {
      if (m case {
        'event': final String name,
        'data': final Map<String, Object?> data,
      }) {
        if (!_events.isClosed) _events.add(ControlEvent(name, data));
        continue;
      }
      final completer = _pending.remove(m['id']);
      if (completer == null) continue;
      switch (m) {
        case {'result': final Map<String, Object?> result}:
          completer.complete(result);
        case {
          'error': {'code': final String code, 'message': final String message},
        }:
          completer.completeError(ControlException(code, message));
        default:
          completer.completeError(
            ControlException('internal', 'неверный ответ: $_process'),
          );
      }
    }
  }

  void _fail() {
    _closed = true;
    for (final c in _pending.values) {
      c.completeError(
        ControlException('unavailable', '$_process закрыл соединение'),
      );
    }
    _pending.clear();
    if (!_events.isClosed) unawaited(_events.close());
    if (!_done.isCompleted) _done.complete();
  }

  Future<void> close() async {
    _closed = true;
    await _subscription.cancel();
    _socket.destroy();
    _fail();
  }
}
