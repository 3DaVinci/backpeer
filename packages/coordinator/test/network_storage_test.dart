// Сеть на стороне клиента (группа 3.9) со всеми настоящими частями:
// координатор, relay и пять демонов узлов на loopback. Четыре узла
// доступны напрямую по TCP, пятый слушает 127.0.0.2 — проверка
// достижимости до него не доходит, адресов у него нет, и клиент
// подключается к нему после сведения по UDP или через relay. Бэкап с
// размещением и талонами координатора, восстановление на новом
// устройстве по LocateSegment, только через relay, восстановление с
// ожиданием перезапущенных узлов, сборка мусора по талонам DELETE.
// Нужен FS_TEST_POSTGRES.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cli/cli.dart';
import 'package:coordinator/coordinator.dart';
import 'package:core/core.dart' hide ConfigException;
import 'package:node/node.dart';
import 'package:protocol/protocol.dart' as pb;
import 'package:relay/relay.dart';
import 'package:test/test.dart';

import 'support/live.dart';
import 'support/postgres.dart';

const pb.ConnectionMethod _direct =
    pb.ConnectionMethod.CONNECTION_METHOD_DIRECT;
const pb.ConnectionMethod _udp = pb.ConnectionMethod.CONNECTION_METHOD_UDP;
const pb.ConnectionMethod _relay = pb.ConnectionMethod.CONNECTION_METHOD_RELAY;

/// Консоль CLI для тестов: отвечает на вопросы функцией, копит вывод.
final class _Console implements Console {
  new([this.answer]);

  final String? Function(String prompt, List<String> out)? answer;
  final List<String> lines = [];

  @override
  void out(String line) => lines.add(line);

  @override
  void err(String line) => lines.add(line);

  @override
  String? ask(String prompt) => answer?.call(prompt, lines);

  @override
  String? askSecret(String prompt) => answer?.call(prompt, lines);

  @override
  void progress(String line) {}
}

