import 'package:agent/src/settings.dart';
import 'package:agent/src/state.dart';

/// Общее состояние данных для пользователя (задача 5.3.4).
enum HealthState {
  /// Всё в порядке.
  ok,

  /// Узлы ушли, координатор восстанавливает фрагменты; данные целы.
  /// Сведения о ремонте приходят от координатора (4.5.1, ремонт — 4.3);
  /// пока их нет, агент это состояние не выставляет.
  repairing,

  /// Требует внимания: бэкап не делается, данные под угрозой.
  attention,

  /// Бэкапа ещё не было.
  unknown,
}

/// Причина состояния: [code] — для приложения (строки интерфейса),
/// [message] — для журнала и уведомления.
final class HealthReason {
  const new(this.code, this.message, {this.attention = true});

  final String code;
  final String message;

  /// Требует внимания; `false` — для сведения.
  final bool attention;

  Map<String, Object?> toJson() => {
    'code': code,
    'message': message,
    'attention': attention,
  };
}

/// Здоровье бэкапа по итогам заданий агента.
final class HealthReport {
  const new({required this.state, required this.reasons, this.lastVerify});

  final HealthState state;
  final List<HealthReason> reasons;
  final JobRecord? lastVerify;

  /// Состояние и причины, требующие внимания, — чтобы не уведомлять о
  /// том же повторно.
  String get signature => [
    state.name,
    for (final r in reasons)
      if (r.attention) r.code,
  ].join(',');

  Map<String, Object?> toJson() => {
    'state': state.name,
    'reasons': [for (final r in reasons) r.toJson()],
    'lastVerify': lastVerify?.toJson(),
  };
}

/// Здоровье по [state] и [settings]: последний бэкап, его давность,
/// последняя проверка. Сводка координатора о ремонте и риске — 4.5.1.
HealthReport assessHealth(
  AgentSettings settings,
  AgentState state, {
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  final reasons = <HealthReason>[];
  final last = state.lastBackup;
  final okAt = state.lastOkBackupAt;
  if (last != null && last.outcome == JobOutcome.failed) {
    reasons.add(
      HealthReason(
        'backup_failed',
        'последний бэкап не удался: ${last.error ?? 'ошибка'}',
      ),
    );
  }
  if (last?.result['warnings'] case final List<Object?> w when w.isNotEmpty) {
    reasons.add(
      HealthReason(
        'rollback_warning',
        'координатор показал не все снимки (${w.join(', ')})',
      ),
    );
  }
  if (settings.intervalMinutes case final interval? when okAt != null) {
    // Пропущено три бэкапа подряд, но не меньше двух суток: ноутбук
    // мог быть выключен на выходные.
    final limit = Duration(minutes: interval * 3);
    final stale = limit > const Duration(days: 2)
        ? limit
        : const Duration(days: 2);
    if (at.difference(okAt) > stale) {
      reasons.add(
        HealthReason(
          'backup_stale',
          'удачного бэкапа не было ${at.difference(okAt).inHours} ч',
        ),
      );
    }
  }
  final verify = state.lastVerify;
  if (verify != null) {
    final r = verify.result;
    if ((r['unrecoverable'] as int? ?? 0) > 0) {
      reasons.add(
        HealthReason(
          'unrecoverable',
          'часть данных нельзя восстановить: сегментов ${r['unrecoverable']}',
        ),
      );
    } else if ((r['atRisk'] as int? ?? 0) > 0) {
      reasons.add(
        HealthReason(
          'at_risk',
          'мало живых фрагментов: сегментов ${r['atRisk']}',
        ),
      );
    } else if ((r['problems'] as int? ?? 0) > 0) {
      reasons.add(
        HealthReason(
          'fragments_missing',
          'недоступно фрагментов: ${r['problems']}, запас есть',
          attention: false,
        ),
      );
    }
    if (verify.outcome == JobOutcome.failed && r.isEmpty) {
      reasons.add(
        HealthReason(
          'verify_failed',
          'проверка не удалась: ${verify.error ?? 'ошибка'}',
          attention: false,
        ),
      );
    }
  } else if (okAt != null) {
    reasons.add(
      const HealthReason(
        'never_verified',
        'бэкап ещё не проверялся',
        attention: false,
      ),
    );
  }
  final HealthState health;
  if (reasons.any((r) => r.attention)) {
    health = HealthState.attention;
  } else if (okAt == null) {
    health = HealthState.unknown;
  } else {
    health = HealthState.ok;
  }
  return HealthReport(state: health, reasons: reasons, lastVerify: verify);
}
