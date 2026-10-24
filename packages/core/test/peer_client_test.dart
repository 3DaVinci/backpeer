// Сторона запросов по каналу Noise (задачи 3.4.2, 3.4.3): предел скорости,
// соединение в памяти с обратным давлением, мультиплексирование, таймауты,
// отмена и нарушения протокола собеседником. Обработчики узла —
// packages/node/test/peer_service_test.dart.

import 'dart:async';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:fixnum/fixnum.dart';
import 'package:protocol/protocol.dart' as pb;
import 'package:test/test.dart';

void main() {
  group('BandwidthLimiter', () {
    test('без предела не ждёт', () async {
      final limiter = BandwidthLimiter(() => 0);
      final watch = Stopwatch()..start();
      for (var i = 0; i < 1000; i++) {
        await limiter.acquire(1 << 20);
      }
      expect(watch.elapsedMilliseconds, lessThan(200));
    });

    test('средняя скорость — предел с точностью до 10%', () async {
      const rate = 2000000;
      final limiter = BandwidthLimiter(() => rate);
      final watch = Stopwatch()..start();
      var sent = 0;
      while (sent < 2 * rate) {
        await limiter.acquire(PeerOperations.maxChunk);
        sent += PeerOperations.maxChunk;
      }
      final expected = sent / rate * 1000;
      expect(watch.elapsedMilliseconds, closeTo(expected, expected * 0.1));
    });

    test('параллельные передачи делят предел', () async {
      const rate = 1000000;
      final limiter = BandwidthLimiter(() => rate);
      final watch = Stopwatch()..start();
      Future<void> transfer() async {
        for (var i = 0; i < 10; i++) {
          await limiter.acquire(50000);
        }
      }

      await Future.wait([transfer(), transfer()]);
      // 1 МБ на двоих при 1 МБ/с.
      expect(watch.elapsedMilliseconds, closeTo(1000, 100));
    });

    test('предел меняется на ходу', () async {
      var rate = 0;
      final limiter = BandwidthLimiter(() => rate);
      await limiter.acquire(10 << 20);
      rate = 500000;
      final watch = Stopwatch()..start();
      for (var i = 0; i < 5; i++) {
        await limiter.acquire(50000);
      }
      expect(watch.elapsedMilliseconds, closeTo(500, 60));
    });
  });

  group('memoryConnectionPair(capacity)', () {
    test('flush ждёт, пока получатель не прочитает', () async {
      final (a, b) = memoryConnectionPair(capacity: 1000);
      final reader = StreamIterator(b.input);
      a.add(Uint8List(3000));
      var flushed = false;
      unawaited(a.flush().then((_) => flushed = true));
      await pumpEventQueue();
      expect(flushed, isFalse);
      expect(await reader.moveNext(), isTrue);
      await pumpEventQueue();
      expect(flushed, isTrue);
      await a.close();
      expect(await reader.moveNext(), isFalse);
    });

    test('без предела flush не ждёт', () async {
      final (a, _) = memoryConnectionPair();
      a.add(Uint8List(1 << 20));
      await a.flush();
    });
  });

  group('PeerClient', () {
    late CryptoProvider crypto;
    late LocalPeer clientPeer;
    late LocalPeer nodePeer;
    late Uint8List nodeId;
    final ticket = pb.Signed(body: [1], signer: Uint8List(32));

    setUpAll(() async {
      crypto = await SodiumCryptoProvider.load();
      final now = DateTime.now();
      final alice = await AccountKeys.fromMasterKey(
        SecretBytes(crypto.randomBytes(32)),
        crypto,
      );
      final bob = await AccountKeys.fromMasterKey(
        SecretBytes(crypto.randomBytes(32)),
        crypto,
      );
      final device = await DeviceKeys.generate(crypto);
      final node = await DeviceKeys.generate(crypto);
      nodeId = node.sign.publicKey;
      clientPeer = LocalPeer(
        role: pb.PeerRole.PEER_ROLE_CLIENT,
        staticKey: device.dh,
        certificate: await DeviceCertificates.issue(
          crypto,
          alice,
          device,
          issuedAt: now,
        ),
      );
      nodePeer = LocalPeer(
        role: pb.PeerRole.PEER_ROLE_NODE,
        staticKey: node.dh,
        certificate: await NodeCertificates.issue(
          crypto,
          bob,
          nodeId: node.sign.publicKey,
          nodeDh: node.dh.publicKey,
          issuedAt: now,
        ),
      );
    });

    /// Клиент и «узел» — сырой канал, которым тест отвечает сам.
    Future<(PeerClient, SecureChannel, StreamIterator<pb.PeerMessage>)>
    connect({
      Duration timeout = PeerClient.defaultTimeout,
      int bufferBytes = PeerClient.defaultBufferBytes,
      int? capacity,
    }) async {
      final (a, b) = memoryConnectionPair(capacity: capacity);
      final results = await Future.wait([
        PeerHandshake.initiate(
          crypto,
          a,
          local: clientPeer,
          policy: PeerPolicy.node(nodeId),
        ),
        PeerHandshake.respond(
          crypto,
          b,
          local: nodePeer,
          policy: PeerPolicy.anyone(),
        ),
      ]);
      final client = PeerClient(
        results[0],
        responseTimeout: timeout,
        idleTimeout: timeout,
        bufferBytes: bufferBytes,
      );
      return (client, results[1], StreamIterator(results[1].messages));
    }

    Future<pb.PeerMessage> next(StreamIterator<pb.PeerMessage> it) async {
      expect(await it.moveNext(), isTrue);
      return it.current;
    }

    Matcher failsWith(pb.ErrorCode code) => throwsA(
      isA<PeerRequestException>().having((e) => e.code, 'code', code),
    );

    pb.PeerMessage data(int id, int length, {bool last = false}) =>
        pb.PeerMessage(
          requestId: Int64(id),
          fragmentData: pb.FragmentData(data: Uint8List(length), last: last),
        );

    test('запросы параллельно, ответы в любом порядке', () async {
      final (client, node, it) = await connect();
      final ping = client.ping();
      final has = client.hasFragments([Uint8List(32), Uint8List(32)]);
      final m1 = await next(it);
      final m2 = await next(it);
      expect(m1.requestId, Int64(1));
      expect(m2.requestId, Int64(2));
      await node.send(
        pb.PeerMessage(
          requestId: Int64(2),
          hasFragmentsResult: pb.HasFragmentsResult(present: [true, false]),
        ),
      );
      await node.send(
        pb.PeerMessage(
          requestId: Int64(1),
          pong: pb.Pong(nonce: m1.ping.nonce),
        ),
      );
      expect(await has, [true, false]);
      expect(await ping, isA<Duration>());
      expect(client.activeRequests, 0);
      await client.close();
    });

    test('ошибка собеседника — PeerRequestException с retry_after', () async {
      final (client, node, it) = await connect();
      final del = client.deleteFragment(ticket);
      final m = await next(it);
      await node.send(
        pb.PeerMessage(
          requestId: m.requestId,
          error: pb.Error(
            code: pb.ErrorCode.ERROR_CODE_RATE_LIMITED,
            message: 'медленнее',
            retryAfterMs: 1500,
          ),
        ),
      );
      await expectLater(
        del,
        throwsA(
          isA<PeerRequestException>()
              .having(
                (e) => e.code,
                'code',
                pb.ErrorCode.ERROR_CODE_RATE_LIMITED,
              )
              .having(
                (e) => e.retryAfter,
                'retryAfter',
                const Duration(milliseconds: 1500),
              ),
        ),
      );
      await client.close();
    });

    test('нет ответа — UNAVAILABLE и Cancel собеседнику', () async {
      final (client, _, it) = await connect(
        timeout: const Duration(milliseconds: 200),
      );
      final ping = client.ping();
      expect((await next(it)).hasPing(), isTrue);
      await expectLater(ping, failsWith(pb.ErrorCode.ERROR_CODE_UNAVAILABLE));
      final cancel = await next(it);
      expect(cancel.hasCancel(), isTrue);
      expect(cancel.requestId, Int64(1));
      await client.close();
    });

    test('ранний ответ на загрузку останавливает отправку частей', () async {
      final (client, node, it) = await connect(capacity: 100000);
      final put = client.putFragment(ticket, Uint8List(2 << 20));
      final start = await next(it);
      expect(start.hasPutFragment(), isTrue);
      await node.send(
        pb.PeerMessage(
          requestId: start.requestId,
          putFragmentResult: pb.PutFragmentResult(fragmentId: Uint8List(32)),
        ),
      );
      expect(await put, Uint8List(32));
      var chunks = 0;
      while (await it.moveNext().timeout(
        const Duration(milliseconds: 200),
        onTimeout: () => false,
      )) {
        expect(it.current.hasFragmentData(), isTrue);
        chunks++;
      }
      // Ушли только части, отправленные до ответа.
      expect(chunks, lessThan(34));
      await client.close();
    });

    test('отмена загрузки — CancelledException и Cancel', () async {
      final (client, _, it) = await connect(capacity: 100000);
      final cancel = Completer<void>();
      final put = client.putFragment(
        ticket,
        Uint8List(4 << 20),
        cancel: cancel.future,
      );
      await next(it);
      await next(it);
      cancel.complete();
      await expectLater(put, throwsA(isA<CancelledException>()));
      var sawCancel = false;
      while (await it.moveNext().timeout(
        const Duration(milliseconds: 200),
        onTimeout: () => false,
      )) {
        if (it.current.hasCancel()) sawCancel = true;
      }
      expect(sawCancel, isTrue);
      await client.close();
    });

    test('выдача: части собираются, медленный потребитель не копит '
        'память', () async {
      final (client, node, it) = await connect(
        bufferBytes: 200000,
        capacity: 100000,
      );
      const size = 3 << 20;
      final chunks = <Uint8List>[];
      // Подписка завершается сама вместе с потоком.
      // ignore: cancel_subscriptions
      final sub = client.getFragment(ticket).listen(chunks.add)..pause();
      final done = sub.asFuture<void>();
      final m = await next(it);
      expect(m.hasGetFragment(), isTrue);
      await node.send(
        pb.PeerMessage(
          requestId: m.requestId,
          getFragmentResult: pb.GetFragmentResult(fragmentSize: size),
        ),
      );
      var sent = 0;
      final sender = () async {
        while (sent < size) {
          final n = size - sent < PeerOperations.maxChunk
              ? size - sent
              : PeerOperations.maxChunk;
          await node.send(data(m.requestId.toInt(), n, last: sent + n == size));
          sent += n;
        }
      }();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      // Потребитель стоит: клиент держит не больше своего буфера, а
      // отправитель упёрся в соединение.
      expect(client.bufferedBytes, lessThanOrEqualTo(200000 + 61440));
      expect(sent, lessThan(1 << 20));
      sub.resume();
      await sender;
      await done;
      expect(chunks.fold<int>(0, (n, c) => n + c.length), size);
      expect(client.bufferedBytes, 0);
      await client.close();
    });

    test('отмена подписки на выдачу — Cancel собеседнику', () async {
      final (client, node, it) = await connect();
      late StreamSubscription<Uint8List> sub;
      final first = Completer<void>();
      sub = client.getFragment(ticket).listen((_) {
        if (!first.isCompleted) first.complete();
      });
      final m = await next(it);
      await node.send(
        pb.PeerMessage(
          requestId: m.requestId,
          getFragmentResult: pb.GetFragmentResult(fragmentSize: 200000),
        ),
      );
      await node.send(data(1, PeerOperations.maxChunk));
      await first.future;
      await sub.cancel();
      final cancel = await next(it);
      expect(cancel.hasCancel(), isTrue);
      expect(cancel.requestId, m.requestId);
      // Остаток отменённой выдачи клиент пропускает.
      await node.send(data(1, PeerOperations.maxChunk));
      await pumpEventQueue();
      expect(client.bufferedBytes, 0);
      expect(client.activeRequests, 0);
      expect(client.isClosed, isFalse);
      await client.close();
    });

    test('нарушения протокола в выдаче — BAD_REQUEST', () async {
      final cases = <String, List<pb.PeerMessage> Function(int id)>{
        'данные до GetFragmentResult': (id) => [data(id, 10)],
        'часть больше 61 440 байт': (id) => [
          pb.PeerMessage(
            requestId: Int64(id),
            getFragmentResult: pb.GetFragmentResult(fragmentSize: 100000),
          ),
          data(id, PeerOperations.maxChunk + 1),
        ],
        'данных больше размера': (id) => [
          pb.PeerMessage(
            requestId: Int64(id),
            getFragmentResult: pb.GetFragmentResult(fragmentSize: 1000),
          ),
          data(id, 1001),
        ],
        'last раньше размера': (id) => [
          pb.PeerMessage(
            requestId: Int64(id),
            getFragmentResult: pb.GetFragmentResult(fragmentSize: 1000),
          ),
          data(id, 999, last: true),
        ],
        'размер меньше заголовка': (id) => [
          pb.PeerMessage(
            requestId: Int64(id),
            getFragmentResult: pb.GetFragmentResult(fragmentSize: 96),
          ),
        ],
        'чужой ответ': (id) => [
          pb.PeerMessage(requestId: Int64(id), pong: pb.Pong()),
        ],
      };
      for (final MapEntry(key: name, value: reply) in cases.entries) {
        final (client, node, it) = await connect();
        final get = expectLater(
          client.readFragment(ticket),
          failsWith(pb.ErrorCode.ERROR_CODE_BAD_REQUEST),
          reason: name,
        );
        final m = await next(it);
        for (final r in reply(m.requestId.toInt())) {
          await node.send(r);
        }
        await get;
        await client.close();
      }
    });

    test('обрыв соединения завершает все запросы', () async {
      final (client, node, it) = await connect();
      final ping = expectLater(
        client.ping(),
        failsWith(pb.ErrorCode.ERROR_CODE_UNAVAILABLE),
      );
      final get = expectLater(
        client.readFragment(ticket),
        failsWith(pb.ErrorCode.ERROR_CODE_UNAVAILABLE),
      );
      await next(it);
      await next(it);
      node.destroy();
      await ping;
      await get;
      expect(client.isClosed, isTrue);
      await expectLater(
        client.ping(),
        failsWith(pb.ErrorCode.ERROR_CODE_UNAVAILABLE),
      );
    });

    test('ошибка соединения (request_id 0) завершает все запросы', () async {
      final (client, node, it) = await connect();
      final ping = client.ping();
      await next(it);
      await node.send(
        pb.PeerMessage(
          error: pb.Error(code: pb.ErrorCode.ERROR_CODE_RATE_LIMITED),
        ),
      );
      await expectLater(ping, failsWith(pb.ErrorCode.ERROR_CODE_RATE_LIMITED));
      await client.close();
    });
  });
}
