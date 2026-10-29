import 'dart:io';
import 'dart:typed_data';

import 'package:agent/agent.dart';
import 'package:cli/cli.dart';
import 'package:core/core.dart';
import 'package:daemon_kit/daemon_kit.dart'
    show ControlClient, ControlEndpoint, ControlException;
import 'package:node/node.dart' show NodeConfig, NodeDaemon;
import 'package:test/test.dart';

import 'support/live.dart';
import 'support/postgres.dart';

/// Демон `node` в том же процессе: настройки — `node.yaml`, который
/// написал агент, плюс окружение теста (порт, журнал).
final class _InProcessLauncher implements NodeLauncher {
  new(this.crypto);

  final CryptoProvider crypto;
  NodeDaemon? daemon;
  int starts = 0;

  @override
  String? get executable => 'in-process';

  @override
  String get kind => 'in-process';

  @override
  Future<void> disable() async {}

  @override
  Future<bool> start(String dataDir) async {
    final yaml = File('$dataDir/node.yaml').readAsStringSync();
    daemon = await NodeDaemon.start(
      NodeConfig.parse(yaml, const {
        'FS_NODE_LISTEN_HOST': '127.0.0.1',
        'FS_NODE_LISTEN_PORT': '0',
        'FS_NODE_LISTEN_PORT_MAPPING': 'off',
        'FS_NODE_STORAGE_FREE_RESERVE_BYTES': '0',
        'FS_NODE_LOG_FILE': '-',
        'FS_NODE_LOG_LEVEL': 'warning',
      }, dataDir: dataDir),
      crypto: crypto,
      handleSignals: false,
    );
    starts++;
    return true;
  }
}

/// Включение роли хранителя из приложения через агента на настоящем
/// координаторе (задачи 5.5.1, 5.5.2): сертификат ключом учётной записи,
/// регистрация узла, сведения координатора в heartbeat, смена квоты,
/// выключение.
void main() {
  if (testPostgresUrl == null) {
    test('роль хранителя через агента', () {}, skip: skipWithoutPostgres);
    return;
  }

  late CryptoProvider crypto;
  late LiveCoordinator live;
  late Directory dir;
  late BackupAgent agent;
  late ControlClient client;
  late _InProcessLauncher launcher;

  setUpAll(() async => crypto = await SodiumCryptoProvider.load());
  setUp(() async {
    live = await LiveCoordinator.start();
    dir = Directory.systemTemp.createTempSync('fs-agent-keeper-');
    launcher = _InProcessLauncher(crypto);
    final home = AppHome(Directory('${dir.path}/home'));
    agent = await BackupAgent.start(
      home: home,
      notifier: const NoNotifier(),
      crypto: crypto,
      secrets: MemorySecretStore(),
      argon2: const Argon2Params(memoryKiB: 1024, iterations: 1),
      handleSignals: false,
      nodeDataDir: '${dir.path}/node',
      nodeLauncher: launcher,
    );
    client = await ControlClient.connect(AgentPaths(home).endpoint());
  });
  tearDown(() async {
    await client.close();
    await agent.stop();
    await launcher.daemon?.stop();
    await live.close();
    dir.deleteSync(recursive: true);
  });

  const long = Duration(minutes: 1);

  Future<void> until(Future<bool> Function() ready, String what) async {
    for (var i = 0; i < 300; i++) {
      if (await ready()) return;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    fail('не дождались: $what');
  }

  test('включение регистрирует узел; квота меняется; выключение', () async {
    final words =
        ((await client.call('account.new_phrase'))['words']! as List<Object?>)
            .cast<String>();
    final created = await client.call('account.create', {
      'coordinator': live.url,
      'fragments': 'folders',
      'nodes': '${dir.path}/nodes',
      'login': 'keeper',
      'password': 'correct horse battery staple',
      'confirm': {'1': words[0], '2': words[1], '3': words[2]},
    }, long);
    final accountId = created['accountId']! as String;

    final signer = await crypto.ed25519FromSeed(
      SecretBytes(Uint8List(32)..fillRange(0, 32, 0xC0)),
    );
    final storageDir = '${dir.path}/disk2/fragments';
    final enabled = await client.call('keeper.enable', {
      'storageDir': storageDir,
      'quotaBytes': 2 << 30,
      'uploadBytesPerSecond': 1000000,
      'schedule': ['mon-fri 09:00-18:00 upload=500000'],
      'coordinatorKeys': [bytesToHex(signer.publicKey)],
    }, long);
    expect(enabled['started'], isTrue);
    expect(enabled['certificateIssued'], isTrue);
    expect(enabled['restarted'], isFalse);

    final daemon = launcher.daemon!;
    await until(() async => daemon.link!.registered, 'узел зарегистрирован');
    await daemon.link!.heartbeat();
    final node = await ControlClient.connect(
      ControlEndpoint.forDataDir('${dir.path}/node'),
    );
    var status = await node.call('status');
    await node.close();
    expect(status['owner'], accountId);
    expect(status['nodeId'], enabled['nodeId']);
    expect(status['storageDir'], storageDir);
    expect(status['quotaBytes'], 2 << 30);
    expect((status['limits']! as Map)['uploadBytesPerSecond'], 1000000);
    expect(Directory('$storageDir/fragments').existsSync(), isTrue);
    final standing =
        (status['coordinator']! as Map<String, Object?>)['standing']!
            as Map<String, Object?>;
    expect(standing['availability'], greaterThan(0));
    expect(standing['reputation'], inInclusiveRange(0, 1));
    expect(standing['onProbation'], isFalse);
    expect(standing['excluded'], isFalse);
    expect(standing['auditsFailed'], 0);

    final info = await client.call('keeper.info');
    expect(info['enabled'], isTrue);
    expect(info['hasCertificate'], isTrue);

    // Новая квота: тот же узел и сертификат, демон перезапущен.
    final changed = await client.call('keeper.enable', {
      'storageDir': storageDir,
      'quotaBytes': 3 << 30,
    }, long);
    expect(changed['restarted'], isTrue);
    expect(changed['certificateIssued'], isFalse);
    expect(changed['nodeId'], enabled['nodeId']);
    expect(launcher.starts, 2);
    final again = launcher.daemon!;
    await until(() async => again.link!.registered, 'узел снова на связи');
    final node2 = await ControlClient.connect(
      ControlEndpoint.forDataDir('${dir.path}/node'),
    );
    status = await node2.call('status');
    await node2.close();
    expect(status['quotaBytes'], 3 << 30);
    // Ключи координатора стенда сохранились из прежних настроек.
    expect(
      File('${dir.path}/node/node.yaml').readAsStringSync(),
      contains(bytesToHex(signer.publicKey)),
    );

    final disabled = await client.call('keeper.disable', const {}, long);
    expect(disabled['stopped'], isTrue);
    await expectLater(
      ControlClient.connect(ControlEndpoint.forDataDir('${dir.path}/node')),
      throwsA(isA<ControlException>()),
    );
    expect((await client.call('keeper.info'))['enabled'], isFalse);
    // Фрагменты и ключи узла остаются.
    expect(File('${dir.path}/node/node.key').existsSync(), isTrue);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
