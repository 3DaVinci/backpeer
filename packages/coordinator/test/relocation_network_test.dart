// Выход узла со всеми настоящими частями (задача 4.4.1; protocol.md,
// раздел 4.15): координатор и 22 демона узлов на loopback. Клиент
// сохраняет сегмент 10 из 20, один из его узлов объявляет выход (`cli node
// exit`, метод `exit` локального API); координатор поручает уходящему
// демону по каналу команд перенести свой фрагмент на новый узел и
// засчитывает его после аудита — число живых не опускается ниже 20. Когда
// переносить нечего, узел удалён из сети, демон удаляет фрагменты,
// останавливается и больше не запускается с этой папкой. Сегмент затем
// восстанавливается без уходящего узла. Нужен FS_TEST_POSTGRES.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:coordinator/coordinator.dart';
import 'package:core/core.dart' hide ConfigException;
import 'package:node/node.dart';
import 'package:postgres/postgres.dart';
import 'package:protocol/protocol.dart' as pb;
import 'package:test/test.dart';

import 'support/live.dart';
import 'support/postgres.dart';

void main() {
  if (testPostgresUrl == null) {
    test('выход узла по сети', () {}, skip: skipWithoutPostgres);
    return;
  }

  const nodeCount = 22;
  // k = 10, n = 20, t = 16 (durability.md).
  final params = DurabilityParameters();
  late CryptoProvider crypto;
  late LiveCoordinator live;
  late Directory dir;
  late Ed25519KeyPair signerKey;
  late Database db;
  final daemons = <NodeDaemon?>[];
  final nodeIds = <Uint8List>[];
  final nodeDirs = <String>[];

  String nodeConfig(int i) =>
      '''
storage:
  quota_bytes: 200000000000
  free_reserve_bytes: 0
listen:
  host: 127.0.0.1
  port: 0
  port_mapping: off
  udp: false
  relay: off
coordinator:
  url: ${live.url}
  keys: [${bytesToHex(signerKey.publicKey)}]
log:
  file: "-"
  level: warning
''';

  Future<void> until(
    FutureOr<bool> Function() ready,
    String what, {
    int tries = 300,
  }) async {
    for (var i = 0; i < tries && !await ready(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(await ready(), isTrue, reason: what);
  }

  setUp(() async {
    crypto = await SodiumCryptoProvider.load();
    live = await LiveCoordinator.start(
      // Новые узлы теста не наберут репутацию исполнителя 0,5 (возраст),
      // планировщик в фоне не мешает проходам теста.
      repair: const RepairPolicy(
        executorMinReputation: 0.05,
        tick: Duration(hours: 1),
      ),
    );
    db = Database.open(live.db.config);
    signerKey = await crypto.ed25519FromSeed(
      SecretBytes(Uint8List(32)..fillRange(0, 32, 0xC0)),
    );
    dir = Directory.systemTemp.createTempSync('fs-relocate-');
    daemons.clear();
    nodeIds.clear();
    nodeDirs.clear();
    final client = live.client();
    for (var i = 0; i < nodeCount; i++) {
      final owner = await AccountKeys.fromMasterKey(
        SecretBytes(crypto.randomBytes(32)),
        crypto,
      );
      await client.registerAccount(
        pb.RegisterAccountRequest(
          deviceCertificate: await DeviceCertificates.issue(
            crypto,
            owner,
            await DeviceKeys.generate(crypto),
            issuedAt: DateTime.now(),
          ),
          login: 'keeper$i',
        ),
        accountKey: owner.accountSign,
      );
      final nodeDir = Directory('${dir.path}/node-$i')..createSync();
      await NodeIdentity.ensureKeys(nodeDir, crypto);
      final identity = await NodeIdentity.load(nodeDir, crypto);
      await NodeIdentity.importCertificate(
        nodeDir,
        crypto,
        (await NodeCertificates.issue(
          crypto,
          owner,
          nodeId: identity.nodeId,
          nodeDh: identity.nodeDh,
          issuedAt: DateTime.now(),
        )).writeToBuffer(),
      );
      nodeIds.add(identity.nodeId);
      nodeDirs.add(nodeDir.path);
      identity.dispose();
      daemons.add(
        await NodeDaemon.start(
          NodeConfig.parse(nodeConfig(i), const {}, dataDir: nodeDir.path),
          crypto: crypto,
          handleSignals: false,
        ),
      );
    }
    client.close();
    for (final d in daemons) {
      await until(() => d!.link!.registered, 'узел зарегистрирован');
      await until(() => d!.reachability!.reachable, 'узел достижим');
      await until(
        () => live.server.channels.isConnected(d!.identity.nodeId),
        'канал команд узла',
      );
      await d!.link!.heartbeat();
    }
  });

  tearDown(() async {
    for (final d in daemons) {
      await d?.stop();
    }
    await db.close();
    await live.close();
    dir.deleteSync(recursive: true);
  });

  test(
    'узел, объявивший выход, уходит без снижения числа живых ниже 20',
    () async {
      final account = await AccountKeys.fromMasterKey(
        SecretBytes(crypto.randomBytes(32)),
        crypto,
      );
      final device = await DeviceKeys.generate(crypto);
      final certificate = await DeviceCertificates.issue(
        crypto,
        account,
        device,
        issuedAt: DateTime.now(),
      );
      final register = live.client();
      await register.registerAccount(
        pb.RegisterAccountRequest(
          deviceCertificate: certificate,
          login: 'alice',
        ),
        accountKey: account.accountSign,
      );
      register.close();
      final client = live.client(device: device);
      addTearDown(client.close);
      final local = LocalPeer(
        role: pb.PeerRole.PEER_ROLE_CLIENT,
        staticKey: device.dh,
        certificate: certificate,
        software: 'cli test',
      );

      ({NetworkFragmentStore store, CoordinatorSegments segments}) session() {
        final book = TicketBook();
        final store = NetworkFragmentStore(
          crypto: crypto,
          transport: ConnectionStrategy.forCoordinator(
            crypto: crypto,
            local: local,
            client: client,
            udp: false,
            relay: false,
          ),
          access: book,
          failureBackoff: Duration.zero,
        );
        addTearDown(store.close);
        return (
          store: store,
          segments: CoordinatorSegments(
            client: client,
            crypto: crypto,
            nodes: store,
            accountId: account.accountId,
            tickets: book,
            distinctSubnets: false,
          ),
        );
      }

      final source = Directory('${dir.path}/src')..createSync();
      final data = crypto.randomBytes(300 << 10);
      File('${source.path}/a.bin').writeAsBytesSync(data);
      final objects = CoordinatorObjectStore(client);
      final index = LocalIndex.inMemory();
      addTearDown(index.close);
      final first = session();
      final backup = await runBackup(
        crypto: crypto,
        keys: account,
        index: index,
        fragments: first.store,
        objects: objects,
        placer: first.segments,
        paths: [source.path],
        deviceId: device.deviceId,
        params: params,
      );
      expect(backup.segmentsStored, 1);

      Future<List<int>> holders() async => [
        for (final [id as List<int>] in await db.run(
          (s) => s.execute('SELECT node_id FROM fragments ORDER BY idx'),
        ))
          nodeIds.indexWhere((n) => constantTimeEquals(n, id)),
      ];
      Future<int> liveCount() async =>
          (await db.run((s) => s.execute('SELECT live FROM segments')))
                  .single
                  .single!
              as int;

      final original = await holders();
      expect(original, hasLength(20));
      expect(await liveCount(), 20);

      final x = original[6];
      Future<Map<String, Object?>> exit() async {
        final control = await NodeControlClient.connect(
          ControlEndpoint.forDataDir(nodeDirs[x]),
        );
        try {
          return await control.call('exit');
        } finally {
          await control.close();
        }
      }

      final declared = await exit();
      expect(declared['done'], isFalse);
      expect(declared['remainingFragments'], 1);

      final repair = live.server.repair!;
      expect(await repair.runOnce(), 1);
      final [kind as int, executorId as List<int>] = (await db.run(
        (s) => s.execute('SELECT kind, executor FROM repair_jobs'),
      )).single;
      expect(kind, 1, reason: 'перенос, не ремонт');
      expect(executorId, nodeIds[x]);
      await until(() async {
        final rows = await db.run(
          (s) => s.execute('SELECT state FROM repair_jobs'),
        );
        return (rows.single.single! as int) != RepairJobState.running.index;
      }, 'уходящий узел отчитался');
      expect(await liveCount(), 20, reason: 'фрагмент живой до проверки');
      await repair.runOnce();
      expect(await liveCount(), 20);
      final moved = await holders();
      expect(moved[6], isNot(x));
      expect(original, isNot(contains(moved[6])));
      expect(daemons[x]!.repairStats.relocationsDone, 1);

      final daemon = daemons[x]!;
      final left = await exit();
      expect(left['done'], isTrue);
      await daemon.done.timeout(const Duration(seconds: 30));
      daemons[x] = null;
      final frags = Directory('${nodeDirs[x]}/fragments');
      expect(
        frags.existsSync()
            ? frags.listSync(recursive: true).whereType<File>().toList()
            : const <File>[],
        isEmpty,
        reason: 'фрагменты удалены',
      );
      await expectLater(
        NodeDaemon.start(
          NodeConfig.parse(nodeConfig(x), const {}, dataDir: nodeDirs[x]),
          crypto: crypto,
          handleSignals: false,
        ),
        throwsA(isA<NodeIdentityException>()),
        reason: 'вышедший узел не запускается',
      );
      final [removed as DateTime?] = (await db.run(
        (s) => s.execute(
          Sql.named('SELECT removed_at FROM nodes WHERE node_id = @n:bytea'),
          parameters: {'n': nodeIds[x]},
        ),
      )).single;
      expect(removed, isNotNull);

      // Восстановление без уходящего узла: из исходных в сети — девять и
      // новый узел номера 6.
      for (final i in [0, 1, 2, 3, 4, 5, 7, 8, 9, 10]) {
        await daemons[original[i]]!.stop();
        daemons[original[i]] = null;
      }
      final other = LocalIndex.inMemory();
      addTearDown(other.close);
      await recoverIndex(
        crypto: crypto,
        manifestKey: account.manifestKey,
        store: objects,
        index: other,
      );
      final second = session();
      final target = Directory('${dir.path}/out');
      final result = await runRestore(
        crypto: crypto,
        keys: account,
        index: other,
        fragments: second.store,
        objects: objects,
        snapshotId: Uint8List.fromList(backup.snapshot.snapshotId),
        target: target,
        locator: second.segments,
      );
      expect(result.isComplete, isTrue, reason: '${result.errors}');
      expect(
        File('${target.path}${source.path}/a.bin').readAsBytesSync(),
        data,
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
