import 'dart:async';
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
(ByteConnection, ByteConnection) memoryConnectionPair() {
  final aToB = StreamController<Uint8List>();
  final bToA = StreamController<Uint8List>();
  return (
    _MemoryConnection(bToA.stream, aToB, bToA),
    _MemoryConnection(aToB.stream, bToA, aToB),
  );
}

final class _MemoryConnection implements ByteConnection {
  new(this.input, this._out, this._in);

  @override
  final Stream<Uint8List> input;

  final StreamController<Uint8List> _out;
  final StreamController<Uint8List> _in;

  @override
  void add(Uint8List data) {
    if (!_out.isClosed) _out.add(Uint8List.fromList(data));
  }

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {
    // Future закрытия ждёт подписчика на той стороне: не ждём его.
    if (!_out.isClosed) unawaited(_out.close());
  }

  @override
  void destroy() {
    if (!_out.isClosed) unawaited(_out.close());
    if (!_in.isClosed) unawaited(_in.close());
  }
}
