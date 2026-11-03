import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Настройки самого приложения (язык, тема, фоновая работа, обновления) —
/// в файле `<home>/app/preferences.json`. Настройки бэкапа живут в агенте,
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
          .._trayAtLogin = json['trayAtLogin'] != false
          .._autoUpdate = json['autoUpdate'] != false
          .._betaChannel = json['betaChannel'] == true
          .._crashReports = json['crashReports'] == true
          .._installId = switch (json['installId']) {
            final String id when _validInstallId(id) => id,
            _ => null,
          };
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
  bool _backgroundService = true;
  bool _trayAtLogin = true;
  bool _autoUpdate = true;
  bool _betaChannel = false;
  bool _crashReports = false;
  String? _installId;

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

  /// Проверять обновления автоматически (5.8.2); `false` — пользователь
  /// выключил согласие.
  bool get autoUpdate => _autoUpdate;
  set autoUpdate(bool value) {
    _autoUpdate = value;
    _save();
  }

  /// Бета-канал обновлений (docs/spec/updates.md, раздел 3).
  bool get betaChannel => _betaChannel;
  set betaChannel(bool value) {
    _betaChannel = value;
    _save();
  }

  /// Отправлять отчёты о сбоях (5.9.3); по умолчанию выключено — согласие
  /// явное.
  bool get crashReports => _crashReports;
  set crashReports(bool value) {
    _crashReports = value;
    _save();
  }

  /// Идентификатор установки для раскатки (docs/spec/updates.md, раздел 5):
  /// 16 случайных байтов, создаётся при первом обращении и сохраняется. Это
  /// не ключ и не связано с учётной записью.
  Uint8List get installId {
    var id = _installId;
    if (id == null) {
      final random = Random.secure();
      final bytes = Uint8List(16);
      for (var i = 0; i < bytes.length; i++) {
        bytes[i] = random.nextInt(256);
      }
      id = base64Encode(bytes);
      _installId = id;
      _save();
    }
    return Uint8List.fromList(base64Decode(id));
  }

  static bool _validInstallId(String id) {
    try {
      return base64Decode(id).length == 16;
    } on FormatException {
      return false;
    }
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
          'autoUpdate': _autoUpdate,
          'betaChannel': _betaChannel,
          'crashReports': _crashReports,
          'installId': _installId,
        }),
      );
    } on FileSystemException {
      // Не сохранилось — действует до перезапуска.
    }
  }
}
