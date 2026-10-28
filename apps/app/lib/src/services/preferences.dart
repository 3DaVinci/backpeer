import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

/// Настройки самого приложения (язык, тема, фоновая работа) — в файле
/// `<home>/app/preferences.json`. Настройки бэкапа живут в агенте,
/// хранителя — в `node`.
final class Preferences extends ChangeNotifier {
  new({this.file});

  /// Из [file]; файла нет или он испорчен — по умолчанию.
  factory load(File? file) {
    final prefs = Preferences(file: file);
    if (file == null) return prefs;
    try {
      final json = jsonDecode(file.readAsStringSync());
      if (json is Map<String, Object?>) {
        prefs
          .._locale = switch (json['locale']) {
            final String code when supportedLanguages.contains(code) => Locale(
              code,
            ),
            _ => null,
          }
          .._themeMode = ThemeMode.values.firstWhere(
            (m) => m.name == json['theme'],
            orElse: () => ThemeMode.system,
          )
          .._backgroundService = json['backgroundService'] != false
          .._trayAtLogin = json['trayAtLogin'] != false;
      }
    } on Object {
      // Нет файла или он испорчен — настройки по умолчанию.
    }
    return prefs;
  }

  static const supportedLanguages = ['ru', 'en'];

  final File? file;
  Locale? _locale;
  ThemeMode _themeMode = ThemeMode.system;

  /// Язык; `null` — как в системе.
  Locale? get locale => _locale;
  set locale(Locale? value) {
    _locale = value;
    _save();
  }

  ThemeMode get themeMode => _themeMode;
  set themeMode(ThemeMode value) {
    _themeMode = value;
    _save();
  }

  bool _backgroundService = true;
  bool _trayAtLogin = true;

  /// Ставить службу агента при запуске (5.6.1); `false` — пользователь
  /// удалил её в настройках, не ставить снова.
  bool get backgroundService => _backgroundService;
  set backgroundService(bool value) {
    _backgroundService = value;
    _save();
  }

  /// Значок в трее при входе (5.6.2); `false` — пользователь выключил.
  bool get trayAtLogin => _trayAtLogin;
  set trayAtLogin(bool value) {
    _trayAtLogin = value;
    _save();
  }

  void _save() {
    notifyListeners();
    final f = file;
    if (f == null) return;
    try {
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(
        jsonEncode({
          'locale': _locale?.languageCode,
          'theme': _themeMode.name,
          'backgroundService': _backgroundService,
          'trayAtLogin': _trayAtLogin,
        }),
      );
    } on FileSystemException {
      // Не сохранилось — действует до перезапуска.
    }
  }
}
