import 'package:app/l10n/app_localizations.dart';
import 'package:app/src/app_scope.dart';
import 'package:app/src/ui/backup/folders_section.dart';
import 'package:app/src/ui/backup/history_section.dart';
import 'package:app/src/ui/backup/retention_section.dart';
import 'package:app/src/ui/backup/schedule_section.dart';
import 'package:app/src/ui/screens/overview_screen.dart';
import 'package:app/src/ui/widgets/job_progress.dart';
import 'package:app/src/ui/widgets/section.dart';
import 'package:flutter/material.dart';

/// Бэкап (задачи 5.3.1–5.3.3, 5.3.5): текущий бэкап, папки и исключения с
/// оценкой объёма, расписание, хранение снимков, история. Всё меняется
/// методом агента `settings` и действует сразу — расписание выполняет
/// агент, а не открытое окно.
class BackupScreen extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final agent = AppScope.of(context).agent;
    final l10n = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: agent,
      builder: (context, _) {
        final status = agent.status;
        final settings =
            (status?['settings'] as Map<String, Object?>?) ?? const {};
        final job = status?['job'] as Map<String, Object?>?;
        return ScreenBody(
          title: l10n.navBackup,
          children: [
            if (job != null && job['kind'] == 'backup')
              Section(
                title: l10n.currentBackup,
                trailing: Chip(
                  label: Text(agentStatusName(l10n, status?['status'])),
                ),
                children: [
                  JobProgress(job: job),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () =>
                        runAction(context, () => agent.call('pause')),
                    icon: const Icon(Icons.pause),
                    label: Text(l10n.pause),
                  ),
                ],
              ),
            FoldersSection(agent: agent, settings: settings),
            ScheduleSection(agent: agent, settings: settings),
            RetentionSection(agent: agent, settings: settings),
            HistorySection(agent: agent),
          ],
        );
      },
    );
  }
}

/// Изменить настройки агента; ошибка — внизу экрана.
Future<void> changeSettings(BuildContext context, Map<String, Object?> patch) =>
    runAction(
      context,
      () => AppScope.of(context).agent.call('settings', patch),
    );
