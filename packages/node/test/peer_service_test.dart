// Операции с фрагментами на узле (задачи 3.4.1–3.4.3, protocol.md,
// разделы 3.4 и 5): правила талона, удаление только владельцем,
// HasFragments только про свои, параллельные передачи по одному
// соединению, обратное давление, таймауты, отмена, пределы соединений,
// запросов и скорости.
//
// Те же тесты идут поверх потока UDP (задача 3.7.4):
// peer_service_udp_test.dart, и через relay (задача 3.8.1):
// peer_service_relay_test.dart.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:fixnum/fixnum.dart';
import 'package:node/node.dart';
import 'package:protocol/protocol.dart' as pb;
import 'package:relay/relay.dart';
import 'package:test/test.dart';

import 'support.dart';

/// Учётная запись с устройством: сторона клиента.
final class _Device {
  new(this.account, this.keys, this.certificate);

  final AccountKeys account;
  final DeviceKeys keys;
  final pb.Signed certificate;

  LocalPeer get local => LocalPeer(
    role: pb.PeerRole.PEER_ROLE_CLIENT,
    staticKey: keys.dh,
    certificate: certificate,
    software: 'cli test',
  );
}

/// [ByteConnection], считающий отправленные байты.
final class _Counting implements ByteConnection {
  new(this._inner);

  final ByteConnection _inner;
  int sent = 0;

  @override
  Stream<Uint8List> get input => _inner.input;

  @override
  void add(Uint8List data) {
    sent += data.length;
    _inner.add(data);
  }

  @override
  Future<void> flush() => _inner.flush();

  @override
  Future<void> close() => _inner.close();

  @override
  void destroy() => _inner.destroy();
}

void main() => peerServiceTests();

