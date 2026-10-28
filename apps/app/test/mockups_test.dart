// Макеты основных экранов (задачи 5.1.2, 5.2) картинками PNG — для
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
    // Первый запуск и фраза восстановления (5.2.1).
    'welcome': null,
    'phrase': null,
  };

  for (final locale in ['ru', 'en']) {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      for (final MapEntry(key: name, value: nav) in screens.entries) {
        testWidgets('$name $locale ${mode.name}', (tester) async {
          tester.view
            ..physicalSize = const Size(1280, 800)
            ..devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final firstRun = name == 'welcome' || name == 'phrase';
          final agent = FakeProcess(
            status: agentStatus(
              configured: !firstRun,
              status: name == 'overview' ? 'working' : 'idle',
              job: name == 'overview'
                  ? {
                      'kind': 'backup',
                      'progress': {
                        'files': 1834,
                        'bytes': 734 << 20,
                        'bytesRead': 512 << 20,
                        'totalFiles': 5210,
                        'totalBytes': 2150 << 20,
                        'bytesPerSecond': 18 << 20,
                        'etaMs': 80 * 1000,
                      },
                    }
                  : null,
              lastBackup: {
                'finishedAt': '2026-10-27T06:12:00Z',
                'outcome': 'ok',
              },
              lastVerify: {
                'finishedAt': '2026-10-27T03:40:00Z',
                'outcome': 'ok',
              },
              nextBackupAt: '2999-10-28T10:00:00Z',
            ),
            answer: (method, _) async => switch (method) {
              'history' => {
                'jobs': [
                  {
                    'kind': 'backup',
                    'trigger': 'schedule',
                    'outcome': 'ok',
                    'startedAt': '2026-10-27T06:10:00Z',
                    'finishedAt': '2026-10-27T06:12:00Z',
                    'result': {
                      'files': 5210,
                      'bytes': 2150 << 20,
                      'newBytes': 14 << 20,
                      'retention': {'kept': 31, 'forgotten': 1},
                    },
                  },
                  {
                    'kind': 'backup',
                    'trigger': 'resume',
                    'outcome': 'partial',
                    'startedAt': '2026-10-27T05:02:00Z',
                    'finishedAt': '2026-10-27T05:09:00Z',
                    'result': {
                      'files': 5209,
                      'bytes': 2149 << 20,
                      'newBytes': 210 << 20,
                      'skipped': 2,
                    },
                  },
                  {
                    'kind': 'backup',
                    'trigger': 'schedule',
                    'outcome': 'cancelled',
                    'startedAt': '2026-10-27T05:00:00Z',
                    'finishedAt': '2026-10-27T05:01:00Z',
                    'result': {'reason': 'on_battery', 'continues': true},
                  },
                ],
              },
              'keeper.info' => {
                'enabled': true,
                'settings': {
                  'enabled': true,
                  'storageDir': '/home/anna/.local/share/backpeer/node',
                  'quotaBytes': 500 * 1000 * 1000 * 1000,
                },
                'minQuotaBytes': 1 << 30,
              },
              'account.info' => {
                'configured': true,
                'coordinator': 'https://coordinator.example',
                'login': 'anna',
                'keyCopy': true,
                'deviceId': 'a1' * 32,
                'hasPhrase': true,
              },
              'account.devices' => {
                'devices': [
                  {
                    'deviceId': 'a1' * 32,
                    'addedAt': '2026-09-01T10:00:00Z',
                    'current': true,
                  },
                  {
                    'deviceId': 'b2' * 32,
                    'addedAt': '2026-10-12T18:30:00Z',
                    'current': false,
                  },
                  {
                    'deviceId': 'c3' * 32,
                    'addedAt': '2026-05-03T08:00:00Z',
                    'revokedAt': '2026-09-02T08:00:00Z',
                    'current': false,
                  },
                ],
              },
              'account.new_phrase' => {
                'words': [
                  'gravity',
                  'mansion',
                  'orbit',
                  'velvet',
                  'harbor',
                  'tissue',
                  'lumber',
                  'cactus',
                  'nephew',
                  'shallow',
                  'pepper',
                  'device',
                  'anchor',
                  'meadow',
                  'rocket',
                  'silent',
                  'bamboo',
                  'quarter',
                  'jungle',
                  'ostrich',
                  'pulse',
                  'ribbon',
                  'canyon',
                  'wisdom',
                ],
                'confirm': 3,
              },
              _ => {
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
            },
          );
          final node = FakeProcess(
            status: {
              ...nodeStatus(),
              'storageDir': '/home/anna/.local/share/backpeer/node',
              'freeBytes': (2 << 40) - (3 << 30),
              'diskAvailableBytes': 3 << 40,
              'listen': {'port': 7340},
              'coordinator': {
                'registered': true,
                'standing': {
                  'availability': 0.986,
                  'reputation': 0.91,
                  'onProbation': false,
                  'auditsPassed': 214,
                  'auditsFailed': 0,
                  'excluded': false,
                },
              },
            },
            answer: (method, _) async => switch (method) {
              'stats' => {'bytesSent': 41 << 30, 'bytesReceived': 380 << 30},
              _ => const {},
            },
          );
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
          if (name == 'phrase') {
            await tester.tap(find.byIcon(Icons.person_add_alt_1_outlined));
            await _settle(tester);
            await tester.tap(find.byType(FilledButton));
            await _settle(tester);
            for (final field in ['newPassword', 'repeatPassword']) {
              await tester.enterText(
                find.byKey(ValueKey(field)),
                'correct horse battery staple',
              );
            }
            await _settle(tester);
            await tester.tap(find.byType(FilledButton));
            await _settle(tester);
          }
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
