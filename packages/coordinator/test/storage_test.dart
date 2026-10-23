// Клиентские хранилища поверх координатора (задача 2.8.2): объекты,
// размещение с проверкой клиентом, поиск фрагментов, сборка мусора.
// Фрагменты — в папках узлов-заглушек. Нужен FS_TEST_POSTGRES.

import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:node/node.dart';
import 'package:protocol/protocol.dart' as pb;
import 'package:test/test.dart';

import '../../core/test/support/object_store_contract.dart';
import 'support/live.dart';
import 'support/postgres.dart';

void main() {
  if (testPostgresUrl == null) {
    test('хранилища через координатор', () {}, skip: skipWithoutPostgres);
    return;
  }
  late LiveCoordinator live;
  late Directory dir;
  late CryptoProvider crypto;
  final params = DurabilityParameters(k: 2, n: 4, repairThreshold: 3);

  setUp(() async {
    live = await LiveCoordinator.start();
    crypto = live.crypto;
    dir = Directory.systemTemp.createTempSync('fs-storage-');
  });
  tearDown(() async {
    await live.close();
    dir.deleteSync(recursive: true);
  });

  /// Учётная запись с устройством на координаторе.
  Future<(AccountKeys, DeviceKeys)> register(String login) async {
    final keys = await AccountKeys.fromMasterKey(
      SecretBytes(crypto.randomBytes(32)),
      crypto,
    );
    final device = await DeviceKeys.generate(crypto);
    final client = live.client();
    await client.registerAccount(
      pb.RegisterAccountRequest(
        deviceCertificate: await DeviceCertificates.issue(
          crypto,
          keys,
          device,
          issuedAt: DateTime.now(),
        ),
        login: login,
      ),
      accountKey: keys.accountSign,
    );
    client.close();
    return (keys, device);
  }

  Future<void> stubNodes(int count) async {
    final client = live.client();
    await StubNodes(
      root: Directory('${dir.path}/nodes'),
      client: client,
      crypto: crypto,
    ).create(count);
    client.close();
  }

  group('контракт ObjectStore', () {
    late CoordinatorClient client;
    tearDown(() => client.close());
    objectStoreContract(() async {
      final (_, device) = await register('alice');
      client = live.client(device: device);
      return CoordinatorObjectStore(client, pageSize: 2);
    });
  });

  test('бэкап через координатор, восстановление на новом устройстве, '
      'сборка мусора', () async {
    await stubNodes(6);
    final (keys, device) = await register('alice');
    final client = live.client(device: device);
    addTearDown(client.close);
    final nodes = NodeFolders(Directory('${dir.path}/nodes'), crypto);
    expect(nodes.nodes, hasLength(6));
    final objects = CoordinatorObjectStore(client);
    final index = LocalIndex.inMemory();
    addTearDown(index.close);
    final segments = CoordinatorSegments(
      client: client,
      crypto: crypto,
      nodes: nodes,
      accountId: keys.accountId,
      fallbackReleaser: LocalSegmentReleaser(index, nodes),
    );

    final source = Directory('${dir.path}/src')..createSync();
    final data = crypto.randomBytes(300 * 1024);
    File('${source.path}/a.bin').writeAsBytesSync(data);
    final first = await runBackup(
      crypto: crypto,
      keys: keys,
      index: index,
      fragments: nodes,
      objects: objects,
      placer: segments,
      paths: [source.path],
      deviceId: device.deviceId,
      params: params,
    );
    expect(first.segmentsStored, greaterThan(0));
    expect(segments.rejectedPlacements, 0);

    // Новое устройство: индекс из объектов-индексов, узлы — LocateSegment.
    final other = LocalIndex.inMemory();
    addTearDown(other.close);
    await recoverIndex(
      crypto: crypto,
      manifestKey: keys.manifestKey,
      store: objects,
      index: other,
    );
    expect(
      other.fragments(other.storedSegments().first).first.node,
      isNull,
      reason: 'узлы фрагментов знает только координатор',
    );
    final target = Directory('${dir.path}/out');
    final restored = await runRestore(
      crypto: crypto,
      keys: keys,
      index: other,
      fragments: nodes,
      objects: objects,
      snapshotId: Uint8List.fromList(first.snapshot.snapshotId),
      target: target,
      locator: segments,
    );
    expect(restored.isComplete, isTrue);
    expect(File('${target.path}${source.path}/a.bin').readAsBytesSync(), data);
    final verify = await runVerify(
      crypto: crypto,
      keys: keys,
      index: other,
      fragments: nodes,
      locator: segments,
      params: params,
    );
    expect(verify.problems.map((p) => p.toString()), isEmpty);
    expect(verify.isHealthy, isTrue);

    // Новый снимок без a.bin, старый удалён — сегменты первого снимка
    // освобождаются.
    File('${source.path}/a.bin').deleteSync();
    File('${source.path}/b.txt').writeAsStringSync('привет');
    await runBackup(
      crypto: crypto,
      keys: keys,
      index: index,
      fragments: nodes,
      objects: objects,
      placer: segments,
      paths: [source.path],
      deviceId: device.deviceId,
      params: params,
    );
    await SnapshotCatalog(
      crypto: crypto,
      manifestKey: keys.manifestKey,
      store: objects,
      index: index,
    ).forget(Uint8List.fromList(first.snapshot.snapshotId));
    int stored() =>
        Directory('${dir.path}/nodes')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.frag'))
            .length;
    final before = stored();
    final report = await collectGarbage(
      crypto: crypto,
      keys: keys,
      index: index,
      fragments: nodes,
      objects: objects,
      releaser: segments,
      locator: segments,
    );
    expect(report.segmentsDeleted, greaterThan(0));
    expect(report.fragmentErrors, isEmpty);
    expect(stored(), before - report.fragmentsDeleted);
    expect(report.fragmentsDeleted, greaterThan(0));
  });

  test('подложное размещение отклоняется', () async {
    await stubNodes(4);
    final (keys, device) = await register('alice');
    final client = live.client(device: device);
    addTearDown(client.close);
    final real = NodeFolders(Directory('${dir.path}/nodes'), crypto);
    // Рукопожатие показывает, что все узлы — одного владельца: так
    // выглядел бы координатор, отдавший сегмент узлам одного человека.
    final owner = await AccountKeys.fromMasterKey(
      SecretBytes(Uint8List(32)..[0] = 9),
      crypto,
    );
    final segments = CoordinatorSegments(
      client: client,
      crypto: crypto,
      nodes: _SameOwner(real, crypto, owner),
      accountId: keys.accountId,
    );
    final index = LocalIndex.inMemory();
    addTearDown(index.close);
    final source = Directory('${dir.path}/src')..createSync();
    File('${source.path}/a').writeAsStringSync('данные');
    await expectLater(
      runBackup(
        crypto: crypto,
        keys: keys,
        index: index,
        fragments: real,
        objects: CoordinatorObjectStore(client),
        placer: segments,
        paths: [source.path],
        deviceId: device.deviceId,
        params: params,
      ),
      throwsA(
        isA<PlacementRejectedException>().having(
          (e) => e.reason,
          'reason',
          contains('владелец'),
        ),
      ),
    );
    expect(segments.rejectedPlacements, 2, reason: 'отказ и повторный запрос');
    expect(index.storedSegments(), isEmpty);
  });
}

/// Папки узлов, чьи сертификаты в «рукопожатии» выпущены одним
/// владельцем.
final class _SameOwner implements NodeDirectory {
  new(this.real, this.crypto, this.owner);

  final NodeFolders real;
  final CryptoProvider crypto;
  final AccountKeys owner;

  @override
  String nameOf(Uint8List nodeId) => real.nameOf(nodeId);

  @override
  Future<pb.Signed?> handshake(String node) async =>
      await NodeCertificates.issue(
        crypto,
        owner,
        nodeId: hexToBytes(node),
        nodeDh: Uint8List(32),
        issuedAt: DateTime.now(),
      );
}
