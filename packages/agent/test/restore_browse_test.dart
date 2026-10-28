import 'dart:async';
import 'dart:io';

import 'package:agent/agent.dart';
import 'package:cli/cli.dart';
import 'package:core/core.dart';
import 'package:daemon_kit/daemon_kit.dart';
import 'package:test/test.dart';

import 'support.dart';

/// Просмотр снимков и восстановление выбранного (задачи 5.4.1, 5.4.2):
/// поиск, версии файла, восстановление на исходное место и рядом с
/// существующими; роль хранителя без координатора (5.5.1).
void main() {
  late CryptoProvider crypto;
  late Directory dir;
  late AppHome home;
  late BackupAgent agent;
  late ControlClient client;
  late Directory data;

  setUpAll(() async => crypto = await SodiumCryptoProvider.load());
  setUp(() async {
    dir = Directory.systemTemp.createTempSync('fs-agent-restore-');
    home = AppHome(Directory('${dir.path}/home'));
    await initHome(home.dir.path);
    data = sampleData('${dir.path}/data');
    agent = await BackupAgent.start(
      home: home,
      crypto: crypto,
      secrets: MemorySecretStore(),
      argon2: const Argon2Params(memoryKiB: 1024, iterations: 1),
      handleSignals: false,
      nodeDataDir: '${dir.path}/node',
    );
    client = await ControlClient.connect(AgentPaths(home).endpoint());
    await client.subscribe(['job_finished', 'progress']);
    await client.call('unlock', {
      'password': testPassword,
    }, const Duration(minutes: 1));
  });
  tearDown(() async {
    await client.close();
    await agent.stop();
    dir.deleteSync(recursive: true);
  });

  Future<Map<String, Object?>> run(
    String method, [
    Map<String, Object?> params = const {},
  ]) async {
    final done = client.events
        .firstWhere(
          (e) =>
              e.name == 'job_finished' &&
              e.data['kind'] == (method == 'backup' ? 'backup' : 'restore'),
        )
        .timeout(const Duration(minutes: 2));
    expect((await client.call(method, params))['started'], isTrue);
    final record = (await done).data;
    expect(record['outcome'], isNot('failed'), reason: '$record');
    return record['result']! as Map<String, Object?>;
  }

  Matcher code(String code) =>
      throwsA(isA<ControlException>().having((e) => e.code, 'code', code));

  test('поиск, версии файла, восстановление выбранного', () async {
    // Папки выбраны — первый бэкап агент начинает сам.
    final scheduled = client.events
        .firstWhere(
          (e) => e.name == 'job_finished' && e.data['kind'] == 'backup',
        )
        .timeout(const Duration(minutes: 2));
    // Хранить все снимки: оба бэкапа — в одном часу.
    await client.call('settings', {
      'paths': [data.path],
      'retention': null,
    });
    final first = (await scheduled).data['result']! as Map<String, Object?>;
    File('${data.path}/a.txt').writeAsStringSync('изменённый');
    final second = await run('backup');
    final newest = second['snapshotId']! as String;

    final found = await client.call('search', {
      'snapshot': newest,
      'query': 'B.TXT',
    });
    expect(found['truncated'], isFalse);
    expect((found['matches']! as List<Object?>).single, {
      'path': [data.path, 'sub', 'b.txt'],
      'name': 'b.txt',
      'type': 'file',
      'size': File('${data.path}/sub/b.txt').lengthSync(),
      'mtime': isA<String>(),
    });
    final glob = await client.call('search', {
      'snapshot': newest,
      'query': '*.txt',
      'under': [data.path, 'sub'],
    });
    expect(glob['matches']! as List<Object?>, hasLength(1));
    await expectLater(
      client.call('search', {'snapshot': newest, 'query': '  '}),
      code('bad_request'),
    );

    final versions =
        (await client.call('versions', {
              'path': [data.path, 'a.txt'],
            }))['versions']!
            as List<Object?>;
    expect(
      [for (final v in versions) (v! as Map)['snapshot']],
      [first['snapshotId'], newest],
    );
    expect([for (final v in versions) (v! as Map)['changed']], [true, true]);
    expect((versions.last! as Map)['size'], 'изменённый'.length * 2);
    final same =
        (await client.call('versions', {
              'path': [data.path, 'sub', 'b.txt'],
            }))['versions']!
            as List<Object?>;
    expect([for (final v in same) (v! as Map)['changed']], [true, false]);

    // Старая версия a.txt рядом с текущей.
    final kept = await run('restore', {
      'snapshot': first['snapshotId'],
      'originalLocation': true,
      'paths': ['${data.path}/a.txt'],
      'existing': 'keepBoth',
      'renameSuffix': 'восстановлено',
    });
    expect(kept['renamedCount'], 1);
    expect(File('${data.path}/a.txt').readAsStringSync(), 'изменённый');
    expect(
      File('${data.path}/a (восстановлено).txt').readAsStringSync(),
      'первый файл\n' * 100,
    );

    // Удалённый каталог — на исходное место; существующее не тронуто.
    Directory('${data.path}/sub').deleteSync(recursive: true);
    final back = await run('restore', {
      'snapshot': newest,
      'originalLocation': true,
      'paths': [data.path],
    });
    expect(back['skippedExisting'], 1);
    expect(back['skippedPaths'], [endsWith('a.txt')]);
    expect(
      File('${data.path}/sub/b.txt').readAsStringSync(),
      'второй файл\n' * 50,
    );

    // Перезапись в другую папку; ход — с объёмом выбранного.
    final target = '${dir.path}/out';
    final progress = <Map<String, Object?>>[];
    final sub = client.events
        .where((e) => e.name == 'progress' && e.data['kind'] == 'restore')
        .listen((e) => progress.add(e.data));
    await run('restore', {
      'snapshot': newest,
      'target': target,
      'paths': ['${data.path}/sub'],
      'existing': 'overwrite',
    });
    await sub.cancel();
    expect(File('$target${data.path}/sub/b.txt').existsSync(), isTrue);

    await expectLater(
      client.call('restore', {'snapshot': newest}),
      code('bad_request'),
    );
    await expectLater(
      client.call('restore', {
        'snapshot': newest,
        'originalLocation': true,
        'existing': 'merge',
      }),
      code('bad_request'),
    );
    await expectLater(
      client.call('restore', {
        'snapshot': newest,
        'originalLocation': true,
        'renameSuffix': '../x',
      }),
      code('bad_request'),
    );
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('роль хранителя без координатора — нельзя; место на диске', () async {
    final info = await client.call('keeper.info');
    expect(info['enabled'], isFalse);
    expect(info['dataDir'], '${dir.path}/node');
    expect(info['hasKeys'], isFalse);
    final disk = await client.call('keeper.disk', {
      'path': '${dir.path}/ещё нет/fragments',
    });
    expect(disk['availableBytes'], greaterThan(0));
    await expectLater(
      client.call('keeper.enable', {'quotaBytes': 1 << 40}),
      code('no_coordinator'),
    );
    expect(File('${dir.path}/node/node.key').existsSync(), isFalse);
  });
}
