// Ремонт со всеми настоящими частями (задача 4.3.4; protocol.md,
// раздел 4.14): координатор и 26 демонов узлов на loopback. Клиент
// сохраняет сегмент 10 из 20, пять его узлов уходят из сети дольше 72
// часов, координатор поручает ремонт демону-исполнителю по каналу команд,
// тот скачивает k фрагментов, пересоздаёт пять недостающих и рассылает их
// новым узлам — без участия клиента; координатор засчитывает их после
// аудита на новых узлах (4.3.5). После ремонта сегмент восстанавливается
// новым устройством, когда из исходных узлов в сети только пять. Нужен
// FS_TEST_POSTGRES.

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
    test('ремонт по сети', () {}, skip: skipWithoutPostgres);
    return;
  }

  const nodeCount = 26;
  // k = 10, n = 20, t = 16 (durability.md).
  final params = DurabilityParameters();
  late CryptoProvider crypto;
  late LiveCoordinator live;
  late Directory dir;
  late Ed25519KeyPair signerKey;
  late Database db;
  final daemons = <NodeDaemon?>[];
  final nodeIds = <Uint8List>[];

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
    dir = Directory.systemTemp.createTempSync('fs-repair-');
    daemons.clear();
    nodeIds.clear();
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

  test('сегмент, потерявший 5 фрагментов, возвращается к 20 живым без '
      'клиента', () async {
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
      pb.RegisterAccountRequest(deviceCertificate: certificate, login: 'alice'),
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

    // Пять узлов уходят: остановлены и молчат дольше 72 часов.
    final gone = [
      for (final i in [0, 3, 7, 11, 19]) original[i],
    ];
    for (final i in gone) {
      await daemons[i]!.stop();
      daemons[i] = null;
    }
    await db.run(
      (s) => s.execute(
        Sql.named('''
          UPDATE nodes SET last_heartbeat_at = @t:timestamptz
            WHERE node_id = ANY(@ids:_bytea)'''),
        parameters: {
          't': DateTime.now().subtract(const Duration(hours: 73)),
          'ids': [for (final i in gone) nodeIds[i]],
        },
      ),
    );
    final repair = live.server.repair!;
    expect(await repair.markLost(), 5);
    expect(await liveCount(), 15);

    expect(await repair.runOnce(), 1);
    final [executorId as List<int>] = (await db.run(
      (s) => s.execute('SELECT executor FROM repair_jobs'),
    )).single;
    final executor = nodeIds.indexWhere(
      (n) => constantTimeEquals(n, executorId),
    );
    expect(original, isNot(contains(executor)));
    await until(() async {
      final rows = await db.run(
        (s) => s.execute('SELECT state FROM repair_jobs'),
      );
      return (rows.single.single! as int) != RepairJobState.running.index;
    }, 'исполнитель отчитался');
    await repair.runOnce();
    expect(await liveCount(), 20);
    final [state as int, down as int, up as int] = (await db.run(
      (s) => s.execute(
        'SELECT state, bytes_downloaded, bytes_uploaded FROM repair_jobs',
      ),
    )).single;
    expect(state, RepairJobState.done.index);
    expect(down, greaterThan(0));
    expect(up, greaterThan(0));
    final stats = daemons[executor]!.repairStats;
    expect(stats.jobsCompleted, 1);
    expect(stats.fragmentsRebuilt, 5);
    expect(stats.bytesDownloaded, down);
    expect(stats.bytesUploaded, up);

    final repaired = await holders();
    final fresh = [
      for (final i in [0, 3, 7, 11, 19]) repaired[i],
    ];
    expect(fresh.toSet().intersection(original.toSet()), isEmpty);
    expect(fresh, isNot(contains(executor)));

    // Из исходных узлов в сети остаются пять: восстановление по новым.
    for (final i in [1, 2, 4, 5, 6, 8, 9, 10, 12, 13]) {
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
    expect(File('${target.path}${source.path}/a.bin').readAsBytesSync(), data);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
