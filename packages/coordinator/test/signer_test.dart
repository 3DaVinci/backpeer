// Подписант талонов (задача 2.2.1, protocol.md, раздел 5).

@TestOn('linux || mac-os')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:coordinator/coordinator.dart';
import 'package:core/core.dart';
import 'package:fixnum/fixnum.dart';
import 'package:protocol/protocol.dart' as pb;
import 'package:test/test.dart';

import 'support/harness.dart';

void main() {
  late CryptoProvider crypto;
  late Ed25519KeyPair key;
  late FakeClock clock;

  setUpAll(() async {
    crypto = await SodiumCryptoProvider.load();
    key = await crypto.ed25519FromSeed(SecretBytes(Uint8List(32)..[0] = 7));
  });
  setUp(() => clock = FakeClock());

  pb.FragmentTicket ticket({
    Duration expiresIn = const Duration(minutes: 30),
    int index = 0,
  }) => pb.FragmentTicket(
    operation: pb.TicketOperation.TICKET_OPERATION_PUT,
    nodeId: Uint8List(32)..fillRange(0, 32, 1),
    deviceSign: Uint8List(32)..fillRange(0, 32, 2),
    fragmentId: Uint8List(32)..fillRange(0, 32, index & 0xFF),
    fragmentSize: 1677824,
    expiresAtUnixMs: Int64(clock.now.add(expiresIn).millisecondsSinceEpoch),
    ticketId: crypto.randomBytes(16),
  );

  TicketSigningService service({
    double rate = 1000,
    int burst = 1000,
    Duration maxLifetime = FragmentTickets.maxLifetime,
  }) => TicketSigningService(
    crypto: crypto,
    key: key,
    limiter: RateLimiter(perSecond: rate, burst: burst, clock: clock.call),
    maxLifetime: maxLifetime,
    clock: clock.call,
  );

  Future<SignerReply?> handle(
    TicketSigningService s,
    List<pb.FragmentTicket> tickets,
  ) async => SignerReply.decode(
    await s.handle(
      SignerWire.encodeRequest([for (final t in tickets) t.writeToBuffer()]),
    ),
    tickets.length,
  );

  Future<bool> verifies(Uint8List body, Uint8List signer, Uint8List sig) =>
      crypto.ed25519Verify(
        publicKey: signer,
        message: signingInput('ticket', body),
        signature: sig,
      );

  group('TicketSigningService', () {
    test('подписывает пачку талонов ключом координатора', () async {
      final tickets = [for (var i = 0; i < 3; i++) ticket(index: i)];
      final reply = await handle(service(), tickets);
      expect(reply, isA<SignerSigned>());
      final signed = reply! as SignerSigned;
      expect(signed.signer, key.publicKey);
      for (var i = 0; i < 3; i++) {
        expect(
          await verifies(
            tickets[i].writeToBuffer(),
            signed.signer,
            signed.signatures[i],
          ),
          isTrue,
        );
      }
    });

    test('срок больше допустимого — отказ всей пачке', () async {
      final reply = await handle(service(), [
        ticket(),
        ticket(expiresIn: const Duration(hours: 1, seconds: 1)),
      ]);
      expect(
        reply,
        isA<SignerRefused>()
            .having((r) => r.code, 'code', pb.ErrorCode.ERROR_CODE_BAD_REQUEST)
            .having((r) => r.index, 'index', 1),
      );
    });

    test('предел срока строже спецификации', () async {
      final s = service(maxLifetime: const Duration(minutes: 10));
      expect(await handle(s, [ticket()]), isA<SignerRefused>());
      expect(
        await handle(s, [ticket(expiresIn: const Duration(minutes: 10))]),
        isA<SignerSigned>(),
      );
      expect(
        () => service(maxLifetime: const Duration(hours: 2)),
        throwsArgumentError,
      );
    });

    test('истёкший талон и неверные поля отклоняются', () async {
      final s = service();
      final bad = [
        ticket(expiresIn: Duration.zero),
        ticket()..clearOperation(),
        ticket()..fragmentSize = 0,
        ticket()..nodeId = Uint8List(31),
      ];
      for (final t in bad) {
        expect(
          await handle(s, [t]),
          isA<SignerRefused>()
              .having(
                (r) => r.code,
                'code',
                pb.ErrorCode.ERROR_CODE_BAD_REQUEST,
              )
              .having((r) => r.index, 'index', 0),
        );
      }
    });

    test('запрос не по формату', () async {
      final s = service();
      final good = SignerWire.encodeRequest([ticket().writeToBuffer()]);
      final requests = [
        Uint8List(0),
        Uint8List.fromList([2, ...good.sublist(1)]), // версия
        Uint8List.fromList([1, 0]), // ноль талонов
        Uint8List.fromList([1, 65]), // больше предела
        good.sublist(0, good.length - 1), // обрезан
        Uint8List.fromList([...good, 0]), // хвост
      ];
      for (final r in requests) {
        final reply = SignerReply.decode(await s.handle(r), 1);
        expect(
          reply,
          isA<SignerRefused>()
              .having(
                (r) => r.code,
                'code',
                pb.ErrorCode.ERROR_CODE_BAD_REQUEST,
              )
              .having((r) => r.index, 'index', isNull),
        );
      }
    });

    test('предел частоты на все талоны', () async {
      final s = service(rate: 10, burst: 64);
      expect(
        await handle(s, [for (var i = 0; i < 60; i++) ticket(index: i)]),
        isA<SignerSigned>(),
      );
      final refused = await handle(s, [for (var i = 0; i < 10; i++) ticket()]);
      expect(
        refused,
        isA<SignerRefused>()
            .having((r) => r.code, 'code', pb.ErrorCode.ERROR_CODE_RATE_LIMITED)
            .having((r) => r.retryAfter, 'retryAfter', isNotNull),
      );
      clock.advance(const Duration(seconds: 1));
      expect(
        await handle(s, [for (var i = 0; i < 10; i++) ticket()]),
        isA<SignerSigned>(),
      );
    });
  });

  group('SignerKeyFile', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('signer-key-'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('создаёт ключ с правами 0600 и читает его', () async {
      final path = '${dir.path}/signer.key';
      final created = await SignerKeyFile.generate(path, crypto);
      expect(FileStat.statSync(path).mode & 511, 384);
      expect(File(path).lengthSync(), 32);
      final loaded = await SignerKeyFile.load(path, crypto);
      expect(loaded.publicKey, created.publicKey);
      expect(
        () => SignerKeyFile.generate(path, crypto),
        throwsA(isA<SignerKeyException>()),
        reason: 'существующий ключ не перезаписывается',
      );
    });

    test('ключ, доступный группе, не загружается', () async {
      final path = '${dir.path}/signer.key';
      await SignerKeyFile.generate(path, crypto);
      setUnixFileMode(path, 416); // 0640
      await expectLater(
        SignerKeyFile.load(path, crypto),
        throwsA(
          isA<SignerKeyException>().having(
            (e) => e.message,
            'message',
            contains('640'),
          ),
        ),
      );
    });

    test('файл неверной длины не загружается', () async {
      final path = '${dir.path}/signer.key';
      writePrivateFileAtomic(File(path), Uint8List(31));
      await expectLater(
        SignerKeyFile.load(path, crypto),
        throwsA(isA<SignerKeyException>()),
      );
    });
  });

  group('сокет', () {
    late Directory dir;
    late String path;
    SignerServer? server;
    SocketTicketSigner? client;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('signer-sock-');
      path = '${dir.path}/signer.sock';
    });
    tearDown(() async {
      await client?.close();
      await server?.close();
      client = null;
      server = null;
      dir.deleteSync(recursive: true);
    });

    Future<int> ownUid() async =>
        int.parse((await Process.run('id', ['-u'])).stdout.toString().trim());

    test('веб-сервер получает подписанные талоны', () async {
      server = await SignerServer.bind(path, service());
      expect(FileStat.statSync(path).mode & 511, 432, reason: 'сокет 0660');
      client = SocketTicketSigner(path);
      // Больше одной пачки: клиент делит запрос.
      final tickets = [for (var i = 0; i < 150; i++) ticket(index: i)];
      final signed = await client!.sign(tickets);
      expect(signed, hasLength(150));
      for (var i = 0; i < signed.length; i += 37) {
        expect(signed[i].body, tickets[i].writeToBuffer());
        expect(
          await verifies(
            signed[i].body as Uint8List,
            key.publicKey,
            signed[i].signature as Uint8List,
          ),
          isTrue,
        );
      }
    });

    test('отказ подписанта — INTERNAL, соединение живо', () async {
      server = await SignerServer.bind(path, service());
      client = SocketTicketSigner(path);
      await expectLater(
        client!.sign([ticket(expiresIn: const Duration(hours: 2))]),
        throwsA(
          isA<RpcException>().having(
            (e) => e.code,
            'code',
            pb.ErrorCode.ERROR_CODE_INTERNAL,
          ),
        ),
      );
      expect(await client!.sign([ticket()]), hasLength(1));
    });

    test(
      'подписант недоступен — UNAVAILABLE, после запуска работает',
      () async {
        client = SocketTicketSigner(path, timeout: const Duration(seconds: 1));
        Matcher unavailable() => throwsA(
          isA<RpcException>().having(
            (e) => e.code,
            'code',
            pb.ErrorCode.ERROR_CODE_UNAVAILABLE,
          ),
        );
        await expectLater(client!.sign([ticket()]), unavailable());
        server = await SignerServer.bind(path, service());
        expect(await client!.sign([ticket()]), hasLength(1));
        await server!.close();
        server = null;
        await expectLater(client!.sign([ticket()]), unavailable());
        server = await SignerServer.bind(path, service());
        expect(await client!.sign([ticket()]), hasLength(1));
      },
    );

    test('оставшийся сокет удаляется, работающий — нет', () async {
      server = await SignerServer.bind(path, service());
      await expectLater(
        SignerServer.bind(path, service()),
        throwsA(isA<FileSystemException>()),
      );
      // Сокет без слушателя (процесс упал): Dart удаляет файл сокета при
      // закрытии, поэтому оставляем его процессом Python.
      final stalePath = '${dir.path}/stale.sock';
      final made = await Process.run('python3', [
        '-I',
        '-c',
        'import socket,sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])',
        stalePath,
      ]);
      expect(made.exitCode, 0, reason: '${made.stderr}');
      expect(
        FileSystemEntity.typeSync(stalePath, followLinks: false),
        FileSystemEntityType.unixDomainSock,
      );
      final second = await SignerServer.bind(stalePath, service());
      final c = SocketTicketSigner(stalePath);
      expect(await c.sign([ticket()]), hasLength(1));
      await c.close();
      await second.close();
    });

    test('обычный файл на месте сокета не удаляется', () async {
      File(path).writeAsStringSync('x');
      await expectLater(
        SignerServer.bind(path, service()),
        throwsA(isA<FileSystemException>()),
      );
      expect(File(path).readAsStringSync(), 'x');
    });

    test('проверка uid собеседника', () async {
      final uid = await ownUid();
      server = await SignerServer.bind(path, service(), allowedUids: {uid});
      client = SocketTicketSigner(path);
      expect(await client!.sign([ticket()]), hasLength(1));
      await client!.close();
      await server!.close();

      server = await SignerServer.bind(path, service(), allowedUids: {uid + 1});
      client = SocketTicketSigner(path, timeout: const Duration(seconds: 1));
      await expectLater(
        client!.sign([ticket()]),
        throwsA(
          isA<RpcException>().having(
            (e) => e.code,
            'code',
            pb.ErrorCode.ERROR_CODE_UNAVAILABLE,
          ),
        ),
      );
    }, testOn: 'linux');

    test('кадр с неверной длиной обрывает соединение', () async {
      server = await SignerServer.bind(path, service());
      final socket = await Socket.connect(
        InternetAddress(path, type: InternetAddressType.unix),
        0,
      );
      socket.add([0xFF, 0xFF, 0xFF, 0xFF]);
      final received = await socket.fold<int>(0, (n, c) => n + c.length);
      expect(received, 0);
      socket.destroy();
    });
  });
}
