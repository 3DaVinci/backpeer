import 'package:app/l10n/app_localizations.dart';
import 'package:app/src/app_scope.dart';
import 'package:app/src/services/process_link.dart';
import 'package:app/src/ui/backup/delete_section.dart';
import 'package:app/src/ui/backup/folders_section.dart';
import 'package:app/src/ui/backup/history_section.dart';
import 'package:app/src/ui/backup/network_section.dart';
import 'package:app/src/ui/backup/retention_section.dart';
import 'package:app/src/ui/backup/schedule_section.dart';
import 'package:app/src/ui/screens/overview_screen.dart';
import 'package:app/src/ui/widgets/job_progress.dart';
import 'package:app/src/ui/widgets/section.dart';
import 'package:flutter/material.dart';

/// Бэкап (задачи 5.3.1–5.3.3, 5.3.5): текущий бэкап с запуском, папки и
/// исключения с оценкой объёма (у каждой папки — свой запуск), расписание,
/// хранение снимков, история. Всё меняется методом агента `settings` и
/// действует сразу — расписание выполняет агент, а не открытое окно.
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
        final backup = job != null && job['kind'] == 'backup' ? job : null;
        final connected = agent.state == LinkState.connected;
        final paused = status?['status'] == 'paused';
        return ScreenBody(
          title: l10n.navBackup,
          children: [
            Section(
              title: l10n.currentBackup,
              trailing: backup == null
                  ? null
                  : Chip(label: Text(agentStatusName(l10n, status?['status']))),
              children: [
                if (backup != null) ...[
                  JobProgress(job: backup),
                  if (backup['paths'] case final List<Object?> paths
                      when paths.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(l10n.backupPaths(paths.join(', '))),
                  ],
                  const SizedBox(height: 12),
                ],
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: connected && job == null && !paused
                          ? () => runAction(context, () => agent.call('backup'))
                          : null,
                      icon: const Icon(Icons.backup_outlined),
                      label: Text(l10n.backupNow),
                    ),
                    if (backup != null && !paused)
                      OutlinedButton.icon(
                        onPressed: () =>
                            runAction(context, () => agent.call('pause')),
                        icon: const Icon(Icons.pause),
                        label: Text(l10n.pause),
                      ),
                    // Пауза снимает задание, и без этой кнопки на экране
                    // бэкапа нечем его продолжить — только на «Обзоре».
                    if (paused)
                      OutlinedButton.icon(
                        onPressed: connected
                            ? () =>
                                  runAction(context, () => agent.call('resume'))
                            : null,
                        icon: const Icon(Icons.play_arrow),
                        label: Text(l10n.resume),
                      ),
                  ],
                ),
              ],
            ),
            FoldersSection(agent: agent, settings: settings),
            ScheduleSection(agent: agent, settings: settings),
            NetworkSection(agent: agent, settings: settings),
            RetentionSection(agent: agent, settings: settings),
            DeleteSection(agent: agent),
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
