import 'dart:async';
import 'dart:io';

import 'package:agent/agent.dart';
import 'package:cli/cli.dart';
import 'package:core/core.dart';
import 'package:daemon_kit/daemon_kit.dart';
import 'package:test/test.dart';

import 'support.dart';

/// Методы `account.*` без координатора (задачи 5.2.1–5.2.3): учётная
/// запись из приложения, фраза, пароль; новое устройство по фразе и
/// «восстановить всё».
/// С координатором (вход по паролю, устройства, отзыв, копия ключа) —
/// `packages/coordinator/test/agent_account_test.dart`.
void main() {
  late CryptoProvider crypto;
  late Directory dir;
  final agents = <BackupAgent>[];
  final clients = <ControlClient>[];

  setUpAll(() async => crypto = await SodiumCryptoProvider.load());
  setUp(() => dir = Directory.systemTemp.createTempSync('fs-account-'));
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

  Future<(AppHome, MemorySecretStore, ControlClient)> start(String name) async {
    final home = AppHome(Directory('${dir.path}/$name'));
    final secrets = MemorySecretStore();
    agents.add(
      await BackupAgent.start(
        home: home,
        crypto: crypto,
        secrets: secrets,
        argon2: const Argon2Params(memoryKiB: 1024, iterations: 1),
        handleSignals: false,
      ),
    );
    final client = await ControlClient.connect(AgentPaths(home).endpoint());
    clients.add(client);
    return (home, secrets, client);
  }

  Matcher code(String code) =>
      throwsA(isA<ControlException>().having((e) => e.code, 'code', code));

  const long = Duration(minutes: 1);

  /// Общие папки-«узлы» и объектов: «другой компьютер» видит те же данные.
  Map<String, Object?> storage() => {
    'nodes': '${dir.path}/nodes',
    'objects': '${dir.path}/objects',
  };

  test('создание: слабый пароль и неподтверждённая фраза не принимаются; '
      'фраза, пароль, бэкап без пароля', () async {
    final (home, secrets, client) = await start('first');
    expect(await client.call('account.info'), {'configured': false});
    await expectLater(
      client.call('account.create', {'password': testPassword}),
      code('phrase_not_confirmed'),
    );
    final draft = await client.call('account.new_phrase');
    final words = (draft['words']! as List<Object?>).cast<String>();
    expect(words, hasLength(24));
    expect(draft['confirm'], 3);
    final confirm = {'3': words[2], '11': words[10], '24': words[23]};

    await expectLater(
      client.call('account.create', {
        'password': 'password123',
        'confirm': confirm,
        ...storage(),
      }),
      code('weak_password'),
    );
    await expectLater(
      client.call('account.create', {
        'password': testPassword,
        'confirm': {'3': words[2], '11': words[10]},
        ...storage(),
      }),
      code('phrase_not_confirmed'),
    );
    await expectLater(
      client.call('account.create', {
        'password': testPassword,
        'confirm': {...confirm, '5': 'неверно'},
        ...storage(),
      }),
      code('phrase_not_confirmed'),
    );
    expect(home.initialized, isFalse);

    final created = await client.call('account.create', {
      'password': testPassword,
      'confirm': confirm,
      ...storage(),
    }, long);
    expect(created['remembered'], isTrue);
    expect(secrets.secrets, hasLength(1));
    expect(home.initialized, isTrue);
    final status = await client.call('status');
    expect(status['configured'], isTrue);
    expect(status['status'], 'idle');
    final info = await client.call('account.info');
    expect(info['configured'], isTrue);
    expect(info['coordinator'], isNull);
    expect(info['hasPhrase'], isTrue);
    await expectLater(client.call('account.new_phrase'), code('exists'));
    await expectLater(client.call('account.devices'), code('no_coordinator'));

    // Фраза снова — только по паролю.
    await expectLater(
      client.call('account.phrase', {'password': 'не тот'}, long),
      code('wrong_password'),
    );
    expect(
      (await client.call('account.phrase', {
        'password': testPassword,
      }, long))['words'],
      words,
    );

    // Смена пароля: старый неверен, новый слабый, затем успешно.
    const next = 'another long sentence for tests';
    await expectLater(
      client.call('account.passwd', {
        'password': 'не тот',
        'newPassword': next,
      }, long),
      code('wrong_password'),
    );
    await expectLater(
      client.call('account.passwd', {
        'password': testPassword,
        'newPassword': 'qwerty',
      }, long),
      code('weak_password'),
    );
    expect(
      await client.call('account.passwd', {
        'password': testPassword,
        'newPassword': next,
      }, long),
      {'keyCopyUpdated': false, 'keyCopyUnknown': false},
    );
    await expectLater(
      client.call('account.phrase', {'password': testPassword}, long),
      code('wrong_password'),
    );
    expect(
      (await client.call('account.phrase', {'password': next}, long))['words'],
      words,
    );

    // Ключи у агента: бэкап без пароля.
    await client.subscribe(['job_finished']);
    final data = sampleData('${dir.path}/data');
    final done = client.events.firstWhere((e) => e.name == 'job_finished');
    await client.call('settings', {
      'paths': [data.path],
    });
    expect((await done.timeout(long)).data['outcome'], 'ok');

    // Новый компьютер: та же учётная запись по фразе, индекс и снимки.
    final (other, _, second) = await start('second');
    await expectLater(
      second.call('account.recover', {
        'phrase': words.reversed.join(' '),
        'password': testPassword,
        ...storage(),
      }, long),
      code('bad_phrase'),
    );
    final recovered = await second.call('account.recover', {
      'phrase': words.join('  ').toUpperCase(),
      'password': testPassword,
      ...storage(),
    }, long);
    expect(recovered['accountId'], created['accountId']);
    expect(recovered['indexes'], 1);
    expect(recovered['segments'], greaterThan(0));
    expect(recovered['remembered'], isTrue);
    expect(other.initialized, isTrue);
    final snapshots =
        (await second.call('snapshots', const {}, long))['snapshots']!
            as List<Object?>;
    expect(snapshots, hasLength(1));

    // «Восстановить всё» — как приложение после входа.
    await second.subscribe(['job_finished']);
    final restored = second.events.firstWhere((e) => e.name == 'job_finished');
    final target = '${dir.path}/restored';
    expect(
      (await second.call('restore', {
        'snapshot': (snapshots.single! as Map<String, Object?>)['id'],
        'target': target,
        'waitMinutes': 60,
      }))['started'],
      isTrue,
    );
    expect((await restored.timeout(long)).data['outcome'], 'ok');
    expect(
      File('$target/${data.path.replaceFirst(RegExp('^/+'), '')}/sub/b.txt')
          .readAsStringSync(),
      'второй файл\n' * 50,
    );
  });
}
