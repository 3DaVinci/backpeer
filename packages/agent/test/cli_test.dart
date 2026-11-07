import 'dart:io';

import 'package:agent/agent.dart';
import 'package:test/test.dart';

/// Команды агента (задачи 5.1.3, 5.7.3). Регрессия: `agent service …`
/// падал с `Could not find an option named "--home"` — опция объявлена у
/// подкоманд `install`, `uninstall` и `status`, а не у `service`.
void main() {
  test('agent --version печатает версию', () async {
    expect(await runAgent(['--version'], environment: const {}), 0);
  });

  test('agent service без подкоманды — подсказка и код usage', () async {
    expect(await runAgent(['service'], environment: const {}), 64);
  });

  test(
    'agent service status принимает --home и не обращается к службам',
    () async {
      final home = Directory.systemTemp.createTempSync('fs-agent-cli');
      addTearDown(() {
        if (home.existsSync()) home.deleteSync(recursive: true);
      });
      final code = await runAgent(
        ['service', 'status', '--home', home.path],
        environment: const {'FS_SERVICES': 'none'},
      );
      expect(code, 0);
    },
  );

  test('agent uninstall с --home и без служб ничего не делает', () async {
    final home = Directory.systemTemp.createTempSync('fs-agent-cli');
    final node = Directory.systemTemp.createTempSync('fs-agent-cli-node');
    addTearDown(() {
      if (home.existsSync()) home.deleteSync(recursive: true);
      if (node.existsSync()) node.deleteSync(recursive: true);
    });
    final code = await runAgent(
      ['uninstall', '--home', home.path, '--yes'],
      environment: {
        'FS_SERVICES': 'none',
        'HOME': home.path,
        'FS_NODE_DATA_DIR': node.path,
      },
    );
    expect(code, 0);
  });
}
