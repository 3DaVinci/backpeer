import 'dart:io';

import 'package:daemon_kit/daemon_kit.dart';
import 'package:test/test.dart';

/// Подделка внешних программ: записывает вызовы, отвечает по [answer].
final class FakeRunner {
  final calls = <String>[];
  ProcessResult Function(String command)? answer;

  Future<ProcessResult> call(String executable, List<String> args) async {
    final command = [executable, ...args].join(' ');
    calls.add(command);
    return answer?.call(command) ?? ProcessResult(0, 0, '', '');
  }
}

void main() {
  late Directory temp;
  setUp(() => temp = Directory.systemTemp.createTempSync('services_test'));
  tearDown(() => temp.deleteSync(recursive: true));

  const spec = ServiceSpec(
    name: 'agent',
    description: 'File Storage: агент бэкапа',
    executable: '/opt/file storage/daemons/agent/bin/agent',
    arguments: ['run', '--home', r'/home/u/50% $data'],
  );

  group('systemd', () {
    test('юнит: кавычки, спецификаторы, условие на программу', () {
      final text = SystemdUserServices.unitText(spec);
      expect(
        text,
        contains(
          'ExecStart="/opt/file storage/daemons/agent/bin/agent" "run" '
          r'"--home" "/home/u/50%% $$data"',
        ),
      );
      expect(
        text,
        contains(
          'ConditionPathExists=/opt/file storage/daemons/agent/bin/agent',
        ),
      );
      expect(text, contains('Restart=on-failure'));
      expect(text, contains('RestartPreventExitStatus=64 69'));
      expect(text, contains('WantedBy=default.target'));
    });

    test('установка, повтор без изменений, удаление', () async {
      final runner = FakeRunner();
      final services = SystemdUserServices(
        unitDir: '${temp.path}/systemd/user',
        runner: runner.call,
      );
      expect(services.serviceName('agent'), 'file-storage-agent.service');
      expect(await services.state('agent'), ServiceState.notInstalled);

      await services.install(spec);
      final unit = File('${temp.path}/systemd/user/file-storage-agent.service');
      expect(unit.readAsStringSync(), SystemdUserServices.unitText(spec));
      expect(runner.calls, [
        'systemctl --user daemon-reload',
        'systemctl --user enable file-storage-agent.service',
        'systemctl --user restart file-storage-agent.service',
      ]);

      // Тот же юнит: без daemon-reload и перезапуска.
      runner.calls.clear();
      await services.install(spec);
      expect(runner.calls, [
        'systemctl --user enable file-storage-agent.service',
        'systemctl --user start file-storage-agent.service',
      ]);

      runner.answer = (c) => ProcessResult(
        0,
        c.contains('is-active') ? 3 : 0,
        c.contains('is-active') ? 'inactive\n' : '',
        '',
      );
      expect(await services.state('agent'), ServiceState.stopped);

      runner.calls.clear();
      await services.uninstall('agent');
      expect(unit.existsSync(), isFalse);
      expect(
        runner.calls.first,
        'systemctl --user disable --now file-storage-agent.service',
      );
    });

    test('ошибка systemctl — ServiceException', () async {
      final runner = FakeRunner()
        ..answer = (c) => c.contains('enable')
            ? ProcessResult(0, 1, '', 'Failed to connect to bus')
            : ProcessResult(0, 0, '', '');
      final services = SystemdUserServices(
        unitDir: temp.path,
        runner: runner.call,
      );
      await expectLater(
        services.install(spec),
        throwsA(
          isA<ServiceException>().having(
            (e) => e.message,
            'message',
            contains('Failed to connect to bus'),
          ),
        ),
      );
    });

    test(
      'настоящий systemd --user: служба запускается и удаляется',
      () async {
        final script = File('${temp.path}/sleeper.sh')
          ..writeAsStringSync('#!/bin/sh\nexec sleep 600\n');
        await Process.run('chmod', ['+x', script.path]);
        final services = SystemdUserServices(
          unitDir: SystemdUserServices.defaultUnitDir(Platform.environment),
          prefix: 'fs-test-$pid',
        );
        try {
          await services.install(
            ServiceSpec(
              name: 'sleeper',
              description: 'тест daemon_kit',
              executable: script.path,
            ),
          );
          expect(await services.state('sleeper'), ServiceState.running);
          await services.stop('sleeper');
          expect(await services.state('sleeper'), ServiceState.stopped);
        } finally {
          await services.uninstall('sleeper');
        }
        expect(await services.state('sleeper'), ServiceState.notInstalled);
      },
      skip: Platform.environment['FS_TEST_SYSTEMD'] == '1'
          ? false
          : 'нужен FS_TEST_SYSTEMD=1 и сеанс systemd --user',
    );
  });

  group('launchd', () {
    test('plist: аргументы, окружение, перезапуск только после сбоя', () {
      final text = LaunchAgentServices.plistText(
        'org.file_storage.agent',
        const ServiceSpec(
          name: 'agent',
          description: '',
          executable: '/Applications/A & B.app/agent',
          arguments: ['run'],
          environment: {'FS_HOME': '/tmp/<x>'},
        ),
      );
      expect(
        text,
        contains('<string>/Applications/A &amp; B.app/agent</string>'),
      );
      expect(text, contains('<key>FS_HOME</key>'));
      expect(text, contains('<string>/tmp/&lt;x&gt;</string>'));
      expect(text, contains('<key>SuccessfulExit</key>\n    <false/>'));
    });

    test('установка через bootstrap в домене gui/<uid>', () async {
      final runner = FakeRunner()
        ..answer = (c) => ProcessResult(0, 0, c == 'id -u' ? '501\n' : '', '');
      final services = LaunchAgentServices(
        agentsDir: temp.path,
        runner: runner.call,
      );
      await services.install(spec);
      expect(
        File('${temp.path}/org.file_storage.agent.plist').existsSync(),
        isTrue,
      );
      expect(runner.calls, [
        'id -u',
        'launchctl bootout gui/501/org.file_storage.agent',
        'launchctl bootstrap gui/501 ${temp.path}/org.file_storage.agent.plist',
      ]);
    });
  });

  group('Планировщик заданий', () {
    test('XML: вход пользователя, без батарейных ограничений', () {
      final xml = ScheduledTaskServices.taskXml(r'PC\user', spec);
      expect(xml, contains(r'<UserId>PC\user</UserId>'));
      expect(xml, contains('<LogonTrigger>'));
      expect(
        xml,
        contains(
          '<DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>',
        ),
      );
      expect(xml, contains('<ExecutionTimeLimit>PT0S</ExecutionTimeLimit>'));
      expect(
        xml,
        contains(
          r'<Arguments>run --home &quot;/home/u/50% $data&quot;</Arguments>',
        ),
      );
    });

    test('установка: /Create из XML и /Run', () async {
      final runner = FakeRunner();
      final services = ScheduledTaskServices(
        user: r'PC\user',
        tempDir: temp.path,
        runner: runner.call,
      );
      await services.install(spec);
      expect(
        runner.calls[1],
        startsWith(r'schtasks /Create /TN \file-storage\agent /XML'),
      );
      expect(runner.calls.last, r'schtasks /Run /TN \file-storage\agent');
      // Временный XML удалён.
      expect(temp.listSync(), isEmpty);
    });
  });

  group('Linger', () {
    test('включён — по файлу logind; отказ polkit — причина', () async {
      Directory('${temp.path}/linger').createSync();
      final runner = FakeRunner()
        ..answer = (_) =>
            ProcessResult(0, 1, '', 'Could not enable linger: Access denied');
      final linger = Linger(
        user: 'alice',
        runner: runner.call,
        lingerDir: '${temp.path}/linger',
      );
      expect(linger.enabled, isFalse);
      expect(await linger.enable(), contains('Access denied'));
      expect(runner.calls, ['loginctl enable-linger alice']);
      expect(linger.manualCommand, 'sudo loginctl enable-linger alice');
      File('${temp.path}/linger/alice').createSync();
      expect(linger.enabled, isTrue);
    });
  });

  group('запуск при входе', () {
    test('XDG Autostart: TryExec и кавычки', () async {
      final item = XdgLoginItem(autostartDir: '${temp.path}/autostart');
      expect(item.enabled, isFalse);
      await item.enable('/home/u/Apps/File Storage.AppImage', ['--hidden']);
      final text = item.file.readAsStringSync();
      expect(text, contains('TryExec=/home/u/Apps/File Storage.AppImage\n'));
      expect(
        text,
        contains('Exec="/home/u/Apps/File Storage.AppImage" --hidden\n'),
      );
      expect(item.enabled, isTrue);
      await item.disable();
      expect(item.enabled, isFalse);
    });
  });
}