void main() {
  if (testPostgresUrl == null) {
    test('сеть на стороне клиента', () {}, skip: skipWithoutPostgres);
    return;
  }

  late CryptoProvider crypto;
  late RelayServer relay;
  late LiveCoordinator live;
  late Directory dir;
  late Ed25519KeyPair signerKey;
  final daemons = <NodeDaemon?>[];
  final nodeIds = <Uint8List>[];
  // Пятый узел недоступен напрямую: адресов у координатора нет.
  const hidden = 4;
  final params = DurabilityParameters(k: 3, n: 5, repairThreshold: 3);

  String nodeConfig(int i) =>
      '''
storage:
  quota_bytes: 200000000000
  free_reserve_bytes: 0
listen:
  host: ${i == hidden ? '127.0.0.2' : '127.0.0.1'}
  port: 0
  port_mapping: off
coordinator:
  url: ${live.url}
  keys: [${bytesToHex(signerKey.publicKey)}]
log:
  file: "-"
  level: warning
''';

  Future<NodeDaemon> startNode(int i) => NodeDaemon.start(
    NodeConfig.parse(nodeConfig(i), const {}, dataDir: '${dir.path}/node-$i'),
    crypto: crypto,
    handleSignals: false,
  );

  Future<void> until(bool Function() ready, String what) async {
    for (var i = 0; i < 300 && !ready(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(ready(), isTrue, reason: what);
  }

  /// Узел зарегистрирован, адреса проверены и сообщены координатору.
  Future<void> ready(int i) async {
    final d = daemons[i]!;
    await until(() => d.link!.registered, 'узел $i зарегистрирован');
    if (i == hidden) {
      await until(() => relay.isListening(nodeIds[i]), 'узел $i на relay');
    } else {
      await until(() => d.reachability!.reachable, 'узел $i достижим');
    }
    bool connected() {
      final link = d.status()['coordinator']! as Map<String, Object?>;
      return (link['channel']! as Map<String, Object?>)['connected'] == true;
    }

    await until(connected, 'канал команд узла $i');
    await d.link!.heartbeat();
  }

  setUp(() async {
    crypto = await SodiumCryptoProvider.load();
    final passKey = await crypto.ed25519FromSeed(
      SecretBytes(crypto.randomBytes(32)),
    );
    relay = await RelayServer.bind(
      crypto: crypto,
      name: 'r1',
      passKeys: CoordinatorKeySet([passKey.publicKey]),
      host: '127.0.0.1',
    );
    live = await LiveCoordinator.start(
      relay: RelayPolicy(
        servers: [
          RelayServerInfo(
            name: 'r1',
            endpoint: '127.0.0.1:${relay.port}',
            publicKey: (await crypto.ed25519FromSeed(
              SecretBytes(crypto.randomBytes(32)),
            )).publicKey,
          ),
        ],
        passKeyFile: '-',
      ),
      relayPassKey: passKey,
    );
    signerKey = await crypto.ed25519FromSeed(
      SecretBytes(Uint8List(32)..fillRange(0, 32, 0xC0)),
    );
    dir = Directory.systemTemp.createTempSync('fs-network-');
    daemons.clear();
    nodeIds.clear();
    for (var i = 0; i < 5; i++) {
      // У каждого узла свой владелец: клиент проверяет, что владельцы
      // фрагментов сегмента различны.
      final owner = await AccountKeys.fromMasterKey(
        SecretBytes(crypto.randomBytes(32)),
        crypto,
      );
      final ownerDevice = await DeviceKeys.generate(crypto);
      final client = live.client();
      await client.registerAccount(
        pb.RegisterAccountRequest(
          deviceCertificate: await DeviceCertificates.issue(
            crypto,
            owner,
            ownerDevice,
            issuedAt: DateTime.now(),
          ),
          login: 'keeper$i',
        ),
        accountKey: owner.accountSign,
      );
      client.close();
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
      daemons.add(await startNode(i));
    }
    for (var i = 0; i < 5; i++) {
      await ready(i);
    }
  });

  tearDown(() async {
    for (final d in daemons) {
      await d?.stop();
    }
    await live.close();
    await relay.close();
    dir.deleteSync(recursive: true);
  });

  test('бэкап и восстановление по сети: TCP, UDP или relay, '
      'ожидание узлов, сборка мусора', () async {
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

    /// Хранилища одной «сессии» клиента.
    ({
      NetworkFragmentStore store,
      CoordinatorSegments segments,
      TrafficMeter meter,
    })
    session(LocalIndex index, {bool udp = true}) {
      final meter = TrafficMeter();
      final book = TicketBook();
      final store = NetworkFragmentStore(
        crypto: crypto,
        transport: ConnectionStrategy.forCoordinator(
          crypto: crypto,
          local: local,
          client: client,
          meter: meter,
          udp: udp,
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
          // Все узлы на loopback, как placement.distinct_subnets: false.
          distinctSubnets: false,
        ),
        meter: meter,
      );
    }

    final source = Directory('${dir.path}/src')..createSync();
    // Больше сегмента (16 МиБ): после удаления файла хотя бы один сегмент
    // никому не нужен.
    final data = crypto.randomBytes(20 << 20);
    File('${source.path}/a.bin').writeAsBytesSync(data);
    File('${source.path}/b.txt').writeAsStringSync('второй');
    final objects = CoordinatorObjectStore(client);
    final index = LocalIndex.inMemory();
    addTearDown(index.close);
    final first = session(index);
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
    expect(backup.segmentsStored, greaterThan(0));
    expect(first.segments.rejectedPlacements, 0);
    final traffic = first.meter.toJson();
    expect(traffic['direct'], greaterThan(0), reason: '$traffic');
    expect(
      (traffic['udp'] ?? 0) + (traffic['relay'] ?? 0),
      greaterThan(0),
      reason: 'узел без адресов — через UDP или relay: $traffic',
    );
    final strategy = first.store.transport as ConnectionStrategy;
    expect(strategy.cachedMethod(nodeIds[0]), _direct);
    expect(strategy.cachedMethod(nodeIds[hidden]), anyOf(_udp, _relay));
    // Отчёт о трафике по способам принимает координатор.
    await TrafficReporter(client: client, meter: first.meter).report();

    /// Восстановление на новом устройстве: индекс из объектов-индексов,
    /// узлы и талоны GET — LocateSegment.
    Future<(RestoreResult, TrafficMeter)> restore(
      String name, {
      bool udp = true,
      RestoreWait wait = RestoreWait.none,
      FutureOr<void> Function()? whileWaiting,
    }) async {
      final other = LocalIndex.inMemory();
      addTearDown(other.close);
      await recoverIndex(
        crypto: crypto,
        manifestKey: account.manifestKey,
        store: objects,
        index: other,
      );
      final s = session(other, udp: udp);
      final target = Directory('${dir.path}/$name');
      var waited = false;
      final result = await runRestore(
        crypto: crypto,
        keys: account,
        index: other,
        fragments: s.store,
        objects: objects,
        snapshotId: Uint8List.fromList(backup.snapshot.snapshotId),
        target: target,
        locator: s.segments,
        wait: wait,
        progressInterval: const Duration(milliseconds: 100),
        onProgress: (p) {
          if (p.nextRetry == null || waited || whileWaiting == null) return;
          waited = true;
          unawaited(Future.sync(whileWaiting));
        },
      );
      expect(result.isComplete, isTrue, reason: '${result.errors}');
      expect(
        File('${target.path}${source.path}/a.bin').readAsBytesSync(),
        data,
      );
      if (whileWaiting != null) expect(waited, isTrue);
      return (result, s.meter);
    }

    await restore('out');

    // Без UDP узел без адресов доступен только через relay.
    final relayOnly = session(index, udp: false);
    final hiddenName = relayOnly.store.nameOf(nodeIds[hidden]);
    final segment = index.storedSegments().first;
    final onHidden = index
        .fragments(segment)
        .firstWhere((f) => f.node == hiddenName);
    await relayOnly.segments.locate(segment);
    final fragment = Fragment.parse(
      await relayOnly.store.get(hiddenName, onHidden.fragmentId),
    )..verify(crypto, expectedFragmentId: onHidden.fragmentId);
    expect(fragment.header.index, onHidden.number);
    final viaRelay = relayOnly.meter.toJson();
    expect(viaRelay.keys, ['relay'], reason: '$viaRelay');
    expect(viaRelay['relay'], greaterThan(fragment.bytes.length));

    // Три узла из пяти выключены (k = 3): восстановление ждёт, пока они
    // не вернутся на новых портах.
    for (final i in [0, 1, 2]) {
      await daemons[i]!.stop();
      daemons[i] = null;
    }
    await restore(
      'out-wait',
      wait: const RestoreWait(
        maxWait: Duration(minutes: 2),
        retryInterval: Duration(milliseconds: 500),
      ),
      whileWaiting: () async {
        for (final i in [0, 1, 2]) {
          daemons[i] = await startNode(i);
          await ready(i);
        }
      },
    );

    // Сборка мусора: талоны DELETE от координатора, удаление по сети.
    File('${source.path}/a.bin').deleteSync();
    final second = session(index);
    await runBackup(
      crypto: crypto,
      keys: account,
      index: index,
      fragments: second.store,
      objects: objects,
      placer: second.segments,
      paths: [source.path],
      deviceId: device.deviceId,
      params: params,
    );
    await SnapshotCatalog(
      crypto: crypto,
      manifestKey: account.manifestKey,
      store: objects,
      index: index,
    ).forget(Uint8List.fromList(backup.snapshot.snapshotId));
    final stored = [for (final d in daemons) d!.status()['fragments']! as int]
        .fold(0, (a, b) => a + b);
    final report = await collectGarbage(
      crypto: crypto,
      keys: account,
      index: index,
      fragments: second.store,
      objects: objects,
      releaser: second.segments,
      locator: second.segments,
    );
    expect(report.segmentsDeleted, greaterThan(0));
    expect(report.fragmentErrors, isEmpty);
    expect(report.fragmentsDeleted, greaterThan(0));
    final left = [for (final d in daemons) d!.status()['fragments']! as int]
        .fold(0, (a, b) => a + b);
    expect(left, stored - report.fragmentsDeleted);
  });

  test('CLI: фрагменты по сети, восстановление с ожиданием', () async {
    final environment = {
      'FS_HOME': '${dir.path}/cli',
      'FS_PASSWORD': 'correct horse battery staple',
      'FS_ARGON2_FAST': '1',
    };
    Future<(int, Map<String, Object?>, List<String>)> cli(
      List<String> args, {
      String? Function(String, List<String>)? answer,
    }) async {
      final console = _Console(answer);
      final code = await runCli(
        ['--json', ...args],
        console: console,
        environment: environment,
      );
      final last = console.lines.isEmpty
          ? const <String, Object?>{}
          : jsonDecode(console.lines.last) as Map<String, Object?>;
      return (code, last, console.lines);
    }

    /// Ответы на проверку слов фразы — из события `phrase`.
    String? words(String prompt, List<String> out) {
      final m = RegExp(r'Слово №(\d+)').firstMatch(prompt);
      if (m == null) return null;
      final phrase = out
          .map((l) => jsonDecode(l) as Map<String, Object?>)
          .firstWhere((e) => e['type'] == 'phrase');
      return (phrase['words']! as List<Object?>)[int.parse(m[1]!) - 1]!
          as String;
    }

    var (code, result, lines) = await cli([
      'register',
      '--coordinator',
      live.url,
      '--login',
      'bob',
      '--k',
      '3',
      '--n',
      '5',
      '--repair-threshold',
      '3',
    ], answer: words);
    expect(code, ExitCode.ok, reason: lines.join('\n'));
    (code, result, lines) = await cli([
      'config',
      '--fragments',
      'network',
      '--subnet-check',
      'off',
    ]);
    expect(code, ExitCode.ok, reason: lines.join('\n'));
    expect(result['fragments'], 'network');
    expect(result['distinctSubnets'], isFalse);

    final source = Directory('${dir.path}/cli-src')..createSync();
    final data = crypto.randomBytes(3 << 20);
    File('${source.path}/doc.bin').writeAsBytesSync(data);
    (code, result, lines) = await cli(['backup', source.path]);
    expect(code, ExitCode.ok, reason: lines.join('\n'));
    final snapshot = result['snapshotId']! as String;
    final stored = [for (final d in daemons) d!.status()['fragments']! as int];
    expect(stored, everyElement(greaterThan(0)), reason: 'n = 5 узлов');

    // Два узла из пяти выключены, третий вернётся во время ожидания.
    for (final i in [0, 1, 2]) {
      await daemons[i]!.stop();
      daemons[i] = null;
    }
    unawaited(
      Future<void>.delayed(const Duration(seconds: 2), () async {
        daemons[2] = await startNode(2);
        await ready(2);
      }),
    );
    final target = '${dir.path}/cli-out';
    (code, result, lines) = await cli([
      'restore',
      snapshot.substring(0, 8),
      '--to',
      target,
      '--wait',
      '2',
    ]);
    expect(code, ExitCode.ok, reason: lines.join('\n'));
    expect(File('$target${source.path}/doc.bin').readAsBytesSync(), data);
    for (final i in [0, 1]) {
      daemons[i] = await startNode(i);
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
