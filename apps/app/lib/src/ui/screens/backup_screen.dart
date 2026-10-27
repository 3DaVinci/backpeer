import 'package:app/l10n/app_localizations.dart';
import 'package:app/src/app_scope.dart';
import 'package:app/src/ui/widgets/section.dart';
import 'package:flutter/material.dart';

/// Бэкап: папки и расписание из настроек агента. Макет: изменение —
/// задачи 5.3.1, 5.3.2.
class BackupScreen extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final agent = AppScope.of(context).agent;
    final l10n = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: agent,
      builder: (context, _) {
        final settings = agent.status?['settings'] as Map<String, Object?>?;
        final paths = (settings?['paths'] as List<Object?>?) ?? const [];
        final interval = settings?['intervalMinutes'];
        final edit = Tooltip(
          message: l10n.comingSoon,
          child: const IconButton(onPressed: null, icon: Icon(Icons.edit)),
        );
        return ScreenBody(
          title: l10n.navBackup,
          children: [
            Section(
              title: l10n.backupFolders,
              trailing: edit,
              children: [
                if (paths.isEmpty) Text(l10n.noFolders),
                for (final p in paths)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.folder_outlined),
                    title: Text('$p'),
                  ),
              ],
            ),
            Section(
              title: l10n.schedule,
              trailing: edit,
              children: [
                Text(
                  interval is int
                      ? l10n.everyMinutes(interval)
                      : l10n.manualOnly,
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
