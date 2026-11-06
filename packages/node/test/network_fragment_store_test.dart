// Хранилище фрагментов поверх сети (задачи 3.9.2, 3.9.3): контракт
// FragmentStore из этапа 1 на NetworkFragmentStore с настоящими узлами
// (PeerService за PeerListener на loopback, стратегия подключения —
// прямой TCP); пул соединений, недоступные узлы, обрыв и переподключение;
// бэкап при недоступной части узлов и восстановление, когда узлы выходят
// в сеть позже. Талоны подписывает тестовый «координатор».

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:fixnum/fixnum.dart';
import 'package:node/node.dart';
import 'package:protocol/protocol.dart' as pb;
import 'package:test/test.dart';

import '../../core/test/support/fragment_store_contract.dart';

/// Узел-хранитель на loopback.
final class _Node {
  new(this.dir, this.local, this.nodeId);

  final Directory dir;
  final LocalPeer local;
  final Uint8List nodeId;
  FragmentStorage? storage;
  PeerService? service;
  PeerListener? listener;

  String get endpoint => '127.0.0.1:${listener!.port}';

  bool get running => listener != null;

  Future<void> start(CryptoProvider crypto, Uint8List coordinatorKey) async {
    final storage = this.storage = FragmentStorage.open(
      dir.path,
      crypto: crypto,
      quotaBytes: 1 << 30,
      diskAvailable: (_) => null,
    );
    final service = this.service = PeerService(
      crypto: crypto,
      local: local,
      nodeId: nodeId,
      storage: storage,
      trustedKeys: CoordinatorKeySet([coordinatorKey]),
    );
    listener = await PeerListener.bind('127.0.0.1', 0, service.serve);
  }

  Future<void> stop() async {
    await listener?.close();
    await service?.close();
    await storage?.close();
    listener = null;
    service = null;
    storage = null;
  }
}

/// Адреса — из [TicketBook], талоны подписывает «координатор» по запросу
/// (размеры фрагментов он помнит с PUT).
final class _Signer implements NodeAccess {
  new(this.crypto, this.key, this.deviceSign);

  final CryptoProvider crypto;
  final Ed25519KeyPair key;
  final Uint8List deviceSign;
  final book = TicketBook();
  final sizes = <String, int>{};
  bool issue = true;
  int issued = 0;

  @override
  List<Uint8List> get knownNodes => book.knownNodes;

  @override
  NodeContact? contact(Uint8List nodeId) => book.contact(nodeId);

  @override
  Future<pb.Signed?> ticket(
    pb.TicketOperation operation,
    Uint8List nodeId,
    Uint8List fragmentId, {
    int? fragmentSize,
  }) async {
    if (!issue) return null;
    final id = bytesToHex(fragmentId);
    if (fragmentSize != null) sizes[id] = fragmentSize;
    issued++;
    return await SignedMessages.sign(
      crypto,
      key,
      FragmentTickets.signingContext,
      pb.FragmentTicket(
        operation: operation,
        nodeId: nodeId,
        deviceSign: deviceSign,
        fragmentId: fragmentId,
        fragmentSize: sizes[id] ?? 1000,
        expiresAtUnixMs: Int64(
          DateTime.now()
              .add(const Duration(minutes: 10))
              .millisecondsSinceEpoch,
        ),
        ticketId: Uint8List(16)..buffer.asByteData().setUint32(0, issued),
      ),
    );
  }

  @override
  void consumed(
    pb.TicketOperation operation,
    Uint8List nodeId,
    Uint8List fragmentId,
  ) {}
}

/// Размещение по узлам хранилища, подтверждения записываются.
final class _Placer implements SegmentPlacer {
  new(this.store);

  final FragmentStore store;
  final commits = <List<int>>[];

  @override
  Future<List<FragmentTarget?>> allocate(SegmentAllocation segment) async {
    final nodes = placeFragments(segment.segmentId, store.nodes, segment.n);
    return [
      for (var i = 0; i < segment.n; i++)
        FragmentTarget(index: i, node: nodes[i]),
    ];
  }

  @override
  Future<void> commit(Uint8List segmentId, List<int> storedIndexes) async =>
      commits.add(storedIndexes);
}

