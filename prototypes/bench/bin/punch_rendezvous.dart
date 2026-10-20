// Прототип 0.5.4: сервер-«сводник» для UDP hole punching.
//
//   punch_rendezvous [порт]        (по умолчанию 3478; занимает порт и порт+1)
//
// Протокол — JSON в UDP-датаграммах:
//   узел → сервер:  {"type":"register","session":"s1","peer":"A"}
//   сервер → узел:  {"type":"peer","peer":"B","address":"1.2.3.4","port":5}
//                   (когда в сессии зарегистрированы оба узла)
//   узел → сервер (порт+1): {"type":"probe"}
//   сервер → узел:  {"type":"observed","address":"…","port":…}
// По ответу на probe узел понимает, меняется ли его внешний порт в
// зависимости от адресата (симметричный NAT, через который пробиться трудно).

import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> arguments) async {
  final port = arguments.isEmpty ? 3478 : int.parse(arguments.first);
  final main = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port);
  final probe = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port + 1);
  stdout.writeln('Сводник слушает UDP $port и ${port + 1}');

  // session → peer → наблюдаемый адрес.
  final sessions = <String, Map<String, (InternetAddress, int)>>{};

  main.listen((event) {
    if (event != RawSocketEvent.read) return;
    final datagram = main.receive();
    if (datagram == null) return;
    final message = _decode(datagram.data);
    if (message == null || message['type'] != 'register') return;
    final session = message['session']! as String;
    final peer = message['peer']! as String;
    final peers = sessions.putIfAbsent(session, () => {});
    peers[peer] = (datagram.address, datagram.port);
    stdout.writeln(
      '$session/$peer: ${datagram.address.address}:${datagram.port}',
    );
    if (peers.length < 2) return;
    for (final MapEntry(key: name, value: (address, port)) in peers.entries) {
      final other = peers.entries.firstWhere((e) => e.key != name);
      main.send(
        utf8.encode(
          jsonEncode({
            'type': 'peer',
            'peer': other.key,
            'address': other.value.$1.address,
            'port': other.value.$2,
          }),
        ),
        address,
        port,
      );
    }
  });

  probe.listen((event) {
    if (event != RawSocketEvent.read) return;
    final datagram = probe.receive();
    if (datagram == null) return;
    probe.send(
      utf8.encode(
        jsonEncode({
          'type': 'observed',
          'address': datagram.address.address,
          'port': datagram.port,
        }),
      ),
      datagram.address,
      datagram.port,
    );
  });
}

Map<String, Object?>? _decode(List<int> data) {
  try {
    return jsonDecode(utf8.decode(data)) as Map<String, Object?>;
  } on FormatException {
    return null;
  }
}
