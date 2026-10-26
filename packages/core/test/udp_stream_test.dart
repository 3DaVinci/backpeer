// Надёжный поток поверх UDP (задача 3.7.3; protocol.md, раздел 3.5):
// доставка по порядку при потерях и перестановках, обратное давление,
// закрытие и сброс, таймауты, «вежливое» управление перегрузкой (LEDBAT)
// рядом с обычным трафиком.
//
// Долгая проверка критерия 3.7.3 — 1 ГиБ по настоящему UDP при потере 2 %
// пакетов: FS_UDP_TEST_BYTES=1073741824 dart test test/udp_stream_test.dart
// -n '2 %' (по умолчанию — 32 МиБ).

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:test/test.dart';

/// Детерминированные данные: байт зависит от смещения.
Uint8List pattern(int length, [int seed = 0]) {
  final out = Uint8List(length);
  var x = seed * 2654435761 + 1;
  for (var i = 0; i < length; i++) {
    x = (x * 1103515245 + 12345) & 0x7fffffff;
    out[i] = x >> 16;
  }
  return out;
}

/// Отправляет [total] байт порциями по 64 КиБ с ожиданием `flush` и
/// закрывает поток.
Future<void> sendAll(ByteConnection c, int total, {int seed = 0}) async {
  const chunk = 64 * 1024;
  final block = pattern(chunk * 4, seed);
  var sent = 0;
  while (sent < total) {
    final n = math.min(chunk, total - sent);
    final off = (sent ~/ chunk % 4) * chunk;
    c.add(Uint8List.sublistView(block, off, off + n));
    sent += n;
    await c.flush();
  }
  await c.close();
}

/// Читает поток до конца и сверяет с тем, что отправляет [sendAll].
Future<int> receiveAll(ByteConnection c, {int seed = 0}) async {
  const chunk = 64 * 1024;
  final block = pattern(chunk * 4, seed);
  var got = 0;
  await for (final data in c.input) {
    for (var i = 0; i < data.length; i++) {
      final pos = got + i;
      final expected = block[(pos ~/ chunk % 4) * chunk + pos % chunk];
      if (data[i] != expected) {
        fail('байт $pos: ${data[i]} вместо $expected');
      }
    }
    got += data.length;
  }
  return got;
}

final class Pair {
  new(this.client, this.server, this.clientEndpoint, this.serverEndpoint);

  final UdpStream client;
  final UdpStream server;
  final UdpEndpoint clientEndpoint;
  final UdpEndpoint serverEndpoint;

  Future<void> close() async {
    await clientEndpoint.close();
    await serverEndpoint.close();
  }
}

Future<Pair> connectPair(
  DatagramTransport a,
  DatagramTransport b,
  InternetAddress bAddress, {
  UdpStreamOptions options = const UdpStreamOptions(),
  UdpStreamOptions? serverOptions,
}) async {
  final ea = UdpEndpoint(a, options: options);
  final eb = UdpEndpoint(b, options: serverOptions ?? options);
  final punchId = Uint8List.fromList(List.generate(16, (i) => i + 1));
  eb.allow(punchId);
  final accepted = eb.incoming.first;
  final client = await ea.connect(bAddress, eb.port, punchId: punchId);
  return Pair(client, await accepted, ea, eb);
}

Future<Pair> simulatedPair({
  LinkConditions a = const LinkConditions(),
  LinkConditions b = const LinkConditions(),
  UdpStreamOptions options = const UdpStreamOptions(),
  UdpStreamOptions? serverOptions,
  int seed = 1,
}) {
  final net = SimulatedNetwork(random: math.Random(seed));
  final ha = net.host('198.51.100.1', uplink: a);
  final hb = net.host('198.51.100.2', uplink: b);
  return connectPair(
    ha.bind(),
    hb.bind(),
    hb.address,
    options: options,
    serverOptions: serverOptions,
  );
}

