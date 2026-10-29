// Экран «Восстановление» (задачи 5.4.1, 5.4.2) на подделке агента: дерево
// снимка постранично, поиск, версии файла, выбор места и поведения с
// существующими файлами, ожидание узлов.

import 'package:app/src/services/preferences.dart';
import 'package:app/src/ui/restore/snapshot_browser.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

const _id = 'a1b2c3d4e5f6';
const _root = '/home/user/Документы';

Map<String, Object?> _snapshot() => {
  'id': _id,
  'sequence': 3,
  'createdAt': '2026-10-27T10:00:00Z',
  'hostname': 'laptop',
  'paths': [_root],
  'files': 1000000,
  'bytes': 40 << 30,
};

/// Каталог `big` на миллион файлов, остальное — маленькое.
Map<String, Object?> _tree(Map<String, Object?> params) {
  final path = params['path']! as List<Object?>;
  final offset = params['offset']! as int;
  final limit = params['limit']! as int;
  Map<String, Object?> file(String name, [int size = 2048]) => {
    'name': name,
    'type': 'file',
    'size': size,
    'mtime': '2026-10-20T08:00:00Z',
  };
  if (path.isEmpty) {
    return {
      'total': 1,
      'entries': [
        {'name': _root, 'type': 'directory', 'size': 0, 'mtime': null},
      ],
    };
  }
  if (path.length == 1) {
    return {
      'total': 2,
      'entries': [
        {'name': 'big', 'type': 'directory', 'size': 0, 'mtime': null},
        file('отчёт.odt'),
      ],
    };
  }
  const total = 1000000;
  return {
    'total': total,
    'entries': [
      for (var i = offset; i < total && i < offset + limit; i++)
        file('file-$i.txt'),
    ],
  };
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized()
      ..platformDispatcher.views.first.physicalSize = const Size(1280, 1600)
      ..platformDispatcher.views.first.devicePixelRatio = 1;
  });

  FakeProcess agent({Map<String, Object?>? status}) => FakeProcess(
    status: status ?? agentStatus(),
    answer: (method, params) async => switch (method) {
      'snapshots' => {
        'snapshots': [_snapshot()],
        'warnings': <Object?>[],
      },
      'tree' => _tree(params),
      'search' => {
        'matches': [
          {
            'path': [_root, 'отчёт.odt'],
            'name': 'отчёт.odt',
            'type': 'file',
            'size': 2048,
            'mtime': '2026-10-20T08:00:00Z',
          },
        ],
        'truncated': false,
        'scanned': 1000003,
      },
      'versions' => {
        'versions': [
          {
            'snapshot': 'old0001',
            'createdAt': '2026-10-01T10:00:00Z',
            'present': true,
            'changed': true,
            'size': 1000,
          },
          {
            'snapshot': 'mid0002',
            'createdAt': '2026-10-10T10:00:00Z',
            'present': false,
            'changed': false,
          },
          {
            'snapshot': _id,
            'createdAt': '2026-10-27T10:00:00Z',
            'present': true,
            'changed': true,
            'size': 2048,
          },
        ],
      },
      'restore' => {'started': true},
      _ => const {},
    },
  );

  Future<void> openRestore(
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
    await tester.tap(find.text('Восстановление').first);
    await tester.pumpAndSettle();
  }

  test('путь в исходном виде', () {
    expect(sourcePath(['/home/u']), '/home/u');
    expect(sourcePath(['/home/u', 'a', 'b.txt']), '/home/u/a/b.txt');
    expect(sourcePath(['/', 'etc']), '/etc');
    expect(sourcePath([r'C:\Users\u', 'a']), r'C:\Users\u/a');
  });

  testWidgets('каталог на миллион файлов читается постранично', (tester) async {
    final a = agent();
    await openRestore(tester, a);
    await tester.tap(find.byKey(const ValueKey('snapshot-$_id')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_root));
    await tester.pumpAndSettle();
    await tester.tap(find.text('big'));
    await tester.pumpAndSettle();
    expect(find.text('file-0.txt'), findsOneWidget);
    final pages = [
      for (final c in a.calls)
        if (c.$1 == 'tree' && (c.$2['path']! as List).length == 2) c.$2,
    ];
    // Открыт один каталог — одна страница, а не миллион строк.
    expect(pages, hasLength(1));
    expect(pages.single['limit'], SnapshotBrowser.pageSize);

    // Прокрутка вниз подгружает следующие страницы, а не всё сразу.
    await tester.drag(find.byType(ListView).last, const Offset(0, -40000));
    await tester.pumpAndSettle();
    final offsets = {
      for (final c in a.calls)
        if (c.$1 == 'tree' && (c.$2['path']! as List).length == 2)
          c.$2['offset'],
    };
    expect(offsets.length, greaterThan(1));
    expect(offsets.length, lessThan(10));

    // Назад по «хлебным крошкам».
    await tester.tap(find.widgetWithText(TextButton, _root));
    await tester.pumpAndSettle();
    expect(find.text('отчёт.odt'), findsOneWidget);
  });

  testWidgets('поиск, выбор и восстановление на исходное место', (
    tester,
  ) async {
    final a = agent();
    await openRestore(tester, a);
    await tester.tap(find.byKey(const ValueKey('snapshot-$_id')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('search')), 'отчёт');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(a.last('search'), {'snapshot': _id, 'query': 'отчёт', 'limit': 500});
    expect(find.text('Найдено: 1'), findsOneWidget);
    expect(find.textContaining('$_root/отчёт.odt'), findsOneWidget);

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(find.text('Выбрано: 1'), findsOneWidget);
    await tester.tap(find.text('Восстановить выбранное'));
    await tester.pumpAndSettle();
    expect(find.text('Что: $_root/отчёт.odt'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('restore-start')));
    await tester.pumpAndSettle();
    expect(a.last('restore'), {
      'snapshot': _id,
      'paths': ['$_root/отчёт.odt'],
      'originalLocation': true,
      'existing': 'keepBoth',
      'renameSuffix': 'восстановлено',
      'waitMinutes': 60,
    });
    expect(find.textContaining('Восстановление началось'), findsOneWidget);
  });

  testWidgets('версии файла: восстановить старую в другую папку с заменой', (
    tester,
  ) async {
    final a = agent();
    await openRestore(tester, a, picked: '/tmp/Старые');
    await tester.tap(find.byKey(const ValueKey('snapshot-$_id')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_root));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Версии файла'));
    await tester.pumpAndSettle();
    expect(a.last('versions'), {
      'path': [_root, 'отчёт.odt'],
    });
    expect(find.text('нет в этом снимке'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('version-old0001')),
        matching: find.text('Восстановить'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('where-folder')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Выбрать папку'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('existing-overwrite')));
    await tester.tap(find.byKey(const ValueKey('wait')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.text('Не ждать — восстановить то, что доступно').last,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('restore-start')));
    await tester.pumpAndSettle();
    expect(a.last('restore'), {
      'snapshot': 'old0001',
      'paths': ['$_root/отчёт.odt'],
      'target': '/tmp/Старые',
      'existing': 'overwrite',
      'renameSuffix': 'восстановлено',
      'waitMinutes': 0,
    });
  });

  testWidgets('ожидание узлов: сколько файлов, какие, сколько ещё ждём', (
    tester,
  ) async {
    final a = agent(
      status: agentStatus(
        status: 'working',
        job: {
          'kind': 'restore',
          'trigger': 'manual',
          'progress': {
            'files': 120,
            'bytes': 300 << 20,
            'totalBytes': 1 << 30,
            'waitingFiles': 7,
            'waitingPaths': ['$_root/big/file-1.txt', '$_root/big/file-2.txt'],
            'waitingReason': 'у сегмента 8 фрагментов из нужных 10',
            'nextRetryMs': 9000,
            'waitLeftMs': 50 * 60000,
          },
        },
      ),
    );
    await openRestore(tester, a);
    expect(find.text('Текущее восстановление'), findsOneWidget);
    expect(find.byKey(const ValueKey('restore-waiting')), findsOneWidget);
    expect(find.text('7 файлов ждут хранителей'), findsOneWidget);
    expect(find.text('• $_root/big/file-1.txt'), findsOneWidget);
    expect(find.text('и ещё 5'), findsOneWidget);
    expect(find.text('Следующая попытка — в течение минуты'), findsOneWidget);
    expect(find.text('Ждём ещё не дольше 50 минут'), findsOneWidget);
    expect(find.textContaining('8 фрагментов из нужных 10'), findsOneWidget);
    expect(find.textContaining('300,0 МиБ из 1,0 ГиБ'), findsOneWidget);
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(a.calls.last.$1, 'cancel');
  });

  testWidgets('итог последнего восстановления', (tester) async {
    final status = agentStatus()
      ..['lastRestore'] = {
        'kind': 'restore',
        'outcome': 'partial',
        'finishedAt': '2026-10-27T11:00:00Z',
        'result': {
          'originalLocation': true,
          'files': 10,
          'bytes': 4096,
          'skippedExisting': 2,
          'renamedCount': 3,
          'errors': [
            {'path': '$_root/b.txt', 'reason': 'нет фрагментов'},
          ],
        },
      };
    await openRestore(tester, agent(status: status));
    expect(find.text('Последнее восстановление'), findsOneWidget);
    expect(find.text('На исходное место'), findsOneWidget);
    expect(find.text('• $_root/b.txt — нет фрагментов'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });
}
