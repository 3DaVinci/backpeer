// Прототип 0.5.4: узел для UDP hole punching.
//
//   punch_peer <адрес сводника> <порт> <сессия> <имя узла>
//
// 1. Регистрируется у сводника (повтор раз в секунду, пока не придёт адрес
//    второго узла) и сравнивает внешний порт, видимый с двух портов
//    сводника: разные порты — признак симметричного NAT.
// 2. Получив адрес второго узла, 15 секунд шлёт ему punch каждые 100 мс.
// 3. Первый пакет от второго узла — успех; затем 10 ping для замера RTT.
// Итог печатается одной строкой JSON для сводной таблицы в docs/benchmarks.md.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 4) {
    stderr.writeln('Использование: punch_peer <сводник> <порт> <сессия> <имя>');
    exit(2);
  }
  final server = (await InternetAddress.lookup(arguments[0])).first;
  final serverPort = int.parse(arguments[1]);
  final session = arguments[2];
  final name = arguments[3];

  final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  final result = <String, Object?>{'peer': name, 'session': session};
  final started = DateTime.now();

  final observed = <int>{};
  (InternetAddress, int)? remote;
  DateTime? punchStarted;
  final connected = Completer<void>();
  final rtts = <int>[];
  final pending = <int, DateTime>{};

  void send(Map<String, Object?> message, InternetAddress to, int port) =>
      socket.send(utf8.encode(jsonEncode(message)), to, port);

  socket.listen((event) {
    if (event != RawSocketEvent.read) return;
    final datagram = socket.receive();
    if (datagram == null) return;
    final Map<String, Object?> message;
    try {
      message = jsonDecode(utf8.decode(datagram.data)) as Map<String, Object?>;
    } on FormatException {
      return;
    }
    switch (message['type']) {
      case 'observed':
        observed.add(message['port']! as int);
      case 'peer' when remote == null:
        remote = (
          InternetAddress(message['address']! as String),
          message['port']! as int,
        );
        punchStarted = DateTime.now();
        result['remote'] = '${message['address']}:${message['port']}';
      case 'punch':
        send({'type': 'ack'}, datagram.address, datagram.port);
        _markConnected(connected, result, punchStarted, datagram);
      case 'ack':
        _markConnected(connected, result, punchStarted, datagram);
      case 'ping':
        send(
          {'type': 'pong', 'seq': message['seq']},
          datagram.address,
          datagram.port,
        );
      case 'pong':
        final sent = pending.remove(message['seq']);
        if (sent != null) {
          rtts.add(DateTime.now().difference(sent).inMilliseconds);
        }
    }
  });

  // Регистрация и проба типа NAT.
  final register = Timer.periodic(const Duration(seconds: 1), (_) {
    if (remote != null) return;
    send(
      {'type': 'register', 'session': session, 'peer': name},
      server,
      serverPort,
    );
    send({'type': 'probe'}, server, serverPort + 1);
  });
  send(
    {'type': 'register', 'session': session, 'peer': name},
    server,
    serverPort,
  );
  send({'type': 'probe'}, server, serverPort + 1);

  // Ждём адрес второго узла (до 120 с), затем пробиваемся (до 15 с).
  while (remote == null &&
      DateTime.now().difference(started) < const Duration(seconds: 120)) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  register.cancel();
  result['natPortsSeenByServer'] = observed.toList();
  result['symmetricNatSuspected'] = observed.length > 1;
  if (remote == null) {
    result['ok'] = false;
    result['error'] = 'второй узел не зарегистрировался';
    _finish(socket, result);
    return;
  }

  final (address, port) = remote!;
  final punch = Timer.periodic(const Duration(milliseconds: 100), (_) {
    send({'type': 'punch', 'from': name}, address, port);
  });
  await connected.future.timeout(const Duration(seconds: 15), onTimeout: () {});
  punch.cancel();
  if (!connected.isCompleted) {
    result['ok'] = false;
    result['error'] = 'нет ответа от узла за 15 с';
    _finish(socket, result);
    return;
  }

  for (var seq = 0; seq < 10; seq++) {
    pending[seq] = DateTime.now();
    send({'type': 'ping', 'seq': seq}, address, port);
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  await Future<void>.delayed(const Duration(seconds: 1));
  result
    ..['ok'] = true
    ..['pingReplies'] = rtts.length
    ..['rttMsMedian'] = rtts.isEmpty ? null : (rtts..sort())[rtts.length ~/ 2];
  _finish(socket, result);
}

void _markConnected(
  Completer<void> connected,
  Map<String, Object?> result,
  DateTime? punchStarted,
  Datagram datagram,
) {
  if (connected.isCompleted) return;
  result['connectedVia'] = '${datagram.address.address}:${datagram.port}';
  if (punchStarted != null) {
    result['punchMs'] = DateTime.now().difference(punchStarted).inMilliseconds;
  }
  connected.complete();
}

void _finish(RawDatagramSocket socket, Map<String, Object?> result) {
  stdout.writeln(jsonEncode(result));
  socket.close();
}
