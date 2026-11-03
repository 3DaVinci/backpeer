// Задачи 5.3.1–5.3.5 на агенте в одном процессе: оценка объёма, история и
// пропущенные файлы, очистка по политике хранения после бэкапа, бэкап
// только от сети, уведомление о проблеме с данными.

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:agent/agent.dart';
import 'package:cli/cli.dart';
import 'package:core/core.dart';
import 'package:daemon_kit/daemon_kit.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late CryptoProvider crypto;
  late Directory dir;
  late AppHome home;
  late MemoryNotifier notifier;
  late FakePowerSource power;
  final agents = <BackupAgent>[];
  final clients = <ControlClient>[];

  setUpAll(() async => crypto = await SodiumCryptoProvider.load());
  setUp(() async {
    dir = Directory.systemTemp.createTempSync('fs-agent-opt-');
    home = AppHome(Directory('${dir.path}/home'));
    notifier = MemoryNotifier();
    power = FakePowerSource();
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

  /// Агент с открытыми ключами и подпиской на все события.
  Future<ControlClient> start() async {
    agents.add(
      await BackupAgent.start(
        home: home,
        crypto: crypto,
        secrets: MemorySecretStore(),
        argon2: const Argon2Params(memoryKiB: 1024, iterations: 1),
        handleSignals: false,
        power: power,
        notifier: notifier,
        powerRetry: const Duration(milliseconds: 100),
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

  Future<Map<String, Object?>> finished(ControlClient client, String kind) =>
      client.events
          .firstWhere((e) => e.name == 'job_finished' && e.data['kind'] == kind)
          .then((e) => e.data)
          .timeout(const Duration(minutes: 2));

  Future<Map<String, Object?>> backup(ControlClient client) async {
    final done = finished(client, 'backup');
    expect((await client.call('backup'))['started'], isTrue);
    return await done;
  }

  test('оценка объёма, пропущенные файлы, история, очистка по политике '
      'хранения', () async {
    final data = sampleData('${dir.path}/data');
    File('${data.path}/draft.tmp').writeAsStringSync('черновик');
    Directory('${data.path}/.cache').createSync();
    File('${data.path}/.cache/blob').writeAsBytesSync(List.filled(5000, 1));
    final locked = File('${data.path}/locked.txt')..writeAsStringSync('тайна');
    if (!Platform.isWindows) Process.runSync('chmod', ['000', locked.path]);
    final lockedReadable = () {
      try {
        locked.readAsStringSync();
        return true;
      } on FileSystemException {
        return false;
      }
    }();

    final client = await start();
    final settings = await client.call('settings', {
      'paths': [data.path],
      'intervalMinutes': null,
      'retention': {
        'last': 2,
        'hourly': 0,
        'daily': 0,
        'weekly': 0,
        'monthly': 0,
      },
    });
    expect(settings['retention'], containsPair('last', 2));
    expect(settings['excludePresets'], ['temporary', 'caches', 'trash']);
    expect(AppConfig.load(home).retention!.last, 2);

    // Оценка до бэкапа: временные файлы и кеш исключены наборами.
    final estimate = await client.call('estimate');
    expect(estimate['files'], 3);
    expect(estimate['excluded'], 2);
    final all = await client.call('estimate', {'excludePresets': <String>[]});
    expect(all['files'], 5);
    expect(all['bytes'], greaterThan(estimate['bytes']! as int));
    await expectLater(
      client.call('estimate', {
        'paths': ['относительный'],
      }),
      throwsA(
        isA<ControlException>().having((e) => e.code, 'code', 'bad_request'),
      ),
    );

    final first = await backup(client);
    expect(first['outcome'], lockedReadable ? 'ok' : 'partial');
    final result = first['result']! as Map<String, Object?>;
    expect(result['excluded'], 2);
    if (!lockedReadable) {
      expect(result['skippedFiles'], [
        allOf(
          containsPair('path', locked.path),
          containsPair('reason', 'error'),
        ),
      ]);
    }
    expect(result['retention'], {'kept': 1, 'forgotten': 0});

    // Все данные новые — новые сегменты; третий бэкап удаляет первый снимок
    // и его сегменты. locked.txt удаляется: если он прочитался (root в CI),
    // он лежит в одном сегменте с прежними a.txt и b.txt и держал бы его.
    locked.deleteSync();
    final rnd = Random(3);
    final nodes = Directory('${home.dir.path}/nodes');
    int nodeBytes() => nodes
        .listSync(recursive: true)
        .whereType<File>()
        .fold(0, (sum, f) => sum + f.lengthSync());
    for (var i = 0; i < 2; i++) {
      for (final name in ['a.txt', 'sub/b.txt']) {
        File(
          '${data.path}/$name',
        ).writeAsBytesSync(List.generate(300 << 10, (_) => rnd.nextInt(256)));
      }
      final r = await backup(client);
      expect(r['outcome'], isNot('failed'), reason: '$r');
    }
    final third =
        agents.single.state.lastBackup!.result['retention']!
            as Map<String, Object?>;
    expect(third['forgotten'], 1);
    expect(third['segmentsDeleted'], greaterThan(0));
    expect(third['bytesFreed'], greaterThan(0));
    final snapshots =
        (await client.call('snapshots'))['snapshots']! as List<Object?>;
    expect(snapshots, hasLength(2));
    expect(nodeBytes(), greaterThan(0));

    final history =
        (await client.call('history', {'kind': 'backup'}))['jobs']!
            as List<Object?>;
    expect(history, hasLength(3));
    expect(history.first, containsPair('trigger', 'manual'));
    expect(
      (await client.call('history', {'limit': 1}))['jobs']! as List<Object?>,
      hasLength(1),
    );
    if (!Platform.isWindows) Process.runSync('chmod', ['600', locked.path]);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('только от сети: ждёт сеть, от батареи останавливается и потом '
      'продолжает', () async {
    final data = Directory('${dir.path}/big')..createSync();
    for (var i = 0; i < 4; i++) {
      File('${data.path}/f$i.bin')
          .writeAsBytesSync(crypto.randomBytes(24 << 20));
    }
    power.battery = true;
    final client = await start();
    final waiting = client.events.firstWhere(
      (e) => e.name == 'status' && e.data['status'] == 'waitingForPower',
    );
    await client.call('settings', {
      'paths': [data.path],
      'onlyOnAcPower': true,
    });
    await waiting.timeout(const Duration(seconds: 10));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(agents.single.job, isNull, reason: 'от батареи — не начинать');

    final stopped = finished(client, 'backup');
    power.battery = false;
    // Первый сохранённый сегмент ждём опросом `status`, а не событием
    // `progress`: события приходят не чаще раза в 500 мс, и на быстрой
    // машине (macOS) бэкап успевает закончиться раньше.
    final deadline = DateTime.now().add(const Duration(minutes: 2));
    while (true) {
      final status = await client.call('status');
      final job = status['job'] as Map<String, Object?>?;
      final progress = job?['progress'] as Map<String, Object?>? ?? const {};
      if ((progress['segmentsStored'] as int? ?? 0) >= 1) break;
      if (DateTime.now().isAfter(deadline)) {
        fail('бэкап не начался: $status');
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    // Сегментов 16 МиБ, данных 96 МиБ: после первого сохранённого сегмента
    // работа ещё идёт.
    power.battery = true;
    final record = await stopped;
    expect(record['outcome'], 'cancelled');
    expect(record['result'], containsPair('reason', 'on_battery'));
    final status = await client.call('status');
    expect(status['status'], 'waitingForPower');
    expect(status['interrupted'], isTrue);

    final resumed = finished(client, 'backup');
    power.battery = false;
    final done = await resumed;
    expect(done['outcome'], 'ok');
    expect(done['trigger'], 'resume');
    final result = done['result']! as Map<String, Object?>;
    expect(result['newBytes']! as int, lessThan(96 << 20));
  }, timeout: const Timeout(Duration(minutes: 4)));

  test('потеряны фрагменты — здоровье «требует внимания» и одно '
      'уведомление', () async {
    final data = sampleData('${dir.path}/data');
    final client = await start();
    await client.call('settings', {
      'paths': [data.path],
      'intervalMinutes': null,
    });
    expect((await backup(client))['outcome'], 'ok');
    var health = await client.call('health');
    expect(health['state'], 'ok');
    expect(notifier.sent, isEmpty);

    // Узлы «потеряли» фрагменты.
    for (final f
        in Directory('${home.dir.path}/nodes')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.frag'))) {
      f.deleteSync();
    }
    final event = client.events.firstWhere(
      (e) => e.name == 'health' && e.data['state'] == 'attention',
    );
    Future<void> verify() async {
      final done = finished(client, 'verify');
      await client.call('verify');
      expect((await done)['outcome'], 'failed');
    }

    await verify();
    final reasons =
        (await event.timeout(const Duration(seconds: 10))).data['reasons']!
            as List<Object?>;
    expect(reasons.single, containsPair('code', 'unrecoverable'));
    await until(() => notifier.sent.isNotEmpty, 'уведомление');
    expect(notifier.sent.single.$1, 'Бэкап требует внимания');
    expect(notifier.sent.single.$2, contains('нельзя восстановить'));
    health = await client.call('health');
    expect(health['state'], 'attention');
    expect(
      (await client.call('status'))['health'],
      containsPair('state', 'attention'),
    );

    // То же состояние — без повторного уведомления, и после перезапуска.
    await verify();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(notifier.sent, hasLength(1));
    expect(agents.single.state.notifiedHealth, isNotNull);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
