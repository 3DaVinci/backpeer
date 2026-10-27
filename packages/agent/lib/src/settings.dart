import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';

/// Часы, в которые можно начинать бэкап и проверку по расписанию:
/// с [from] до [to] по местному времени (`to` не входит). `from > to` —
/// через полночь: 22–7 — с 22:00 до 7:00.
final class BackupHours {
  const new(this.from, this.to);

  factory fromJson(Object? json) {
    if (json case {'from': final int from, 'to': final int to}
        when from >= 0 && from <= 23 && to >= 0 && to <= 23 && from != to) {
      return BackupHours(from, to);
    }
    throw const ConfigException(
      key: 'hours',
      reason: 'нужно {"from": час, "to": час}, часы 0–23, не равны',
    );
  }

  final int from;
  final int to;

  /// Входит ли [hour] (0–23) в разрешённые часы.
  bool contains(int hour) =>
      from < to ? hour >= from && hour < to : hour >= from || hour < to;

  Map<String, Object?> toJson() => {'from': from, 'to': to};
}

/// Что и когда бэкапить (`agent/settings.json`; `docs/ops/agent.md`,
/// раздел «Настройки»). Меняется методом `settings` локального API;
/// исключения из `config.json` действуют вместе с [excludes] и наборами
/// [excludePresets]. Политика хранения снимков — в `config.json`, общая с
/// CLI (`AppConfig.retention`).
final class AgentSettings {
  new({
    this.paths = const [],
    this.excludes = const [],
    this.excludePresets = ExcludePreset.defaults,
    this.intervalMinutes = 60,
    this.retryMinutes = 10,
    this.hours,
    this.onlyOnAcPower = false,
    this.verifyIntervalHours = 24,
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

    int? positive(String key, int? fallback, String unit) {
      if (!json.containsKey(key)) return fallback;
      final value = json[key];
      if (value == null) return null;
      if (value is int && value >= 1) return value;
      throw ConfigException(key: key, reason: 'целое число $unit ≥ 1');
    }

    final presets = json.containsKey('excludePresets')
        ? [
            for (final name in strings('excludePresets'))
              ExcludePreset.byName(name) ??
                  (throw ConfigException(
                    key: 'excludePresets',
                    reason:
                        'нет набора $name; есть '
                        '${ExcludePreset.values.map((p) => p.name).join(', ')}',
                  )),
          ]
        : ExcludePreset.defaults;
    final power = json['onlyOnAcPower'] ?? false;
    if (power is! bool) {
      throw const ConfigException(key: 'onlyOnAcPower', reason: 'true/false');
    }
    return AgentSettings(
      paths: strings('paths'),
      excludes: strings('excludes'),
      excludePresets: presets,
      intervalMinutes: positive('intervalMinutes', 60, 'минут'),
      retryMinutes: positive('retryMinutes', 10, 'минут') ?? 10,
      hours: json['hours'] == null ? null : BackupHours.fromJson(json['hours']),
      onlyOnAcPower: power,
      verifyIntervalHours: positive('verifyIntervalHours', 24, 'часов'),
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

  /// Готовые наборы исключений: временные файлы, кеши и т. п.
  final List<ExcludePreset> excludePresets;

  /// Как часто бэкапить; `null` — только вручную.
  final int? intervalMinutes;

  /// Через сколько повторить неудачный бэкап (не позже [intervalMinutes]).
  final int retryMinutes;

  /// В какие часы начинать бэкап и проверку по расписанию; `null` — в
  /// любые. Ручной бэкап — в любое время.
  final BackupHours? hours;

  /// Бэкап и проверка по расписанию — только при питании от сети; при
  /// переходе на батарею бэкап по расписанию останавливается с
  /// продолжением.
  final bool onlyOnAcPower;

  /// Как часто проверять бэкап (быстрая проверка: есть ли фрагменты на
  /// узлах) после бэкапа по расписанию; `null` — только вручную.
  final int? verifyIntervalHours;

  /// Правила исключения наборов и свои; правила из `config.json`
  /// добавляются к ним при бэкапе.
  List<String> get excludeRulesList => [
    for (final p in excludePresets) ...p.rules,
    ...excludes,
  ];

  /// Новые настройки: поля [patch] заменяют свои (`intervalMinutes: null`
  /// — только вручную).
  AgentSettings merge(Map<String, Object?> patch) =>
      AgentSettings.fromJson({...toJson(), ...patch});

  Map<String, Object?> toJson() => {
    'paths': paths,
    'excludes': excludes,
    'excludePresets': [for (final p in excludePresets) p.name],
    'intervalMinutes': intervalMinutes,
    'retryMinutes': retryMinutes,
    'hours': hours?.toJson(),
    'onlyOnAcPower': onlyOnAcPower,
    'verifyIntervalHours': verifyIntervalHours,
  };

  void save(File file) => writePrivateFileAtomic(
    file,
    utf8.encode('${const JsonEncoder.withIndent('  ').convert(toJson())}\n'),
  );
}
