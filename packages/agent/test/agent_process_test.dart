// Агент отдельным процессом, как его запускает служба: `kill -9` посреди
// бэкапа — следующий запуск продолжает бэкап сам, без повторной отправки
// сохранённых сегментов; второй экземпляр на тот же каталог не стартует.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agent/agent.dart';
import 'package:cli/cli.dart';
import 'package:daemon_kit/daemon_kit.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late Directory dir;
  late AppHome home;
  late Map<String, String> env;
  final processes = <Process>[];

  setUp(() {
    dir = Directory.systemTemp.createTempSync('fs-agent-proc-');
    home = AppHome(Directory('${dir.path}/home'));
    env = testEnv(home.dir.path);
  });
  tearDown(() async {
    for (final p in processes) {
      p.kill(ProcessSignal.sigkill);
      await p.exitCode;
    }
    processes.clear();
    dir.deleteSync(recursive: true);
  });

  Future<Process> spawn() async {
    final process = await Process.start(Platform.resolvedExecutable, [
      'run',
      'bin/agent.dart',
      'run',
      '--log',
      '-',
    ], environment: env);
    processes.add(process);
    return process;
  }

  /// Подключение к запущенному агенту (ждёт, пока он поднимет API).
  Future<ControlClient> connect() async {
    final endpoint = AgentPaths(home).endpoint();
    final deadline = DateTime.now().add(const Duration(minutes: 2));
    for (;;) {
      try {
        return await ControlClient.connect(endpoint);
      } on ControlException {
        if (DateTime.now().isAfter(deadline)) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
  }

  test(
    'kill -9 посреди бэкапа: следующий запуск продолжает; второй экземпляр '
    'не стартует',
    () async {
      await initHome(home.dir.path);
      final data = Directory('${dir.path}/big')..createSync();
      final random = File('/dev/urandom').openSync();
      const files = 8;
      const fileSize = 12 << 20;
      for (var i = 0; i < files; i++) {
        File('${data.path}/f$i.bin')
            .writeAsBytesSync(random.readSync(fileSize));
      }
      random.closeSync();
      AgentSettings(paths: [data.path]).save(AgentPaths(home).settings);

      final first = await spawn();
      final stderrText = StringBuffer();
      first.stderr.transform(utf8.decoder).listen(stderrText.write);
      unawaited(first.stdout.drain<void>());
      var client = await connect();
      await client.subscribe(['progress']);
      final progressed = client.events.firstWhere(
        (e) => (e.data['segmentsStored']! as int) >= 1,
      );
      // Второй экземпляр на тот же каталог.
      final second = await Process.run(Platform.resolvedExecutable, [
        'run',
        'bin/agent.dart',
        'run',
        '--log',
        '-',
      ], environment: env);
      expect(second.exitCode, 69, reason: '${second.stderr}');
      expect('${second.stderr}', contains('уже запущен'));

      // Хранилища ОС нет (FS_AGENT_SECRETS=none): ключи — в памяти.
      final unlocked = await client.call('unlock', {
        'password': testPassword,
      }, const Duration(minutes: 1));
      expect(unlocked['remembered'], isFalse);
      await progressed.timeout(
        const Duration(minutes: 3),
        onTimeout: () => fail('бэкап не начался: $stderrText'),
      );

      first.kill(ProcessSignal.sigkill);
      await first.exitCode;
      await client.close();
      final state = AgentState.load(AgentPaths(home).state);
      expect(state.interrupted, isNotNull);
      expect(state.lastBackup, isNull);

      // Следующий запуск: ключи из памяти пропали — пароль ещё раз, и
      // бэкап продолжается сам, без команды.
      final restarted = await spawn();
      unawaited(restarted.stdout.drain<void>());
      unawaited(restarted.stderr.drain<void>());
      client = await connect();
      await client.subscribe(['job_finished']);
      final done = client.events
          .firstWhere((e) => e.data['kind'] == 'backup')
          .timeout(const Duration(minutes: 3));
      final status = await client.call('status');
      expect(status['interrupted'], isTrue);
      await client.call('unlock', {
        'password': testPassword,
      }, const Duration(minutes: 1));
      final record = (await done).data;
      expect(record['outcome'], 'ok', reason: '$record');
      final result = record['result']! as Map<String, Object?>;
      expect(result['files'], files);
      // Сегменты, сохранённые до kill -9, повторно не отправлялись.
      expect(result['newBytes']! as int, lessThan(files * fileSize));
      expect((await client.call('status'))['interrupted'], isFalse);

      // Остановка по команде.
      await client.call('stop');
      await client.close();
      expect(await restarted.exitCode.timeout(const Duration(seconds: 30)), 0);
    },
    testOn: '!windows',
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
