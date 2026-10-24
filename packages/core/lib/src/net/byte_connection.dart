import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

/// Надёжный упорядоченный поток байт между двумя сторонами: TCP сейчас,
/// поток поверх UDP и relay позже (этап 3, группы 3.7 и 3.8). Поверх него
/// идёт канал Noise (`SecureChannel`); как поток установлен, решает
/// стратегия подключения (`Transport`, задача 3.9.1).
abstract interface class ByteConnection {
  /// Входящие байты; подписка одна. Пауза подписки приостанавливает
  /// чтение из сети.
  Stream<Uint8List> get input;

  /// Ставит байты в очередь отправки. Не вызывать, пока не завершён
  /// [flush].
  void add(Uint8List data);

  /// Ждёт, пока очередь отправки уйдёт в сеть: обратное давление.
  Future<void> flush();

  /// Отправляет остаток очереди и закрывает поток.
  Future<void> close();

  /// Закрывает поток немедленно, без отправки очереди.
  void destroy();
}

/// [ByteConnection] поверх [Socket].
final class SocketConnection implements ByteConnection {
  new(this._socket);

  final Socket _socket;

  @override
  Stream<Uint8List> get input => _socket;

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

/// Пара соединённых потоков в памяти: для тестов и для связи внутри
/// процесса.
///
/// [capacity] — сколько байт может ждать в одном направлении, пока
/// получатель их не прочитал: `flush` отправителя ждёт, пока непрочитанного
/// не станет не больше [capacity], как у TCP с заполненными буферами.
/// `null` — без предела (`flush` завершается сразу).
(ByteConnection, ByteConnection) memoryConnectionPair({int? capacity}) {
  final aToB = _Pipe(capacity);
  final bToA = _Pipe(capacity);
  return (_MemoryConnection(bToA, aToB), _MemoryConnection(aToB, bToA));
}

/// Одно направление пары: очередь байт, которые получатель забирает, пока
/// его подписка не на паузе.
final class _Pipe {
  new(this.capacity) {
    // Синхронная доставка: пауза подписчика сразу останавливает очередь, и
    // непрочитанное остаётся в [_queue], а не в буфере контроллера.
    _controller = StreamController<Uint8List>(
      sync: true,
      onListen: () => scheduleMicrotask(_deliver),
      onResume: () => scheduleMicrotask(_deliver),
      onCancel: () {
        _queue.clear();
        _pending = 0;
        _wake();
      },
    );
  }

  final int? capacity;
  late final StreamController<Uint8List> _controller;
  final _queue = Queue<Uint8List>();
  int _pending = 0;
  bool _closing = false;
  final _waiters = <Completer<void>>[];

  Stream<Uint8List> get stream => _controller.stream;

  bool get isClosed => _closing || _controller.isClosed;

  void add(Uint8List data) {
    if (isClosed) return;
    _queue.add(Uint8List.fromList(data));
    _pending += data.length;
    _deliver();
  }

  Future<void> flush() {
    final limit = capacity;
    if (limit == null || _pending <= limit || isClosed) return Future.value();
    final waiter = Completer<void>();
    _waiters.add(waiter);
    return waiter.future;
  }

  /// Закрывает направление после доставки очереди.
  void close() {
    if (isClosed) return;
    _closing = true;
    _deliver();
  }

  /// Закрывает немедленно, очередь пропадает.
  void destroy() {
    _queue.clear();
    _pending = 0;
    _closing = true;
    _wake();
    if (!_controller.isClosed) unawaited(_controller.close());
  }

  void _deliver() {
    while (_queue.isNotEmpty &&
        _controller.hasListener &&
        !_controller.isPaused) {
      final chunk = _queue.removeFirst();
      _pending -= chunk.length;
      _controller.add(chunk);
    }
    _wake();
    if (_closing && _queue.isEmpty && !_controller.isClosed) {
      // Future закрытия ждёт подписчика на той стороне: не ждём его.
      unawaited(_controller.close());
    }
  }

  void _wake() {
    final limit = capacity;
    if (limit != null && _pending > limit && !_closing) return;
    for (final w in _waiters) {
      w.complete();
    }
    _waiters.clear();
  }
}

final class _MemoryConnection implements ByteConnection {
  new(this._in, this._out);

  final _Pipe _in;
  final _Pipe _out;

  @override
  Stream<Uint8List> get input => _in.stream;

  @override
  void add(Uint8List data) => _out.add(data);

  @override
  Future<void> flush() => _out.flush();

  @override
  Future<void> close() async => _out.close();

  @override
  void destroy() {
    _out.destroy();
    _in.destroy();
  }
}
