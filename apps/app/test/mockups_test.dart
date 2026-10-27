// Макеты основных экранов (задача 5.1.2) картинками PNG — для
// согласования без запуска приложения:
//
//   FS_APP_MOCKUPS=/tmp/mockups flutter test test/mockups_test.dart
//
// Каждый раздел — в светлой и тёмной теме, на русском и английском.
// Шрифты — Roboto и значки Material из Flutter SDK (в обычных тестах
// вместо букв прямоугольники). Без переменной тест пропускается.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:app/src/services/preferences.dart';
import 'package:app/src/services/process_link.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

final String? _out = Platform.environment['FS_APP_MOCKUPS'];

Future<void> _loadFonts() async {
  final sdk = File(Platform.resolvedExecutable).parent.parent.parent.parent;
  final fonts = '${sdk.path}/artifacts/material_fonts';
  Future<void> family(String name, List<String> files) async {
    final loader = FontLoader(name);
    for (final f in files) {
      final bytes = File('$fonts/$f').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }

  await family('Roboto', [
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
  ]);
  await family('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

/// Как pumpAndSettle, но с бесконечным индикатором прогресса.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  if (_out == null) {
    test('макеты', () {}, skip: 'FS_APP_MOCKUPS не задан');
    return;
  }
  setUpAll(_loadFonts);

  const screens = {
    'overview': null,
    'backup': 'Бэкап',
    'restore': 'Восстановление',
    'keeper': 'Хранитель',
    'settings': 'Настройки',
  };

  for (final locale in ['ru', 'en']) {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      for (final MapEntry(key: name, value: nav) in screens.entries) {
        testWidgets('$name $locale ${mode.name}', (tester) async {
          tester.view
            ..physicalSize = const Size(1280, 800)
            ..devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final agent = FakeProcess(
            status: agentStatus(
              status: name == 'overview' ? 'working' : 'idle',
              job: name == 'overview'
                  ? {
                      'kind': 'backup',
                      'progress': {'files': 1834, 'bytesRead': 734 << 20},
                    }
                  : null,
              lastBackup: {
                'finishedAt': '2026-10-27T06:12:00Z',
                'outcome': 'ok',
              },
              nextBackupAt: '2999-10-28T10:00:00Z',
            ),
            answer: (method, _) async => {
              'snapshots': [
                for (var i = 0; i < 4; i++)
                  {
                    'id': '$i' * 64,
                    'createdAt': '2026-10-2${7 - i}T06:00:00Z',
                    'paths': ['/home/anna/Документы', '/home/anna/Фото'],
                    'files': 12840 - i * 17,
                    'bytes': (48 << 30) - i * (120 << 20),
                  },
              ],
            },
          );
          final node = FakeProcess(status: nodeStatus());
          final key = GlobalKey();
          await tester.pumpWidget(
            RepaintBoundary(
              key: key,
              child: testApp(
                agent,
                node,
                preferences: Preferences()
                  ..locale = Locale(locale)
                  ..themeMode = mode,
              ),
            ),
          );
          await _settle(tester);
          if (nav != null) {
            final labels = {
              'Бэкап': ['Бэкап', 'Backup'],
              'Восстановление': ['Восстановление', 'Restore'],
              'Хранитель': ['Хранитель', 'Keeper'],
              'Настройки': ['Настройки', 'Settings'],
            }[nav]!;
            await tester.tap(find.text(labels[locale == 'ru' ? 0 : 1]).first);
            await _settle(tester);
          }
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final bytes = await tester.runAsync(() async {
            final image = await boundary.toImage();
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            return data!.buffer.asUint8List();
          });
          File('$_out/$name-$locale-${mode.name}.png')
            ..createSync(recursive: true)
            ..writeAsBytesSync(bytes!);
        });
      }
    }
  }

  testWidgets('полоса о связи и запрос пароля', (tester) async {
    tester.view
      ..physicalSize = const Size(1280, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: testApp(
          FakeProcess(
            state: LinkState.unavailable,
            status: agentStatus(status: 'waitingForKeys'),
          ),
          FakeProcess(state: LinkState.unavailable),
          preferences: Preferences()..locale = const Locale('ru'),
        ),
      ),
    );
    await _settle(tester);
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final bytes = await tester.runAsync(() async {
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    });
    File('$_out/offline-ru-light.png').writeAsBytesSync(bytes!);
  });
}
