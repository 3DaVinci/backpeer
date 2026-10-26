import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:core/src/net/udp/datagram_transport.dart';

/// Поведение NAT по RFC 4787: как выделяется внешний порт и кого он
/// пропускает внутрь.
enum NatType {
  /// Один внешний порт на внутренний сокет, внутрь — от кого угодно.
  fullCone,

  /// Один внешний порт, внутрь — только с адресов, куда сокет уже слал.
  addressRestricted,

  /// Один внешний порт, внутрь — только с адресов и портов, куда сокет
  /// уже слал (самый частый домашний роутер).
  portRestricted,

  /// Свой внешний порт на каждого адресата: адрес, который увидел
  /// сводник, собеседнику не годится.
  symmetric,
}

/// Условия исходящего канала узла: потери, задержка и узкое место с
/// очередью, как у домашнего роутера.
final class LinkConditions {
  const new({
    this.loss = 0,
    this.delay = Duration.zero,
    this.bytesPerSecond,
    this.queueBytes = 256 * 1024,
  });

  /// Доля пакетов, потерянных случайно.
  final double loss;

  /// Задержка распространения в одну сторону.
  final Duration delay;

  /// Скорость узкого места; `null` — без предела.
  final int? bytesPerSecond;

  /// Очередь перед узким местом; пакет, который не помещается,
  /// отбрасывается.
  final int queueBytes;
}

/// Статистика исходящего канала.
final class LinkStats {
  int packets = 0;
  int bytes = 0;
  int dropped = 0;
  int lost = 0;

  /// Задержки в очереди узкого места, микросекунды, по пакетам.
  final queueDelays = <int>[];

  /// Средняя задержка в очереди за последние [last] пакетов.
  Duration averageQueueDelay([int last = 1 << 30]) {
    if (queueDelays.isEmpty) return Duration.zero;
    final tail = queueDelays.length > last
        ? queueDelays.sublist(queueDelays.length - last)
        : queueDelays;
    return Duration(microseconds: tail.reduce((a, b) => a + b) ~/ tail.length);
  }
}

/// Модель сети в памяти процесса для тестов сведения узлов и потока
/// поверх UDP: узлы с публичными адресами, узлы за NAT разных типов,
/// потери, задержки, узкое место с очередью. Сокеты — [DatagramTransport],
/// как у [RawDatagramTransport].
final class SimulatedNetwork {
  new({math.Random? random}) : _random = random ?? math.Random(1);

  final math.Random _random;
  final _public = <String, SimulatedHost>{};
  final _nats = <String, SimulatedNat>{};
  static final _clock = Stopwatch()..start();

  /// Узел с публичным адресом [address].
  SimulatedHost host(
    String address, {
    LinkConditions uplink = const LinkConditions(),
  }) {
    final h = SimulatedHost._(this, InternetAddress(address), null, uplink);
    _public[address] = h;
    return h;
  }

  /// Роутер с NAT типа [type] и внешним адресом [publicAddress].
  SimulatedNat nat(String publicAddress, NatType type) => _nats[publicAddress] =
      SimulatedNat._(this, InternetAddress(publicAddress), type);

  void _send(
    SimulatedHost from,
    int fromPort,
    Uint8List data,
    InternetAddress to,
    int toPort,
  ) {
    final link = from.uplink;
    final stats = from.stats
      ..packets += 1
      ..bytes += data.length;
    if (link.loss > 0 && _random.nextDouble() < link.loss) {
      stats.lost++;
      return;
    }
    final now = _clock.elapsedMicroseconds;
    var departure = now;
    final bps = link.bytesPerSecond;
    if (bps != null) {
      final start = math.max(now, from._busyUntil);
      final queued = (start - now) * bps ~/ 1000000;
      if (queued + data.length > link.queueBytes) {
        stats.dropped++;
        return;
      }
      stats.queueDelays.add(start - now);
      departure = from._busyUntil = start + data.length * 1000000 ~/ bps;
    }
    final copy = Uint8List.fromList(data);
    final at = departure + link.delay.inMicroseconds;
    Timer(
      Duration(microseconds: at - now),
      () => _route(from, fromPort, copy, to, toPort),
    );
  }

  void _route(
    SimulatedHost from,
    int fromPort,
    Uint8List data,
    InternetAddress to,
    int toPort,
  ) {
    var srcAddress = from.address;
    var srcPort = fromPort;
    if (from.nat case final nat?) {
      (srcAddress, srcPort) = nat._outbound(from, fromPort, to, toPort);
    }
    final key = to.address;
    if (_public[key] case final host?) {
      host._deliver(toPort, data, srcAddress, srcPort);
      return;
    }
    if (_nats[key] case final nat?) {
      nat._inbound(toPort, data, srcAddress, srcPort);
    }
  }
}

/// Роутер с NAT в [SimulatedNetwork].
final class SimulatedNat {
  new _(this._network, this.publicAddress, this.type);

