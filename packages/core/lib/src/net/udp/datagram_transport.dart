import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// Принятая датаграмма.
final class ReceivedDatagram {
  const new(this.data, this.address, this.port);

  final Uint8List data;
  final InternetAddress address;
  final int port;
}

/// Сокет UDP: настоящий ([RawDatagramTransport]) или в модели сети для
/// тестов (`SimulatedNetwork`). Поверх него `UdpEndpoint` ведёт запросы к
/// своднику, пробивание NAT и потоки.
abstract interface class DatagramTransport {
  /// Адрес и порт, к которым привязан сокет.
  InternetAddress get address;
  int get port;

  /// Входящие датаграммы; подписка одна.
  Stream<ReceivedDatagram> get datagrams;

  /// Отправляет датаграмму. `false` — буфер отправки ОС полон: повторить
  /// после [writable].
  bool send(Uint8List data, InternetAddress address, int port);

  /// Завершается, когда в сокет снова можно писать.
  Future<void> get writable;

  void close();
}

/// [DatagramTransport] поверх [RawDatagramSocket].
final class RawDatagramTransport implements DatagramTransport {
  new _(this._socket) {
    _socket
      ..readEventsEnabled = true
      ..writeEventsEnabled = false;
    _subscription = _socket.listen(
      _onEvent,
      onError: (Object _) {
        // Ошибки ICMP («порт недоступен») на UDP не значат ничего для
        // остальных собеседников этого сокета.
      },
      onDone: () => unawaited(_controller.close()),
    );
  }

  /// Привязывает сокет к [host] (по умолчанию все адреса IPv4) и [port]
  /// (0 — любой свободный).
  static Future<RawDatagramTransport> bind({
    Object? host,
    int port = 0,
  }) async => RawDatagramTransport._(
    await RawDatagramSocket.bind(host ?? InternetAddress.anyIPv4, port),
  );

  final RawDatagramSocket _socket;
  late final StreamSubscription<RawSocketEvent> _subscription;
  final _controller = StreamController<ReceivedDatagram>(sync: true);
  Completer<void>? _writable;

  @override
  InternetAddress get address => _socket.address;

  @override
  int get port => _socket.port;

  @override
  Stream<ReceivedDatagram> get datagrams => _controller.stream;

  @override
  bool send(Uint8List data, InternetAddress address, int port) {
    try {
      return _socket.send(data, address, port) == data.length;
    } on SocketException {
      // Сеть недоступна, адрес другого семейства: как потеря пакета.
      return true;
    }
  }

  @override
  Future<void> get writable {
    final w = _writable ??= Completer<void>();
    _socket.writeEventsEnabled = true;
    return w.future;
  }

  void _onEvent(RawSocketEvent event) {
    switch (event) {
      case RawSocketEvent.read:
        // За одно событие — всё, что накопилось: меньше переходов через
        // цикл событий.
        while (true) {
          final d = _socket.receive();
          if (d == null) break;
          if (!_controller.isClosed) {
            _controller.add(ReceivedDatagram(d.data, d.address, d.port));
          }
        }
      case RawSocketEvent.write:
        final w = _writable;
        _writable = null;
        if (w != null && !w.isCompleted) w.complete();
      case RawSocketEvent.readClosed:
      case RawSocketEvent.closed:
        break;
    }
  }

  @override
  void close() {
    unawaited(_subscription.cancel());
    _socket.close();
    final w = _writable;
    _writable = null;
    if (w != null && !w.isCompleted) w.complete();
    if (!_controller.isClosed) unawaited(_controller.close());
  }
}