/// Тесты операций; [udp] — соединения клиента с узлом идут потоком поверх
/// UDP через loopback (`UdpEndpoint`), [relay] — через relay на loopback
/// (узел и клиент оба только подключаются к нему), а не парой в памяти.
void peerServiceTests({bool udp = false, bool relay = false}) {
  final network = udp || relay;
  late CryptoProvider crypto;
  late Ed25519KeyPair coordinator;
  late Ed25519KeyPair stranger;
  late DeviceKeys node;
  late LocalPeer nodePeer;
  late _Device alice;
  late _Device alicePhone;
  late _Device bob;
  late Directory dir;
  late FragmentStorage storage;
  late PeerService service;
  late Fragment fragment;
  late Uint8List fragmentId;

  Future<_Device> device(AccountKeys account) async {
    final keys = await DeviceKeys.generate(crypto);
    return _Device(
      account,
      keys,
      await DeviceCertificates.issue(
        crypto,
        account,
        keys,
        issuedAt: DateTime.now(),
      ),
    );
  }

  Future<AccountKeys> account() =>
      AccountKeys.fromMasterKey(SecretBytes(crypto.randomBytes(32)), crypto);

  setUpAll(() async {
    crypto = await SodiumCryptoProvider.load();
    coordinator = await crypto.ed25519FromSeed(
      SecretBytes(crypto.randomBytes(32)),
    );
    stranger = await crypto.ed25519FromSeed(
      SecretBytes(crypto.randomBytes(32)),
    );
    node = await DeviceKeys.generate(crypto);
    final owner = await account();
    nodePeer = LocalPeer(
      role: pb.PeerRole.PEER_ROLE_NODE,
      staticKey: node.dh,
      certificate: await NodeCertificates.issue(
        crypto,
        owner,
        nodeId: node.sign.publicKey,
        nodeDh: node.dh.publicKey,
        issuedAt: DateTime.now(),
      ),
      software: 'node test',
    );
    final aliceAccount = await account();
    alice = await device(aliceAccount);
    alicePhone = await device(aliceAccount);
    bob = await device(await account());
    fragment = testFragment(crypto, blobLength: 300000);
    fragmentId = fragmentIdOf(crypto, fragment);
  });

  PeerService makeService({
    PeerLimits limits = const PeerLimits(),
    int upload = 0,
    int download = 0,
    TransferGate? gate,
  }) => PeerService(
    crypto: crypto,
    local: nodePeer,
    nodeId: node.sign.publicKey,
    storage: storage,
    trustedKeys: CoordinatorKeySet([coordinator.publicKey]),
    gate: gate,
    limits: limits,
    uploadLimiter: BandwidthLimiter(() => upload),
    downloadLimiter: BandwidthLimiter(() => download),
  );

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('fs_peer_service_');
    storage = FragmentStorage.open(
      dir.path,
      crypto: crypto,
      quotaBytes: 1 << 30,
      diskAvailable: (_) => null,
    );
    service = makeService();
  });

  final endpoints = <UdpEndpoint>[];
  final relayListeners = <RelayListener>[];
  RelayServer? relayServer;
  late Ed25519KeyPair relayPassKey;

  setUpAll(() async {
    if (!relay) return;
    relayPassKey = await crypto.ed25519FromSeed(
      SecretBytes(crypto.randomBytes(32)),
    );
    relayServer = await RelayServer.bind(
      crypto: crypto,
      name: 'test',
      passKeys: CoordinatorKeySet([relayPassKey.publicKey]),
      host: '127.0.0.1',
    );
  });

  tearDownAll(() async => await relayServer?.close());

  tearDown(() async {
    await service.close();
    for (final e in endpoints) {
      await e.close();
    }
    endpoints.clear();
    for (final l in relayListeners) {
      l.close();
    }
    relayListeners.clear();
    await storage.close();
    dir.deleteSync(recursive: true);
  });

  var punches = 0;

  var relayPasses = 0;

  /// Пропуск relay [role] для ключа [holder].
  Future<pb.Signed> relayPass(pb.RelayRole role, Ed25519KeyPair holder) =>
      RelayPasses.issue(
        crypto,
        relayPassKey,
        pb.RelayPass(
          role: role,
          holder: holder.publicKey,
          nodeId: node.sign.publicKey,
          accountId: alice.account.accountId,
          relay: 'test',
          passId: Uint8List(16)
            ..buffer.asByteData().setUint32(0, ++relayPasses),
          expiresAtUnixMs: Int64(
            DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch,
          ),
        ),
      );

  /// Предел памяти в тестах обратного давления меньше буферов ядра у
  /// двух соединений TCP через relay: на них проверяется пара в памяти и
  /// UDP с заданным окном.
  final tcpBuffers = relay ? 'буферы TCP через relay больше предела' : null;

  /// Клиент и узел через relay: узел держит управляющее соединение и
  /// принимает сеанс, клиент подключается по пропуску CONNECT.
  Future<(ByteConnection, ByteConnection)> relayPair() async {
    final server = relayServer!;
    final listener = await RelayListener.open(
      crypto,
      host: '127.0.0.1',
      port: server.port,
      pass: await relayPass(pb.RelayRole.RELAY_ROLE_LISTEN, node.sign),
      key: node.sign,
    );
    relayListeners.add(listener);
    final accepted = listener.incoming.first.then(listener.accept);
    final client = await RelayClient.connect(
      crypto,
      host: '127.0.0.1',
      port: server.port,
      pass: await relayPass(pb.RelayRole.RELAY_ROLE_CONNECT, alice.keys.sign),
      key: alice.keys.sign,
    );
    return (client, await accepted);
  }

  /// Пара соединений клиент — узел: в памяти, поток UDP или через relay.
  /// [capacity] — для UDP окно получателя и буфер отправителя.
  Future<(ByteConnection, ByteConnection)> pair({int? capacity}) async {
    if (relay) return await relayPair();
    if (!udp) return memoryConnectionPair(capacity: capacity);
    final options = UdpStreamOptions(
      receiveWindow: capacity ?? 1 << 20,
      sendBuffer: capacity ?? 1 << 20,
    );
    final client = await UdpEndpoint.bind(
      host: InternetAddress.loopbackIPv4,
      options: options,
    );
    final node = await UdpEndpoint.bind(
      host: InternetAddress.loopbackIPv4,
      options: options,
    );
    endpoints.addAll([client, node]);
    final punchId = Uint8List(16)..buffer.asByteData().setUint32(0, ++punches);
    node.allow(punchId);
    final accepted = node.incoming.first;
    final stream = await client.connect(
      InternetAddress.loopbackIPv4,
      node.port,
      punchId: punchId,
    );
    return (stream as ByteConnection, await accepted as ByteConnection);
  }

  var ticketCounter = 0;

  /// Талон координатора; поля можно испортить для проверки правил.
  Future<pb.Signed> ticket(
    pb.TicketOperation operation,
    _Device to, {
    Uint8List? id,
    int? size,
    Duration expiresIn = const Duration(minutes: 30),
    Uint8List? nodeId,
    Uint8List? ticketId,
    Ed25519KeyPair? signer,
  }) {
    ticketCounter++;
    return SignedMessages.sign(
      crypto,
      signer ?? coordinator,
      FragmentTickets.signingContext,
      pb.FragmentTicket(
        operation: operation,
        nodeId: nodeId ?? node.sign.publicKey,
        deviceSign: to.keys.sign.publicKey,
        fragmentId: id ?? fragmentId,
        fragmentSize: size ?? fragment.bytes.length,
        expiresAtUnixMs: Int64(
          DateTime.now().add(expiresIn).millisecondsSinceEpoch,
        ),
        ticketId:
            ticketId ??
            (Uint8List(16)..buffer.asByteData().setUint32(0, ticketCounter)),
      ),
    );
  }

  Future<pb.Signed> put(_Device d, {Uint8List? id, int? size}) =>
      ticket(pb.TicketOperation.TICKET_OPERATION_PUT, d, id: id, size: size);
  Future<pb.Signed> get(_Device d) =>
      ticket(pb.TicketOperation.TICKET_OPERATION_GET, d);
  Future<pb.Signed> delete(_Device d) =>
      ticket(pb.TicketOperation.TICKET_OPERATION_DELETE, d);

  /// Соединение клиента [d] с узлом [s] через пару в памяти.
  Future<PeerClient> connect(
    _Device d, {
    PeerService? s,
    int? capacity,
    void Function(_Counting client, _Counting node)? counters,
    Duration timeout = PeerClient.defaultTimeout,
  }) async {
    final (a, b) = await pair(capacity: capacity);
    final ca = _Counting(a);
    final cb = _Counting(b);
    counters?.call(ca, cb);
    unawaited((s ?? service).serve(cb));
    final channel = await PeerHandshake.initiate(
      crypto,
      ca,
      local: d.local,
      policy: PeerPolicy.node(node.sign.publicKey),
    );
    return PeerClient(channel, responseTimeout: timeout, idleTimeout: timeout);
  }

  Matcher failsWith(pb.ErrorCode code, [String? detail]) => throwsA(
    isA<PeerRequestException>()
        .having((e) => e.code, 'code', code)
        .having((e) => e.detail, 'detail', contains(detail ?? '')),
  );

  Future<void> upload(PeerClient c, _Device d) async {
    expect(await c.putFragment(await put(d), fragment.bytes), fragmentId);
  }

  group('3.4.1: операции', () {
    test('загрузка, наличие, выдача, удаление, ping', () async {
      final c = await connect(alice);
      expect(await c.ping(), lessThan(const Duration(seconds: 1)));
      expect(await c.hasFragments([fragmentId]), [false]);
      await upload(c, alice);
      expect(storage.record(fragmentId)!.accountId, alice.account.accountId);
      expect(await c.hasFragments([fragmentId, Uint8List(32)]), [true, false]);
      expect(await c.readFragment(await get(alice)), fragment.bytes);
      await c.deleteFragment(await delete(alice));
      expect(storage.record(fragmentId), isNull);
      expect(await c.hasFragments([fragmentId]), [false]);
      final stats = service.stats;
      expect(stats.fragmentsReceived, 1);
      expect(stats.fragmentsSent, 1);
      expect(stats.fragmentsDeleted, 1);
      expect(stats.bytesReceived, fragment.bytes.length);
      expect(stats.bytesSent, fragment.bytes.length);
      expect(service.gate.active, 0);
      await c.close();
    });

    test('другое устройство той же учётной записи видит и удаляет', () async {
      final c = await connect(alice);
      await upload(c, alice);
      final phone = await connect(alicePhone);
      expect(await phone.hasFragments([fragmentId]), [true]);
      await phone.deleteFragment(await delete(alicePhone));
      expect(storage.record(fragmentId), isNull);
      await c.close();
      await phone.close();
    });

    test('HasFragments — только про фрагменты своей учётной записи', () async {
      final c = await connect(alice);
      await upload(c, alice);
      final other = await connect(bob);
      expect(await other.hasFragments([fragmentId]), [false]);
      await expectLater(
        other.hasFragments([Uint8List(31)]),
        failsWith(pb.ErrorCode.ERROR_CODE_BAD_REQUEST),
      );
      await c.close();
      await other.close();
    });

    test('чужой фрагмент не удаляется и с талоном DELETE (К-4)', () async {
      final c = await connect(alice);
      await upload(c, alice);
      final other = await connect(bob);
      await expectLater(
        other.deleteFragment(await delete(bob)),
        failsWith(pb.ErrorCode.ERROR_CODE_PERMISSION_DENIED, 'другой учётной'),
      );
      expect(storage.record(fragmentId), isNotNull);
      // Талон на устройство Алисы у Боба не работает: он не её собеседник.
      await expectLater(
        other.deleteFragment(await delete(alice)),
        failsWith(pb.ErrorCode.ERROR_CODE_PERMISSION_DENIED, 'device_sign'),
      );
      expect(storage.record(fragmentId), isNotNull);
      await c.close();
      await other.close();
    });

    test('узел-собеседник не удаляет фрагменты', () async {
      final c = await connect(alice);
      await upload(c, alice);
      // Другой узел (ремонт, этап 4) приходит со своим сертификатом узла.
      final otherNode = await DeviceKeys.generate(crypto);
      final otherPeer = LocalPeer(
        role: pb.PeerRole.PEER_ROLE_NODE,
        staticKey: otherNode.dh,
        certificate: await NodeCertificates.issue(
          crypto,
          alice.account,
          nodeId: otherNode.sign.publicKey,
          nodeDh: otherNode.dh.publicKey,
          issuedAt: DateTime.now(),
        ),
      );
      final (a, b) = await pair();
      unawaited(service.serve(b));
      final nodeClient = PeerClient(
        await PeerHandshake.initiate(
          crypto,
          a,
          local: otherPeer,
          policy: PeerPolicy.node(node.sign.publicKey),
        ),
      );
      final t = await SignedMessages.sign(
        crypto,
        coordinator,
        FragmentTickets.signingContext,
        pb.FragmentTicket(
          operation: pb.TicketOperation.TICKET_OPERATION_DELETE,
          nodeId: node.sign.publicKey,
          deviceSign: otherNode.sign.publicKey,
          fragmentId: fragmentId,
          fragmentSize: fragment.bytes.length,
          expiresAtUnixMs: Int64(
            DateTime.now()
                .add(const Duration(minutes: 5))
                .millisecondsSinceEpoch,
          ),
          ticketId: Uint8List(16)..fillRange(0, 16, 0xee),
        ),
      );
      await expectLater(
        nodeClient.deleteFragment(t),
        failsWith(pb.ErrorCode.ERROR_CODE_PERMISSION_DENIED, 'владельца'),
      );
      expect(storage.record(fragmentId), isNotNull);
      await c.close();
      await nodeClient.close();
    });

    test('узел-исполнитель ремонта загружает фрагмент владельца сегмента '
        '(4.3.3)', () async {
      final repairer = await DeviceKeys.generate(crypto);
      final repairerPeer = LocalPeer(
        role: pb.PeerRole.PEER_ROLE_NODE,
        staticKey: repairer.dh,
        certificate: await NodeCertificates.issue(
          crypto,
          bob.account,
          nodeId: repairer.sign.publicKey,
          nodeDh: repairer.dh.publicKey,
          issuedAt: DateTime.now(),
        ),
      );
      Future<PeerClient> connectAs(LocalPeer local) async {
        final (a, b) = await pair();
        unawaited(service.serve(b));
        return PeerClient(
          await PeerHandshake.initiate(
            crypto,
            a,
            local: local,
            policy: PeerPolicy.node(node.sign.publicKey),
          ),
        );
      }

      var n = 0;
      Future<pb.Signed> repairPut(List<int> device, {List<int>? owner}) =>
          SignedMessages.sign(
            crypto,
            coordinator,
            FragmentTickets.signingContext,
            pb.FragmentTicket(
              operation: pb.TicketOperation.TICKET_OPERATION_PUT,
              nodeId: node.sign.publicKey,
              deviceSign: device,
              fragmentId: fragmentId,
              fragmentSize: fragment.bytes.length,
              expiresAtUnixMs: Int64(
                DateTime.now()
                    .add(const Duration(minutes: 5))
                    .millisecondsSinceEpoch,
              ),
              ticketId: Uint8List(16)..fillRange(0, 16, 0xd0 + ++n),
              ownerAccount: owner,
            ),
          );

      final nodeClient = await connectAs(repairerPeer);
      // Без owner_account узел фрагмент не загружает.
      await expectLater(
        nodeClient.putFragment(
          await repairPut(repairer.sign.publicKey),
          fragment.bytes,
        ),
        failsWith(pb.ErrorCode.ERROR_CODE_PERMISSION_DENIED, 'owner_account'),
      );
      // Клиент не загружает от чужого имени.
      final c = await connect(bob);
      await expectLater(
        c.putFragment(
          await repairPut(
            bob.keys.sign.publicKey,
            owner: alice.account.accountId,
          ),
          fragment.bytes,
        ),
        failsWith(pb.ErrorCode.ERROR_CODE_PERMISSION_DENIED, 'owner_account'),
      );
      expect(storage.record(fragmentId), isNull);

      expect(
        await nodeClient.putFragment(
          await repairPut(
            repairer.sign.publicKey,
            owner: alice.account.accountId,
          ),
          fragment.bytes,
        ),
        fragmentId,
      );
      expect(storage.record(fragmentId)!.accountId, alice.account.accountId);
      // Повтор после потерянного ответа — успех; удаляет только владелец.
      expect(
        await nodeClient.putFragment(
          await repairPut(
            repairer.sign.publicKey,
            owner: alice.account.accountId,
          ),
          fragment.bytes,
        ),
        fragmentId,
      );
      await expectLater(
        c.deleteFragment(await delete(bob)),
        failsWith(pb.ErrorCode.ERROR_CODE_PERMISSION_DENIED),
      );
      final owner = await connect(alicePhone);
      expect(await owner.hasFragments([fragmentId]), [true]);
      await owner.deleteFragment(await delete(alicePhone));
      expect(storage.record(fragmentId), isNull);
      await c.close();
      await owner.close();
      await nodeClient.close();
    });

    test('повтор загрузки той же учётной записью — успех без '
        'передачи', () async {
      final c = await connect(alice, capacity: 1 << 16);
      await upload(c, alice);
      final received = service.stats.bytesReceived;
      await upload(c, alice);
      expect(service.stats.fragmentsReceived, 1);
      expect(service.stats.bytesReceived, received);
      await c.close();
    });

    test('тот же фрагмент от другой учётной записи — ALREADY_EXISTS', () async {
      final c = await connect(alice);
      await upload(c, alice);
      final other = await connect(bob);
      await expectLater(
        other.putFragment(await put(bob), fragment.bytes),
        failsWith(pb.ErrorCode.ERROR_CODE_ALREADY_EXISTS),
      );
      await c.close();
      await other.close();
    });

    test('квота — QUOTA_EXCEEDED', () async {
      await storage.close();
      storage = FragmentStorage.open(
        dir.path,
        crypto: crypto,
        quotaBytes: 1 << 20,
        diskAvailable: (_) => null,
      );
      service = makeService();
      final big = testFragment(crypto, seed: 2, blobLength: 2 << 20);
      final c = await connect(alice);
      await expectLater(
        c.putFragment(
          await put(
            alice,
            id: fragmentIdOf(crypto, big),
            size: big.bytes.length,
          ),
          big.bytes,
        ),
        failsWith(pb.ErrorCode.ERROR_CODE_QUOTA_EXCEEDED),
      );
      expect(storage.incomingCount, 0);
      await c.close();
    });

    test('нет фрагмента — NOT_FOUND', () async {
      final c = await connect(alice);
      await expectLater(
        c.readFragment(await get(alice)),
        failsWith(pb.ErrorCode.ERROR_CODE_NOT_FOUND),
      );
      await expectLater(
        c.deleteFragment(await delete(alice)),
        failsWith(pb.ErrorCode.ERROR_CODE_NOT_FOUND),
      );
      await c.close();
    });

    test('пауза — UNAVAILABLE с retry_after, HasFragments и Ping '
        'работают', () async {
      final c = await connect(alice);
      service.gate.paused = true;
      await expectLater(
        c.putFragment(await put(alice), fragment.bytes),
        throwsA(
          isA<PeerRequestException>()
              .having(
                (e) => e.code,
                'code',
                pb.ErrorCode.ERROR_CODE_UNAVAILABLE,
              )
              .having(
                (e) => e.retryAfter,
                'retryAfter',
                PeerService.pausedRetryAfter,
              ),
        ),
      );
      await c.ping();
      expect(await c.hasFragments([fragmentId]), [false]);
      service.gate.paused = false;
      await upload(c, alice);
      await c.close();
    });
  });

  group('3.4.1: правила талона', () {
    Future<void> rejected(
      Future<pb.Signed> Function() makeTicket,
      pb.ErrorCode code,
      String detail, {
      pb.TicketOperation op = pb.TicketOperation.TICKET_OPERATION_PUT,
    }) async {
      final c = await connect(alice);
      if (op != pb.TicketOperation.TICKET_OPERATION_PUT) await upload(c, alice);
      final t = await makeTicket();
      final Future<Object?> call = switch (op) {
        pb.TicketOperation.TICKET_OPERATION_GET => c.readFragment(t),
        pb.TicketOperation.TICKET_OPERATION_DELETE => c.deleteFragment(t),
        _ => c.putFragment(t, fragment.bytes),
      };
      await expectLater(call, failsWith(code, detail));
      if (op == pb.TicketOperation.TICKET_OPERATION_PUT) {
        expect(storage.record(fragmentId), isNull);
        expect(storage.incomingCount, 0);
      } else {
        expect(storage.record(fragmentId), isNotNull);
      }
      expect(service.stats.requestsRejected, greaterThan(0));
      await c.close();
    }

    test('подпись не ключом координатора — UNAUTHENTICATED', () async {
      await rejected(
        () => ticket(
          pb.TicketOperation.TICKET_OPERATION_PUT,
          alice,
          signer: stranger,
        ),
        pb.ErrorCode.ERROR_CODE_UNAUTHENTICATED,
        'untrusted',
      );
    });

    test('неверная подпись — UNAUTHENTICATED', () async {
      await rejected(
        () async {
          final t = await put(alice);
          final sig = Uint8List.fromList(t.signature);
          sig[0] ^= 1;
          return t..signature = sig;
        },
        pb.ErrorCode.ERROR_CODE_UNAUTHENTICATED,
        'signature',
      );
    });

    test('неканоническое тело — BAD_REQUEST', () async {
      await rejected(
        () async {
          final t = await put(alice);
          final body = Uint8List.fromList([...t.body, 0x78, 0x01]);
          return await SignedMessages.sign(
            crypto,
            coordinator,
            FragmentTickets.signingContext,
            pb.FragmentTicket.fromBuffer(body),
          );
        },
        pb.ErrorCode.ERROR_CODE_BAD_REQUEST,
        'неканоническ',
      );
    });

    test('талон на другую операцию — PERMISSION_DENIED', () async {
      await rejected(
        () => get(alice),
        pb.ErrorCode.ERROR_CODE_PERMISSION_DENIED,
        'operation',
      );
      // DELETE по талону GET.
      await rejected(
        () => get(alice),
        pb.ErrorCode.ERROR_CODE_PERMISSION_DENIED,
        'operation',
        op: pb.TicketOperation.TICKET_OPERATION_DELETE,
      );
    });

    test('другой узел — PERMISSION_DENIED', () async {
      await rejected(
        () => ticket(
          pb.TicketOperation.TICKET_OPERATION_PUT,
          alice,
          nodeId: crypto.randomBytes(32),
        ),
        pb.ErrorCode.ERROR_CODE_PERMISSION_DENIED,
        'node_id',
      );
    });

    test('другое устройство — PERMISSION_DENIED', () async {
      await rejected(
        () => put(alicePhone),
        pb.ErrorCode.ERROR_CODE_PERMISSION_DENIED,
        'device_sign',
      );
    });

    test('истёкший талон — TICKET_EXPIRED', () async {
      await rejected(
        () => ticket(
          pb.TicketOperation.TICKET_OPERATION_GET,
          alice,
          expiresIn: const Duration(minutes: -6),
        ),
        pb.ErrorCode.ERROR_CODE_TICKET_EXPIRED,
        'expired',
        op: pb.TicketOperation.TICKET_OPERATION_GET,
      );
    });

    test('истёкший в пределах допуска на часы — принимается', () async {
      final c = await connect(alice);
      final t = await ticket(
        pb.TicketOperation.TICKET_OPERATION_PUT,
        alice,
        expiresIn: const Duration(minutes: -4),
      );
      expect(await c.putFragment(t, fragment.bytes), fragmentId);
      await c.close();
    });

    test('срок дальше часа — PERMISSION_DENIED', () async {
      await rejected(
        () => ticket(
          pb.TicketOperation.TICKET_OPERATION_PUT,
          alice,
          expiresIn: const Duration(minutes: 66),
        ),
        pb.ErrorCode.ERROR_CODE_PERMISSION_DENIED,
        'tooLong',
      );
    });

    test('фрагмент не тот, что в талоне — INTEGRITY_FAILED', () async {
      await rejected(
        () => put(alice, id: crypto.randomBytes(32)),
        pb.ErrorCode.ERROR_CODE_INTEGRITY_FAILED,
        'fragment_id',
      );
    });

    test('размер не тот, что в талоне — BAD_REQUEST', () async {
      await rejected(
        () => put(alice, size: fragment.bytes.length + 1),
        pb.ErrorCode.ERROR_CODE_BAD_REQUEST,
        'размер',
      );
    });

    test('GET с другим размером — PERMISSION_DENIED', () async {
      await rejected(
        () => ticket(
          pb.TicketOperation.TICKET_OPERATION_GET,
          alice,
          size: fragment.bytes.length + 1,
        ),
        pb.ErrorCode.ERROR_CODE_PERMISSION_DENIED,
        'fragment_size',
        op: pb.TicketOperation.TICKET_OPERATION_GET,
      );
    });

    test('использованный талон отклоняется, и после перезапуска', () async {
      final c = await connect(alice);
      await upload(c, alice);
      final t = await get(alice);
      expect(await c.readFragment(t), fragment.bytes);
      await expectLater(
        c.readFragment(t),
        failsWith(pb.ErrorCode.ERROR_CODE_PERMISSION_DENIED, 'использован'),
      );
      await c.close();
      await service.close();
      await storage.close();
      storage = FragmentStorage.open(
        dir.path,
        crypto: crypto,
        quotaBytes: 1 << 30,
        diskAvailable: (_) => null,
      );
      service = makeService();
      final again = await connect(alice);
      await expectLater(
        again.readFragment(t),
        failsWith(pb.ErrorCode.ERROR_CODE_PERMISSION_DENIED, 'использован'),
      );
      await again.close();
    });

    test('один талон в двух запросах сразу — второй отклонён', () async {
      final c = await connect(alice);
      final t = await put(alice);
      final first = c.putFragment(t, fragment.bytes);
      final second = c.putFragment(t, fragment.bytes);
      await expectLater(
        second,
        failsWith(pb.ErrorCode.ERROR_CODE_PERMISSION_DENIED, 'использован'),
      );
      expect(await first, fragmentId);
      await c.close();
    });

    test('прерванная выдача не расходует талон', () async {
      final c = await connect(alice);
      await upload(c, alice);
      final t = await get(alice);
      await c.getFragment(t).first;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(await c.readFragment(t), fragment.bytes);
      await c.close();
    });
  });

  group('3.4.2: мультиплексирование и обратное давление', () {
    test('параллельные загрузки и выдачи по одному соединению', () async {
      service = makeService(download: 4 << 20);
      final fragments = [
        for (var i = 0; i < 4; i++)
          testFragment(crypto, seed: 10 + i, blobLength: 400000),
      ];
      final c = await connect(alice, capacity: 1 << 16);
      var maxActive = 0;
      final watch = Timer.periodic(const Duration(milliseconds: 5), (_) {
        if (service.gate.active > maxActive) maxActive = service.gate.active;
      });
      final ids = await Future.wait([
        for (final f in fragments)
          put(
            alice,
            id: fragmentIdOf(crypto, f),
            size: f.bytes.length,
          ).then((t) => c.putFragment(t, f.bytes)),
      ]);
      expect(ids, [for (final f in fragments) fragmentIdOf(crypto, f)]);
      expect(maxActive, 4);
      final got = await Future.wait([
        for (final f in fragments)
          ticket(
            pb.TicketOperation.TICKET_OPERATION_GET,
            alice,
            id: fragmentIdOf(crypto, f),
            size: f.bytes.length,
          ).then(c.readFragment),
      ]);
      watch.cancel();
      for (var i = 0; i < fragments.length; i++) {
        expect(got[i], fragments[i].bytes);
      }
      await c.close();
    });

    test(
      'клиент не читает выдачу: узел не копит её в памяти',
      skip: tcpBuffers,
      () async {
        final big = testFragment(crypto, seed: 3, blobLength: 8 << 20);
        final id = fragmentIdOf(crypto, big);
        final uploader = await connect(alice);
        await uploader.putFragment(
          await put(alice, id: id, size: big.bytes.length),
          big.bytes,
        );
        late _Counting nodeSide;
        final c = await connect(
          alice,
          capacity: 1 << 16,
          counters: (_, n) => nodeSide = n,
        );
        final before = nodeSide.sent;
        final chunks = <Uint8List>[];
        final t = await ticket(
          pb.TicketOperation.TICKET_OPERATION_GET,
          alice,
          id: id,
          size: big.bytes.length,
        );
        // Подписка завершается сама вместе с потоком.
        // ignore: cancel_subscriptions
        late final StreamSubscription<Uint8List> sub;
        sub = c.getFragment(t).listen((chunk) {
          chunks.add(chunk);
          // Потребитель встаёт после первой части.
          if (chunks.length == 1) sub.pause();
        });
        final done = sub.asFuture<void>();
        await Future<void>.delayed(const Duration(milliseconds: 500));
        // Отправлено не больше буфера клиента (1 МиБ), соединения (64 КиБ) и
        // нескольких частей в пути — далеко не 8 МиБ.
        expect(nodeSide.sent - before, lessThan(2 << 20));
        expect(service.gate.active, 1);
        sub.resume();
        await done;
        expect(
          BytesBuilder()..addAllChunks(chunks),
          hasLength(big.bytes.length),
        );
        await uploader.close();
        await c.close();
      },
    );

    test(
      'узел пишет медленно: клиент упирается в соединение',
      skip: tcpBuffers,
      () async {
        service = makeService(download: 1 << 20);
        final big = testFragment(crypto, seed: 4, blobLength: 4 << 20);
        late _Counting clientSide;
        final c = await connect(
          alice,
          capacity: 1 << 16,
          counters: (cl, _) => clientSide = cl,
        );
        final upload = c.putFragment(
          await put(
            alice,
            id: fragmentIdOf(crypto, big),
            size: big.bytes.length,
          ),
          big.bytes,
        );
        await Future<void>.delayed(const Duration(seconds: 1));
        // За секунду при 1 МиБ/с принято около 1 МиБ; в очереди узла — не
        // больше его буфера (1 МиБ), в соединении — 64 КиБ.
        expect(clientSide.sent, lessThan(3 << 20));
        expect(await upload, fragmentIdOf(crypto, big));
      },
    );

    test('загрузка встала — UNAVAILABLE, приём отброшен', () async {
      service = makeService(
        limits: const PeerLimits(transferTimeout: Duration(milliseconds: 300)),
      );
      final (a, b) = await pair();
      unawaited(service.serve(b));
      final channel = await PeerHandshake.initiate(
        crypto,
        a,
        local: alice.local,
        policy: PeerPolicy.node(node.sign.publicKey),
      );
      final replies = StreamIterator(channel.messages);
      await channel.send(
        pb.PeerMessage(
          requestId: Int64(1),
          putFragment: pb.PutFragment(ticket: await put(alice)),
        ),
      );
      await channel.send(
        pb.PeerMessage(
          requestId: Int64(1),
          fragmentData: pb.FragmentData(
            data: Uint8List.sublistView(fragment.bytes, 0, 1000),
          ),
        ),
      );
      expect(await replies.moveNext(), isTrue);
      expect(replies.current.error.code, pb.ErrorCode.ERROR_CODE_UNAVAILABLE);
      await pumpEventQueue();
      expect(storage.incomingCount, 0);
      expect(service.gate.active, 0);
      channel.destroy();
    });

    test('отмена загрузки: приём отброшен, талон не израсходован', () async {
      service = makeService(download: 1 << 20);
      final c = await connect(alice, capacity: 1 << 16);
      final t = await put(alice);
      final cancel = Completer<void>();
      final first = c.putFragment(t, fragment.bytes, cancel: cancel.future);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(storage.incomingCount, 1);
      cancel.complete();
      await expectLater(first, throwsA(isA<CancelledException>()));
      for (var i = 0; i < 50 && storage.incomingCount > 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(storage.incomingCount, 0);
      expect(storage.record(fragmentId), isNull);
      expect(await c.putFragment(t, fragment.bytes), fragmentId);
      await c.close();
    });

    test('request_id не растёт — соединение закрывается', () async {
      final (a, b) = await pair();
      final served = service.serve(b);
      final channel = await PeerHandshake.initiate(
        crypto,
        a,
        local: alice.local,
        policy: PeerPolicy.node(node.sign.publicKey),
      );
      final replies = StreamIterator(channel.messages);
      await channel.send(
        pb.PeerMessage(
          requestId: Int64(5),
          ping: pb.Ping(nonce: Int64(1)),
        ),
      );
      expect(await replies.moveNext(), isTrue);
      await channel.send(
        pb.PeerMessage(
          requestId: Int64(5),
          ping: pb.Ping(nonce: Int64(2)),
        ),
      );
      expect(await replies.moveNext(), isFalse);
      await served;
    });

    test('FragmentData без PutFragment — соединение закрывается', () async {
      final (a, b) = await pair();
      final served = service.serve(b);
      final channel = await PeerHandshake.initiate(
        crypto,
        a,
        local: alice.local,
        policy: PeerPolicy.node(node.sign.publicKey),
      );
      final replies = StreamIterator(channel.messages);
      await channel.send(
        pb.PeerMessage(
          requestId: Int64(3),
          fragmentData: pb.FragmentData(data: [1]),
        ),
      );
      expect(await replies.moveNext(), isFalse);
      await served;
    });

    test('соединение без запросов закрывается по idle_timeout', () async {
      service = makeService(
        limits: const PeerLimits(idleTimeout: Duration(milliseconds: 200)),
      );
      final c = await connect(alice);
      await c.ping();
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(c.isClosed, isTrue);
      expect(service.connectionCount, 0);
    });

    test('по TCP', skip: network ? 'проверяется в памяти' : null, () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((s) => unawaited(service.serve(SocketConnection(s))));
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        server.port,
      );
      final c = PeerClient(
        await PeerHandshake.initiate(
          crypto,
          SocketConnection(socket),
          local: alice.local,
          policy: PeerPolicy.node(node.sign.publicKey),
        ),
      );
      final big = testFragment(crypto, seed: 5, blobLength: 6 << 20);
      final id = fragmentIdOf(crypto, big);
      await c.putFragment(
        await put(alice, id: id, size: big.bytes.length),
        big.bytes,
      );
      expect(
        await c.readFragment(
          await ticket(
            pb.TicketOperation.TICKET_OPERATION_GET,
            alice,
            id: id,
            size: big.bytes.length,
          ),
        ),
        big.bytes,
      );
      await c.close();
      await server.close();
    });
  });

  // Тег serial: замеры скорости с допуском 10% идут отдельным прогоном
  // с -j 1, чтобы на них не влияли параллельные тестовые файлы.
  group('3.4.3: пределы', tags: 'serial', () {
    test('скорость отдачи — в пределах 10% на длинной передаче', () async {
      const rate = 4000000;
      service = makeService(upload: rate);
      final big = testFragment(crypto, seed: 6, blobLength: 8 << 20);
      final id = fragmentIdOf(crypto, big);
      final c = await connect(alice);
      await c.putFragment(
        await put(alice, id: id, size: big.bytes.length),
        big.bytes,
      );
      final watch = Stopwatch()..start();
      await c.readFragment(
        await ticket(
          pb.TicketOperation.TICKET_OPERATION_GET,
          alice,
          id: id,
          size: big.bytes.length,
        ),
      );
      final expected = big.bytes.length / rate * 1000;
      expect(watch.elapsedMilliseconds, closeTo(expected, expected * 0.1));
      await c.close();
    });

    test('скорость приёма — в пределах 10%, общая на соединения', () async {
      const rate = 4000000;
      service = makeService(download: rate);
      final fragments = [
        testFragment(crypto, seed: 7, blobLength: 4 << 20),
        testFragment(crypto, seed: 8, blobLength: 4 << 20),
      ];
      final clients = [await connect(alice), await connect(alicePhone)];
      final tickets = [
        await put(
          alice,
          id: fragmentIdOf(crypto, fragments[0]),
          size: fragments[0].bytes.length,
        ),
        await put(
          alicePhone,
          id: fragmentIdOf(crypto, fragments[1]),
          size: fragments[1].bytes.length,
        ),
      ];
      final watch = Stopwatch()..start();
      await Future.wait([
        for (var i = 0; i < 2; i++)
          clients[i].putFragment(tickets[i], fragments[i].bytes),
      ]);
      final total = fragments[0].bytes.length + fragments[1].bytes.length;
      final expected = total / rate * 1000;
      expect(watch.elapsedMilliseconds, closeTo(expected, expected * 0.1));
      for (final c in clients) {
        await c.close();
      }
    });

    test('соединений на собеседника больше предела — RATE_LIMITED', () async {
      service = makeService(limits: const PeerLimits(maxConnectionsPerPeer: 1));
      final first = await connect(alice);
      final second = await connect(alice);
      await expectLater(
        second.ping(),
        failsWith(pb.ErrorCode.ERROR_CODE_RATE_LIMITED),
      );
      // Другое устройство — другой собеседник.
      final phone = await connect(alicePhone);
      await phone.ping();
      await first.ping();
      await first.close();
      await phone.close();
    });

    test('соединений всего больше предела — отказ до рукопожатия', () async {
      service = makeService(limits: const PeerLimits(maxConnections: 1));
      final first = await connect(alice);
      await expectLater(connect(bob), throwsA(isA<PeerRejectedException>()));
      await first.ping();
      await first.close();
    });

    test('одновременных запросов собеседника больше предела — '
        'RATE_LIMITED', () async {
      service = makeService(
        download: 1 << 20,
        limits: const PeerLimits(maxRequestsPerPeer: 1),
      );
      final c = await connect(alice, capacity: 1 << 16);
      final phone = await connect(alice, capacity: 1 << 16);
      final upload = c.putFragment(await put(alice), fragment.bytes);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      // Предел — на собеседника по всем его соединениям.
      await expectLater(
        phone.ping(),
        failsWith(pb.ErrorCode.ERROR_CODE_RATE_LIMITED),
      );
      expect(await upload, fragmentId);
      await phone.ping();
      await c.close();
      await phone.close();
    });

    test('запросов в секунду больше предела — RATE_LIMITED с '
        'retry_after', () async {
      service = makeService(limits: const PeerLimits(requestsPerSecond: 5));
      final c = await connect(alice);
      final results = await Future.wait([
        for (var i = 0; i < 20; i++)
          c.ping().then<Object>((d) => d, onError: (Object e) => e),
      ]);
      final limited = results.whereType<PeerRequestException>().toList();
      // Запас — вдвое больше предела: 10 проходят сразу.
      expect(results.length - limited.length, 10);
      expect(
        limited.every(
          (e) =>
              e.code == pb.ErrorCode.ERROR_CODE_RATE_LIMITED &&
              e.retryAfter != null,
        ),
        isTrue,
      );
      await c.close();
    });
  });

  group('демон', skip: network ? 'проверяется в памяти' : null, () {
    test('NodeDaemon принимает соединение по TCP (3.5.1), пределы по '
        'расписанию', () async {
      final data = Directory.systemTemp.createTempSync('fs_peer_daemon_');
      addTearDown(() => data.deleteSync(recursive: true));
      await nodeWithCertificate(data, crypto);
      final daemon = await NodeDaemon.start(
        NodeConfig(
          dataDir: data.path,
          listenPort: 0,
          portMapping: PortMappingMode.off,
          quotaBytes: 1 << 30,
          freeReserveBytes: 0,
          coordinatorKeys: [bytesToHex(coordinator.publicKey)],
          limits: const SpeedLimits(uploadBytesPerSecond: 5000000),
          schedule: SpeedSchedule.parse(['00:00-24:00 download=3000000']),
          log: const LogConfig(file: '-'),
        ),
        crypto: crypto,
        handleSignals: false,
      );
      expect(daemon.effectiveLimits.uploadBytesPerSecond, 5000000);
      expect(daemon.effectiveLimits.downloadBytesPerSecond, 3000000);
      final identity = daemon.identity;
      final port = daemon.listener!.port;
      final c = PeerClient(
        await PeerHandshake.initiate(
          crypto,
          SocketConnection(
            await Socket.connect(InternetAddress.loopbackIPv4, port),
          ),
          local: alice.local,
          policy: PeerPolicy.node(identity.nodeId),
        ),
      );
      final t = await SignedMessages.sign(
        crypto,
        coordinator,
        FragmentTickets.signingContext,
        pb.FragmentTicket(
          operation: pb.TicketOperation.TICKET_OPERATION_PUT,
          nodeId: identity.nodeId,
          deviceSign: alice.keys.sign.publicKey,
          fragmentId: fragmentId,
          fragmentSize: fragment.bytes.length,
          expiresAtUnixMs: Int64(
            DateTime.now()
                .add(const Duration(minutes: 5))
                .millisecondsSinceEpoch,
          ),
          ticketId: Uint8List(16)..fillRange(0, 16, 7),
        ),
      );
      expect(await c.putFragment(t, fragment.bytes), fragmentId);
      expect(daemon.stats.fragmentsReceived, 1);
      final status = daemon.status();
      expect(status['fragments'], 1);
      expect(status['connections'], 1);
      expect((status['listen']! as Map)['accepted'], 1);
      expect((status['limits']! as Map)['effective'], {
        'uploadBytesPerSecond': 5000000,
        'downloadBytesPerSecond': 3000000,
      });
      await daemon.stop();
      await pumpEventQueue();
      expect(c.isClosed, isTrue);
      await expectLater(
        Socket.connect(InternetAddress.loopbackIPv4, port),
        throwsA(isA<SocketException>()),
        reason: 'после остановки порт закрыт',
      );
    });
  });
}

extension on BytesBuilder {
  BytesBuilder addAllChunks(List<Uint8List> chunks) {
    chunks.forEach(add);
    return this;
  }
}
