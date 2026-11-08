// `agent service install|uninstall|status` (задачи 5.6.1, 5.7.3): команды
// управления службой ОС. Регрессия: `--home` есть только у подкоманд
// `service`, а CLI спрашивал опцию у самой команды и падал с
// «Could not find an option named --home» ещё до всякой работы.

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'support.dart';

void main() {
  late Directory dir;
  late Map<String, String> env;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('fs-agent-service-');
    // `none` — без настоящих служб ОС: проверяются разбор аргументов и вывод.
    env = {...testEnv(dir.path), 'FS_SERVICES': 'none'};
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<ProcessResult> run(List<String> args) => Process.run(
    Platform.resolvedExecutable,
    ['run', 'bin/agent.dart', ...args, '--home', dir.path],
    environment: env,
  );

  test('agent service status: разбирает --home и печатает состояние', () async {
    final result = await run(['service', 'status']);
    final out = '${result.stdout}';
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(out, isNot(contains('Could not find an option')));
    final json = jsonDecode(out) as Map<String, Object?>;
    expect(json['kind'], 'none');
    expect((json['agent']! as Map<String, Object?>)['state'], 'notInstalled');
    expect((json['node']! as Map<String, Object?>)['state'], 'notInstalled');
  });

  test('agent service install и uninstall: без служб ОС — понятная '
      'ошибка и код возврата 69', () async {
    final install = await run(['service', 'install']);
    expect(install.exitCode, 69, reason: '${install.stderr}');
    expect('${install.stderr}', contains('Службы ОС недоступны'));

    // Удаление службы без служб ОС — не ошибка: удалять нечего.
    final uninstall = await run(['service', 'uninstall']);
    expect(uninstall.exitCode, 0, reason: '${uninstall.stderr}');
  });

  test('agent status --home: остальные команды по-прежнему работают', () async {
    final result = await run(['status']);
    expect(result.exitCode, 69, reason: '${result.stderr}');
    expect('${result.stderr}', contains('не запущен'));
  });
}
