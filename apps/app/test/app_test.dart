import 'package:app/src/services/preferences.dart';
import 'package:app/src/services/process_link.dart';
import 'package:daemon_kit/daemon_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  setUp(() {
    // Окно настольного размера: навигация с подписями.
    TestWidgetsFlutterBinding.ensureInitialized()
      ..platformDispatcher.views.first.physicalSize = const Size(1280, 900)
      ..platformDispatcher.views.first.devicePixelRatio = 1;
  });

  Future<void> pump(
    WidgetTester tester,
    FakeProcess agent,
    FakeProcess node, {
    Preferences? preferences,
    Locale locale = const Locale('ru'),
  }) async {
    await tester.pumpWidget(
      testApp(
        agent,
        node,
        preferences: (preferences ?? Preferences())..locale = locale,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('обзор: состояние агента и хранителя, бэкап сейчас', (
    tester,
  ) async {
    final agent = FakeProcess(
      status: agentStatus(
        lastBackup: {'finishedAt': '2026-10-27T09:00:00Z', 'outcome': 'ok'},
        nextBackupAt: '2999-01-01T10:00:00Z',
      ),
    );
    final node = FakeProcess(status: nodeStatus());
    await pump(tester, agent, node);
    expect(find.text('Обзор'), findsWidgets);
    expect(find.text('Ждёт расписания'), findsOneWidget);
    expect(find.textContaining('успешно'), findsOneWidget);
    expect(find.text('работает'), findsOneWidget);
    await tester.tap(find.text('Сделать бэкап сейчас'));
    await tester.pump();
    expect(agent.calls.single.$1, 'backup');

    // Идёт бэкап: прогресс, кнопка бэкапа недоступна.
    agent.update(
      status: agentStatus(
        status: 'working',
        job: {
          'kind': 'backup',
          'progress': {'files': 5, 'bytesRead': 3 << 20},
        },
      ),
    );
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('5 файлов, прочитано 3,0 МиБ'), findsOneWidget);
    final button = tester.widget<ButtonStyleButton>(
      find.ancestor(
        of: find.text('Сделать бэкап сейчас'),
        matching: find.bySubtype<ButtonStyleButton>(),
      ),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('процесс перезапускается: полоса о связи и возврат', (
    tester,
  ) async {
    final agent = FakeProcess(status: agentStatus());
    final node = FakeProcess(state: LinkState.unavailable);
    await pump(tester, agent, node);
    expect(find.text('Агент бэкапа не запущен'), findsNothing);
    expect(
      find.text('Роль хранителя не включена или служба не запущена.'),
      findsOneWidget,
    );

    agent.update(state: LinkState.unavailable);
    await tester.pump();
    expect(find.text('Агент бэкапа не запущен'), findsOneWidget);
    // Последнее известное состояние остаётся, но кнопки недоступны.
    expect(find.text('Ждёт расписания'), findsOneWidget);
    agent.update(state: LinkState.connecting);
    await tester.pump();
    expect(find.text('Агент бэкапа: подключение…'), findsOneWidget);
    agent.update(
      state: LinkState.connected,
      status: agentStatus(status: 'paused'),
    );
    await tester.pump();
    expect(find.textContaining('Агент бэкапа'), findsWidgets);
    expect(find.text('Агент бэкапа не запущен'), findsNothing);
    expect(find.text('Пауза'), findsWidgets);
    await tester.tap(find.text('Продолжить'));
    await tester.pump();
    expect(agent.calls.last.$1, 'resume');
  });

  testWidgets('нужен пароль: диалог, неверный пароль, открыто', (tester) async {
    final agent = FakeProcess(
      status: agentStatus(status: 'waitingForKeys'),
      answer: (method, params) async {
        if (params['password'] != 'верный') {
          throw const ControlException('wrong_password', 'неверный пароль');
        }
        return {'remembered': true};
      },
    );
    await pump(tester, agent, FakeProcess(status: nodeStatus()));
    expect(find.text('Бэкап ждёт пароль'), findsOneWidget);
    await tester.tap(find.text('Ввести пароль'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'не тот');
    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();
    expect(find.text('Неверный пароль'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'верный');
    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(agent.calls.last.$2, {'password': 'верный', 'remember': true});
  });

  testWidgets('переключение языка и темы в настройках', (tester) async {
    final prefs = Preferences();
    await pump(
      tester,
      FakeProcess(status: agentStatus()),
      FakeProcess(status: nodeStatus()),
      preferences: prefs,
    );
    await tester.tap(find.text('Настройки'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(prefs.locale, const Locale('en'));
    expect(find.text('Settings'), findsWidgets);
    expect(find.text('Overview'), findsOneWidget);
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(prefs.themeMode, ThemeMode.dark);
    final context = tester.element(find.text('Settings').first);
    expect(Theme.of(context).brightness, Brightness.dark);
    await tester.tap(find.text('Overview'));
    await tester.pumpAndSettle();
    expect(find.text('Back up now'), findsOneWidget);
  });

  testWidgets('разделы: бэкап, восстановление, хранитель', (tester) async {
    final agent = FakeProcess(
      status: agentStatus(),
      answer: (method, _) async => method == 'snapshots'
          ? {
              'snapshots': [
                {
                  'id': 'ab' * 32,
                  'createdAt': '2026-10-27T09:00:00Z',
                  'paths': ['/home/user/Документы'],
                  'files': 21,
                  'bytes': 1536,
                },
              ],
            }
          : const {},
    );
    await pump(tester, agent, FakeProcess(status: nodeStatus()));
    await tester.tap(find.text('Бэкап').first);
    await tester.pumpAndSettle();
    expect(find.text('/home/user/Документы'), findsOneWidget);
    expect(find.text('раз в час'), findsOneWidget);

    await tester.tap(find.text('Восстановление'));
    await tester.pumpAndSettle();
    expect(agent.calls.last.$1, 'snapshots');
    expect(find.textContaining('21 файл · 1,5 КиБ'), findsOneWidget);

    await tester.tap(find.text('Хранитель'));
    await tester.pumpAndSettle();
    expect(find.text('2,0 ТиБ'), findsOneWidget);
    expect(find.text('прямое'), findsOneWidget);
  });
}