  final SimulatedNetwork _network;
  final InternetAddress publicAddress;
  final NatType type;
  final _hosts = <String, SimulatedHost>{};
  final _out = <String, _Mapping>{};
  final _in = <int, _Mapping>{};
  int _nextPort = 40000;

  /// Сколько внешних портов выделено.
  int get mappings => _in.length;

  /// Узел за этим NAT с частным адресом [address].
  SimulatedHost host(
    String address, {
    LinkConditions uplink = const LinkConditions(),
  }) => _hosts[address] = SimulatedHost._(
    _network,
    InternetAddress(address),
    this,
    uplink,
  );

  (InternetAddress, int) _outbound(
    SimulatedHost host,
    int port,
    InternetAddress to,
    int toPort,
  ) {
    final key = type == NatType.symmetric
        ? '${host.address.address}/$port/${to.address}/$toPort'
        : '${host.address.address}/$port';
    final m = _out.putIfAbsent(key, () {
      final mapping = _Mapping(host, port, _nextPort++);
      _in[mapping.publicPort] = mapping;
      return mapping;
    });
    m.allowed.add(switch (type) {
      NatType.fullCone => '*',
      NatType.addressRestricted => to.address,
      NatType.portRestricted || NatType.symmetric => '${to.address}/$toPort',
    });
    return (publicAddress, m.publicPort);
  }

  void _inbound(int port, Uint8List data, InternetAddress from, int fromPort) {
    final m = _in[port];
    if (m == null) return;
    final pass = switch (type) {
      NatType.fullCone => true,
      NatType.addressRestricted => m.allowed.contains(from.address),
      NatType.portRestricted ||
      NatType.symmetric => m.allowed.contains('${from.address}/$fromPort'),
    };
    if (pass) m.host._deliver(m.port, data, from, fromPort);
  }
}

final class _Mapping {
  new(this.host, this.port, this.publicPort);

  final SimulatedHost host;
  final int port;
  final int publicPort;
  final allowed = <String>{};
}

/// Узел в [SimulatedNetwork].
final class SimulatedHost {
  new _(this._network, this.address, this.nat, this.uplink);

  final SimulatedNetwork _network;
  final InternetAddress address;

  /// Роутер, за которым узел; `null` — публичный адрес.
  final SimulatedNat? nat;
  final LinkConditions uplink;
  final stats = LinkStats();
  final _sockets = <int, _SimulatedSocket>{};
  int _nextPort = 50000;
  int _busyUntil = 0;

  /// Сокет на порту [port] (0 — любой свободный).
  DatagramTransport bind([int port = 0]) {
    var p = port;
    if (p == 0) {
      while (_sockets.containsKey(_nextPort)) {
        _nextPort++;
      }
      p = _nextPort++;
    }
    if (_sockets.containsKey(p)) {
      throw SocketException('порт $p занят', port: p);
    }
    return _sockets[p] = _SimulatedSocket(this, p);
  }

  void _deliver(int port, Uint8List data, InternetAddress from, int fromPort) =>
      _sockets[port]?._receive(data, from, fromPort);
}

final class _SimulatedSocket implements DatagramTransport {
  new(this._host, this.port);

  final SimulatedHost _host;
  @override
  final int port;
  final _controller = StreamController<ReceivedDatagram>(sync: true);
  bool _closed = false;

  @override
  InternetAddress get address => _host.address;

  @override
  Stream<ReceivedDatagram> get datagrams => _controller.stream;

  @override
  bool send(Uint8List data, InternetAddress address, int port) {
    if (!_closed) _host._network._send(_host, this.port, data, address, port);
    return true;
  }

  @override
  Future<void> get writable => Future.value();

  void _receive(Uint8List data, InternetAddress from, int fromPort) {
    if (_closed || !_controller.hasListener) return;
    _controller.add(ReceivedDatagram(data, from, fromPort));
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _host._sockets.remove(port);
    unawaited(_controller.close());
  }
}

/// [DatagramTransport], теряющий долю [loss] исходящих датаграмм: для
/// проверки потока поверх настоящего UDP с потерями.
final class LossyTransport implements DatagramTransport {
  new(this._inner, {required this.loss, math.Random? random})
    : _random = random ?? math.Random(2);

  final DatagramTransport _inner;
  final double loss;
  final math.Random _random;
  int dropped = 0;

  @override
  InternetAddress get address => _inner.address;

  @override
  int get port => _inner.port;

  @override
  Stream<ReceivedDatagram> get datagrams => _inner.datagrams;

  @override
  bool send(Uint8List data, InternetAddress address, int port) {
    if (_random.nextDouble() < loss) {
      dropped++;
      return true;
    }
    return _inner.send(data, address, port);
  }

  @override
  Future<void> get writable => _inner.writable;

  @override
  void close() => _inner.close();
}
