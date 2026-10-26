import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:core/src/net/udp/datagram_transport.dart';
import 'package:core/src/net/udp/udp_packets.dart';
import 'package:core/src/net/udp/udp_stream.dart';
import 'package:core/src/util/bytes.dart';

/// Сведение узлов не удалось: сводник не ответил, собеседник не ответил
/// на пробивание, NAT симметричный.
final class UdpRendezvousException implements Exception {
  const new(this.message);

  final String message;

  @override
  String toString() => 'UdpRendezvousException: $message';
}

/// Внешний UDP-адрес сокета, каким его видит сводник (protocol.md,
/// раздел 4.11), с подтверждением сводника для координатора.
final class UdpBinding {
  const new({
    required this.address,
    required this.port,
    required this.token,
    required this.symmetric,
  });

  final InternetAddress address;
  final int port;
  final Uint8List token;

  /// Два порта сводника видят разные внешние адреса или порты: NAT
  /// выделяет отображение на каждого адресата, и пробиться через него
  /// почти нельзя.
  final bool symmetric;

  /// `хост:порт`, IPv6 — в квадратных скобках.
  String get endpoint => formatEndpoint(address, port);
}

/// `хост:порт`, IPv6 — в квадратных скобках.
String formatEndpoint(InternetAddress address, int port) =>
    address.type == InternetAddressType.IPv6
    ? '[${address.address}]:$port'
    : '${address.address}:$port';

/// Разбирает `IP:порт` или `[IPv6]:порт`; `null` — не адрес.
(InternetAddress, int)? parseIpEndpoint(String endpoint) {
  final colon = endpoint.lastIndexOf(':');
  if (colon <= 0) return null;
  var host = endpoint.substring(0, colon);
  final port = int.tryParse(endpoint.substring(colon + 1));
  if (port == null || port < 1 || port > 65535) return null;
  if (host.startsWith('[') && host.endsWith(']')) {
    host = host.substring(1, host.length - 1);
  } else if (host.contains(':')) {
    return null;
  }
  final address = InternetAddress.tryParse(host);
  return address == null ? null : (address, port);
}

/// Один сокет UDP узла или клиента (задачи 3.7.2, 3.7.3): запросы к
/// своднику ([discover]), пробивание NAT ([punch]), исходящие ([connect])
/// и входящие ([incoming]) потоки. Всё идёт через один сокет, потому что
/// отображение в NAT принадлежит сокету: адрес, который узнал сводник,
/// годится только для него.
///
/// Входящий поток принимается, только если SYN несёт номер сведения,
/// разрешённый [allow] или [punch]: случайный отправитель не заставит
/// узел держать поток. Номер разрешает один поток.
final class UdpEndpoint {
  new(
    this.transport, {
    this.options = const UdpStreamOptions(),
    math.Random? random,
  }) : _random = random ?? math.Random.secure() {
    _subscription = transport.datagrams.listen(_onDatagram);
  }

  /// Привязывает сокет к [host] (по умолчанию все адреса IPv4) и [port]
  /// (0 — любой свободный).
  static Future<UdpEndpoint> bind({
    Object? host,
    int port = 0,
    UdpStreamOptions options = const UdpStreamOptions(),
  }) async => UdpEndpoint(
    await RawDatagramTransport.bind(host: host, port: port),
    options: options,
  );

  final DatagramTransport transport;
  final UdpStreamOptions options;
  final math.Random _random;
  late final StreamSubscription<ReceivedDatagram> _subscription;

  final _streams = <String, UdpStream>{};
  final _bindings = <String, Completer<BindingResponse>>{};
  final _punches = <String, _Punch>{};
  final _allowed = <String, int>{};
  final _incoming = StreamController<UdpStream>();
  bool _closed = false;

  int punchesSucceeded = 0;
  int punchesFailed = 0;
  int streamsAccepted = 0;
  int streamsOpened = 0;

  static final _clock = Stopwatch()..start();

  int get port => transport.port;

  /// Входящие потоки после сведения; без подписчика SYN пропускаются.
  Stream<UdpStream> get incoming => _incoming.stream;

  /// Открытых потоков.
  int get streamCount => _streams.length;

