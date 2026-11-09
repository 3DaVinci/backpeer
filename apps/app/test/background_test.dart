// Задачи 5.6.1, 5.6.2, 5.6.4: меню значка в трее по состоянию агента и его
// команды, раздел «Фоновая работа» в настройках, хранитель без входа.

import 'package:app/src/services/preferences.dart';
import 'package:app/src/services/process_link.dart';
import 'package:daemon_kit/daemon_kit.dart' show ServiceState;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized()
      ..platformDispatcher.views.first.physicalSize = const Size(1280, 1400)
      ..platformDispatcher.views.first.devicePixelRatio = 1;
  });

  testWidgets('значок в трее: состояние, бэкап сейчас, пауза и '
      'продолжение, нет связи', (tester) async {
    final agent = FakeProcess(status: agentStatus());
    final tray = FakeTray();
    await tester.pumpWidget(
      testApp(
        agent,
        FakeProcess(status: nodeStatus()),
        preferences: Preferences()..locale = const Locale('ru'),
        tray: tray,
      ),
    );
    await tester.pumpAndSettle();
    expect(tray.status, 'Агент бэкапа: Ждёт расписания');
    expect(tray.items.map((i) => i.id), [
      'backup',
      'pause',
      '-',
      'open',
      'quit',
    ]);
    expect(tray.item('backup').enabled, isTrue);

    tray.tap('backup');
    await tester.pumpAndSettle();
    expect(agent.calls.last.$1, 'backup');

    agent.update(status: agentStatus(status: 'working'));
    await tester.pumpAndSettle();
    expect(tray.status, 'Агент бэкапа: Работает');
    expect(tray.item('backup').enabled, isFalse);

    tray.tap('pause');
    await tester.pumpAndSettle();
    expect(agent.calls.last.$1, 'pause');
    agent.update(status: agentStatus(status: 'paused'));
    await tester.pumpAndSettle();
    expect(tray.item('resume').label, 'Продолжить');
    tray.tap('resume');
    await tester.pumpAndSettle();
    expect(agent.calls.last.$1, 'resume');

    // Меню не пересылается, если ничего не изменилось.
    final menus = tray.menus;
    agent.update(status: agentStatus(status: 'paused'));
    await tester.pumpAndSettle();
    expect(tray.menus, menus);

    agent.update(state: LinkState.unavailable);
    await tester.pumpAndSettle();
    expect(tray.status, 'Агент бэкапа не запущен');
    expect(tray.item('resume').enabled, isFalse);
    expect(tray.item('open').enabled, isTrue);
  });

  testWidgets('нет трея — меню не задаётся', (tester) async {
    final tray = FakeTray(isAvailable: false);
    await tester.pumpWidget(
      testApp(
        FakeProcess(status: agentStatus()),
        FakeProcess(status: nodeStatus()),
        preferences: Preferences()..locale = const Locale('ru'),
        tray: tray,
      ),
    );
    await tester.pumpAndSettle();
    expect(tray.menus, 0);
  });

  Future<void> openSettings(
    WidgetTester tester, {
    required FakeBackground background,
    required Preferences preferences,
    FakeTray? tray,
  }) async {
    await tester.pumpWidget(
      testApp(
        FakeProcess(status: agentStatus()),
        FakeProcess(status: nodeStatus()),
        preferences: preferences..locale = const Locale('ru'),
        tray: tray,
        background: background,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Настройки').first);
    await tester.pumpAndSettle();
  }

  testWidgets('фоновая работа: удаление службы с подтверждением, установка, '
      'значок при входе', (tester) async {
    final background = FakeBackground();
    final preferences = Preferences();
    await openSettings(
      tester,
      background: background,
      preferences: preferences,
      tray: FakeTray(),
    );
    expect(find.text('Фоновая работа'), findsOneWidget);
    expect(find.text('работает'), findsWidgets);

    await tester.ensureVisible(find.byKey(const ValueKey('service-remove')));
    await tester.tap(find.byKey(const ValueKey('service-remove')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('service-remove-confirm')));
    await tester.pumpAndSettle();
    expect(background.calls, ['uninstall']);
    expect(preferences.backgroundService, isFalse);
    expect(find.text('не установлена'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('service-install')));
    await tester.pumpAndSettle();
    expect(background.calls.last, 'install');
    expect(preferences.backgroundService, isTrue);

    await tester.ensureVisible(find.byKey(const ValueKey('tray-at-login')));
    await tester.tap(find.byKey(const ValueKey('tray-at-login')));
    await tester.pumpAndSettle();
    expect(background.calls.last, 'autostart true');
    expect(background.autostart, isTrue);
  });

  testWidgets('фоновая работа: службы запускаются, останавливаются и '
      'перезапускаются', (tester) async {
    final background = FakeBackground(agentState: ServiceState.stopped);
    await openSettings(
      tester,
      background: background,
      preferences: Preferences(),
      tray: FakeTray(),
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('service-agent-start')),
    );
    await tester.tap(find.byKey(const ValueKey('service-agent-start')));
    await tester.pumpAndSettle();
    expect(background.calls.last, 'start agent');
    expect(background.agentState, ServiceState.running);

    IconButton button(String key) =>
        tester.widget<IconButton>(find.byKey(ValueKey(key)));
    // Запущенная служба не запускается повторно, но останавливается и
    // перезапускается.
    expect(button('service-agent-start').onPressed, isNull);
    expect(button('service-agent-stop').onPressed, isNotNull);

    await tester.tap(find.byKey(const ValueKey('service-agent-stop')));
    await tester.pumpAndSettle();
    expect(background.calls.last, 'stop agent');
    expect(background.agentState, ServiceState.stopped);

    await tester.tap(find.byKey(const ValueKey('service-agent-restart')));
    await tester.pumpAndSettle();
    expect(background.calls.last, 'restart agent');
    expect(background.agentState, ServiceState.running);

    await tester.tap(find.byKey(const ValueKey('service-node-stop')));
    await tester.pumpAndSettle();
    expect(background.calls.last, 'stop node');
    expect(background.nodeState, ServiceState.stopped);
  });

  testWidgets('фоновая работа: службы не установлены — кнопки неактивны, '
      'подсказка про хранителя', (tester) async {
    final background = FakeBackground(
      agentState: ServiceState.notInstalled,
      nodeState: ServiceState.notInstalled,
    );
    await openSettings(
      tester,
      background: background,
      preferences: Preferences(),
      tray: FakeTray(),
    );
    expect(find.textContaining('Роль хранителя выключена'), findsOneWidget);
    for (final key in [
      'service-agent-start',
      'service-agent-stop',
      'service-agent-restart',
      'service-node-start',
      'service-node-stop',
      'service-node-restart',
    ]) {
      expect(
        tester.widget<IconButton>(find.byKey(ValueKey(key))).onPressed,
        isNull,
        reason: key,
      );
    }
    expect(find.byKey(const ValueKey('service-install')), findsOneWidget);
  });

  testWidgets('фоновая работа: служб нет, трея нет — подсказки', (
    tester,
  ) async {
    await openSettings(
      tester,
      background: FakeBackground(available: false),
      preferences: Preferences(),
      tray: FakeTray(isAvailable: false),
    );
    expect(find.textContaining('запускать вручную'), findsOneWidget);
    expect(find.textContaining('расширение AppIndicator'), findsOneWidget);
    expect(find.byKey(const ValueKey('tray-at-login')), findsNothing);
  });

  testWidgets('хранитель без входа не разрешён — команда для '
      'администратора', (tester) async {
    final agent = FakeProcess(
      status: agentStatus(),
      answer: (method, params) async => switch (method) {
        'keeper.info' => {
          'enabled': true,
          'settings': {'storageDir': '/data', 'quotaBytes': 1 << 30},
          'dataDir': '/data',
          'defaultStorageDir': '/data',
          'nodeExecutable': '/opt/node',
          'launcher': 'systemd',
          'linger': {
            'enabled': false,
            'problem': 'Access denied',
            'command': 'sudo loginctl enable-linger user',
          },
          'minQuotaBytes': 1 << 30,
        },
        _ => const {},
      },
    );
    await tester.pumpWidget(
      testApp(
        agent,
        FakeProcess(status: nodeStatus()),
        preferences: Preferences()..locale = const Locale('ru'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Хранитель').first);
    await tester.pumpAndSettle();
    expect(find.text('Хранитель без входа в систему'), findsOneWidget);
    expect(find.text('sudo loginctl enable-linger user'), findsOneWidget);
  });
}
