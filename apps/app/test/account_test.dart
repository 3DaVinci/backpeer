import 'package:app/src/app.dart';
import 'package:app/src/app_scope.dart';
import 'package:app/src/services/preferences.dart';
import 'package:daemon_kit/daemon_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

/// Учётная запись в приложении (задачи 5.2.1–5.2.3): создание с
/// проверкой фразы и пароля, вход на новом устройстве с «восстановить
/// всё», настройки учётной записи и устройства.
void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized()
      ..platformDispatcher.views.first.physicalSize = const Size(1280, 1000)
      ..platformDispatcher.views.first.devicePixelRatio = 1;
  });

  const words = [
    'abandon', 'ability', 'able', 'about', 'above', 'absent', //
    'absorb', 'abstract', 'absurd', 'abuse', 'access', 'accident',
    'account', 'accuse', 'achieve', 'acid', 'acoustic', 'acquire',
    'across', 'act', 'action', 'actor', 'actress', 'actual',
  ];
  const strong = 'correct horse battery staple';

  Future<void> pump(
    WidgetTester tester,
    FakeProcess agent, {
    String coordinator = '',
  }) async {
    await tester.pumpWidget(
      App(
        services: AppServices(
          agent: agent,
          node: FakeProcess(status: nodeStatus()),
          preferences: Preferences()..locale = const Locale('ru'),
          coordinator: coordinator,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  bool enabled(WidgetTester tester, String label) => tester
      .widget<ButtonStyleButton>(
        find.ancestor(
          of: find.text(label),
          matching: find.bySubtype<ButtonStyleButton>(),
        ),
      )
      .enabled;

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> enter(WidgetTester tester, String key, String text) async {
    await tester.ensureVisible(find.byKey(ValueKey(key)));
    await tester.enterText(find.byKey(ValueKey(key)), text);
    await tester.pumpAndSettle();
  }

  /// Номера слов, которые просит экран проверки.
  List<int> asked(WidgetTester tester) => [
    for (final w in tester.widgetList<TextField>(find.byType(TextField)))
      if (w.key case ValueKey<String>(:final value)
          when value.startsWith('check'))
        int.parse(value.substring(5)),
  ];

  testWidgets('создание: слабый пароль и неподтверждённая фраза не дают '
      'продолжить', (tester) async {
    final agent = FakeProcess(
      status: agentStatus(configured: false),
      answer: (method, params) async => switch (method) {
        'account.new_phrase' => {'words': words, 'confirm': 3},
        'account.create' => {'remembered': true, 'accountId': 'ab' * 32},
        _ => const {},
      },
    );
    await pump(tester, agent);
    expect(find.text('Добро пожаловать в Backpeer'), findsOneWidget);
    // Без сервера вход по паролю недоступен.
    expect(
      tester
          .widget<ListTile>(find.widgetWithText(ListTile, 'Войти по паролю'))
          .enabled,
      isFalse,
    );
    await tap(tester, find.text('Создать учётную запись'));
    expect(find.text('Шаг 1 из 4'), findsOneWidget);
    expect(find.text('Без сервера'), findsOneWidget);
    await tap(tester, find.text('Далее'));

    // Пароль: слабый не принимается, средний — только с согласием.
    await enter(tester, 'newPassword', 'qwerty');
    await enter(tester, 'repeatPassword', 'qwerty');
    expect(find.text('Стойкость: слабый'), findsOneWidget);
    expect(find.text('Короче 12 символов'), findsOneWidget);
    expect(enabled(tester, 'Далее'), isFalse);
    await enter(tester, 'newPassword', 'dragon kitchen7');
    await enter(tester, 'repeatPassword', 'dragon kitchen7');
    expect(find.text('Стойкость: средний'), findsOneWidget);
    expect(enabled(tester, 'Далее'), isFalse);
    await tap(tester, find.byKey(const ValueKey('acceptWeak')));
    expect(enabled(tester, 'Далее'), isTrue);
    await enter(tester, 'newPassword', strong);
    expect(find.text('Пароли не совпадают'), findsOneWidget);
    expect(enabled(tester, 'Далее'), isFalse);
    await enter(tester, 'repeatPassword', strong);
    expect(find.text('Стойкость: стойкий'), findsOneWidget);
    await tap(tester, find.text('Далее'));

    // Фраза: 24 слова, дальше — только после отметки «записана».
    expect(agent.calls.last.$1, 'account.new_phrase');
    expect(find.text('Фраза восстановления'), findsOneWidget);
    expect(find.byKey(const ValueKey('word24')), findsOneWidget);
    expect(find.text('Как хранить фразу'), findsOneWidget);
    expect(enabled(tester, 'Далее'), isFalse);
    await tap(tester, find.byKey(const ValueKey('phraseWritten')));
    await tap(tester, find.text('Далее'));

    // Проверка: неверное слово — создать нельзя.
    final positions = asked(tester);
    expect(positions, hasLength(3));
    for (final p in positions) {
      await enter(tester, 'check$p', 'zzzzzzzzzz');
    }
    expect(find.text('Не то слово'), findsNWidgets(3));
    expect(enabled(tester, 'Создать учётную запись'), isFalse);
    for (final p in positions) {
      await enter(tester, 'check$p', words[p - 1].toUpperCase());
    }
    expect(enabled(tester, 'Создать учётную запись'), isTrue);
    await tap(tester, find.text('Создать учётную запись'));
    final (method, params) = agent.calls.last;
    expect(method, 'account.create');
    expect(params['password'], strong);
    expect(params['confirm'], {for (final p in positions) '$p': words[p - 1]});
    expect(params.containsKey('coordinator'), isFalse);
    expect(find.text('Учётная запись создана'), findsOneWidget);

    agent.update(status: agentStatus());
    await tap(tester, find.text('Перейти к бэкапу'));
    expect(find.text('Обзор'), findsWidgets);
    expect(find.text('Сделать бэкап сейчас'), findsOneWidget);
  });

  testWidgets('создание с сервером: имя занято, режим без копии ключа', (
    tester,
  ) async {
    var taken = true;
    final agent = FakeProcess(
      status: agentStatus(configured: false),
      answer: (method, params) async {
        if (method == 'account.new_phrase') {
          return {'words': words, 'confirm': 3};
        }
        if (method == 'account.create' && taken) {
          taken = false;
          throw const ControlException('login_taken', 'занято');
        }
        return {'remembered': false};
      },
    );
    await pump(tester, agent, coordinator: 'https://coordinator.example');
    await tap(tester, find.text('Создать учётную запись'));
    expect(enabled(tester, 'Далее'), isFalse);
    await enter(tester, 'login', 'Я');
    expect(find.text('Недопустимое имя'), findsOneWidget);
    await enter(tester, 'login', 'Alice');
    await tap(tester, find.byKey(const ValueKey('keyCopyOff')));
    expect(find.text('Фраза станет единственным ключом'), findsOneWidget);
    await tap(tester, find.text('Далее'));
    await enter(tester, 'newPassword', strong);
    await enter(tester, 'repeatPassword', strong);
    await tap(tester, find.text('Далее'));
    await tap(tester, find.byKey(const ValueKey('phraseWritten')));
    await tap(tester, find.text('Далее'));
    for (final p in asked(tester)) {
      await enter(tester, 'check$p', words[p - 1]);
    }
    await tap(tester, find.text('Создать учётную запись'));
    // Имя занято — назад к имени, с ошибкой.
    expect(find.text('Это имя занято, выберите другое'), findsOneWidget);
    expect(agent.calls.last.$2['login'], 'alice');
    expect(agent.calls.last.$2['keyCopy'], isFalse);
    expect(agent.calls.last.$2['coordinator'], 'https://coordinator.example');
    await enter(tester, 'login', 'alice2');
    await tap(tester, find.text('Далее'));
    await enter(tester, 'newPassword', strong);
    await enter(tester, 'repeatPassword', strong);
    await tap(tester, find.text('Далее'));
    await tap(tester, find.text('Далее'));
    await tap(tester, find.text('Создать учётную запись'));
    expect(agent.calls.last.$2['login'], 'alice2');
    expect(find.text('Учётная запись создана'), findsOneWidget);
    // Хранилище ключей недоступно — пользователь знает о пароле.
    expect(find.text('Бэкап ждёт пароль'), findsOneWidget);

    // Следующий шаг — хранитель; «Позже» — к разделам.
    agent.update(status: agentStatus());
    await tap(tester, find.text('Далее'));
    expect(find.text('Станьте хранителем'), findsOneWidget);
    await tap(tester, find.byKey(const ValueKey('keeper-later')));
    expect(agent.calls.where((c) => c.$1 == 'keeper.enable'), isEmpty);
    expect(find.text('Сделать бэкап сейчас'), findsOneWidget);
  });

  testWidgets('после создания с сервером первым настраивается хранитель', (
    tester,
  ) async {
    final agent = FakeProcess(
      status: agentStatus(configured: false),
      answer: (method, params) async => switch (method) {
        'account.new_phrase' => {'words': words, 'confirm': 3},
        'account.create' => {'remembered': true, 'accountId': 'ab' * 32},
        'keeper.info' => {
          'enabled': false,
          'settings': null,
          'defaultStorageDir': '/home/user/.local/share/backpeer/node',
          'minQuotaBytes': 1 << 30,
        },
        'keeper.disk' => {
          'path': params['path'],
          'availableBytes': 400000000000,
        },
        'keeper.enable' => {'started': true, 'nodeId': 'ab' * 32},
        _ => const {},
      },
    );
    await pump(tester, agent, coordinator: 'https://coordinator.example');
    await tap(tester, find.text('Создать учётную запись'));
    await enter(tester, 'login', 'alice');
    await tap(tester, find.text('Далее'));
    await enter(tester, 'newPassword', strong);
    await enter(tester, 'repeatPassword', strong);
    await tap(tester, find.text('Далее'));
    await tap(tester, find.byKey(const ValueKey('phraseWritten')));
    await tap(tester, find.text('Далее'));
    for (final p in asked(tester)) {
      await enter(tester, 'check$p', words[p - 1]);
    }
    await tap(tester, find.text('Создать учётную запись'));
    expect(find.text('Перейти к бэкапу'), findsNothing);
    agent.update(status: agentStatus());
    await tap(tester, find.text('Далее'));

    expect(find.text('Станьте хранителем'), findsOneWidget);
    expect(find.textContaining('не может их прочитать'), findsOneWidget);
    expect(agent.calls.last.$1, 'keeper.info');
    await tap(tester, find.byKey(const ValueKey('keeper-enable')));
    // Половина свободного, не больше 500 ГБ.
    expect(find.text('200'), findsOneWidget);
    await tap(tester, find.byKey(const ValueKey('keeper-submit')));
    final (method, params) = agent.calls.last;
    expect(method, 'keeper.enable');
    expect(params['storageDir'], '/home/user/.local/share/backpeer/node');
    expect(params['quotaBytes'], 200 * 1000 * 1000 * 1000);
    expect(find.text('Роль хранителя включена'), findsOneWidget);
    expect(find.text('Сделать бэкап сейчас'), findsOneWidget);
  });

  testWidgets('новый компьютер: вход по паролю, последний снимок, '
      'восстановить всё', (tester) async {
    final agent = FakeProcess(
      status: agentStatus(configured: false),
      answer: (method, params) async => switch (method) {
        'account.login' when params['password'] != strong =>
          throw const ControlException('unauthenticated', 'нет'),
        'account.login' => {'remembered': true, 'indexes': 2},
        'snapshots' => {
          'snapshots': [
            {
              'id': 'cd' * 32,
              'sequence': 2,
              'createdAt': '2026-10-27T09:00:00Z',
              'hostname': 'laptop',
              'paths': ['/home/user/Документы'],
              'files': 21,
              'bytes': 1536,
            },
            {
              'id': 'ab' * 32,
              'sequence': 1,
              'createdAt': '2026-10-20T09:00:00Z',
              'hostname': 'laptop',
              'paths': ['/home/user/Документы'],
              'files': 20,
              'bytes': 1024,
            },
          ],
          'warnings': <String>[],
        },
        'restore' => {'started': true},
        _ => const {},
      },
    );
    await pump(tester, agent, coordinator: 'https://coordinator.example');
    await tap(tester, find.text('Войти по паролю'));
    expect(enabled(tester, 'Войти'), isFalse);
    await enter(tester, 'login', 'alice');
    await enter(tester, 'password', 'не тот');
    await tap(tester, find.text('Войти'));
    expect(find.textContaining('Неверное имя или пароль'), findsOneWidget);
    await enter(tester, 'password', strong);
    await tap(tester, find.text('Войти'));
    expect(agent.calls.where((c) => c.$1 == 'account.login').last.$2, {
      'coordinator': 'https://coordinator.example',
      'login': 'alice',
      'password': strong,
    });

    // Последний снимок и предупреждение о возможном откате.
    expect(find.text('Компьютер подключён'), findsOneWidget);
    expect(find.textContaining('компьютер laptop'), findsOneWidget);
    expect(find.textContaining('21 файл · 1,5 КиБ'), findsOneWidget);
    expect(find.text('Всего 2 снимка'), findsOneWidget);
    expect(find.text('Сверьте последний снимок'), findsOneWidget);

    await enter(tester, 'target', 'относительный');
    expect(enabled(tester, 'Восстановить всё'), isFalse);
    await enter(tester, 'target', '/home/user/Восстановлено');
    agent.update(status: agentStatus());
    await tap(tester, find.text('Восстановить всё'));
    expect(agent.calls.last.$1, 'restore');
    expect(agent.calls.last.$2, {
      'snapshot': 'cd' * 32,
      'target': '/home/user/Восстановлено',
      'waitMinutes': 60,
    });
    expect(find.text('Сделать бэкап сейчас'), findsOneWidget);
  });

  testWidgets('новый компьютер по фразе: счёт слов, новый пароль, откат', (
    tester,
  ) async {
    final agent = FakeProcess(
      status: agentStatus(configured: false),
      answer: (method, params) async => switch (method) {
        'account.recover' => {'remembered': true, 'indexes': 1},
        'snapshots' => {
          'snapshots': <Object?>[],
          'warnings': ['sequenceRegressed'],
        },
        _ => const {},
      },
    );
    await pump(tester, agent);
    await tap(tester, find.text('Восстановить по фразе'));
    await enter(tester, 'phrase', words.take(5).join(' '));
    expect(find.text('5 слов из 24'), findsOneWidget);
    await enter(tester, 'newPassword', strong);
    await enter(tester, 'repeatPassword', strong);
    expect(enabled(tester, 'Восстановить'), isFalse);
    await enter(tester, 'phrase', words.join(' '));
    expect(find.text('24 слова из 24'), findsOneWidget);
    await tap(tester, find.text('Восстановить'));
    expect(agent.calls.firstWhere((c) => c.$1 == 'account.recover').$2, {
      'phrase': words.join(' '),
      'password': strong,
      'acceptWeak': true,
    });
    expect(find.text('Снимков пока нет'), findsOneWidget);
    agent.update(status: agentStatus());
    await tap(tester, find.text('Готово'));
    expect(find.text('Сделать бэкап сейчас'), findsOneWidget);
  });

  testWidgets('настройки: устройства и отзыв, пароль, фраза, копия ключа', (
    tester,
  ) async {
    final current = '11' * 32;
    final laptop = '22' * 32;
    var revoked = false;
    final agent = FakeProcess(
      status: agentStatus(),
      answer: (method, params) async {
        switch (method) {
          case 'account.info':
            return {
              'configured': true,
              'coordinator': 'https://coordinator.example',
              'login': 'alice',
              'keyCopy': true,
              'deviceId': current,
              'hasPhrase': true,
            };
          case 'account.devices':
            return {
              'devices': [
                {
                  'deviceId': current,
                  'addedAt': '2026-10-01T09:00:00Z',
                  'revokedAt': null,
                  'current': true,
                },
                {
                  'deviceId': laptop,
                  'addedAt': '2026-10-02T09:00:00Z',
                  'revokedAt': revoked ? '2026-10-27T09:00:00Z' : null,
                  'current': false,
                },
              ],
              'invalid': 0,
            };
          case 'account.revoke':
            revoked = true;
            return {'deviceId': laptop};
          case 'account.phrase' || 'account.passwd' || 'account.key_copy'
              when params['password'] != strong:
            throw const ControlException('wrong_password', 'нет');
          case 'account.phrase':
            return {'words': words};
          case 'account.passwd':
            return {'keyCopyUpdated': true, 'keyCopyUnknown': false};
          case 'account.key_copy':
            return {'keyCopy': params['enabled']};
        }
        return const {};
      },
    );
    await pump(tester, agent);
    await tap(tester, find.text('Настройки'));
    expect(find.text('alice'), findsOneWidget);
    expect(find.text('по паролю или по фразе'), findsOneWidget);
    expect(find.text('1111111111111111… — это устройство'), findsOneWidget);

    // Отзыв: подтверждение, вызов, список обновлён.
    await tap(tester, find.text('Отозвать'));
    expect(find.text('Отозвать устройство?'), findsOneWidget);
    await tap(tester, find.widgetWithText(FilledButton, 'Отозвать'));
    expect(agent.calls.firstWhere((c) => c.$1 == 'account.revoke').$2, {
      'device': laptop,
    });
    expect(find.text('Устройство отозвано — доступ закрыт.'), findsOneWidget);
    expect(find.textContaining(RegExp('^отозвано ')), findsOneWidget);
    expect(find.text('Отозвать'), findsNothing);

    // Фраза — только по паролю.
    await tap(tester, find.text('Показать фразу'));
    await tester.enterText(find.byType(TextField), 'не тот');
    await tap(tester, find.text('Показать'));
    expect(find.text('Неверный пароль'), findsOneWidget);
    await tester.enterText(find.byType(TextField), strong);
    await tap(tester, find.text('Показать'));
    expect(find.byKey(const ValueKey('word24')), findsOneWidget);
    await tap(tester, find.text('Закрыть'));

    // Смена пароля.
    await tap(tester, find.text('Сменить пароль'));
    await enter(tester, 'currentPassword', strong);
    await enter(tester, 'newPassword', 'another long sentence for tests');
    await enter(tester, 'repeatPassword', 'another long sentence for tests');
    await tap(tester, find.widgetWithText(FilledButton, 'Сменить пароль'));
    expect(agent.calls.lastWhere((c) => c.$1 == 'account.passwd').$2, {
      'password': strong,
      'newPassword': 'another long sentence for tests',
      'acceptWeak': true,
    });
    expect(
      find.text('Пароль изменён здесь и в копии ключа на сервере.'),
      findsOneWidget,
    );

    // Выключить копию ключа: предупреждение и пароль.
    await tap(tester, find.byKey(const ValueKey('keyCopySwitch')));
    expect(find.text('Выключить вход по паролю'), findsOneWidget);
    expect(find.textContaining('данные не вернуть никак'), findsOneWidget);
    await tester.enterText(find.byType(TextField), strong);
    await tap(tester, find.text('Выключить'));
    expect(agent.calls.lastWhere((c) => c.$1 == 'account.key_copy').$2, {
      'password': strong,
      'enabled': false,
    });
    expect(find.text('только по фразе'), findsOneWidget);
  });
}
