// Настройки приложения: идентификатор установки для раскатки обновлений и
// согласие на автообновление (задача 5.8.2).

import 'dart:convert';
import 'dart:io';

import 'package:app/src/services/preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late File file;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('fs-app-prefs-');
    file = File('${dir.path}/preferences.json');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('installId создаётся один раз и сохраняется', () {
    final prefs = Preferences.load(file);
    final first = prefs.installId;
    expect(first, hasLength(16));
    final reloaded = Preferences.load(file);
    expect(reloaded.installId, first);
  });

  test('autoUpdate и betaChannel по умолчанию и сохраняются', () {
    final prefs = Preferences.load(file);
    expect(prefs.autoUpdate, isTrue);
    expect(prefs.betaChannel, isFalse);
    prefs
      ..autoUpdate = false
      ..betaChannel = true;
    final reloaded = Preferences.load(file);
    expect(reloaded.autoUpdate, isFalse);
    expect(reloaded.betaChannel, isTrue);
  });

  test('битый installId в файле заменяется новым', () {
    file.writeAsStringSync(jsonEncode({'installId': 'не-base64'}));
    final prefs = Preferences.load(file);
    expect(prefs.installId, hasLength(16));
  });
}
