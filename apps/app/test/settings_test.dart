// Настройки: автообновление, бета-канал и отчёты о сбоях (5.8.2, 5.9.3).

import 'dart:io';

import 'package:app/src/services/preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized()
      ..platformDispatcher.views.first.physicalSize = const Size(1280, 1600)
      ..platformDispatcher.views.first.devicePixelRatio = 1;
  });

  testWidgets('переключатели обновлений и отчётов о сбоях', (tester) async {
    final dir = Directory.systemTemp.createTempSync('fs-app-settings-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final prefs = Preferences.load(File('${dir.path}/preferences.json'))
      ..locale = const Locale('ru');

    await tester.pumpWidget(
      testApp(
        FakeProcess(status: agentStatus()),
        FakeProcess(status: nodeStatus()),
        preferences: prefs,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Настройки'));
    await tester.pumpAndSettle();

    // По умолчанию: автообновление включено, бета и отчёты — выключены.
    SwitchListTile tile(String key) =>
        tester.widget<SwitchListTile>(find.byKey(ValueKey(key)));
    expect(tile('auto-update').value, isTrue);
    expect(tile('beta-channel').value, isFalse);
    expect(tile('crash-reports').value, isFalse);

    await tester.tap(find.byKey(const ValueKey('auto-update')));
    await tester.tap(find.byKey(const ValueKey('beta-channel')));
    await tester.tap(find.byKey(const ValueKey('crash-reports')));
    await tester.pumpAndSettle();

    expect(prefs.autoUpdate, isFalse);
    expect(prefs.betaChannel, isTrue);
    expect(prefs.crashReports, isTrue);
    expect(prefs.installId, hasLength(16));

    // Настройки сохранились в файл.
    final reloaded = Preferences.load(File('${dir.path}/preferences.json'));
    expect(reloaded.autoUpdate, isFalse);
    expect(reloaded.betaChannel, isTrue);
    expect(reloaded.crashReports, isTrue);
  });
}
