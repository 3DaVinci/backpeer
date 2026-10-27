import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';

/// Что и когда бэкапить (`agent/settings.json`; `docs/ops/agent.md`,
/// раздел «Настройки»). Меняется методом `settings` локального API;
/// исключения из `config.json` действуют вместе с [excludes].
final class AgentSettings {
  new({
    this.paths = const [],
    this.excludes = const [],
    this.intervalMinutes = 60,
    this.retryMinutes = 10,
  });

  /// Чтение с проверкой; ошибки — [ConfigException].
  factory fromJson(Map<String, Object?> json) {
    List<String> strings(String key) {
      final value = json[key];
      if (value == null) return const [];
      if (value is List<Object?> && value.every((e) => e is String)) {
        return value.cast<String>().toList();
      }
      throw ConfigException(key: key, reason: 'нужен список строк');
    }

    int? minutes(String key, int? fallback) {
      if (!json.containsKey(key)) return fallback;
      final value = json[key];
      if (value == null) return null;
      if (value is int && value >= 1) return value;
      throw ConfigException(key: key, reason: 'целое число минут ≥ 1');
    }

    return AgentSettings(
      paths: strings('paths'),
      excludes: strings('excludes'),
      intervalMinutes: minutes('intervalMinutes', 60),
      retryMinutes: minutes('retryMinutes', 10) ?? 10,
    );
  }

  /// Из файла; файла нет — настройки по умолчанию (бэкапить нечего).
  factory load(File file) {
    final String text;
    try {
      text = file.readAsStringSync();
    } on PathNotFoundException {
      return AgentSettings();
    }
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException catch (e) {
      throw ConfigException(key: file.path, reason: e.message);
    }
    if (json is! Map<String, Object?>) {
      throw ConfigException(key: file.path, reason: 'нужен объект');
    }
    return AgentSettings.fromJson(json);
  }

  /// Абсолютные пути папок для бэкапа.
  final List<String> paths;

  /// Правила исключения (как `.gitignore`).
  final List<String> excludes;

  /// Как часто бэкапить; `null` — только вручную.
  final int? intervalMinutes;

  /// Через сколько повторить неудачный бэкап (не позже [intervalMinutes]).
  final int retryMinutes;

  /// Новые настройки: поля [patch] заменяют свои (`intervalMinutes: null`
  /// — только вручную).
  AgentSettings merge(Map<String, Object?> patch) =>
      AgentSettings.fromJson({...toJson(), ...patch});

  Map<String, Object?> toJson() => {
    'paths': paths,
    'excludes': excludes,
    'intervalMinutes': intervalMinutes,
    'retryMinutes': retryMinutes,
  };

  void save(File file) => writePrivateFileAtomic(
    file,
    utf8.encode('${const JsonEncoder.withIndent('  ').convert(toJson())}\n'),
  );
}
