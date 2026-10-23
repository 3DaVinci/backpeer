import 'dart:async';
import 'dart:io';

import 'package:node/src/control/control_endpoint.dart';
import 'package:node/src/control/control_wire.dart';

/// Клиент локального API демона узла: для `cli node …` и приложения
/// (этап 5). Запросы по одному соединению, ответы по `id`.
final class NodeControlClient {
  new _(this._socket) {
    _subscription = _socket.listen(
      _onData,
      onError: (Object _) => _fail(),
      onDone: _fail,
    );
    // Ошибка записи (демон сбросил соединение) приходит сюда.
    unawaited(_socket.done.then<void>((_) {}, onError: (Object _) => _fail()));
  }

  /// Подключается к демону; демона нет — [ControlException] с кодом
  /// `unavailable`.
  static Future<NodeControlClient> connect(
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
      throw const ControlException('unavailable', 'демон узла не запущен');
    }
    final client = NodeControlClient._(socket);
    if (token != null) {
      await client.call('auth', {'token': token}, timeout);
    }
    return client;
  }

  final Socket _socket;
  late final StreamSubscription<List<int>> _subscription;
  final _reader = LineReader();
  final _pending = <int, Completer<Map<String, Object?>>>{};
  var _nextId = 1;
  var _closed = false;

  /// Вызов [method]; ошибка демона — [ControlException].
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
        throw const ControlException('unavailable', 'демон не ответил');
      },
    );
  }

  void _onData(List<int> chunk) {
    final List<Map<String, Object?>> messages;
    try {
      messages = _reader.add(chunk);
    } on FormatException {
      _fail();
      return;
    }
    for (final m in messages) {
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
            const ControlException('internal', 'неверный ответ демона'),
          );
      }
    }
  }

  void _fail() {
    _closed = true;
    for (final c in _pending.values) {
      c.completeError(
        const ControlException('unavailable', 'демон закрыл соединение'),
      );
    }
    _pending.clear();
  }

  Future<void> close() async {
    _closed = true;
    await _subscription.cancel();
    _socket.destroy();
  }
}
