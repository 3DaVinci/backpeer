// Задачи 5.6.1, 5.6.3, 5.6.4, 5.7.3 на агенте в одном процессе: сон посреди
// бэкапа с задержкой сна и продолжение после пробуждения, повтор неудачного
// бэкапа при появлении сети, хранитель службой ОС с linger, удаление клиента.

import 'dart:async';
import 'dart:io';

import 'package:agent/agent.dart';
import 'package:cli/cli.dart';
import 'package:core/core.dart';
import 'package:daemon_kit/daemon_kit.dart';
import 'package:test/test.dart';

import 'support.dart';

/// Службы ОС в памяти: что поставлено и запущено.
final class MemoryServices implements UserServices {
  final installed = <String, ServiceSpec>{};
  final running = <String>{};

  @override
  String get kind => 'memory';

  @override
  bool get available => true;

  @override
  String serviceName(String name) => 'test-$name';

  @override
  Future<ServiceState> state(String name) async => !installed.containsKey(name)
      ? ServiceState.notInstalled
      : running.contains(name)
      ? ServiceState.running
      : ServiceState.stopped;

  @override
  Future<void> install(ServiceSpec spec, {bool start = true}) async {
    installed[spec.name] = spec;
    if (start) running.add(spec.name);
  }

  @override
  Future<void> uninstall(String name) async {
    installed.remove(name);
    running.remove(name);
  }

  @override
  Future<void> start(String name) async => running.add(name);

  @override
  Future<void> stop(String name) async => running.remove(name);
}