  Map<String, Object?> toJson() => {
    'port': port,
    'streams': _streams.length,
    'punchesSucceeded': punchesSucceeded,
    'punchesFailed': punchesFailed,
    'streamsAccepted': streamsAccepted,
    'streamsOpened': streamsOpened,
  };

  /// Узнаёт внешний адрес этого сокета у сводника: запрос на оба его
  /// порта [servers], повторы через 200, 400, 800 мс… до [timeout]. Ответ
  /// одного порта — адрес без признака симметричного NAT.
  Future<UdpBinding> discover(
    List<(InternetAddress, int)> servers, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    if (servers.isEmpty) {
      throw ArgumentError.value(servers, 'servers', 'пустой список');
    }
    final requests = [
      for (final s in servers)
        (s, _randomBytes(UdpPackets.transactionIdLength)),
    ];
    final answers = List<BindingResponse?>.filled(servers.length, null);
    final waits = <Future<void>>[];
    for (final (i, (_, tx)) in requests.indexed) {
      final c = Completer<BindingResponse>();
      _bindings[bytesToHex(tx)] = c;
      waits.add(c.future.then((r) => answers[i] = r));
    }
    final all = Future.wait(waits);
    final deadline = _clock.elapsed + timeout;
    var pause = const Duration(milliseconds: 200);
    try {
      while (answers.any((a) => a == null)) {
        for (final (i, ((address, port), tx)) in requests.indexed) {
          if (answers[i] != null) continue;
          transport.send(UdpPackets.encodeBindingRequest(tx), address, port);
        }
        final left = deadline - _clock.elapsed;
        if (left <= Duration.zero) break;
        await all.timeout(left < pause ? left : pause, onTimeout: () => []);
        pause *= 2;
      }
    } finally {
      for (final (_, tx) in requests) {
        _bindings.remove(bytesToHex(tx));
      }
    }
    final got = answers.nonNulls.toList();
    if (got.isEmpty) {
      throw const UdpRendezvousException('сводник не отвечает');
    }
    final first = got.first;
    return UdpBinding(
      address: first.address,
      port: first.port,
      token: first.token,
      symmetric: got.any(
        (r) => r.port != first.port || r.address != first.address,
      ),
    );
  }

  /// Пробивает NAT к собеседнику [address]:[port]: пакеты с номером
  /// сведения [punchId] каждые [interval], пока от собеседника не придёт
  /// пакет с тем же номером, не дольше [timeout]. Возвращает адрес, с
  /// которого он пришёл (NAT собеседника мог выбрать другой порт). Заодно
  /// разрешает входящий поток с этим номером ([allow]).
  Future<(InternetAddress, int)> punch(
    Uint8List punchId,
    InternetAddress address,
    int port, {
    Duration timeout = const Duration(seconds: 15),
    Duration interval = const Duration(milliseconds: 100),
  }) async {
    final key = bytesToHex(punchId);
    allow(punchId, ttl: timeout + const Duration(seconds: 60));
    final p = _punches[key] = _Punch();
    final packet = UdpPackets.encodePunch(punchId);
    void send() => transport.send(packet, address, port);
    send();
    final timer = Timer.periodic(interval, (_) => send());
    try {
      final result = await p.done.future.timeout(timeout);
      punchesSucceeded++;
      return result;
    } on TimeoutException {
      punchesFailed++;
      throw UdpRendezvousException(
        'собеседник не ответил за ${timeout.inSeconds} с',
      );
    } finally {
      timer.cancel();
      if (identical(_punches[key], p)) _punches.remove(key);
    }
  }

  /// Разрешает один входящий поток с номером сведения [punchId] на [ttl].
  void allow(Uint8List punchId, {Duration ttl = const Duration(seconds: 75)}) {
    final now = _clock.elapsedMicroseconds;
    _allowed.removeWhere((_, until) => until <= now);
    _allowed[bytesToHex(punchId)] = now + ttl.inMicroseconds;
  }

