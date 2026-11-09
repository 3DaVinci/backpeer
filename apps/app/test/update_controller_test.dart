// Автообновление в приложении (задача 5.8.2): проверка, автоматическая
// установка, ожидание окончания бэкапа и ошибки.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:app/src/services/preferences.dart';
import 'package:app/src/services/update_control.dart';
import 'package:app/src/services/update_controller.dart';
import 'package:app/src/services/updater.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

final class _FakeControl implements UpdateControl {
  new({this.manifest, this.outcome = const UpdateOutcome()});

  UpdateManifest? manifest;
  UpdateOutcome outcome;
  Error? error;
  int checks = 0;
  int applies = 0;

  @override
  Future<UpdateManifest?> check() async {
    checks++;
    if (error case final e?) throw e;
    return manifest;
  }

  @override
  Future<UpdateOutcome> apply(UpdateManifest manifest) async {
    applies++;
    if (error case final e?) throw e;
    return outcome;
  }
}

UpdateManifest _manifest([String version = '0.0.3']) => UpdateManifest.parse(
  jsonEncode({
    'format': 1,
    'channel': 'stable',
    'version': version,
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
  late Directory dir;
  late Preferences preferences;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('fs-update-controller-');
    preferences = Preferences.load(File('${dir.path}/preferences.json'))
      ..autoUpdate = true;
  });
  tearDown(() => dir.deleteSync(recursive: true));

  UpdateController controller(
    _FakeControl control, {
    bool Function()? canApply,
    void Function()? onExit,
    Duration exitDelay = Duration.zero,
  }) {
    final result = UpdateController(
      control: control,
      preferences: preferences,
      canApply: canApply ?? () => true,
      checkDelay: Duration.zero,
      exitDelay: exitDelay,
      onExit: onExit,
    );
    addTearDown(result.dispose);
    return result;
  }

  test('ручная проверка показывает обновление, но не ставит его', () async {
    final control = _FakeControl(manifest: _manifest());
    final c = controller(control);
    await c.checkNow();
    expect(c.state, UpdateState.available);
    expect(c.manifest?.version, ProductVersion.parse('0.0.3'));
    expect(control.checks, 1);
    expect(control.applies, 0);
  });

  test('автопроверка скачивает и ставит, затем приложение выходит', () async {
    var exited = false;
    final control = _FakeControl(
      manifest: _manifest(),
      outcome: const UpdateOutcome(restartRequired: true),
    );
    final c = controller(control, onExit: () => exited = true)..start();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(control.checks, 1);
    expect(control.applies, 1);
    expect(c.state, UpdateState.done);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(exited, isTrue);
  });

  test('идёт бэкап — автоматическая установка ждёт', () async {
    var canApply = false;
    final control = _FakeControl(manifest: _manifest());
    final c = controller(control, canApply: () => canApply)..start();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(c.state, UpdateState.available);
    expect(c.waitingForBackup, isTrue);
    expect(control.applies, 0);

    canApply = true;
    await c.applyNow();
    expect(control.applies, 1);
    expect(c.state, UpdateState.done);
  });

  test('ошибка проверки — состояние failed и текст ошибки', () async {
    final control = _FakeControl()..error = StateError('нет сети');
    final c = controller(control);
    await c.checkNow();
    expect(c.state, UpdateState.failed);
    expect(c.error, contains('нет сети'));
    expect(c.checked, isTrue);
  });

  test('ошибка установки не выходит из приложения', () async {
    var exited = false;
    final control = _FakeControl(manifest: _manifest())
      ..error = StateError('не удалось');
    final c = controller(control, onExit: () => exited = true);
    await c.checkNow();
    // Проверка уже вернула ошибку; для установки дадим новый манифест.
    control.error = null;
    await c.checkNow();
    control.error = StateError('не удалось');
    await c.applyNow();
    expect(c.state, UpdateState.failed);
    expect(exited, isFalse);
  });
}
