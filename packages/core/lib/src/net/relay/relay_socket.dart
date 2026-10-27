import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:core/src/net/byte_connection.dart';
import 'package:core/src/net/relay/relay_wire.dart';
import 'package:protobuf/protobuf.dart';

/// TCP-соединение с relay в кадрах `u16be длина || сообщение` до начала
/// ретрансляции (protocol.md, раздел 4.12). Общее для relay и его
/// клиентов: кадры читаются по одному ([next]) или подпиской ([listen]),
/// а после рукопожатия соединение передаётся дальше вместе с уже
/// прочитанными байтами собеседника ([handoff], [detach]).
final class RelaySocket {
  new(this.socket) {
    _subscription = socket.listen(_onData, onError: _fail, onDone: _onDone);
  }

  final Socket socket;
  late final StreamSubscription<Uint8List> _subscription;
  final _reader = RelayFrameReader();
  final _frames = Queue<Uint8List>();
  Completer<void>? _waiting;
  void Function(Uint8List frame)? _onFrame;
  void Function()? _onClosed;
  Exception? _error;
  bool _closed = false;
  bool _detached = false;

  /// Адрес собеседника; `null` — сокет уже закрыт.
  InternetAddress? get remoteAddress {
    try {
      return socket.remoteAddress;
    } on SocketException {
      return null;
    }
  }

  bool get isClosed => _closed;

  /// Отправляет кадр с [message].
  void send(GeneratedMessage message) {
    if (_closed || _detached) return;
    socket.add(RelayWire.frame(message));
  }

  /// Следующий кадр. Соединение закрылось — `null`; кадр не по формату —
  /// [FormatException]; не пришёл за [timeout] — [TimeoutException].
  Future<Uint8List?> next({Duration? timeout}) async {
    final deadline = timeout == null ? null : DateTime.now().add(timeout);
    while (true) {
      if (_frames.isNotEmpty) return _frames.removeFirst();
      if (_error case final e?) throw e;
      if (_closed) return null;
      final waiting = _waiting = Completer<void>();
      if (deadline == null) {
        await waiting.future;
      } else {
        final left = deadline.difference(DateTime.now());
        if (left <= Duration.zero) throw TimeoutException('кадр relay');
        await waiting.future.timeout(left);
      }
    }
  }

  /// Кадры дальше — в [onFrame], закрытие или ошибка — один вызов
  /// [onClosed] (управляющее соединение узла).
  void listen(
    void Function(Uint8List frame) onFrame,
    void Function() onClosed,
  ) {
    _onFrame = onFrame;
    _onClosed = onClosed;
    while (_frames.isNotEmpty && _onFrame != null) {
      onFrame(_frames.removeFirst());
    }
    if (_closed) _notifyClosed();
  }

  /// Соединение — дальше поток байт без кадров relay: уже прочитанные
  /// байты собеседника идут первыми.
  ByteConnection handoff() {
    final (rest, subscription) = detach();
    return _HandoffConnection(socket, subscription, rest);
  }

  /// Подписка на сокет (на паузе) и прочитанные, но не разобранные байты
  /// — для склейки двух соединений на relay.
  (Uint8List, StreamSubscription<Uint8List>) detach() {
    _detached = true;
    _subscription.pause();
    final rest = BytesBuilder(copy: false);
    // Кадры, прочитанные сверх рукопожатия, не ожидаются: собеседник шлёт
    // данные только после RelayOpened. Если они есть — это уже байты Noise.
    for (final f in _frames) {
      rest
        ..addByte(f.length >> 8)
        ..addByte(f.length & 0xFF)
        ..add(f);
    }
    _frames.clear();
    rest.add(_reader.takeRest());
    return (rest.takeBytes(), _subscription);
  }

  void destroy() {
    if (!_detached) unawaited(_subscription.cancel());
    socket.destroy();
    _closed = true;
    _wake();
    _notifyClosed();
  }

  void _onData(Uint8List chunk) {
    if (_detached) return;
    _reader.add(chunk);
    try {
      while (true) {
        final frame = _reader.next();
        if (frame == null) break;
        final handler = _onFrame;
        if (handler != null) {
          handler(frame);
          if (_closed || _detached) return;
        } else {
          _frames.add(frame);
        }
      }
    } on FormatException catch (e) {
      _fail(e);
      return;
    }
    _wake();
  }

  void _onDone() {
    _closed = true;
    _wake();
    _notifyClosed();
  }

  void _fail(Object e) {
    _error ??= e is Exception ? e : Exception('$e');
    destroy();
  }

  void _wake() {
    final w = _waiting;
    _waiting = null;
    if (w != null && !w.isCompleted) w.complete();
  }

  void _notifyClosed() {
    final callback = _onClosed;
    _onClosed = null;
    _onFrame = null;
    callback?.call();
  }
}

/// [ByteConnection] поверх сокета после рукопожатия с relay: сначала
/// [_rest] — байты собеседника, прочитанные вместе с последним кадром.
final class _HandoffConnection implements ByteConnection {
  new(this._socket, StreamSubscription<Uint8List> subscription, this._rest) {
    _controller = StreamController<Uint8List>(
      onListen: () {
        if (_rest.isNotEmpty) _controller.add(_rest);
        subscription.resume();
      },
      onPause: subscription.pause,
      onResume: subscription.resume,
      onCancel: subscription.cancel,
    );
    subscription
      ..onData(_controller.add)
      ..onError(_controller.addError)
      ..onDone(() => unawaited(_controller.close()));
  }

  final Socket _socket;
  final Uint8List _rest;
  late final StreamController<Uint8List> _controller;

  @override
  Stream<Uint8List> get input => _controller.stream;

  @override
  void add(Uint8List data) => _socket.add(data);

  @override
  Future<void> flush() => _socket.flush();

  @override
  Future<void> close() async {
    try {
      await _socket.close();
    } on SocketException {
      // Собеседник уже закрыл соединение.
    }
  }

  @override
  void destroy() => _socket.destroy();
}
