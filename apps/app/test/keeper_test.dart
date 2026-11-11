// Экран «Хранитель» (задачи 5.5.1, 5.5.2) на подделках агента и `node`:
// включение роли, статистика, сведения координатора, подсказка про порт,
// выключение.

import 'package:app/src/services/preferences.dart';
import 'package:app/src/services/process_link.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

const int _gb = 1000 * 1000 * 1000;

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized()
      ..platformDispatcher.views.first.physicalSize = const Size(1280, 2000)
      ..platformDispatcher.views.first.devicePixelRatio = 1;
  });

  FakeProcess agent({
    Map<String, Object?>? settings,
    int available = 400 * _gb,
  }) => FakeProcess(
    status: agentStatus(),
    answer: (method, params) async => switch (method) {
      'keeper.info' => {
        'enabled': settings != null,
        'settings': settings,
        'dataDir': '/home/user/.local/share/backpeer/node',
        'defaultStorageDir': '/home/user/.local/share/backpeer/node',
        'minQuotaBytes': 1 << 30,
      },
      'keeper.disk' => {'path': params['path'], 'availableBytes': available},
      'keeper.enable' => {'started': true, 'nodeId': 'ab' * 32},
      'keeper.disable' => {'enabled': false, 'stopped': true},
      _ => const {},
    },
  );

  Future<void> openKeeper(
    WidgetTester tester,
    FakeProcess agent,
    FakeProcess node, {
    String? picked,
  }) async {
    await tester.pumpWidget(
      testApp(
        agent,
        node,
        preferences: Preferences()..locale = const Locale('ru'),
        pickFolder: ({initialDirectory}) async => picked,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Хранитель').first);
    await tester.pumpAndSettle();
  }

  testWidgets('включение: папка, место, пределы, объяснение', (tester) async {
    final a = agent();
    final node = FakeProcess(state: LinkState.unavailable);
    await openKeeper(tester, a, node, picked: '/mnt/disk2/fs');
    expect(find.textContaining('не может их прочитать'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('keeper-enable')));
    await tester.pumpAndSettle();
    expect(a.last('keeper.disk'), {
      'path': '/home/user/.local/share/backpeer/node',
    });
    // Сразу — половина свободного, не больше 500 ГБ.
    expect(find.text('200'), findsOneWidget);
    expect(find.textContaining('Свободно на диске: 372,5 ГиБ'), findsOneWidget);

    await tester.tap(find.byTooltip('Выбрать папку'));
    await tester.pumpAndSettle();
    expect(a.last('keeper.disk'), {'path': '/mnt/disk2/fs'});
    await tester.enterText(find.byKey(const ValueKey('keeper-quota')), '150');
    await tester.tap(find.byKey(const ValueKey('speed-Отдача')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('5,0 МиБ/с').last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('speed-В рабочие часы (пн–пт, 9–18)')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('1,0 МиБ/с').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('keeper-submit')));
    await tester.pumpAndSettle();
    expect(a.last('keeper.enable'), {
      'storageDir': '/mnt/disk2/fs',
      'quotaBytes': 150 * _gb,
      'uploadBytesPerSecond': 5 << 20,
      'downloadBytesPerSecond': 0,
      'schedule': ['mon-fri 09:00-18:00 upload=1048576 download=1048576'],
    });
    expect(find.text('Роль хранителя включена'), findsOneWidget);
  });

  testWidgets('места меньше квоты — включить нельзя', (tester) async {
    final a = agent(available: 50 * _gb);
    await openKeeper(tester, a, FakeProcess(state: LinkState.unavailable));
    await tester.tap(find.byKey(const ValueKey('keeper-enable')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('keeper-quota')), '100');
    await tester.pumpAndSettle();
    expect(find.text('Больше, чем свободно на диске'), findsOneWidget);
    final submit = tester.widget<FilledButton>(
      find.byKey(const ValueKey('keeper-submit')),
    );
    expect(submit.onPressed, isNull);
  });

  testWidgets('статистика, сведения сервера, способ подключения, выключение', (
    tester,
  ) async {
    final a = agent(
      settings: {
        'enabled': true,
        'storageDir': '/mnt/disk2/fs',
        'quotaBytes': 150 * _gb,
        'uploadBytesPerSecond': 0,
        'downloadBytesPerSecond': 0,
        'schedule': <Object?>[],
      },
    );
    final node = FakeProcess(
      status: {
        ...nodeStatus(),
        'storageDir': '/mnt/disk2/fs',
        'freeBytes': 100 << 30,
        'diskAvailableBytes': 300 << 30,
        'listen': {'port': 7340},
        'reachability': {
          'reachable': false,
          'checkedAt': '2026-10-28T09:00:00Z',
        },
        'udp': {'symmetricNat': false},
        'relay': {'connected': true},
        'portMapping': {'lastError': 'роутер не отвечает по UPnP'},
        'coordinator': {
          'registered': true,
          'standing': {
            'availability': 0.97,
            'reputation': 0.5,
            'onProbation': true,
            'probationEndsAt': '2026-10-31T10:00:00Z',
            'auditsPassed': 12,
            'auditsFailed': 1,
            'excluded': false,
          },
        },
      },
      answer: (method, params) async => switch (method) {
        'stats' => {'bytesSent': 1 << 30, 'bytesReceived': 2 << 30},
        _ => const {},
      },
    );
    await openKeeper(tester, a, node);
    expect(find.text('Статистика'), findsOneWidget);
    expect(find.text('/mnt/disk2/fs'), findsOneWidget);
    expect(find.text('отдано 1,0 ГиБ, принято 2,0 ГиБ'), findsOneWidget);
    expect(find.text('по UDP после сведения; через relay'), findsOneWidget);
    expect(find.byKey(const ValueKey('port-hint')), findsOneWidget);
    expect(find.textContaining('роутер не отвечает по UPnP'), findsOneWidget);
    expect(find.textContaining('97'), findsOneWidget);
    expect(find.textContaining('испытательный срок до'), findsOneWidget);
    expect(find.text('пройдено 12, провалено 1'), findsOneWidget);
    expect(find.textContaining('баланс бартера'), findsOneWidget);
    // Пределы сети видны в статистике и меняются тем же диалогом.
    expect(find.text('Пределы скорости'), findsOneWidget);
    expect(
      find.text('Отдача: без предела, Приём: без предела'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('keeper-limits-edit')));
    await tester.pumpAndSettle();
    expect(find.text('Настройки хранителя'), findsOneWidget);
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    // Выход с переносом фрагментов — позже (4.4.1): кнопка недоступна.
    final leave = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Выйти из роли'),
    );
    expect(leave.onPressed, isNull);

    await tester.tap(find.byKey(const ValueKey('keeper-stop')));
    await tester.pumpAndSettle();
    expect(find.textContaining('фрагменты останутся на диске'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('keeper-stop-confirm')));
    await tester.pumpAndSettle();
    expect(a.calls.any((c) => c.$1 == 'keeper.disable'), isTrue);
  });

  testWidgets('роль включена, служба не запущена — запустить', (tester) async {
    final settings = {
      'enabled': true,
      'storageDir': '/mnt/disk2/fs',
      'quotaBytes': 150 * _gb,
    };
    final a = agent(settings: settings);
    await openKeeper(tester, a, FakeProcess(state: LinkState.unavailable));
    expect(
      find.text('Роль включена, но служба хранителя не запущена.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Запустить'));
    await tester.pumpAndSettle();
    expect(a.last('keeper.enable'), settings);
  });
}
