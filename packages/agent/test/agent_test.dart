import 'dart:async';
import 'dart:io';

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
  late MemorySecretStore secrets;
  final agents = <BackupAgent>[];
  final clients = <ControlClient>[];

  setUpAll(() async => crypto = await SodiumCryptoProvider.load());
  setUp(() async {
    dir = Directory.systemTemp.createTempSync('fs-agent-');
    home = AppHome(Directory('${dir.path}/home'));
    secrets = MemorySecretStore();
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

  Future<BackupAgent> start({
    Duration keysRetry = const Duration(minutes: 1),
  }) async {
    final agent = await BackupAgent.start(
      home: home,
      crypto: crypto,
      secrets: secrets,
      argon2: const Argon2Params(memoryKiB: 1024, iterations: 1),
      handleSignals: false,
      keysRetry: keysRetry,
    );
    agents.add(agent);
    return agent;
  }

  Future<ControlClient> connect() async {
    final client = await ControlClient.connect(AgentPaths(home).endpoint());
    clients.add(client);
    return client;
  }

  /// Ждёт события `job_finished` задания [kind].
  Future<Map<String, Object?>> finished(ControlClient client, String kind) =>
      client.events
          .firstWhere((e) => e.name == 'job_finished' && e.data['kind'] == kind)
          .then((e) => e.data)
          .timeout(const Duration(minutes: 2));

  test('без учётной записи: состояние есть, заданий нет', () async {
    await start();
    final client = await connect();
    final status = await client.call('status');
    expect(status['configured'], isFalse);
    expect(status['status'], 'idle');
    expect(status['nextBackupAt'], isNull);
    await expectLater(
      client.call('backup'),
      throwsA(
        isA<ControlException>().having((e) => e.code, 'code', 'not_configured'),
      ),
    );
  });

  test('бэкап по расписанию, снимки, дерево, восстановление, проверка; '
      'после перезапуска — без пароля', () async {
    await initHome(home.dir.path);
    final data = sampleData('${dir.path}/data');
    var agent = await start();
    var client = await connect();
    await client.subscribe();
    final keysRequired = client.events.firstWhere(
      (e) => e.name == 'keys_required',
    );
    // Папки выбраны — первый бэкап сразу, но ключей нет: агент ждёт.
    await client.call('settings', {
      'paths': [data.path],
    });
    expect((await keysRequired).data['reason'], contains('не сохранены'));
    expect((await client.call('status'))['status'], 'waitingForKeys');
    await expectLater(
      client.call('unlock', {'password': 'не тот пароль'}),
      throwsA(
        isA<ControlException>().having((e) => e.code, 'code', 'wrong_password'),
      ),
    );
    final first = finished(client, 'backup');
    final unlocked = await client.call('unlock', {
      'password': testPassword,
    }, const Duration(minutes: 1));
    expect(unlocked['remembered'], isTrue);
    expect(secrets.secrets, hasLength(1));
    final record = await first;
    expect(record['outcome'], 'ok', reason: '$record');
    final result = record['result']! as Map<String, Object?>;
    expect(result['files'], 2);
    final status = await client.call('status');
    expect(status['status'], 'idle');
    expect(status['interrupted'], isFalse);
    expect(
      DateTime.parse(status['nextBackupAt']! as String)
          .isAfter(DateTime.now().add(const Duration(minutes: 55))),
      isTrue,
    );

    // Второй агент на тот же каталог не стартует.
    await expectLater(start(), throwsA(isA<FileSystemException>()));

    final snapshots =
        (await client.call('snapshots'))['snapshots']! as List<Object?>;
    expect(snapshots, hasLength(1));
    final snapshot = snapshots.single! as Map<String, Object?>;
    final id = snapshot['id']! as String;
    final root = await client.call('tree', {'snapshot': id});
    final rootName =
        ((root['entries']! as List<Object?>).single!
            as Map<String, Object?>)['name']!;
    expect(rootName, data.path);
    final inside = await client.call('tree', {
      'snapshot': id.substring(0, 8),
      'path': [rootName],
      'limit': 1,
    });
    expect(inside['total'], 2);
    expect(inside['entries'], [containsPair('name', 'a.txt')]);
    await expectLater(
      client.call('tree', {
        'snapshot': id,
        'path': [rootName, 'нет такого'],
      }),
      throwsA(isA<ControlException>().having((e) => e.code, 'code', 'failed')),
    );

    final target = '${dir.path}/restored';
    final restored = finished(client, 'restore');
    expect(
      (await client.call('restore', {
        'snapshot': id,
        'target': target,
      }))['started'],
      isTrue,
    );
    expect((await restored)['outcome'], 'ok');
    final copy = File(
      '$target/${data.path.replaceFirst(RegExp('^/+'), '')}/sub/b.txt',
    );
    expect(copy.readAsStringSync(), 'второй файл\n' * 50);

    final verified = finished(client, 'verify');
    await client.call('verify', {'full': true});
    final health = await verified;
    expect(health['outcome'], 'ok');
    expect((health['result']! as Map<String, Object?>)['healthy'], isTrue);
    expect(
      ((await client.call('health'))['lastVerify']!
          as Map<String, Object?>)['outcome'],
      'ok',
    );

    // Перезапуск: ключи из хранилища ОС, ручной бэкап без пароля.
    await agent.stop();
    agents.clear();
    clients.clear();
    agent = await start();
    client = await connect();
    await client.subscribe(['job_finished']);
    File('${data.path}/c.txt').writeAsStringSync('новый файл');
    final second = finished(client, 'backup');
    expect((await client.call('backup'))['started'], isTrue);
    final again = await second;
    expect(again['outcome'], 'ok');
    expect((again['result']! as Map<String, Object?>)['files'], 3);
    expect(agent.state.lastBackup!.outcome, JobOutcome.ok);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('хранилище закрыто — ждёт; открылось — продолжает сам', () async {
    await initHome(home.dir.path);
    final data = sampleData('${dir.path}/data');
    var agent = await start();
    var client = await connect();
    await client.call('settings', {
      'paths': [data.path],
      'intervalMinutes': null,
    });
    await client.call('unlock', {
      'password': testPassword,
    }, const Duration(minutes: 1));
    await agent.stop();
    agents.clear();
    clients.clear();

    // После перезагрузки связка ключей ещё закрыта.
    secrets.locked = true;
    agent = await start(keysRetry: const Duration(milliseconds: 200));
    client = await connect();
    await client.subscribe();
    final keysRequired = client.events.firstWhere(
      (e) => e.name == 'keys_required',
    );
    final done = finished(client, 'backup');
    // Включили расписание: бэкап пора делать, но ключей нет — ждём.
    await client.call('settings', {'intervalMinutes': 60});
    expect((await keysRequired).data['reason'], contains('недоступно'));
    expect((await client.call('status'))['status'], 'waitingForKeys');
    // Пользователь вошёл, связка открылась — агент сам повторяет.
    secrets.locked = false;
    expect((await done)['outcome'], 'ok');
  });

  test('пауза останавливает бэкап с продолжением; resume продолжает', () async {
    await initHome(home.dir.path);
    final data = Directory('${dir.path}/big')..createSync();
    // Много сегментов по 16 МиБ: пауза должна прийти посреди бэкапа,
    // даже если прогресс приходит раз в полсекунды (а на быстрой машине
    // четыре файла успевали закончиться до неё).
    for (var i = 0; i < 16; i++) {
      File('${data.path}/f$i.bin')
          .writeAsBytesSync(crypto.randomBytes(12 << 20));
    }
    await start();
    final client = await connect();
    await client.subscribe();
    await client.call('unlock', {
      'password': testPassword,
    }, const Duration(minutes: 1));
    final progressed = client.events.firstWhere(
      (e) => e.name == 'progress' && (e.data['segmentsStored']! as int) >= 1,
    );
    final cancelled = finished(client, 'backup');
    await client.call('settings', {
      'paths': [data.path],
    });
    await progressed.timeout(const Duration(minutes: 2));
    expect((await client.call('pause'))['status'], 'paused');
    expect((await cancelled)['outcome'], 'cancelled');
    final status = await client.call('status');
    expect(status['status'], 'paused');
    expect(status['interrupted'], isTrue);
    expect(status['nextBackupAt'], isNull);

    final resumed = finished(client, 'backup');
    await client.call('resume');
    final record = await resumed;
    expect(record['outcome'], 'ok');
    final result = record['result']! as Map<String, Object?>;
    // Часть сегментов уже была отправлена до паузы: всего 16 файлов по
    // 12 МиБ, после продолжения — меньше всех.
    expect(result['newBytes']! as int, lessThan(16 * 12 << 20));
    expect((await client.call('status'))['interrupted'], isFalse);
  }, timeout: const Timeout(Duration(minutes: 4)));
}
