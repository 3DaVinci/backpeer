import 'package:agent/src/settings.dart';
import 'package:agent/src/state.dart';

/// Когда следующий бэкап по расписанию; `null` — не по расписанию (нет
/// папок или только вручную).
///
/// - незаконченный бэкап ([AgentState.interrupted]) — сразу;
/// - бэкапа ещё не было — сразу;
/// - последний не удался — через `retryMinutes`, но не позже интервала;
/// - иначе — через интервал после начала последнего: длинный бэкап не
///   сдвигает расписание.
///
/// Затем время сдвигается в разрешённые часы ([AgentSettings.hours]).
///
/// Остановленный пользователем бэкап считается неудачным: при отметке
/// незаконченного он всё равно продолжится сразу после снятия паузы.
DateTime? nextScheduledBackup(
  AgentSettings settings,
  AgentState state, {
  DateTime? now,
}) {
  if (settings.paths.isEmpty) return null;
  final at = _due(settings, state);
  if (at == null) return null;
  return fitHours(at, settings.hours, now ?? DateTime.now());
}

DateTime? _due(AgentSettings settings, AgentState state) {
  if (state.interrupted case final at?) return at;
  final interval = settings.intervalMinutes;
  if (interval == null) return null;
  final last = state.lastBackup;
  if (last == null) return DateTime.fromMillisecondsSinceEpoch(0);
  if (last.outcome == JobOutcome.ok || last.outcome == JobOutcome.partial) {
    return last.startedAt.add(Duration(minutes: interval));
  }
  final retry = settings.retryMinutes < interval
      ? settings.retryMinutes
      : interval;
  return last.finishedAt.add(Duration(minutes: retry));
}

/// Когда следующая проверка по расписанию; `null` — проверки только
/// вручную, удачного бэкапа ещё не было или бэкап не закончен. Первая
/// проверка — через `verifyIntervalHours` после первого удачного бэкапа,
/// дальше — через столько же после начала предыдущей (узлы уходят и без
/// новых бэкапов); тоже в разрешённые часы.
DateTime? nextScheduledVerify(
  AgentSettings settings,
  AgentState state, {
  DateTime? now,
}) {
  final hours = settings.verifyIntervalHours;
  final ok = state.lastOkBackupAt;
  if (hours == null || ok == null || state.interrupted != null) return null;
  final at = switch (state.lastVerify) {
    final v? => v.startedAt.add(Duration(hours: hours)),
    null => ok.add(Duration(hours: hours)),
  };
  return fitHours(at, settings.hours, now ?? DateTime.now());
}

/// Ближайшее время не раньше [at], когда местный час входит в [hours].
/// Время уже прошло и сейчас разрешённый час — [at] как есть (пора).
DateTime fitHours(DateTime at, BackupHours? hours, DateTime now) {
  if (hours == null) return at;
  final from = (at.isBefore(now) ? now : at).toLocal();
  if (hours.contains(from.hour)) return at;
  var start = DateTime(from.year, from.month, from.day, hours.from);
  if (!start.isAfter(from)) {
    start = DateTime(from.year, from.month, from.day + 1, hours.from);
  }
  return start;
}
