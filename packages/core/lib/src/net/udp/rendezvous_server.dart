import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:core/src/net/udp/datagram_transport.dart';
import 'package:core/src/net/udp/udp_packets.dart';

/// Сводник (protocol.md, раздел 4.11): на запрос сообщает отправителю его
/// внешний адрес и порт, каким их видит, с подтверждением [issueToken] для
/// координатора. Слушает два порта: по разнице ответов сторона узнаёт
/// симметричный NAT. Состояния не хранит; ответ не длиннее запроса, так
/// что запрос с поддельным адресом отправителя не усиливается.
final class RendezvousServer {
  new(this.sockets, {required this.issueToken, this.allow}) {
    for (final s in sockets) {
      _subscriptions.add(s.datagrams.listen((d) => _onDatagram(s, d)));
    }
  }

  /// Привязывает два сокета: [port] и `port + 1` на [host].
  static Future<RendezvousServer> bind({
    required int port,
    required Uint8List Function(InternetAddress address, int port) issueToken,
    Object? host,
    bool Function(InternetAddress address)? allow,
  }) async {
    final first = await RawDatagramTransport.bind(host: host, port: port);
    try {
      final second = await RawDatagramTransport.bind(
        host: host,
        port: port == 0 ? 0 : port + 1,
      );
      return RendezvousServer(
        [first, second],
        issueToken: issueToken,
        allow: allow,
      );
    } on Object {
      first.close();
      rethrow;
    }
  }

  final List<DatagramTransport> sockets;

  /// Подтверждение адреса: [UdpPackets.bindingTokenLength] байт.
  final Uint8List Function(InternetAddress address, int port) issueToken;

  /// Предел частоты по адресу отправителя; `false` — запрос пропускается.
  final bool Function(InternetAddress address)? allow;

  final _subscriptions = <StreamSubscription<ReceivedDatagram>>[];

  int requests = 0;

  List<int> get ports => [for (final s in sockets) s.port];

  void _onDatagram(DatagramTransport socket, ReceivedDatagram d) {
    final tx = UdpPackets.decodeBindingRequest(d.data);
    if (tx == null) return;
    if (allow != null && !allow!(d.address)) return;
    requests++;
    socket.send(
      UdpPackets.encodeBindingResponse(
        BindingResponse(
          transactionId: tx,
          address: d.address,
          port: d.port,
          token: issueToken(d.address, d.port),
        ),
      ),
      d.address,
      d.port,
    );
  }

  Future<void> close() async {
    for (final s in _subscriptions) {
      await s.cancel();
    }
    for (final s in sockets) {
      s.close();
    }
  }
}
