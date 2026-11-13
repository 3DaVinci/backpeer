// Обновления в «Настройках» (задача 5.8.2): проверка, доступная версия и
// установка.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:app/src/services/preferences.dart';
import 'package:app/src/services/update_control.dart';
import 'package:app/src/services/update_controller.dart';
import 'package:app/src/services/updater.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

final class _FakeControl implements UpdateControl {
  new({this.manifest, this.outcome = const UpdateOutcome()});

  UpdateManifest? manifest;
  UpdateOutcome outcome;
  int checks = 0;
  int applies = 0;

  @override
  Future<UpdateManifest?> check() async {
    checks++;
    return manifest;
  }

  @override
  Future<UpdateOutcome> apply(UpdateManifest manifest) async {
    applies++;
    return outcome;
  }

  @override
  Future<String?> takeLastFailure() async => null;
}

UpdateManifest _manifest() => UpdateManifest.parse(
  jsonEncode({
    'format': 1,
    'channel': 'stable',
    'version': '0.0.3',
    'minVersion': '0.0.0',
    'releasedAt': '2026-11-03T10:00:00Z',
    'rollout': 1,
    'packages': [
      {
        'platform': 'linux',
        'arch': null,
        'url': 'https://u.example/pkg',
        'sha256': '00' * 32,
        'size': 1,
      },
    ],
    'signer': base64Encode(Uint8List(32)),
  }),
);

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized()
      ..platformDispatcher.views.first.physicalSize = const Size(1280, 1800)
      ..platformDispatcher.views.first.devicePixelRatio = 1;
  });

  testWidgets('обновления: проверка, доступная версия и установка', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('fs-update-ui-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final preferences = Preferences.load(File('${dir.path}/preferences.json'))
      ..locale = const Locale('ru');
    final control = _FakeControl(
      manifest: _manifest(),
      outcome: const UpdateOutcome(url: 'https://u.example/pkg'),
    );
    final updates = UpdateController(
      control: control,
      preferences: preferences,
      canApply: () => true,
    );
    addTearDown(updates.dispose);

    await tester.pumpWidget(
      testApp(
        FakeProcess(status: agentStatus()),
        FakeProcess(status: nodeStatus()),
        preferences: preferences,
        updates: updates,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Настройки').first);
    await tester.pumpAndSettle();

    expect(find.text('Обновления'), findsOneWidget);
    expect(find.text('Обновления ещё не проверялись.'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey('update-check')));
    await tester.tap(find.byKey(const ValueKey('update-check')));
    await tester.pumpAndSettle();
    expect(find.text('Доступна версия 0.0.3'), findsOneWidget);
    expect(control.checks, 1);

    await tester.tap(find.byKey(const ValueKey('update-install')));
    await tester.pumpAndSettle();
    expect(control.applies, 1);
    expect(
      find.textContaining('Новая версия доступна вручную'),
      findsOneWidget,
    );
  });
}
