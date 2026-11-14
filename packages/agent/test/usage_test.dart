// Место, занятое бэкапами учётной записи (метод `usage`): числа приходят
// от координатора (`GetBackupHealth`), поэтому без него метода нет — с
// координатором и настоящими сегментами проверяется в
// `packages/coordinator/test/backup_health_test.dart`.

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
  late BackupAgent agent;
  late ControlClient client;

  setUpAll(() async => crypto = await SodiumCryptoProvider.load());
  setUp(() async {
    dir = Directory.systemTemp.createTempSync('fs-usage-');
    final home = AppHome(Directory('${dir.path}/agent'));
    agent = await BackupAgent.start(
      home: home,
      notifier: const NoNotifier(),
      crypto: crypto,
      secrets: MemorySecretStore(),
      argon2: const Argon2Params(memoryKiB: 1024, iterations: 1),
      handleSignals: false,
    );
    client = await ControlClient.connect(AgentPaths(home).endpoint());
  });
  tearDown(() async {
    await client.close();
    await agent.stop();
    dir.deleteSync(recursive: true);
  });

  Matcher code(String code) =>
      throwsA(isA<ControlException>().having((e) => e.code, 'code', code));

  test('место бэкапов: без учётной записи и без координатора', () async {
    await expectLater(client.call('usage'), code('not_configured'));

    final words =
        ((await client.call('account.new_phrase'))['words']! as List<Object?>)
            .cast<String>();
    await client.call('account.create', {
      'password': testPassword,
      'confirm': {'1': words[0], '2': words[1], '3': words[2]},
      'nodes': '${dir.path}/nodes',
      'objects': '${dir.path}/objects',
    }, const Duration(minutes: 1));

    // Сегменты локальные: объём данных и место фрагментов на дисках
    // хранителей знает только координатор.
    await expectLater(client.call('usage'), code('no_coordinator'));
  });
}
