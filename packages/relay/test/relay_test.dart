// Relay (задачи 3.8.1, 3.8.2; protocol.md, раздел 4.12): пропуск и
// доказательство владения ключом, управляющее соединение узла, сеансы
// с половинным закрытием, предел объёма пропуска, учёт по учётным записям.
// Операции с фрагментами через relay — node/test/peer_service_relay_test.dart,
// сквозной тест с координатором — coordinator/test/relay_test.dart.

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:fixnum/fixnum.dart';
import 'package:protocol/protocol.dart' as pb;
import 'package:relay/relay.dart';
import 'package:test/test.dart';

import '../../core/test/support/fuzz.dart' show fuzzRuns, fuzzSeed, mutate;

void main() {
  late CryptoProvider crypto;
  late Ed25519KeyPair passKey;
  late Ed25519KeyPair node;
  late Ed25519KeyPair device;
  late Ed25519KeyPair stranger;
  late Uint8List account;
  late RelayServer relay;
  var passes = 0;

  setUpAll(() async {
    crypto = await SodiumCryptoProvider.load();
    Future<Ed25519KeyPair> key() =>
        crypto.ed25519FromSeed(SecretBytes(crypto.randomBytes(32)));
    passKey = await key();
    node = await key();
    device = await key();
    stranger = await key();
    account = crypto.randomBytes(32);
  });

  Future<RelayServer> start({
    RelayLimits limits = const RelayLimits(),
    DateTime Function()? clock,
  }) => RelayServer.bind(
    crypto: crypto,
    name: 'r1',
    passKeys: CoordinatorKeySet([passKey.publicKey]),
    host: '127.0.0.1',
    limits: limits,
    clock: clock,
  );

  setUp(() async => relay = await start());
  tearDown(() => relay.close());

  Future<pb.Signed> pass(
    pb.RelayRole role, {
    Ed25519KeyPair? holder,
    Uint8List? nodeId,
    Duration expiresIn = const Duration(minutes: 30),
    int maxBytes = 0,
    String name = 'r1',
    Ed25519KeyPair? signer,
  }) {
    final h =
        holder ?? (role == pb.RelayRole.RELAY_ROLE_LISTEN ? node : device);
    passes++;
    return RelayPasses.issue(
      crypto,
      signer ?? passKey,
      pb.RelayPass(
        role: role,
        holder: h.publicKey,
        nodeId: nodeId ?? node.publicKey,
        accountId: account,
        relay: name,
        passId: Uint8List(16)..buffer.asByteData().setUint32(0, passes),
        expiresAtUnixMs: Int64(
          DateTime.now().add(expiresIn).millisecondsSinceEpoch,
        ),
        maxBytes: Int64(maxBytes),
      ),
    );
  }

  Future<RelayListener> listen({RelayServer? on}) async =>
      await RelayListener.open(
        crypto,
        host: '127.0.0.1',
        port: (on ?? relay).port,
        pass: await pass(pb.RelayRole.RELAY_ROLE_LISTEN),
        key: node,
      );

  Future<ByteConnection> dial({
    pb.Signed? with_,
    Ed25519KeyPair? key,
    RelayServer? on,
  }) async => await RelayClient.connect(
    crypto,
    host: '127.0.0.1',
    port: (on ?? relay).port,
    pass: with_ ?? await pass(pb.RelayRole.RELAY_ROLE_CONNECT),
    key: key ?? device,
  );

  /// Клиент и узел через relay: узел принимает первое входящее.
  Future<(ByteConnection, ByteConnection)> session(
    RelayListener listener, {
    pb.Signed? with_,
  }) async {
    final accepted = listener.incoming.first.then(listener.accept);
    final client = await dial(with_: with_);
    return (client, await accepted);
  }

  Matcher refused(pb.ErrorCode code) =>
      throwsA(isA<RelayException>().having((e) => e.code, 'code', code));

  Future<Uint8List> readAll(ByteConnection c) async {
    final out = BytesBuilder(copy: false);
    await c.input.forEach(out.add);
    return out.takeBytes();
  }

  group('3.8.1: ретрансляция', () {
    test('байты в обе стороны и половинное закрытие', () async {
      final listener = await listen();
      final (client, server) = await session(listener);
      final big = crypto.randomBytes(3 << 20);
      final fromServer = readAll(server);
      client.add(big);
      await client.flush();
      await client.close();
      expect(await fromServer, big);
      // Клиент закрыл свою сторону, но ещё читает ответ.
      final fromClient = readAll(client);
      server.add(Uint8List.fromList([1, 2, 3]));
      await server.close();
      expect(await fromClient, [1, 2, 3]);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(relay.sessions, 0);
      expect(relay.sessionsOpened, 1);
      expect(relay.bytesRelayed, big.length + 3);
      listener.close();
    });

    test('несколько сеансов параллельно', () async {
      final listener = await listen();
      final pairs = <(ByteConnection, ByteConnection)>[];
      final accepted = <Future<ByteConnection>>[];
      final sub = listener.incoming.listen(
        (id) => accepted.add(listener.accept(id)),
      );
      final clients = await Future.wait([for (var i = 0; i < 5; i++) dial()]);
      final servers = await Future.wait(accepted);
      for (var i = 0; i < 5; i++) {
        pairs.add((clients[i], servers[i]));
      }
      expect(relay.sessions, 5);
      // Сеансы сопоставлены не по порядку: проверяем, что каждый байт
      // клиента дошёл ровно до одного узла.
      for (var i = 0; i < 5; i++) {
        clients[i].add(Uint8List.fromList([i]));
        await clients[i].close();
      }
      final got = await Future.wait([for (final s in servers) readAll(s)]);
      expect(got.map((b) => b.single).toSet(), {0, 1, 2, 3, 4});
      await sub.cancel();
      for (final s in servers) {
        s.destroy();
      }
      listener.close();
    });

    test('узла нет на relay — NOT_FOUND', () async {
      await expectLater(dial(), refused(pb.ErrorCode.ERROR_CODE_NOT_FOUND));
    });

    test('узел не принял соединение — UNAVAILABLE', () async {
      await relay.close();
      relay = await start(
        limits: const RelayLimits(acceptTimeout: Duration(milliseconds: 200)),
      );
      final listener = await listen();
      await expectLater(dial(), refused(pb.ErrorCode.ERROR_CODE_UNAVAILABLE));
      listener.close();
    });

    test('новое управляющее соединение заменяет прежнее', () async {
      final first = await listen();
      final second = await listen();
      await first.done.timeout(const Duration(seconds: 5));
      expect(relay.listeners, 1);
      final (client, server) = await session(second);
      client.add(Uint8List.fromList([7]));
      await client.close();
      expect(await readAll(server), [7]);
      second.close();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(relay.listeners, 0);
    });

    test('relay закрывает управляющее соединение по сроку пропуска', () async {
      await relay.close();
      // Часы relay — почти на допуск впереди: пропуск истекает через
      // секунду с учётом допуска.
      relay = await start(
        clock: () => DateTime.now().add(
          RelayPasses.clockSkew - const Duration(seconds: 1),
        ),
      );
      final listener = await RelayListener.open(
        crypto,
        host: '127.0.0.1',
        port: relay.port,
        pass: await pass(
          pb.RelayRole.RELAY_ROLE_LISTEN,
          expiresIn: Duration.zero,
        ),
        key: node,
      );
      await listener.done.timeout(const Duration(seconds: 5));
      expect(relay.listeners, 0);
    });

    test('ping управляющего соединения', () async {
      await relay.close();
      relay = await start(
        limits: const RelayLimits(pingInterval: Duration(milliseconds: 100)),
      );
      final listener = await RelayListener.open(
        crypto,
        host: '127.0.0.1',
        port: relay.port,
        pass: await pass(pb.RelayRole.RELAY_ROLE_LISTEN),
        key: node,
        pingInterval: const Duration(milliseconds: 100),
      );
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(listener.isClosed, isFalse);
      expect(relay.listeners, 1);
      listener.close();
    });
  });

  group('3.8.2: пропуск', () {
    test('чужой ключ пропусков — UNAUTHENTICATED', () async {
      await listen();
      await expectLater(
        dial(
          with_: await pass(pb.RelayRole.RELAY_ROLE_CONNECT, signer: stranger),
        ),
        refused(pb.ErrorCode.ERROR_CODE_UNAUTHENTICATED),
      );
    });

    test('истёкший пропуск — UNAUTHENTICATED', () async {
      await expectLater(
        dial(
          with_: await pass(
            pb.RelayRole.RELAY_ROLE_CONNECT,
            expiresIn: -const Duration(minutes: 6),
          ),
        ),
        refused(pb.ErrorCode.ERROR_CODE_UNAUTHENTICATED),
      );
    });

    test('слишком долгий пропуск — UNAUTHENTICATED', () async {
      await expectLater(
        dial(
          with_: await pass(
            pb.RelayRole.RELAY_ROLE_CONNECT,
            expiresIn: const Duration(hours: 3),
          ),
        ),
        refused(pb.ErrorCode.ERROR_CODE_UNAUTHENTICATED),
      );
    });

    test('ключ не владельца пропуска — UNAUTHENTICATED', () async {
      await listen();
      await expectLater(
        dial(key: stranger),
        refused(pb.ErrorCode.ERROR_CODE_UNAUTHENTICATED),
      );
      // И узел: чужим ключом управляющее соединение не открыть.
      await expectLater(
        RelayListener.open(
          crypto,
          host: '127.0.0.1',
          port: relay.port,
          pass: await pass(pb.RelayRole.RELAY_ROLE_LISTEN),
          key: stranger,
        ),
        refused(pb.ErrorCode.ERROR_CODE_UNAUTHENTICATED),
      );
    });

    test('пропуск другого relay', () async {
      // Клиент видит имя в вызове и не отправляет пропуск.
      await expectLater(
        dial(with_: await pass(pb.RelayRole.RELAY_ROLE_CONNECT, name: 'r2')),
        refused(pb.ErrorCode.ERROR_CODE_BAD_REQUEST),
      );
      // Relay тоже проверяет имя.
      final socket = RelaySocket(await Socket.connect('127.0.0.1', relay.port));
      final challenge = pb.RelayChallenge.fromBuffer((await socket.next())!);
      final other = await pass(pb.RelayRole.RELAY_ROLE_CONNECT, name: 'r2');
      socket.send(
        pb.RelayOpen(
          pass: other,
          proof: await RelayWire.prove(crypto, device, challenge.nonce, other),
        ),
      );
      final opened = pb.RelayOpened.fromBuffer((await socket.next())!);
      expect(opened.error.code, pb.ErrorCode.ERROR_CODE_UNAUTHENTICATED);
      expect(await socket.next(), isNull);
    });

    test('без пропуска соединение не устанавливается', () async {
      await listen();
      final socket = RelaySocket(await Socket.connect('127.0.0.1', relay.port));
      await socket.next();
      // Не RelayOpen — relay закрывает соединение без ответа.
      socket.socket.add([0, 3, 0xFF, 0xFF, 0xFF]);
      expect(await socket.next(), isNull);
      // Молчание — закрытие по таймауту рукопожатия.
      await relay.close();
      relay = await start(
        limits: const RelayLimits(
          handshakeTimeout: Duration(milliseconds: 100),
        ),
      );
      final silent = RelaySocket(await Socket.connect('127.0.0.1', relay.port));
      await silent.next();
      expect(await silent.next(timeout: const Duration(seconds: 5)), isNull);
      expect(relay.sessionsOpened, 0);
    });

    test('чужой сеанс узлу не принять', () async {
      final listener = await listen();
      final id = listener.incoming.first;
      final client = dial();
      final sessionId = await id;
      // Другой узел с верным пропуском LISTEN на себя не примет сеанс.
      final otherNode = await crypto.ed25519FromSeed(
        SecretBytes(crypto.randomBytes(32)),
      );
      final otherListener = await RelayListener.open(
        crypto,
        host: '127.0.0.1',
        port: relay.port,
        pass: await pass(
          pb.RelayRole.RELAY_ROLE_LISTEN,
          holder: otherNode,
          nodeId: otherNode.publicKey,
        ),
        key: otherNode,
      );
      await expectLater(
        otherListener.accept(sessionId),
        refused(pb.ErrorCode.ERROR_CODE_NOT_FOUND),
      );
      final server = await listener.accept(sessionId);
      (await client).destroy();
      server.destroy();
      otherListener.close();
      listener.close();
    });

    test('LISTEN не для себя и CONNECT к себе не выпускаются', () async {
      expect(
        () => pass(pb.RelayRole.RELAY_ROLE_LISTEN, holder: device),
        throwsA(isA<DataFormatException>()),
      );
      expect(
        () => pass(pb.RelayRole.RELAY_ROLE_CONNECT, holder: node),
        throwsA(isA<DataFormatException>()),
      );
    });

    test('предел объёма пропуска на все его сеансы', () async {
      final listener = await listen();
      final limited = await pass(
        pb.RelayRole.RELAY_ROLE_CONNECT,
        maxBytes: 100000,
      );
      final (client, server) = await session(listener, with_: limited);
      final received = readAll(server);
      client.add(crypto.randomBytes(300000));
      await client.flush().catchError((_) {});
      final got = await received;
      expect(got.length, lessThanOrEqualTo(300000));
      expect(relay.sessions, 0);
      await expectLater(
        dial(with_: limited),
        refused(pb.ErrorCode.ERROR_CODE_QUOTA_EXCEEDED),
      );
      client.destroy();
      listener.close();
    });

    test('предел сеансов на пропуск', () async {
      await relay.close();
      relay = await start(limits: const RelayLimits(maxSessionsPerPass: 1));
      final listener = await listen();
      final one = await pass(pb.RelayRole.RELAY_ROLE_CONNECT);
      final (client, server) = await session(listener, with_: one);
      await expectLater(
        dial(with_: one),
        refused(pb.ErrorCode.ERROR_CODE_RATE_LIMITED),
      );
      client.destroy();
      server.destroy();
      listener.close();
    });
  });

  group('3.8.3: учёт', () {
    test('прирост трафика по учётной записи и его возврат', () async {
      final listener = await listen();
      final (client, server) = await session(listener);
      final received = readAll(server);
      client.add(Uint8List(1000));
      await client.close();
      expect((await received).length, 1000);
      server.destroy();
      final report = relay.takeReport();
      expect(report.relay, 'r1');
      expect(report.bytes.toInt(), 1000);
      expect(report.sessionsOpened.toInt(), 1);
      expect(report.listeners, 1);
      expect(report.usage.single.accountId, account);
      expect(report.usage.single.bytes.toInt(), 1000);
      expect(report.usage.single.sessions, 1);
      expect(relay.takeReport().bytes.toInt(), 0);
      relay.usage.restore(report);
      expect(relay.takeReport().usage.single.bytes.toInt(), 1000);
      listener.close();
    });

    test('TrafficMeter: прирост по способам подключения', () async {
      final meter = TrafficMeter();
      final (a, b) = memoryConnectionPair();
      final metered = meter.wrap(
        a,
        pb.ConnectionMethod.CONNECTION_METHOD_RELAY,
      );
      final got = metered.input.first;
      metered.add(Uint8List(10));
      b.add(Uint8List(5));
      await got;
      final report = meter.takeReport()!;
      expect(
        report.traffic.single.method,
        pb.ConnectionMethod.CONNECTION_METHOD_RELAY,
      );
      expect(report.traffic.single.bytes.toInt(), 15);
      expect(report.traffic.single.connections, 1);
      expect(meter.takeReport(), isNull);
      meter.restore(report);
      expect(meter.takeReport()!.traffic.single.bytes.toInt(), 15);
      expect(meter.toJson(), {'relay': 15});
    });
  });

  group('фаззинг', () {
    test('RelayPasses.parse и кадры: только DataFormatException', () async {
      final r = Random(fuzzSeed);
      final sample = (await pass(pb.RelayRole.RELAY_ROLE_CONNECT)).body;
      for (var i = 0; i < fuzzRuns; i++) {
        final body = mutate(r, Uint8List.fromList(sample));
        try {
          RelayPasses.parse(body);
        } on DataFormatException {
          // Ожидаемо.
        }
        final reader = RelayFrameReader()..add(body);
        try {
          while (reader.next() != null) {}
        } on FormatException {
          // Ожидаемо.
        }
      }
    });

    test('relay выдерживает мусор вместо RelayOpen', () async {
      await relay.close();
      // Обрезанный кадр relay ждёт до таймаута рукопожатия.
      relay = await start(
        limits: const RelayLimits(
          handshakeTimeout: Duration(milliseconds: 200),
          opensPerIpPerSecond: 10000,
          opensPerIpBurst: 10000,
        ),
      );
      final r = Random(fuzzSeed + 1);
      final good = await pass(pb.RelayRole.RELAY_ROLE_CONNECT);
      final sample = RelayWire.frame(
        pb.RelayOpen(pass: good, proof: Uint8List(64)),
      );
      final runs = fuzzRuns ~/ 20;
      for (var i = 0; i < runs; i++) {
        final socket = RelaySocket(
          await Socket.connect('127.0.0.1', relay.port),
        );
        await socket.next();
        socket.socket.add(mutate(r, sample));
        // Ответ — отказ или закрытие, но не сеанс и не падение relay.
        while (await socket.next(timeout: const Duration(seconds: 5)) !=
            null) {}
      }
      expect(relay.sessionsOpened, 0);
      final listener = await listen();
      final (client, server) = await session(listener);
      client.destroy();
      server.destroy();
      listener.close();
    });
  });

  group('настройки', () {
    test('файл и окружение', () {
      final key = bytesToHex(Uint8List(32));
      final config = RelayConfig.parse(
        '''
name: eu1
pass_keys: ['$key']
listen:
  port: 7400
limits:
  idle_seconds: 60
''',
        {'FS_RELAY_LISTEN_HOST': '0.0.0.0'},
      );
      expect(config.name, 'eu1');
      expect(config.port, 7400);
      expect(config.host, '0.0.0.0');
      expect(config.limits.idleTimeout, const Duration(seconds: 60));
      expect(config.passKeys.trusts(Uint8List(32)), isTrue);
      expect(
        () => RelayConfig.parse('name: eu1', {}),
        throwsA(isA<RelayConfigException>()),
      );
      expect(
        () => RelayConfig.parse('name: EU\npass_keys: [$key]', {}),
        throwsA(isA<RelayConfigException>()),
      );
      expect(
        () => RelayConfig.parse(
          'name: eu1\npass_keys: [$key]\ncoordinator:\n  url: https://c',
          {},
        ),
        throwsA(isA<RelayConfigException>()),
      );
      expect(
        () => RelayConfig.parse('name: eu1\npass_keys: [$key]\nx: 1', {}),
        throwsA(isA<RelayConfigException>()),
      );
    });
  });
}