  /// Открывает поток к [address]:[port] после сведения с номером
  /// [punchId]. Ошибка — собеседник не ответил на SYN
  /// ([UdpStreamException]).
  Future<UdpStream> connect(
    InternetAddress address,
    int port, {
    required Uint8List punchId,
    UdpStreamOptions? options,
  }) async {
    if (_closed) throw StateError('сокет закрыт');
    late String key;
    late int id;
    do {
      id = _random.nextInt(0xffffffff) + 1;
      key = _key(address, port, id);
    } while (_streams.containsKey(key));
    final stream = UdpStream.attach(
      remoteAddress: address,
      remotePort: port,
      connectionId: id,
      initiator: true,
      punchId: punchId,
      options: options ?? this.options,
      send: (d) => transport.send(d, address, port),
      writable: () => transport.writable,
      onClosed: (s) => _remove(key, s),
    );
    _streams[key] = stream;
    await stream.ready;
    streamsOpened++;
    return stream;
  }

  /// Закрывает потоки и сокет.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final s in _streams.values.toList()) {
      s.destroy();
    }
    for (final p in _punches.values) {
      if (!p.done.isCompleted) {
        p.done.completeError(const UdpRendezvousException('сокет закрыт'));
      }
    }
    await _subscription.cancel();
    transport.close();
    // Без подписчика future закрытия не завершится: не ждём его.
    unawaited(_incoming.close());
  }

  void _remove(String key, UdpStream stream) {
    if (identical(_streams[key], stream)) _streams.remove(key);
  }

  static String _key(InternetAddress address, int port, int id) =>
      '${address.address}/$port/$id';

  void _onDatagram(ReceivedDatagram d) {
    if (_closed || d.data.isEmpty) return;
    final type = d.data[0];
    if (StreamPacket.isStreamType(type)) {
      final p = StreamPacket.decode(d.data);
      if (p != null) _onStreamPacket(p, d);
      return;
    }
    switch (type) {
      case UdpPackets.bindingResponse:
        final r = UdpPackets.decodeBindingResponse(d.data);
        if (r == null) return;
        final c = _bindings.remove(bytesToHex(r.transactionId));
        if (c != null && !c.isCompleted) c.complete(r);
      case UdpPackets.punch:
        final decoded = UdpPackets.decodePunch(d.data);
        if (decoded == null) return;
        final (id, reply) = decoded;
        final key = bytesToHex(id);
        final p = _punches[key];
        if (p == null && !_isAllowed(key)) return;
        if (!reply) {
          transport.send(
            UdpPackets.encodePunch(id, reply: true),
            d.address,
            d.port,
          );
        }
        if (p != null && !p.done.isCompleted) {
          p.done.complete((d.address, d.port));
        }
    }
  }

  bool _isAllowed(String key) {
    final until = _allowed[key];
    return until != null && until > _clock.elapsedMicroseconds;
  }

  void _onStreamPacket(StreamPacket p, ReceivedDatagram d) {
    final key = _key(d.address, d.port, p.connectionId);
    final stream = _streams[key];
    if (stream != null) {
      stream.receive(p);
      return;
    }
    if (p.type == UdpPackets.syn) {
      if (p.payload.length != UdpPackets.punchIdLength ||
          !_incoming.hasListener) {
        return;
      }
      final punch = bytesToHex(p.payload);
      if (!_isAllowed(punch)) return;
      _allowed.remove(punch);
      final accepted = UdpStream.attach(
        remoteAddress: d.address,
        remotePort: d.port,
        connectionId: p.connectionId,
        initiator: false,
        options: options,
        send: (data) => transport.send(data, d.address, d.port),
        writable: () => transport.writable,
        onClosed: (s) => _remove(key, s),
      );
      _streams[key] = accepted;
      streamsAccepted++;
      _incoming.add(accepted);
      return;
    }
    if (p.type == UdpPackets.reset) return;
    // Поток неизвестен (закрыт или узел перезапущен): сбросить у
    // собеседника, чтобы он не ждал таймаута. Ответ не длиннее запроса.
    transport.send(
      StreamPacket(
        type: UdpPackets.reset,
        connectionId: p.connectionId,
        seq: 0,
        ack: 0,
        timestamp: 0,
        timestampDiff: 0,
        window: 0,
      ).encode(),
      d.address,
      d.port,
    );
  }

  Uint8List _randomBytes(int n) =>
      Uint8List.fromList(List<int>.generate(n, (_) => _random.nextInt(256)));
}

final class _Punch {
  final done = Completer<(InternetAddress, int)>();
}
