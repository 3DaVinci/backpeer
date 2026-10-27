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
/// Остановленный пользователем бэкап считается неудачным: при отметке
/// незаконченного он всё равно продолжится сразу после снятия паузы.
DateTime? nextScheduledBackup(AgentSettings settings, AgentState state) {
  if (settings.paths.isEmpty) return null;
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
