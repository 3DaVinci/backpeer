import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';

/// Итог задания агента.
enum JobOutcome {
  /// Выполнено без замечаний.
  ok,

  /// Выполнено, но часть файлов пропущена или есть предупреждения.
  partial,

  /// Не выполнено: ошибка.
  failed,

  /// Остановлено пользователем (пауза, отмена) или остановкой агента.
  cancelled;

  static JobOutcome parse(Object? value) =>
      values.firstWhere((v) => v.name == value, orElse: () => failed);
}

/// Итог последнего задания одного вида.
final class JobRecord {
  const new({
    required this.startedAt,
    required this.finishedAt,
    required this.outcome,
    this.kind,
    this.trigger,
    this.error,
    this.result = const {},
  });

  factory fromJson(Map<String, Object?> json) => JobRecord(
    startedAt: DateTime.parse(json['startedAt']! as String),
    finishedAt: DateTime.parse(json['finishedAt']! as String),
    outcome: JobOutcome.parse(json['outcome']),
    kind: json['kind'] as String?,
    trigger: json['trigger'] as String?,
    error: json['error'] as String?,
    result: (json['result'] as Map<String, Object?>?) ?? const {},
  );

  /// `backup`, `verify`, `restore`; в старых записях — `null`.
  final String? kind;

  /// `schedule`, `manual`, `resume`.
  final String? trigger;

  final DateTime startedAt;
  final DateTime finishedAt;
  final JobOutcome outcome;

  /// Сообщение об ошибке для человека, без ключей.
  final String? error;

  /// Сводка: снимок, файлы, байты (как `result` в `cli --json`).
  final Map<String, Object?> result;

  Map<String, Object?> toJson() => {
    'kind': ?kind,
    'trigger': ?trigger,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'finishedAt': finishedAt.toUtc().toIso8601String(),
    'outcome': outcome.name,
    'error': ?error,
    'result': result,
  };
}

/// Состояние агента между запусками (`agent/state.json`): итоги последних
/// заданий, история и отметка незаконченного бэкапа. Отметка ставится до начала
/// бэкапа и снимается после итога, поэтому после `kill -9`, сбоя питания
/// или паузы следующий запуск видит её и продолжает бэкап сразу:
/// сохранённые сегменты уже в локальном индексе и повторно не отправляются.
final class AgentState {
  new({
    this.lastBackup,
    this.lastVerify,
    this.lastRestore,
    this.interrupted,
    this.lastOkBackupAt,
    List<JobRecord>? history,
    this.notifiedHealth,
  }) : history = history ?? [];

  factory load(File file) {
    try {
      final json = jsonDecode(file.readAsStringSync());
      if (json is! Map<String, Object?>) return AgentState();
      JobRecord? record(String key) => switch (json[key]) {
        final Map<String, Object?> m => JobRecord.fromJson(m),
        _ => null,
      };
      DateTime? time(String key) => switch (json[key]) {
        final String s => DateTime.parse(s),
        _ => null,
      };
      return AgentState(
        lastBackup: record('lastBackup'),
        lastVerify: record('lastVerify'),
        lastRestore: record('lastRestore'),
        interrupted: time('interrupted'),
        lastOkBackupAt: time('lastOkBackupAt'),
        history: [
          for (final r in (json['history'] as List<Object?>?) ?? const [])
            if (r is Map<String, Object?>) JobRecord.fromJson(r),
        ],
        notifiedHealth: json['notifiedHealth'] as String?,
      );
    } on PathNotFoundException {
      return AgentState();
    } on Object {
      // Испорченный файл не мешает работать: начнём с чистого состояния.
      return AgentState();
    }
  }

  /// Сколько итогов заданий хранить в [history].
  static const historyLimit = 100;

  JobRecord? lastBackup;
  JobRecord? lastVerify;
  JobRecord? lastRestore;

  /// Когда начат бэкап, который не закончился; `null` — такого нет.
  DateTime? interrupted;

  /// Когда закончился последний удачный бэкап (`ok` или `partial`).
  DateTime? lastOkBackupAt;

  /// Итоги заданий, от старых к новым, не больше [historyLimit].
  final List<JobRecord> history;

  /// О каком состоянии здоровья уже уведомили (`HealthReport.signature`);
  /// `null` — уведомлять не о чем.
  String? notifiedHealth;

  /// Записать итог задания [kind] в последние и в историю.
  void record(String kind, JobRecord record) {
    switch (kind) {
      case 'backup':
        lastBackup = record;
        if (record.outcome == JobOutcome.ok ||
            record.outcome == JobOutcome.partial) {
          lastOkBackupAt = record.finishedAt;
        }
      case 'verify':
        lastVerify = record;
      case 'restore':
        lastRestore = record;
    }
    history.add(record);
    if (history.length > historyLimit) {
      history.removeRange(0, history.length - historyLimit);
    }
  }

  Map<String, Object?> toJson() => {
    'lastBackup': ?lastBackup?.toJson(),
    'lastVerify': ?lastVerify?.toJson(),
    'lastRestore': ?lastRestore?.toJson(),
    'interrupted': ?interrupted?.toUtc().toIso8601String(),
    'lastOkBackupAt': ?lastOkBackupAt?.toUtc().toIso8601String(),
    'history': [for (final r in history) r.toJson()],
    'notifiedHealth': ?notifiedHealth,
  };

  void save(File file) => writePrivateFileAtomic(
    file,
    utf8.encode('${const JsonEncoder.withIndent('  ').convert(toJson())}\n'),
  );
}