void main() {
  late CryptoProvider crypto;
  late Directory dir;
  late AppHome home;
  late FakeSystemEvents events;
  final agents = <BackupAgent>[];
  final clients = <ControlClient>[];

  setUpAll(() async => crypto = await SodiumCryptoProvider.load());
  setUp(() async {
    dir = Directory.systemTemp.createTempSync('fs-agent-bg-');
    home = AppHome(Directory('${dir.path}/home'));
    events = FakeSystemEvents();
    await initHome(home.dir.path);
  });
  tearDown(() async {
    for (final c in clients) {
      await c.close();
    }
    clients.clear();
    for (final a in agents) {
      await a.stop();
    }
    agents.clear();
    dir.deleteSync(recursive: true);
  });

  Future<ControlClient> start({NodeLauncher? launcher, Linger? linger}) async {
    agents.add(
      await BackupAgent.start(
        home: home,
        crypto: crypto,
        secrets: MemorySecretStore(),
        argon2: const Argon2Params(memoryKiB: 1024, iterations: 1),
        handleSignals: false,
        power: FakePowerSource(),
        notifier: MemoryNotifier(),
        systemEvents: events,
        wakeDelay: const Duration(milliseconds: 200),
        nodeLauncher: launcher,
        nodeDataDir: '${dir.path}/node',
        linger: linger,
      ),
    );
    final client = await ControlClient.connect(AgentPaths(home).endpoint());
    clients.add(client);
    await client.subscribe();
    await client.call('unlock', {
      'password': testPassword,
    }, const Duration(minutes: 1));
    return client;
  }

  Future<Map<String, Object?>> finished(ControlClient client) => client.events
      .firstWhere((e) => e.name == 'job_finished' && e.data['kind'] == 'backup')
      .then((e) => e.data)
      .timeout(const Duration(minutes: 2));

  test('сон посреди бэкапа: остановка с продолжением, задержка сна '
      'снята; после пробуждения бэкап продолжается', () async {
    final data = Directory('${dir.path}/big')..createSync();
    for (var i = 0; i < 4; i++) {
      File('${data.path}/f$i.bin')
          .writeAsBytesSync(crypto.randomBytes(12 << 20));
    }
    final client = await start();
    final progressed = client.events.firstWhere(
      (e) => e.name == 'progress' && (e.data['segmentsStored']! as int) >= 1,
    );
    final stopped = finished(client);
    await client.call('settings', {
      'paths': [data.path],
    });
    await progressed.timeout(const Duration(minutes: 2));
    expect(events.inhibits, 1, reason: 'бэкап задерживает сон');

    events.emit(SystemEvent.sleep);
    final record = await stopped;
    expect(record['outcome'], 'cancelled');
    expect(record['result'], containsPair('reason', 'sleep'));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(events.released, 1, reason: 'задержка сна снята');
    // Во сне не продолжает, хотя бэкап не закончен.
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(agents.single.job, isNull);
    expect((await client.call('status'))['interrupted'], isTrue);

    final resumed = finished(client);
    events.emit(SystemEvent.wake);
    final done = await resumed;
    expect(done['outcome'], 'ok');
    expect(done['trigger'], 'resume');
    final result = done['result']! as Map<String, Object?>;
    expect(result['newBytes']! as int, lessThan(48 << 20));
    expect(events.released, events.inhibits);
  }, timeout: const Timeout(Duration(minutes: 4)));

  test('появилась сеть — неудачный бэкап повторяется, не дожидаясь '
      'retryMinutes', () async {
    final data = sampleData('${dir.path}/data');
    // «Сеть» недоступна: на месте папки «узлов» — файл.
    final nodes = Directory(AppConfig.load(home).nodes);
    if (nodes.existsSync()) nodes.renameSync('${nodes.path}.away');
    final blocker = File(nodes.path)..writeAsStringSync('');
    final client = await start();
    final failed = finished(client);
    await client.call('settings', {
      'paths': [data.path],
      'retryMinutes': 30,
    });
    expect((await failed)['outcome'], 'failed');
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(agents.single.job, isNull, reason: 'повтор — через 30 минут');

    blocker.deleteSync();
    if (Directory('${nodes.path}.away').existsSync()) {
      Directory('${nodes.path}.away').renameSync(nodes.path);
    }
    final retried = finished(client);
    events.emit(SystemEvent.networkUp);
    final done = await retried;
    expect(done['outcome'], 'ok');
    expect(done['trigger'], 'schedule');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('хранитель службой ОС: служба и linger при включении роли, '
      'удаление при выключении', () async {
    final services = MemoryServices();
    final lingerDir = Directory('${dir.path}/linger')..createSync();
    final loginctl = <String>[];
    final linger = Linger(
      user: 'tester',
      lingerDir: lingerDir.path,
      runner: (exe, args) async {
        loginctl.add('$exe ${args.join(' ')}');
        final file = File('${lingerDir.path}/tester');
        args.first == 'enable-linger' ? file.createSync() : file.deleteSync();
        return ProcessResult(0, 0, '', '');
      },
    );
    final nodeExe = File('${dir.path}/bin/node')..createSync(recursive: true);
    final client = await start(
      launcher: ServiceNodeLauncher(
        services: services,
        executable: nodeExe.path,
      ),
      linger: linger,
    );
    final info = await client.call('keeper.info');
    expect(info['launcher'], 'memory');
    expect(info['linger'], {
      'enabled': false,
      'command': 'sudo loginctl enable-linger tester',
    });

    // Без координатора роль не включается; координатор для теста —
    // любой адрес: демон «запускает» служба в памяти.
    AppConfig.load(home)
      ..coordinator = 'https://127.0.0.1:9'
      ..save(home);
    final enabled = await client.call('keeper.enable', {
      'quotaBytes': 1 << 30,
    }, const Duration(minutes: 1));
    expect(enabled['launcher'], 'memory');
    expect(enabled['linger'], {'enabled': true});
    expect(loginctl, ['loginctl enable-linger tester']);
    final spec = services.installed['node']!;
    expect(spec.executable, nodeExe.path);
    expect(spec.arguments, ['run', '--data', '${dir.path}/node']);
    expect(KeeperSettings.load(AgentPaths(home).keeper)!.lingerByAgent, isTrue);

    await client.call('keeper.disable');
    expect(services.installed, isEmpty);
    expect(loginctl.last, 'loginctl disable-linger tester');
    expect(linger.enabled, isFalse);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('linger уже включён администратором — роль его не выключает', () async {
    final lingerDir = Directory('${dir.path}/linger')..createSync();
    File('${lingerDir.path}/tester').createSync();
    final calls = <String>[];
    final linger = Linger(
      user: 'tester',
      lingerDir: lingerDir.path,
      runner: (exe, args) async {
        calls.add(args.join(' '));
        return ProcessResult(0, 0, '', '');
      },
    );
    final nodeExe = File('${dir.path}/bin/node')..createSync(recursive: true);
    final client = await start(
      launcher: ServiceNodeLauncher(
        services: MemoryServices(),
        executable: nodeExe.path,
      ),
      linger: linger,
    );
    AppConfig.load(home)
      ..coordinator = 'https://127.0.0.1:9'
      ..save(home);
    await client.call('keeper.enable', {
      'quotaBytes': 1 << 30,
    }, const Duration(minutes: 1));
    await client.call('keeper.disable');
    expect(calls, isEmpty);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('удаление клиента: службы, запуск при входе, копия программ; '
      '--purge — и данные', () async {
    final services = MemoryServices();
    await services.install(
      const ServiceSpec(name: 'agent', description: '', executable: '/a'),
    );
    await services.install(
      const ServiceSpec(name: 'node', description: '', executable: '/n'),
    );
    final login = XdgLoginItem(autostartDir: '${dir.path}/autostart');
    await login.enable('/opt/app', ['--hidden']);
    final persistent = PersistentDaemons(
      target: Directory('${dir.path}/local/lib/backpeer/daemons'),
    );
    final source = Directory('${dir.path}/bundle/agent/bin')
      ..createSync(recursive: true);
    File('${source.path}/agent').writeAsStringSync('#!/bin/sh\n');
    expect(
      persistent.sync(DaemonBundle('${dir.path}/bundle'), '1.0.0'),
      isTrue,
    );
    expect(
      persistent.sync(DaemonBundle('${dir.path}/bundle'), '1.0.0'),
      isFalse,
    );
    expect(
      persistent.sync(DaemonBundle('${dir.path}/bundle'), '1.0.1'),
      isTrue,
    );
    expect(
      DaemonBundle(persistent.target.path).executable('agent'),
      endsWith('/daemons/agent/bin/agent'),
    );

    final nodeDir = Directory('${dir.path}/node')..createSync();
    final secrets = MemorySecretStore();
    await secrets.write(home.dir.absolute.path, 'тест', 'секрет');

    final kept = await uninstallClient(
      home: home,
      nodeDataDir: nodeDir.path,
      services: services,
      loginItem: login,
      persistent: persistent,
      secrets: secrets,
    );
    expect(kept, hasLength(4));
    expect(services.installed, isEmpty);
    expect(login.enabled, isFalse);
    expect(persistent.target.parent.existsSync(), isFalse);
    expect(home.dir.existsSync(), isTrue, reason: 'данные остаются');
    expect(await secrets.read(home.dir.absolute.path), 'секрет');

    final purged = await uninstallClient(
      home: home,
      nodeDataDir: nodeDir.path,
      services: services,
      loginItem: login,
      secrets: secrets,
      purge: true,
    );
    expect(purged, hasLength(3));
    expect(home.dir.existsSync(), isFalse);
    expect(nodeDir.existsSync(), isFalse);
    expect(await secrets.read(home.dir.absolute.path), isNull);
  });

  test('разбор сигналов logind и NetworkManager, вывода pmset', () {
    expect(
      parseMonitorLine(
        '/org/freedesktop/login1: '
        'org.freedesktop.login1.Manager.PrepareForSleep (true,)',
      ),
      SystemEvent.sleep,
    );
    expect(
      parseMonitorLine(
        '/org/freedesktop/login1: '
        'org.freedesktop.login1.Manager.PrepareForSleep (false,)',
      ),
      SystemEvent.wake,
    );
    expect(
      parseMonitorLine(
        '/org/freedesktop/NetworkManager: '
        'org.freedesktop.NetworkManager.StateChanged (uint32 70,)',
      ),
      SystemEvent.networkUp,
    );
    expect(
      parseMonitorLine(
        '/org/freedesktop/NetworkManager: '
        'org.freedesktop.NetworkManager.StateChanged (uint32 20,)',
      ),
      isNull,
    );
    expect(
      PmsetPowerSource.parsePmset(
        "Now drawing from 'Battery Power'\n -InternalBattery-0 80%",
      ),
      isTrue,
    );
    expect(
      PmsetPowerSource.parsePmset("Now drawing from 'AC Power'\n"),
      isFalse,
    );
  });
}