void main() {
  late CryptoProvider crypto;
  late Ed25519KeyPair coordinator;
  late AccountKeys account;
  late DeviceKeys device;
  late LocalPeer client;
  late Directory root;
  late List<_Node> nodes;
  late _Signer access;
  late NetworkFragmentStore store;

  setUpAll(() async {
    crypto = await SodiumCryptoProvider.load();
    coordinator = await crypto.ed25519FromSeed(
      SecretBytes(crypto.randomBytes(32)),
    );
    account = await AccountKeys.fromMasterKey(
      SecretBytes(crypto.randomBytes(32)),
      crypto,
    );
    device = await DeviceKeys.generate(crypto);
    client = LocalPeer(
      role: pb.PeerRole.PEER_ROLE_CLIENT,
      staticKey: device.dh,
      certificate: await DeviceCertificates.issue(
        crypto,
        account,
        device,
        issuedAt: DateTime.now(),
      ),
      software: 'cli test',
    );
  });

  void publish(_Node node) => access.book.addNode(
    pb.NodeAddress(
      nodeId: node.nodeId,
      endpoints: [if (node.running) node.endpoint],
    ),
  );

  NetworkFragmentStore open({Duration failureBackoff = Duration.zero}) =>
      NetworkFragmentStore(
        crypto: crypto,
        transport: ConnectionStrategy(crypto: crypto, local: client),
        access: access,
        failureBackoff: failureBackoff,
        idleTimeout: const Duration(seconds: 1),
      );

  setUp(() async {
    root = Directory.systemTemp.createTempSync('fs-net-store-');
    nodes = [];
    for (var i = 0; i < 4; i++) {
      final keys = await DeviceKeys.generate(crypto);
      final owner = await AccountKeys.fromMasterKey(
        SecretBytes(crypto.randomBytes(32)),
        crypto,
      );
      final node = _Node(
        Directory('${root.path}/node-$i')..createSync(),
        LocalPeer(
          role: pb.PeerRole.PEER_ROLE_NODE,
          staticKey: keys.dh,
          certificate: await NodeCertificates.issue(
            crypto,
            owner,
            nodeId: keys.sign.publicKey,
            nodeDh: keys.dh.publicKey,
            issuedAt: DateTime.now(),
          ),
          software: 'node test',
        ),
        keys.sign.publicKey,
      );
      await node.start(crypto, coordinator.publicKey);
      nodes.add(node);
    }
    access = _Signer(crypto, coordinator, device.sign.publicKey);
    nodes.forEach(publish);
    store = open();
  });

  tearDown(() async {
    await store.close();
    for (final n in nodes) {
      await n.stop();
    }
    root.deleteSync(recursive: true);
  });

  group('контракт FragmentStore', () {
    fragmentStoreContract(() async => store, () => crypto);
  });

  test('сертификат узла — из рукопожатия', () async {
    final name = store.nameOf(nodes[1].nodeId);
    expect(await store.handshake(name), nodes[1].local.certificate);
    await nodes[2].stop();
    expect(await store.handshake(store.nameOf(nodes[2].nodeId)), isNull);
  });

  test('пул: одно соединение на узел, параллельные запросы по нему, '
      'простаивающее закрывается', () async {
    final node = store.nameOf(nodes[0].nodeId);
    final fragments = [
      for (var s = 1; s <= 3; s++) ...sampleFragments(crypto, seed: s),
    ];
    final ids = await Future.wait([
      for (final f in fragments) store.put(node, f.toBytes()),
    ]);
    expect(await store.has(node, ids), everyElement(isTrue));
    expect(store.connectionsOpened, 1);
    expect(store.openConnections, 1);
    await Future<void>.delayed(const Duration(milliseconds: 1800));
    expect(store.openConnections, 0, reason: 'простой дольше idleTimeout');
    expect(await store.get(node, ids.first), fragments.first.toBytes());
    expect(store.connectionsOpened, 2);
  });

  test('узел выключен — unavailable; пауза после неудачи', () async {
    await store.close();
    store = open(failureBackoff: const Duration(seconds: 30));
    final node = store.nameOf(nodes[3].nodeId);
    await nodes[3].stop();
    final fragment = sampleFragments(crypto).first.toBytes();
    final unavailable = throwsA(
      isA<StorageException>().having(
        (e) => e.problem,
        'problem',
        StorageProblem.unavailable,
      ),
    );
    await expectLater(store.put(node, fragment), unavailable);
    // Узел снова в сети, но пауза не вышла: попытки нет.
    await nodes[3].start(crypto, coordinator.publicKey);
    publish(nodes[3]);
    await expectLater(store.put(node, fragment), unavailable);
  });

  test('обрыв соединения — новое соединение и повтор операции', () async {
    final node = store.nameOf(nodes[0].nodeId);
    final fragment = sampleFragments(crypto).first;
    final id = await store.put(node, fragment.toBytes());
    // Узел перезапущен на другом порту: старое соединение оборвано.
    await nodes[0].stop();
    await nodes[0].start(crypto, coordinator.publicKey);
    publish(nodes[0]);
    expect(await store.get(node, id), fragment.toBytes());
    expect(store.connectionsOpened, 2);
  });

  test('нет талона — unavailable без подключения', () async {
    access.issue = false;
    await expectLater(
      store.get(store.nameOf(nodes[0].nodeId), Uint8List(32)),
      throwsA(
        isA<StorageException>().having(
          (e) => e.cause,
          'cause',
          contains('талона'),
        ),
      ),
    );
    expect(store.connectionsOpened, 0);
  });

  group('бэкап и восстановление по сети', () {
    late Directory data;
    late LocalIndex index;
    late LocalObjectStore objects;
    final params = DurabilityParameters(k: 2, n: 4, repairThreshold: 2);

    setUp(() {
      data = Directory('${root.path}/data')..createSync();
      File('${data.path}/a.bin').writeAsBytesSync(crypto.randomBytes(3 << 20));
      File('${data.path}/b.txt').writeAsStringSync('второй файл');
      index = LocalIndex.inMemory();
      objects = LocalObjectStore(Directory('${root.path}/objects'));
    });
    tearDown(() => index.close());

    Future<BackupResult> backup(_Placer placer) => runBackup(
      crypto: crypto,
      keys: account,
      index: index,
      fragments: store,
      objects: objects,
      placer: placer,
      paths: [data.path],
      deviceId: device.deviceId,
      params: params,
    );

    test('часть узлов недоступна — загрузка на остальные и подтверждение '
        'загруженных', () async {
      await nodes[2].stop();
      final placer = _Placer(store);
      final result = await backup(placer);
      expect(result.segmentsStored, greaterThan(0));
      final down = store.nameOf(nodes[2].nodeId);
      for (final (i, stored) in placer.commits.indexed) {
        expect(stored, hasLength(3), reason: 'сегмент $i');
      }
      for (final s in index.storedSegments()) {
        for (final f in index.fragments(s)) {
          if (f.node == down) fail('фрагмент на недоступном узле');
        }
      }
    });

    test('узлы выходят в сеть во время восстановления — оно завершается '
        'само', () async {
      final result = await backup(_Placer(store));
      // Три узла из четырёх выключены: k = 2 не набрать.
      for (final n in nodes.take(3)) {
        await n.stop();
        publish(n);
      }
      final target = Directory('${root.path}/out');
      final progress = <RestoreProgress>[];
      final pending = runRestore(
        crypto: crypto,
        keys: account,
        index: index,
        fragments: store,
        objects: objects,
        snapshotId: Uint8List.fromList(result.snapshot.snapshotId),
        target: target,
        wait: const RestoreWait(
          maxWait: Duration(minutes: 1),
          retryInterval: Duration(milliseconds: 300),
        ),
        onProgress: progress.add,
        progressInterval: const Duration(milliseconds: 50),
      );
      // Под нагрузкой восстановление может не успеть сообщить о повторе за
      // фиксированную секунду: ждём событие с nextRetry, но не дольше 10 с.
      for (var i = 0; i < 200; i++) {
        if (progress.isNotEmpty && progress.last.nextRetry != null) break;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(progress, isNotEmpty, reason: 'нет событий о восстановлении');
      expect(progress.last.nextRetry, isNotNull);
      for (final n in nodes.take(3)) {
        await n.start(crypto, coordinator.publicKey);
        publish(n);
      }
      final restored = await pending;
      expect(restored.isComplete, isTrue, reason: '${restored.errors}');
      expect(
        File('${target.path}${data.path}/a.bin').readAsBytesSync(),
        File('${data.path}/a.bin').readAsBytesSync(),
      );
      expect(
        File('${target.path}${data.path}/b.txt').readAsStringSync(),
        'второй файл',
      );
    });
  });
}