void main() {
  group('пакеты', () {
    test('заголовок потока туда и обратно', () {
      final p = StreamPacket(
        type: UdpPackets.data,
        connectionId: 0xdeadbeef,
        seq: 0xfffffffe,
        ack: 7,
        timestamp: 123456789,
        timestampDiff: 0x80000001,
        window: 1 << 20,
        sack: Uint8List.fromList([0x81, 0, 4]),
        payload: Uint8List.fromList([1, 2, 3]),
      );
      final d = StreamPacket.decode(p.encode())!;
      expect(d.type, p.type);
      expect(d.connectionId, p.connectionId);
      expect(d.seq, p.seq);
      expect(d.ack, 7);
      expect(d.timestamp, 123456789);
      expect(d.timestampDiff, 0x80000001);
      expect(d.window, 1 << 20);
      expect(d.sack, [0x81, 0, 4]);
      expect(d.payload, [1, 2, 3]);
    });

    test('битые пакеты не разбираются', () {
      final ok = StreamPacket(
        type: UdpPackets.state,
        connectionId: 1,
        seq: 1,
        ack: 0,
        timestamp: 0,
        timestampDiff: 0,
        window: 0,
      ).encode();
      expect(StreamPacket.decode(Uint8List.sublistView(ok, 0, 25)), isNull);
      expect(StreamPacket.decode(Uint8List.fromList(ok)..[0] = 0x20), isNull);
      expect(StreamPacket.decode(Uint8List.fromList(ok)..[25] = 33), isNull);
      expect(StreamPacket.decode(Uint8List.fromList(ok)..[25] = 1), isNull);
      final big = Uint8List(StreamPacket.headerLength + 1153)..[0] = 0x11;
      expect(StreamPacket.decode(big), isNull);
    });

    test('ответ сводника не длиннее запроса', () {
      final tx = Uint8List(12)..[0] = 9;
      final request = UdpPackets.encodeBindingRequest(tx);
      expect(UdpPackets.decodeBindingRequest(request), tx);
      for (final address in [
        InternetAddress('203.0.113.7'),
        InternetAddress('2001:db8::1'),
      ]) {
        final response = UdpPackets.encodeBindingResponse(
          BindingResponse(
            transactionId: tx,
            address: address,
            port: 40001,
            token: Uint8List(20)..[19] = 1,
          ),
        );
        expect(response.length, lessThanOrEqualTo(request.length));
        final r = UdpPackets.decodeBindingResponse(response)!;
        expect(r.address, address);
        expect(r.port, 40001);
        expect(r.token[19], 1);
      }
      expect(
        UdpPackets.decodeBindingRequest(Uint8List.sublistView(request, 0, 63)),
        isNull,
      );
    });

    test('номер восстанавливается по младшим 32 битам', () {
      expect(expandSequence(5, 3), 5);
      expect(expandSequence(0xffffffff, (1 << 32) + 2), 0xffffffff);
      expect(expandSequence(1, 0xfffffff0), (1 << 32) + 1);
      expect(expandSequence(0, 0), 0);
    });
  });

  group('поток', () {
    test('8 МиБ без потерь — по порядку', () async {
      final p = await simulatedPair();
      final received = receiveAll(p.server);
      await sendAll(p.client, 8 << 20);
      expect(await received, 8 << 20);
      await p.close();
    });

    test('в обе стороны одновременно', () async {
      final p = await simulatedPair(
        a: const LinkConditions(delay: Duration(milliseconds: 5)),
        b: const LinkConditions(delay: Duration(milliseconds: 5)),
      );
      final results = await Future.wait([
        receiveAll(p.server, seed: 1),
        receiveAll(p.client, seed: 2),
        sendAll(p.client, 2 << 20, seed: 1).then((_) => 0),
        sendAll(p.server, 3 << 20, seed: 2).then((_) => 0),
      ]);
      expect(results.take(2), [2 << 20, 3 << 20]);
      await p.close();
    });

    test('потери 5 % и задержка в обе стороны — данные целы', () async {
      const link = LinkConditions(
        loss: 0.05,
        delay: Duration(milliseconds: 10),
      );
      final p = await simulatedPair(a: link, b: link, seed: 7);
      final received = receiveAll(p.server);
      await sendAll(p.client, 4 << 20);
      expect(await received, 4 << 20);
      expect(p.client.retransmissions, greaterThan(0));
      await p.close();
    });

    test('перестановки: узкое место и потери — данные целы', () async {
      final p = await simulatedPair(
        a: const LinkConditions(
          loss: 0.02,
          bytesPerSecond: 4 << 20,
          queueBytes: 64 << 10,
          delay: Duration(milliseconds: 3),
        ),
        seed: 3,
      );
      final received = receiveAll(p.server);
      await sendAll(p.client, 2 << 20);
      expect(await received, 2 << 20);
      await p.close();
    });

    test('читатель встал: отправитель упирается в окно и буфер', () async {
      const options = UdpStreamOptions(
        receiveWindow: 256 << 10,
        sendBuffer: 256 << 10,
      );
      final p = await simulatedPair(options: options);
      final chunks = <Uint8List>[];
      // Подписка завершается сама вместе с потоком.
      // ignore: cancel_subscriptions
      final sub = p.server.input.listen(chunks.add)..pause();
      final done = sub.asFuture<void>();
      var flushed = 0;
      final writer = () async {
        final block = pattern(64 << 10);
        for (var i = 0; i < 64; i++) {
          p.client.add(block);
          await p.client.flush();
          flushed++;
        }
      }();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      // Окно получателя и буфер отправителя — по 256 КиБ: из 4 МиБ ушло
      // не больше их суммы.
      expect(flushed * (64 << 10), lessThanOrEqualTo(640 << 10));
      expect(p.client.bytesSent, lessThan(400 << 10));
      sub.resume();
      await writer;
      expect(flushed, 64);
      await p.client.close();
      await done;
      expect(chunks.fold<int>(0, (n, c) => n + c.length), 64 * (64 << 10));
      await p.close();
    });

    test('сообщение об открытии окна потерялось — помогает проба', () async {
      const options = UdpStreamOptions(
        receiveWindow: 64 << 10,
        sendBuffer: 64 << 10,
      );
      final p = await simulatedPair(
        options: options,
        b: const LinkConditions(loss: 0.3),
        seed: 11,
      );
      // ignore: cancel_subscriptions — завершается вместе с потоком.
      final sub = p.server.input.listen(null)..pause();
      final done = sub.asFuture<void>();
      final sent = sendAll(p.client, 1 << 20);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      sub.resume();
      await sent;
      await done;
      await p.close();
    });

    test(
      'закрытие: FIN доходит после данных, вторая сторона дописывает',
      () async {
        final p = await simulatedPair(
          a: const LinkConditions(loss: 0.1),
          b: const LinkConditions(loss: 0.1),
          seed: 5,
        );
        p.client.add(Uint8List.fromList([1, 2, 3]));
        final closed = p.client.close();
        final got = <int>[];
        await p.server.input.forEach(got.addAll);
        expect(got, [1, 2, 3]);
        // Половина закрыта: в обратную сторону поток работает.
        p.server.add(Uint8List.fromList([4, 5]));
        final back = <int>[];
        final reading = p.client.input.forEach(back.addAll);
        await p.server.close();
        await reading;
        await closed;
        expect(back, [4, 5]);
        await Future<void>.delayed(const Duration(milliseconds: 1500));
        expect(p.client.isClosed, isTrue);
        expect(p.server.isClosed, isTrue);
        expect(p.clientEndpoint.streamCount, 0);
        expect(p.serverEndpoint.streamCount, 0);
        await p.close();
      },
    );

    test('destroy: у собеседника чтение кончается', () async {
      final p = await simulatedPair();
      final done = p.server.input.drain<void>();
      p.client.destroy();
      await done;
      expect(p.server.isClosed, isTrue);
      expect(p.serverEndpoint.streamCount, 0);
      await p.close();
    });

    test('собеседник пропал — ошибка по таймауту молчания', () async {
      const options = UdpStreamOptions(
        idleTimeout: Duration(milliseconds: 600),
        keepalive: Duration(milliseconds: 100),
      );
      final p = await simulatedPair(options: options);
      // Держит соединение keepalive: за две idleTimeout поток жив.
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      expect(p.client.isClosed, isFalse);
      final error = p.client.input.drain<void>();
      p.serverEndpoint.transport.close();
      await expectLater(error, throwsA(isA<UdpStreamException>()));
      await p.close();
    });

    test('данные не подтверждаются — ошибка за deadTimeout', () async {
      const options = UdpStreamOptions(
        deadTimeout: Duration(milliseconds: 800),
        minRto: Duration(milliseconds: 50),
      );
      final net = SimulatedNetwork();
      final ha = net.host('198.51.100.1');
      final hb = net.host('198.51.100.2');
      final p = await connectPair(
        ha.bind(),
        hb.bind(),
        hb.address,
        options: options,
      );
      final error = p.client.input.drain<void>();
      p.serverEndpoint.transport.close();
      p.client.add(Uint8List(10000));
      await expectLater(error, throwsA(isA<UdpStreamException>()));
      await p.close();
    });

    test('SYN без разрешённого номера сведения не принимается', () async {
      final net = SimulatedNetwork();
      final ha = net.host('198.51.100.1');
      final hb = net.host('198.51.100.2');
      final ea = UdpEndpoint(
        ha.bind(),
        options: const UdpStreamOptions(
          connectTimeout: Duration(milliseconds: 700),
        ),
      );
      final eb = UdpEndpoint(hb.bind());
      final accepted = <UdpStream>[];
      eb.incoming.listen(accepted.add);
      eb.allow(Uint8List(16)..[0] = 1);
      await expectLater(
        ea.connect(hb.address, eb.port, punchId: Uint8List(16)),
        throwsA(isA<UdpStreamException>()),
      );
      expect(accepted, isEmpty);
      // Разрешённый номер — один поток.
      final ok = await ea.connect(
        hb.address,
        eb.port,
        punchId: Uint8List(16)..[0] = 1,
      );
      await expectLater(
        ea.connect(hb.address, eb.port, punchId: Uint8List(16)..[0] = 1),
        throwsA(isA<UdpStreamException>()),
      );
      expect(accepted, hasLength(1));
      ok.destroy();
      await ea.close();
      await eb.close();
    });

    test('пакет неизвестному потоку — RST', () async {
      final net = SimulatedNetwork();
      final ha = net.host('198.51.100.1');
      final hb = net.host('198.51.100.2');
      final p = await connectPair(ha.bind(), hb.bind(), hb.address);
      final done = p.client.input.drain<void>();
      // Узел перезапущен на том же порту: о потоке он не знает.
      final port = p.serverEndpoint.port;
      p.serverEndpoint.transport.close();
      final restarted = UdpEndpoint(hb.bind(port));
      p.client.add(Uint8List(10));
      await done;
      expect(p.client.isClosed, isTrue);
      await restarted.close();
      await p.close();
    });

    test('по настоящему UDP при потере 2 % пакетов', () async {
      final total =
          int.tryParse(Platform.environment['FS_UDP_TEST_BYTES'] ?? '') ??
          32 << 20;
      final a = LossyTransport(
        await RawDatagramTransport.bind(host: InternetAddress.loopbackIPv4),
        loss: 0.02,
        random: math.Random(1),
      );
      final b = LossyTransport(
        await RawDatagramTransport.bind(host: InternetAddress.loopbackIPv4),
        loss: 0.02,
        random: math.Random(2),
      );
      const options = UdpStreamOptions(
        receiveWindow: 4 << 20,
        sendBuffer: 4 << 20,
      );
      final p = await connectPair(
        a,
        b,
        InternetAddress.loopbackIPv4,
        options: options,
      );
      final watch = Stopwatch()..start();
      final received = receiveAll(p.server);
      await sendAll(p.client, total);
      expect(await received, total);
      final seconds = watch.elapsedMilliseconds / 1000;
      printOnFailure('$total байт за $seconds с');
      if (total >= 1 << 30) {
        // Итог долгого замера — в журнал прогона.
        // ignore: avoid_print
        print(
          '${total >> 20} МиБ за ${seconds.toStringAsFixed(1)} с '
          '(${(total / seconds / (1 << 20)).toStringAsFixed(1)} МиБ/с), '
          'потеряно ${a.dropped + b.dropped} пакетов, повторов '
          '${p.client.retransmissions}',
        );
      }
      expect(a.dropped, greaterThan(0));
      await p.close();
    }, timeout: const Timeout(Duration(minutes: 30)));
  });

  group('управление перегрузкой', () {
    // Канал узла: 1 МиБ/с, очередь роутера на секунду (обычный домашний
    // роутер с «раздутым» буфером), 20 мс до собеседника.
    const uplink = LinkConditions(
      bytesPerSecond: 1 << 20,
      queueBytes: 1 << 20,
      delay: Duration(milliseconds: 20),
    );

    test('LEDBAT один занимает канал и держит очередь около цели', () async {
      final net = SimulatedNetwork();
      final ha = net.host('198.51.100.1', uplink: uplink);
      final hb = net.host('198.51.100.2');
      final p = await connectPair(ha.bind(), hb.bind(), hb.address);
      final got = <int>[];
      var bytes = 0;
      final reading = p.server.input.listen((d) => bytes += d.length);
      final writing = () async {
        final block = Uint8List(64 << 10);
        while (!p.client.isClosed) {
          p.client.add(block);
          await p.client.flush();
        }
      }();
      for (var s = 0; s < 8; s++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        got.add(bytes);
      }
      final delay = ha.stats.averageQueueDelay(400);
      p.client.destroy();
      await writing;
      await reading.cancel();
      // Последние 2 секунды: не меньше 70 % канала, очередь — около цели
      // 100 мс, а не секунда буфера роутера.
      final rate = (got.last - got[got.length - 5]) / 2;
      printOnFailure('скорость $rate Б/с, очередь $delay');
      expect(rate, greaterThan(0.7 * (1 << 20)));
      expect(delay, lessThan(const Duration(milliseconds: 160)));
      await p.close();
    }, timeout: const Timeout(Duration(minutes: 1)));

    test('рядом с обычным TCP-подобным трафиком LEDBAT уступает', () async {
      final net = SimulatedNetwork();
      final ha = net.host('198.51.100.1', uplink: uplink);
      final hb = net.host('198.51.100.2');
      final backup = await connectPair(ha.bind(), hb.bind(), hb.address);
      final browser = await connectPair(
        ha.bind(),
        hb.bind(),
        hb.address,
        options: const UdpStreamOptions(congestion: Reno.new),
      );
      var backupBytes = 0;
      var browserBytes = 0;
      final r1 = backup.server.input.listen((d) => backupBytes += d.length);
      final r2 = browser.server.input.listen((d) => browserBytes += d.length);
      Future<void> pump(UdpStream s) async {
        final block = Uint8List(64 << 10);
        while (!s.isClosed) {
          s.add(block);
          await s.flush();
        }
      }

      final w1 = pump(backup.client);
      // Бэкап занял канал, затем пользователь начал загрузку в браузере.
      await Future<void>.delayed(const Duration(seconds: 2));
      final w2 = pump(browser.client);
      await Future<void>.delayed(const Duration(seconds: 2));
      final (b0, w0) = (backupBytes, browserBytes);
      await Future<void>.delayed(const Duration(seconds: 4));
      final backupRate = (backupBytes - b0) / 4;
      final browserRate = (browserBytes - w0) / 4;
      printOnFailure('бэкап $backupRate Б/с, браузер $browserRate Б/с');
      // Бэкап уступает: у него меньше пятой части того, что у браузера.
      expect(backupRate, lessThan(browserRate / 5));
      expect(browserRate, greaterThan(0.6 * (1 << 20)));
      backup.client.destroy();
      browser.client.destroy();
      await Future.wait([w1, w2]);
      await r1.cancel();
      await r2.cancel();
      await backup.close();
      await browser.close();
    }, timeout: const Timeout(Duration(minutes: 1)));
  });
}
