// Экран «Бэкап» и здоровье данных (задачи 5.3.1–5.3.5) на подделке агента.

import 'package:app/src/services/preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized()
      ..platformDispatcher.views.first.physicalSize = const Size(1280, 2400)
      ..platformDispatcher.views.first.devicePixelRatio = 1;
  });

  Future<void> openBackup(
    WidgetTester tester,
    FakeProcess agent, {
    String? picked,
  }) async {
    await tester.pumpWidget(
      testApp(
        agent,
        FakeProcess(status: nodeStatus()),
        preferences: Preferences()..locale = const Locale('ru'),
        pickFolder: ({initialDirectory}) async => picked,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Бэкап').first);
    await tester.pumpAndSettle();
  }

  testWidgets('папки, наборы исключений, свои правила, оценка объёма', (
    tester,
  ) async {
    final agent = FakeProcess(
      status: agentStatus(),
      answer: (method, params) async => switch (method) {
        'estimate' => {
          'files': 1234,
          'bytes': 5 << 30,
          'excluded': 17,
          'skipped': 2,
          'truncated': false,
        },
        _ => const {},
      },
    );
    await openBackup(tester, agent, picked: '/home/user/Фото');

    await tester.tap(find.text('Добавить папку'));
    await tester.pumpAndSettle();
    expect(agent.last('settings')['paths'], [
      '/home/user/Документы',
      '/home/user/Фото',
    ]);
    await tester.tap(find.byTooltip('Убрать из бэкапа'));
    await tester.pumpAndSettle();
    expect(agent.last('settings')['paths'], isEmpty);

    // Наборы: включены три по умолчанию; выключаем кеши, включаем сборку.
    await tester.tap(find.text('Кеши программ'));
    await tester.pumpAndSettle();
    expect(agent.last('settings')['excludePresets'], ['temporary', 'trash']);
    await tester.tap(find.text('Зависимости и сборка программ'));
    await tester.pumpAndSettle();
    expect(agent.last('settings')['excludePresets'], [
      'temporary',
      'caches',
      'trash',
      'development',
    ]);

    await tester.tap(find.widgetWithText(TextButton, 'Добавить правило'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '*.iso');
    await tester.tap(find.widgetWithText(FilledButton, 'Добавить правило'));
    await tester.pumpAndSettle();
    expect(agent.last('settings')['excludes'], ['*.iso']);

    expect(find.textContaining('до его запуска'), findsOneWidget);
    await tester.tap(find.text('Оценить объём'));
    await tester.pumpAndSettle();
    expect(find.text('1234 файла, 5,0 ГиБ'), findsOneWidget);
    expect(find.text('Исключено правилами: 17'), findsOneWidget);
    expect(find.text('Нет доступа или особые файлы: 2'), findsOneWidget);
  });

  testWidgets('расписание: частота, часы, только от сети, проверка', (
    tester,
  ) async {
    final agent = FakeProcess(status: agentStatus());
    await openBackup(tester, agent);
    expect(find.text('раз в час'), findsOneWidget);
    await tester.tap(find.text('раз в час'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('раз в неделю').last);
    await tester.pumpAndSettle();
    expect(agent.last('settings'), {'intervalMinutes': 7 * 24 * 60});

    await tester.tap(find.text('Только в заданные часы'));
    await tester.pumpAndSettle();
    expect(agent.last('settings'), {
      'hours': {'from': 22, 'to': 7},
    });
    await tester.tap(find.text('Только от сети'));
    await tester.pumpAndSettle();
    expect(agent.last('settings'), {'onlyOnAcPower': true});

    // Часы заданы — выбор начала окна.
    agent.update(
      status: agentStatus(
        settings: {
          'hours': {'from': 22, 'to': 7},
          'onlyOnAcPower': true,
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('22:00'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1:00').last);
    await tester.pumpAndSettle();
    expect(agent.last('settings'), {
      'hours': {'from': 1, 'to': 7},
    });
    expect(find.textContaining('окно можно закрыть'), findsOneWidget);
  });

  testWidgets('хранение снимков: изменить, хранить все', (tester) async {
    final agent = FakeProcess(status: agentStatus());
    await openBackup(tester, agent);
    final save = find.widgetWithText(FilledButton, 'Сохранить');
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    await tester.enterText(find.widgetWithText(TextField, 'Дневных'), '30');
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(agent.last('settings'), {
      'retention': {
        'last': 1,
        'hourly': 24,
        'daily': 30,
        'weekly': 4,
        'monthly': 12,
      },
    });
    await tester.enterText(find.widgetWithText(TextField, 'Последних'), '0');
    await tester.pumpAndSettle();
    expect(find.textContaining('хотя бы 1'), findsOneWidget);
    expect(tester.widget<FilledButton>(save).onPressed, isNull);

    await tester.tap(find.text('Хранить все снимки'));
    await tester.pumpAndSettle();
    expect(agent.last('settings'), {'retention': null});
  });

  testWidgets('ход бэкапа с оценкой, история с остановленным и '
      'продолженным бэкапом, пропущенные файлы', (tester) async {
    final history = [
      {
        'kind': 'backup',
        'trigger': 'resume',
        'outcome': 'partial',
        'startedAt': '2026-10-27T10:00:00Z',
        'finishedAt': '2026-10-27T10:05:00Z',
        'result': {
          'files': 120,
          'bytes': 3 << 20,
          'newBytes': 1 << 20,
          'skipped': 1,
          'skippedFiles': [
            {
              'path': '/home/user/Документы/закрыто.txt',
              'reason': 'error',
              'detail': 'Permission denied',
            },
          ],
          'retention': {'kept': 5, 'forgotten': 2, 'bytesFreed': 4 << 20},
        },
      },
      {
        'kind': 'backup',
        'trigger': 'schedule',
        'outcome': 'cancelled',
        'startedAt': '2026-10-27T09:00:00Z',
        'finishedAt': '2026-10-27T09:01:00Z',
        'result': {'reason': 'on_battery', 'continues': true},
      },
    ];
    final agent = FakeProcess(
      status: agentStatus(
        status: 'working',
        job: {
          'kind': 'backup',
          'trigger': 'resume',
          'progress': {
            'files': 60,
            'bytes': 1 << 30,
            'bytesRead': 1 << 29,
            'doneBytes': 1 << 30,
            'totalFiles': 120,
            'totalBytes': 4 << 30,
            'bytesPerSecond': 10 << 20,
            'etaMs': 5 * 60 * 1000,
          },
        },
      ),
      answer: (method, params) async =>
          method == 'history' ? {'jobs': history} : const {},
    );
    await openBackup(tester, agent);
    expect(find.text('Текущий бэкап'), findsOneWidget);
    expect(find.text('Продолжение прерванного бэкапа'), findsOneWidget);
    expect(
      find.text('60 файлов из 120, 1,0 ГиБ из 4,0 ГиБ, 25%'),
      findsOneWidget,
    );
    expect(find.text('10,0 МиБ/с, осталось около 5 минут'), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, closeTo(0.25, 1e-9));
    await tester.tap(find.widgetWithText(OutlinedButton, 'Пауза'));
    await tester.pump();
    expect(agent.calls.last.$1, 'pause');

    expect(
      find.text('Бэкап — с предупреждениями (продолжение)'),
      findsOneWidget,
    );
    expect(find.textContaining('пропущен 1 файл'), findsOneWidget);
    expect(find.textContaining('удалено 2 старых снимка'), findsOneWidget);
    expect(find.text('Бэкап — остановлен (по расписанию)'), findsOneWidget);
    expect(
      find.textContaining('переход на батарею, продолжится с того же места'),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Подробности').first);
    await tester.pumpAndSettle();
    expect(find.text('Пропущенные файлы'), findsOneWidget);
    expect(find.text('/home/user/Документы/закрыто.txt'), findsOneWidget);
    expect(
      find.text('нет доступа или ошибка чтения: Permission denied'),
      findsOneWidget,
    );
    expect(find.textContaining('освобождено 4,0 МиБ'), findsOneWidget);
    await tester.tap(find.text('Закрыть'));
    await tester.pumpAndSettle();

    // Задание закончилось — история загружается снова.
    final before = agent.calls.where((c) => c.$1 == 'history').length;
    agent.emit('job_finished', {'kind': 'backup', 'outcome': 'ok'});
    await tester.pumpAndSettle();
    expect(agent.calls.where((c) => c.$1 == 'history').length, before + 1);
  });

  testWidgets('запуск бэкапа: всех папок и отдельной', (tester) async {
    final agent = FakeProcess(
      status: agentStatus(
        settings: {
          'paths': ['/home/user/Документы', '/home/user/Фото'],
        },
      ),
    );
    await openBackup(tester, agent);

    await tester.tap(find.widgetWithText(FilledButton, 'Сделать бэкап сейчас'));
    await tester.pump();
    expect(agent.last('backup'), isEmpty);

    await tester.tap(find.byTooltip('Сделать бэкап этой папки').first);
    await tester.pump();
    expect(agent.last('backup'), {
      'paths': ['/home/user/Документы'],
    });
    await tester.tap(find.byTooltip('Сделать бэкап этой папки').last);
    await tester.pump();
    expect(agent.last('backup'), {
      'paths': ['/home/user/Фото'],
    });

    // Идёт задание — запускать нечего.
    agent.update(
      status: agentStatus(
        status: 'working',
        job: {'kind': 'verify', 'trigger': 'manual', 'progress': {}},
        settings: {
          'paths': ['/home/user/Документы'],
        },
      ),
    );
    await tester.pump();
    final start = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Сделать бэкап сейчас'),
    );
    expect(start.onPressed, isNull);
    expect(
      tester
          .widget<IconButton>(
            find.ancestor(
              of: find.byTooltip('Сделать бэкап этой папки'),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
      isNull,
    );

    // Пауза: задание остановлено, но с этого экрана его видно и можно
    // продолжить.
    agent.update(status: agentStatus(status: 'paused'));
    await tester.pump();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Продолжить'));
    await tester.pump();
    expect(agent.last('resume'), isEmpty);
  });

  testWidgets('прогресс: полоса по сделанному, а не по обходу', (tester) async {
    final agent = FakeProcess(
      status: agentStatus(
        status: 'working',
        job: {
          'kind': 'backup',
          'trigger': 'manual',
          'progress': {
            'files': 40,
            'bytes': 3 << 30,
            'bytesRead': 3 << 30,
            'doneBytes': 1 << 30,
            'totalFiles': 500,
            'totalBytes': 4 << 30,
            'bytesPerSecond': 10 << 20,
            'etaMs': 3 * 60 * 1000,
            'stage': 'walking',
            'currentFile': '/home/user/Документы/большой.iso',
          },
        },
      ),
    );
    await openBackup(tester, agent);
    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, closeTo(0.25, 1e-9));
    expect(
      find.text('40 файлов из 500, 1,0 ГиБ из 4,0 ГиБ, 25%'),
      findsOneWidget,
    );
    expect(
      find.text('Читаем: /home/user/Документы/большой.iso'),
      findsOneWidget,
    );

    // Сегменты отправляются — файл уже не читается.
    agent.update(
      status: agentStatus(
        status: 'working',
        job: {
          'kind': 'backup',
          'trigger': 'manual',
          'progress': {
            'files': 500,
            'doneBytes': 2 << 30,
            'totalFiles': 500,
            'totalBytes': 4 << 30,
            'stage': 'storing',
            'segmentsStored': 3,
          },
        },
      ),
    );
    await tester.pump();
    expect(
      find.text('Отправляем данные на узлы (сегментов: 3)'),
      findsOneWidget,
    );
  });

  testWidgets('пределы скорости сети: выбор сохраняется', (tester) async {
    final agent = FakeProcess(status: agentStatus());
    await openBackup(tester, agent);

    await tester.tap(
      find.byKey(const ValueKey('network-uploadBytesPerSecond')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('1,0 МиБ/с').last);
    await tester.pumpAndSettle();
    expect(agent.last('settings'), {'uploadBytesPerSecond': 1 << 20});
  });

  testWidgets('удаление данных бэкапа: все снимки с подтверждением', (
    tester,
  ) async {
    final agent = FakeProcess(status: agentStatus());
    await openBackup(tester, agent);

    await tester.tap(find.byKey(const ValueKey('delete-all')));
    await tester.pumpAndSettle();
    expect(find.text('Удалить все снимки этого компьютера?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('delete-all-confirm')));
    await tester.pumpAndSettle();
    expect(agent.last('forget'), {'all': true});
  });

  testWidgets('удаление данных бэкапа блокирует кнопку сразу', (tester) async {
    final agent = FakeProcess(
      status: agentStatus(),
      answer: (method, params) async =>
          method == 'forget' ? {'started': true} : const {},
    );
    await openBackup(tester, agent);

    await tester.tap(find.byKey(const ValueKey('delete-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('delete-all-confirm')));
    // Не pumpAndSettle: неопределённый индикатор хода анимируется вечно.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(agent.last('forget'), {'all': true});

    // Задание ещё не пришло в status, но второй запуск уже невозможен.
    OutlinedButton button() =>
        tester.widget<OutlinedButton>(find.byKey(const ValueKey('delete-all')));
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(button().onPressed, isNull);

    // Задание закончилось — кнопка снова доступна.
    agent.emit('job_finished', {'kind': 'forget'});
    await tester.pumpAndSettle();
    expect(button().onPressed, isNotNull);
  });

  testWidgets('здоровье: требует внимания с причинами, проверить сейчас', (
    tester,
  ) async {
    final agent = FakeProcess(
      status: agentStatus(
        health: {
          'state': 'attention',
          'reasons': [
            {
              'code': 'unrecoverable',
              'message': 'часть данных нельзя восстановить',
              'attention': true,
            },
            {'code': 'something_new', 'message': 'новая причина'},
          ],
        },
        lastVerify: {'finishedAt': '2026-10-27T09:00:00Z', 'outcome': 'failed'},
      ),
    );
    await tester.pumpWidget(
      testApp(
        agent,
        FakeProcess(status: nodeStatus()),
        preferences: Preferences()..locale = const Locale('ru'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Здоровье данных'), findsOneWidget);
    expect(find.text('Требует внимания'), findsOneWidget);
    expect(find.text('Часть данных нельзя восстановить'), findsOneWidget);
    expect(find.text('новая причина'), findsOneWidget);
    expect(find.textContaining('ошибка'), findsOneWidget);
    await tester.tap(find.text('Проверить сейчас'));
    await tester.pump();
    expect(agent.calls.last.$1, 'verify');

    agent.update(
      status: agentStatus(
        status: 'waitingForPower',
        health: {'state': 'ok', 'reasons': <Object?>[]},
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Всё в порядке'), findsOneWidget);
    expect(find.text('Ждёт питания от сети'), findsOneWidget);
  });
}
