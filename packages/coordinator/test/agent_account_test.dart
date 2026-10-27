import 'dart:io';

import 'package:agent/agent.dart';
import 'package:cli/cli.dart';
import 'package:core/core.dart';
import 'package:daemon_kit/daemon_kit.dart'
    show ControlClient, ControlException;
import 'package:test/test.dart';

import 'support/live.dart';
import 'support/postgres.dart';

/// Учётная запись из приложения через агента бэкапа на настоящем
/// координаторе (задачи 5.2.1–5.2.3): создание, вход по паролю на новом
/// устройстве, по фразе, устройства и отзыв, смена пароля, копия ключа.
void main() {
  if (testPostgresUrl == null) {
    test('учётная запись через агента', () {}, skip: skipWithoutPostgres);
    return;
  }

  late CryptoProvider crypto;
  late LiveCoordinator live;
  late Directory dir;
  final agents = <BackupAgent>[];
  final clients = <ControlClient>[];

  setUpAll(() async => crypto = await SodiumCryptoProvider.load());
  setUp(() async {
    live = await LiveCoordinator.start();
    dir = Directory.systemTemp.createTempSync('fs-agent-account-');
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
    await live.close();
    dir.deleteSync(recursive: true);
  });

  /// Агент нового «компьютера».
  Future<ControlClient> computer(String name) async {
    final home = AppHome(Directory('${dir.path}/$name'));
    agents.add(
      await BackupAgent.start(
        home: home,
        notifier: const NoNotifier(),
        crypto: crypto,
        secrets: MemorySecretStore(),
        argon2: const Argon2Params(memoryKiB: 1024, iterations: 1),
        handleSignals: false,
      ),
    );
    final client = await ControlClient.connect(AgentPaths(home).endpoint());
    clients.add(client);
    return client;
  }

  Matcher code(String code) =>
      throwsA(isA<ControlException>().having((e) => e.code, 'code', code));

  const long = Duration(minutes: 1);
  const password = 'correct horse battery staple';
  const newPassword = 'another long sentence for tests';

  test('создание, вход по паролю и по фразе, устройства, отзыв, пароль, '
      'копия ключа', () async {
    Map<String, Object?> server() => {
      'coordinator': live.url,
      'fragments': 'folders',
      'nodes': '${dir.path}/nodes',
    };

    final first = await computer('first');
    final words =
        ((await first.call('account.new_phrase'))['words']! as List<Object?>)
            .cast<String>();
    final confirm = {'1': words[0], '2': words[1], '3': words[2]};
    await expectLater(
      first.call('account.create', {
        ...server(),
        'password': password,
        'confirm': confirm,
      }),
      code('bad_request'),
    );
    final created = await first.call('account.create', {
      ...server(),
      'login': 'Alice',
      'password': password,
      'confirm': confirm,
    }, long);
    expect(created['keyCopy'], isTrue);
    expect(created['remembered'], isTrue);
    final info = await first.call('account.info');
    expect(info['login'], 'alice');
    expect(info['coordinator'], live.url);

    // Имя занято.
    final other = await computer('other');
    final otherWords =
        ((await other.call('account.new_phrase'))['words']! as List<Object?>)
            .cast<String>();
    await expectLater(
      other.call('account.create', {
        ...server(),
        'login': 'alice',
        'password': password,
        'confirm': {'4': otherWords[3], '5': otherWords[4], '6': otherWords[5]},
      }, long),
      code('login_taken'),
    );

    // Новый компьютер: вход по паролю.
    final second = await computer('second');
    await expectLater(
      second.call('account.login', {
        ...server(),
        'login': 'alice',
        'password': 'не тот пароль',
      }, long),
      code('unauthenticated'),
    );
    final loggedIn = await second.call('account.login', {
      ...server(),
      'login': 'alice',
      'password': password,
    }, long);
    expect(loggedIn['accountId'], created['accountId']);
    expect(loggedIn['indexes'], 0);
    expect((await second.call('account.info'))['hasPhrase'], isFalse);
    await expectLater(
      second.call('account.phrase', {'password': password}, long),
      code('no_phrase'),
    );

    // Устройства: оба, текущее отмечено; отзыв действует сразу.
    final devices =
        ((await first.call('account.devices', const {}, long))['devices']!
                as List<Object?>)
            .cast<Map<String, Object?>>();
    expect(devices, hasLength(2));
    final own = devices.singleWhere((d) => d['current'] == true);
    final secondId = loggedIn['deviceId']! as String;
    expect(devices.map((d) => d['deviceId']), contains(secondId));
    await expectLater(
      first.call('account.revoke', {'device': own['deviceId']}, long),
      code('current_device'),
    );
    // Запросы, подписанные ключом устройства, работают до отзыва.
    expect(
      (await second.call('snapshots', const {}, long))['snapshots'],
      isEmpty,
    );
    expect(
      await first.call('account.revoke', {
        'device': secondId.substring(0, 8),
      }, long),
      {'deviceId': secondId},
    );
    await expectLater(
      second.call('snapshots', const {}, long),
      throwsA(
        isA<ControlException>()
            .having((e) => e.code, 'code', 'failed')
            .having((e) => e.message, 'message', contains('отозван')),
      ),
    );
    final after =
        ((await first.call('account.devices', const {}, long))['devices']!
                as List<Object?>)
            .cast<Map<String, Object?>>();
    expect(
      after.singleWhere((d) => d['deviceId'] == secondId)['revokedAt'],
      isNotNull,
    );

    // Смена пароля меняет и копию ключа на координаторе.
    expect(
      await first.call('account.passwd', {
        'password': password,
        'newPassword': newPassword,
      }, long),
      {'keyCopyUpdated': true, 'keyCopyUnknown': false},
    );
    final third = await computer('third');
    await expectLater(
      third.call('account.login', {
        ...server(),
        'login': 'alice',
        'password': password,
      }, long),
      code('unauthenticated'),
    );

    // Без копии ключа вход по паролю невозможен — только по фразе.
    expect(
      await first.call('account.key_copy', {
        'password': newPassword,
        'enabled': false,
      }, long),
      {'keyCopy': false},
    );
    expect((await first.call('account.info'))['keyCopy'], isFalse);
    await expectLater(
      third.call('account.login', {
        ...server(),
        'login': 'alice',
        'password': newPassword,
      }, long),
      code('unauthenticated'),
    );
    final recovered = await third.call('account.recover', {
      ...server(),
      'phrase': words.join(' '),
      'password': newPassword,
    }, long);
    expect(recovered['accountId'], created['accountId']);
    expect(
      (await third.call('account.devices', const {}, long))['devices'],
      hasLength(3),
    );
  });
}
