// Relay на координаторе (задачи 3.8.2, 3.8.3; protocol.md, раздел 4.12):
// пропуска LISTEN и CONNECT, назначение relay узлу, суточный предел
// учётной записи по отчётам relay, отчёты клиентов о трафике и метрики
// оператора. Сквозной тест: демон узла без адресов сам держит соединение
// с relay, клиент получает пропуск и обменивается с узлом фрагментами;
// без пропуска relay соединение не устанавливает. Нужен FS_TEST_POSTGRES.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:coordinator/coordinator.dart';
import 'package:core/core.dart' hide ConfigException;
import 'package:fixnum/fixnum.dart';
import 'package:node/node.dart';
import 'package:protocol/protocol.dart' as pb;
import 'package:relay/relay.dart';
import 'package:test/test.dart';

import 'support/db_harness.dart';
import 'support/live.dart';
import 'support/postgres.dart';

void main() {
  test('настройки relay', () {
    final key = bytesToHex(Uint8List(32)..[0] = 0xab);
    final config = CoordinatorConfig.parse('''
relay:
  servers:
    - "eu1 relay1.example.org:7350 $key"
    - "eu2 [2001:db8::1]:7350 $key"
  pass_key_file: /etc/fs/relay-pass.key
  pass_minutes: 30
  account_bytes_per_day: 1000000000
''', {});
    final relay = config.relay;
    expect(relay.enabled, isTrue);
    expect(relay.servers.map((s) => s.name), ['eu1', 'eu2']);
    expect(relay.servers[1].endpoint, '[2001:db8::1]:7350');
    expect(relay.passLifetime, const Duration(minutes: 30));
    expect(relay.accountBytesPerDay, 1000000000);
    expect(relay.byKey(Uint8List(32)..[0] = 0xab)!.name, 'eu1');
    final fromEnv = CoordinatorConfig.parse('', {
      'FS_COORDINATOR_RELAY_SERVERS': 'a 203.0.113.1:7350 $key,b h:1 $key',
    });
    expect(fromEnv.relay.servers.map((s) => s.name), ['a', 'b']);
    expect(fromEnv.relay.enabled, isFalse, reason: 'нет pass_key_file');
    for (final bad in [
      'x 203.0.113.1:7350',
      'X 203.0.113.1:7350 $key',
      'x 203.0.113.1 $key',
      'x 203.0.113.1:7350 ${key.toUpperCase()}',
      'x h:1 $key,x h:2 $key',
    ]) {
      expect(
        () =>
            CoordinatorConfig.parse('', {'FS_COORDINATOR_RELAY_SERVERS': bad}),
        throwsA(isA<ConfigException>()),
        reason: bad,
      );
    }
  });

  if (testPostgresUrl == null) {
    test('relay на координаторе', () {}, skip: skipWithoutPostgres);
    return;
  }

  group('пропуска и учёт', () {
    late DbHarness h;
    late Ed25519KeyPair passKey;
    late Ed25519KeyPair relayKey;
    late Ed25519KeyPair otherRelayKey;
    late AccountKeys alice;
    late Ed25519KeyPair device;
    late AccountKeys owner;
    late Ed25519KeyPair node;
    late Ed25519KeyPair otherNode;

    const day = 10 << 20;
    const perPass = 4 << 20;

    setUp(() async {
      final crypto = await SodiumCryptoProvider.load();
      Future<Ed25519KeyPair> key() =>
          crypto.ed25519FromSeed(SecretBytes(crypto.randomBytes(32)));
      passKey = await key();
      relayKey = await key();
      otherRelayKey = await key();
      h = await DbHarness.create(
        config: CoordinatorConfig(
          nodes: DbHarness.testConfig.nodes,
          placement: DbHarness.testConfig.placement,
          relay: RelayPolicy(
            servers: [
              RelayServerInfo(
                name: 'r1',
                endpoint: '203.0.113.30:7350',
                publicKey: relayKey.publicKey,
              ),
              RelayServerInfo(
                name: 'r2',
                endpoint: '203.0.113.31:7350',
                publicKey: otherRelayKey.publicKey,
              ),
            ],
            passKeyFile: '-',
            passBytes: perPass,
            accountBytesPerDay: day,
            passLifetime: const Duration(minutes: 30),
          ),
        ),
        relayPassKey: passKey,
      );
      alice = await h.newAccount();
      device = await h.newKey();
      await h.register(alice, device, login: 'alice');
      owner = await h.newAccount();
      await h.register(owner, await h.newKey(), login: 'keeper');
      node = await h.newKey();
      otherNode = await h.newKey();
      await h.registerNode(owner, node, endpoints: const []);
      await h.registerNode(owner, otherNode, ip: '203.0.113.11');
    });
    tearDown(() => h.close());

    Future<pb.GetRelayPassResponse> getPass(
      Ed25519KeyPair caller,
      Ed25519KeyPair to,
    ) => h.call(
      'GetRelayPass',
      pb.GetRelayPassRequest(nodeId: to.publicKey),
      pb.GetRelayPassResponse.fromBuffer,
      key: caller,
    );

    /// Пропуск из ответа, проверенный, как его проверит relay из ответа.
    Future<pb.RelayPass> open(pb.GetRelayPassResponse r) => RelayPasses.verify(
      h.crypto,
      r.pass,
      CoordinatorKeySet([passKey.publicKey]),
      relay: r.relayEndpoint == '203.0.113.30:7350' ? 'r1' : 'r2',
      now: h.clock.now,
    );

    Future<void> report(
      Ed25519KeyPair key,
      String relay,
      Map<List<int>, int> usage,
    ) => h.call(
      'ReportRelayUsage',
      pb.ReportRelayUsageRequest(
        relay: relay,
        usage: [
          for (final MapEntry(:key, :value) in usage.entries)
            pb.RelayAccountUsage(
              accountId: key,
              bytes: Int64(value),
              sessions: 1,
            ),
        ],
        listeners: 1,
        sessions: 1,
        sessionsOpened: Int64(usage.length),
        bytes: Int64(usage.values.fold(0, (a, b) => a + b)),
      ),
      pb.ReportRelayUsageResponse.fromBuffer,
      key: key,
    );

    test('LISTEN: узлу на себя, relay назначается и сохраняется', () async {
      final first = await getPass(node, node);
      final pass = await open(first);
      expect(pass.role, pb.RelayRole.RELAY_ROLE_LISTEN);
      expect(pass.holder, node.publicKey);
      expect(pass.nodeId, node.publicKey);
      expect(pass.accountId, owner.accountId);
      expect(pass.maxBytes.toInt(), 0);
      expect(
        pass.expiresAtUnixMs.toInt(),
        h.clock.now.add(const Duration(minutes: 30)).millisecondsSinceEpoch,
      );
      // Повторный пропуск — на тот же relay.
      for (var i = 0; i < 3; i++) {
        expect((await getPass(node, node)).relayEndpoint, first.relayEndpoint);
      }
    });

    test('CONNECT: к узлу на relay, тот же relay, предел пропуска', () async {
      await expectLater(
        getPass(device, node),
        failsWith(pb.ErrorCode.ERROR_CODE_NOT_FOUND),
      );
      final listen = await getPass(node, node);
      final connect = await getPass(device, node);
      expect(connect.relayEndpoint, listen.relayEndpoint);
      final pass = await open(connect);
      expect(pass.role, pb.RelayRole.RELAY_ROLE_CONNECT);
      expect(pass.holder, device.publicKey);
      expect(pass.nodeId, node.publicKey);
      expect(pass.accountId, alice.accountId);
      expect(pass.maxBytes.toInt(), perPass);
      // Узел при ремонте — тоже CONNECT, учёт — на владельца узла.
      final repair = await open(await getPass(otherNode, node));
      expect(repair.role, pb.RelayRole.RELAY_ROLE_CONNECT);
      expect(repair.accountId, owner.accountId);
      // Пропуск LISTEN истёк — узел больше не на relay.
      h.clock.advance(const Duration(minutes: 31));
      await expectLater(
        getPass(device, node),
        failsWith(pb.ErrorCode.ERROR_CODE_NOT_FOUND),
      );
    });

    test('суточный предел учётной записи по отчётам relay', () async {
      await getPass(node, node);
      await report(relayKey, 'r1', {alice.accountId: day - (1 << 20)});
      var pass = await open(await getPass(device, node));
      expect(pass.maxBytes.toInt(), 1 << 20);
      // Отчёт другого relay складывается с первым.
      await report(otherRelayKey, 'r2', {alice.accountId: 2 << 20});
      await expectLater(
        getPass(device, node),
        throwsA(
          isA<RpcFailure>()
              .having(
                (f) => f.code,
                'code',
                pb.ErrorCode.ERROR_CODE_QUOTA_EXCEEDED,
              )
              .having((f) => f.error.retryAfterMs, 'retryAfter', isPositive),
        ),
      );
      // Другая учётная запись предела не делит.
      expect(
        (await open(await getPass(otherNode, node))).maxBytes.toInt(),
        perPass,
      );
      // Новые сутки UTC — предел снова полный.
      h.clock.advance(const Duration(days: 1));
      await getPass(node, node);
      pass = await open(await getPass(device, node));
      expect(pass.maxBytes.toInt(), perPass);
    });

    test(
      'отчёт relay: только ключом relay из настроек и под своим именем',
      () async {
        await expectLater(
          report(device, 'r1', {}),
          failsWith(pb.ErrorCode.ERROR_CODE_PERMISSION_DENIED),
        );
        await expectLater(
          report(node, 'r1', {}),
          failsWith(pb.ErrorCode.ERROR_CODE_PERMISSION_DENIED),
        );
        await expectLater(
          report(relayKey, 'r2', {}),
          failsWith(pb.ErrorCode.ERROR_CODE_BAD_REQUEST),
        );
        await expectLater(
          report(relayKey, 'r1', {Uint8List(31): 1}),
          failsWith(pb.ErrorCode.ERROR_CODE_BAD_REQUEST),
        );
        // Неизвестная учётная запись пропускается.
        await report(relayKey, 'r1', {Uint8List(32): 1000});
        final response = await h.call(
          'ReportRelayUsage',
          pb.ReportRelayUsageRequest(relay: 'r1'),
          pb.ReportRelayUsageResponse.fromBuffer,
          key: relayKey,
        );
        expect(response.nextReportMs, 60000);
      },
    );

    test('отчёты трафика и метрики оператора', () async {
      Future<void> traffic(Ed25519KeyPair key, Map<int, int> bytes) => h.call(
        'ReportTraffic',
        pb.ReportTrafficRequest(
          traffic: [
            for (final MapEntry(:key, :value) in bytes.entries)
              pb.TrafficByMethod(
                method: pb.ConnectionMethod.valueOf(key),
                bytes: Int64(value),
                connections: 1,
              ),
          ],
        ),
        pb.ReportTrafficResponse.fromBuffer,
        key: key,
      );
      await traffic(device, {1: 6000, 3: 3000});
      await traffic(device, {3: 1000});
      await traffic(otherNode, {2: 10000});
      await expectLater(
        h.call(
          'ReportTraffic',
          pb.ReportTrafficRequest(
            traffic: [
              pb.TrafficByMethod(
                method: pb.ConnectionMethod.CONNECTION_METHOD_RELAY,
              ),
              pb.TrafficByMethod(
                method: pb.ConnectionMethod.CONNECTION_METHOD_RELAY,
              ),
            ],
          ),
          pb.ReportTrafficResponse.fromBuffer,
          key: device,
        ),
        failsWith(pb.ErrorCode.ERROR_CODE_BAD_REQUEST),
      );
      await getPass(node, node);
      await report(relayKey, 'r1', {alice.accountId: 5000});
      final admin = AdminService(
        h.db,
        onlineWindow: const Duration(minutes: 15),
        probation: Duration.zero,
        clock: h.clock.call,
      );
      final stats = await admin.relayStats();
      expect(stats['nodesOnRelay'], 1);
      expect(stats['accountsUsingRelay'], 1);
      final relays = stats['relays']! as List<Object?>;
      final r1 = relays.single! as Map<String, Object?>;
      expect(r1['relay'], 'r1');
      expect(r1['bytes'], 5000);
      expect(r1['listeners'], 1);
      final traffics = stats['traffic']! as Map<String, Object?>;
      expect((traffics['relay']! as Map)['bytes'], 4000);
      expect((traffics['direct']! as Map)['bytes'], 6000);
      expect((traffics['udp']! as Map)['accounts'], 1);
      expect(stats['relayShare'], 0.2);
      // То же через CLI оператора.
      final lines = <String>[];
      final code = await runAdmin(
        ['relay', 'stats', '--days', '1'],
        service: admin,
        osUser: 'test',
        console: _Console(lines),
      );
      expect(code, AdminExit.ok);
      expect(lines.join('\n'), contains('relayShare: 0.2'));
    });

    test('relay выключен — NOT_FOUND', () async {
      final off = await DbHarness.create();
      addTearDown(off.close);
      final n = await off.newKey();
      final o = await off.newAccount();
      await off.register(o, await off.newKey(), login: 'keeper');
      await off.registerNode(o, n);
      await expectLater(
        off.call(
          'GetRelayPass',
          pb.GetRelayPassRequest(nodeId: n.publicKey),
          pb.GetRelayPassResponse.fromBuffer,
          key: n,
        ),
        failsWith(pb.ErrorCode.ERROR_CODE_NOT_FOUND),
      );
    });
  });

  group('сквозной: узел без адресов через relay', () {
    late CryptoProvider crypto;
    late RelayServer relay;
    late Ed25519KeyPair passKey;
    late Ed25519KeyPair relayKey;
    late LiveCoordinator live;
    late Directory dir;
    late NodeDaemon daemon;
    late Uint8List nodeId;
    late DeviceKeys device;
    late pb.Signed deviceCertificate;
    late Ed25519KeyPair signerKey;

    setUp(() async {
      crypto = await SodiumCryptoProvider.load();
      passKey = await crypto.ed25519FromSeed(
        SecretBytes(crypto.randomBytes(32)),
      );
      relayKey = await crypto.ed25519FromSeed(
        SecretBytes(crypto.randomBytes(32)),
      );
      relay = await RelayServer.bind(
        crypto: crypto,
        name: 'r1',
        passKeys: CoordinatorKeySet([passKey.publicKey]),
        host: '127.0.0.1',
      );
      // Проверка достижимости с частных адресов выключена: узел на
      // loopback для координатора «за NAT», адресов у него нет.
      live = await LiveCoordinator.start(
        relay: RelayPolicy(
          servers: [
            RelayServerInfo(
              name: 'r1',
              endpoint: '127.0.0.1:${relay.port}',
              publicKey: relayKey.publicKey,
            ),
          ],
          passKeyFile: '-',
        ),
        relayPassKey: passKey,
        checkPrivateAddresses: false,
      );
      dir = Directory.systemTemp.createTempSync('fs-relay-');
      final owner = await AccountKeys.fromMasterKey(
        SecretBytes(crypto.randomBytes(32)),
        crypto,
      );
      device = await DeviceKeys.generate(crypto);
      deviceCertificate = await DeviceCertificates.issue(
        crypto,
        owner,
        device,
        issuedAt: DateTime.now(),
      );
      final client = live.client();
      await client.registerAccount(
        pb.RegisterAccountRequest(
          deviceCertificate: deviceCertificate,
          login: 'relay-owner',
        ),
        accountKey: owner.accountSign,
      );
      client.close();
      await NodeIdentity.ensureKeys(dir, crypto);
      final identity = await NodeIdentity.load(dir, crypto);
      await NodeIdentity.importCertificate(
        dir,
        crypto,
        (await NodeCertificates.issue(
          crypto,
          owner,
          nodeId: identity.nodeId,
          nodeDh: identity.nodeDh,
          issuedAt: DateTime.now(),
        )).writeToBuffer(),
      );
      nodeId = identity.nodeId;
      identity.dispose();
      signerKey = await crypto.ed25519FromSeed(
        SecretBytes(Uint8List(32)..fillRange(0, 32, 0xC0)),
      );
      daemon = await NodeDaemon.start(
        NodeConfig.parse(
          '''
storage:
  quota_bytes: 200000000000
  free_reserve_bytes: 0
listen:
  host: 127.0.0.1
  port: 0
  port_mapping: off
  udp: false
coordinator:
  url: ${live.url}
  keys: [${bytesToHex(signerKey.publicKey)}]
log:
  file: "-"
  level: warning
''',
          const {},
          dataDir: dir.path,
        ),
        crypto: crypto,
        handleSignals: false,
      );
      for (var i = 0; i < 200 && !relay.isListening(nodeId); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(relay.isListening(nodeId), isTrue);
    });

    tearDown(() async {
      await daemon.stop();
      await live.close();
      await relay.close();
      dir.deleteSync(recursive: true);
    });

    test('фрагменты через relay, учёт трафика и метрики', () async {
      expect(daemon.status()['relay'], containsPair('connected', true));
      expect((daemon.status()['reachability']! as Map)['endpoints'], isEmpty);
      final client = live.client(device: device);
      addTearDown(client.close);
      final meter = TrafficMeter();
      final connection = meter.wrap(
        await RelayConnector(client: client).connect(nodeId),
        pb.ConnectionMethod.CONNECTION_METHOD_RELAY,
      );
      final peer = PeerClient(
        await PeerHandshake.initiate(
          crypto,
          connection,
          local: LocalPeer(
            role: pb.PeerRole.PEER_ROLE_CLIENT,
            staticKey: device.dh,
            certificate: deviceCertificate,
            software: 'cli test',
          ),
          policy: PeerPolicy.node(nodeId),
        ),
      );
      await peer.ping();
      final fragment = encodeFragments(
        crypto,
        blob: crypto.randomBytes(1 << 20),
        segmentId: crypto.randomBytes(32),
        k: 1,
        n: 2,
      ).first;
      final id = fragment.header.fragmentId(crypto);
      Future<pb.Signed> ticket(pb.TicketOperation op, int n) =>
          SignedMessages.sign(
            crypto,
            signerKey,
            FragmentTickets.signingContext,
            pb.FragmentTicket(
              operation: op,
              nodeId: nodeId,
              deviceSign: device.sign.publicKey,
              fragmentId: id,
              fragmentSize: fragment.bytes.length,
              expiresAtUnixMs: Int64(
                DateTime.now()
                    .add(const Duration(minutes: 5))
                    .millisecondsSinceEpoch,
              ),
              ticketId: Uint8List(16)..[0] = n,
            ),
          );
      expect(
        await peer.putFragment(
          await ticket(pb.TicketOperation.TICKET_OPERATION_PUT, 1),
          fragment.bytes,
        ),
        id,
      );
      expect(
        await peer.readFragment(
          await ticket(pb.TicketOperation.TICKET_OPERATION_GET, 2),
        ),
        fragment.bytes,
      );
      await peer.close();
      expect(daemon.relay!.accepted, 1);

      // Отчёт relay — учёт на учётной записи клиента.
      final reporterClient = CoordinatorClient(
        baseUri: Uri.parse(live.url),
        crypto: crypto,
      );
      addTearDown(reporterClient.close);
      final reporter = RelayReporter(
        client: reporterClient,
        key: relayKey,
        server: relay,
      );
      await reporter.report();
      expect(reporter.reported, 1, reason: '${reporter.lastError}');
      // Отчёт клиента — доля relay в его трафике.
      await TrafficReporter(client: client, meter: meter).report();
      final admin = AdminService(
        Database.open(live.db.config),
        onlineWindow: const Duration(minutes: 15),
        probation: Duration.zero,
      );
      final stats = await admin.relayStats();
      final relays = stats['relays']! as List<Object?>;
      final r1 = relays.single! as Map<String, Object?>;
      expect(r1['bytes'], greaterThan(2 << 20));
      expect(r1['nodesAssigned'], 1);
      expect(stats['relayShare'], 1.0);
      final traffics = stats['traffic']! as Map<String, Object?>;
      expect((traffics['relay']! as Map)['bytes'], meter.toJson()['relay']);
    });

    test('без пропуска relay соединение не устанавливает', () async {
      // Пропуск, подписанный не ключом пропусков координатора.
      final forged = await RelayPasses.issue(
        crypto,
        device.sign,
        pb.RelayPass(
          role: pb.RelayRole.RELAY_ROLE_CONNECT,
          holder: device.sign.publicKey,
          nodeId: nodeId,
          accountId: Uint8List(32),
          relay: 'r1',
          passId: Uint8List(16),
          expiresAtUnixMs: Int64(
            DateTime.now()
                .add(const Duration(minutes: 5))
                .millisecondsSinceEpoch,
          ),
        ),
      );
      await expectLater(
        RelayClient.connect(
          crypto,
          host: '127.0.0.1',
          port: relay.port,
          pass: forged,
          key: device.sign,
        ),
        throwsA(
          isA<RelayException>().having(
            (e) => e.code,
            'code',
            pb.ErrorCode.ERROR_CODE_UNAUTHENTICATED,
          ),
        ),
      );
      // Настоящий пропуск чужого устройства без его ключа не работает.
      final client = live.client(device: device);
      addTearDown(client.close);
      final real = await client.getRelayPass(
        pb.GetRelayPassRequest(nodeId: nodeId),
      );
      final thief = await crypto.ed25519FromSeed(
        SecretBytes(crypto.randomBytes(32)),
      );
      await expectLater(
        RelayClient.connect(
          crypto,
          host: '127.0.0.1',
          port: relay.port,
          pass: real.pass,
          key: thief,
        ),
        throwsA(isA<RelayException>()),
      );
      expect(relay.sessionsOpened, 0);
    });
  });
}

final class _Console implements AdminConsole {
  new(this.lines);

  final List<String> lines;

  @override
  void out(String line) => lines.add(line);

  @override
  void err(String line) => lines.add(line);

  @override
  String? ask(String prompt) => null;
}
