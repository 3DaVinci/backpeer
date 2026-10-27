import 'package:app/l10n/app_localizations.dart';
import 'package:app/src/app_scope.dart';
import 'package:app/src/ui/screens/backup_screen.dart';
import 'package:app/src/ui/screens/keeper_screen.dart';
import 'package:app/src/ui/screens/overview_screen.dart';
import 'package:app/src/ui/screens/restore_screen.dart';
import 'package:app/src/ui/screens/settings_screen.dart';
import 'package:app/src/ui/widgets/process_banner.dart';
import 'package:flutter/material.dart';

/// Разделы приложения.
enum Destination { overview, backup, restore, keeper, settings }

/// Каркас: навигация слева, полоса о связи с агентом сверху, раздел.
class Shell extends StatefulWidget {
  const new({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  Destination _current = Destination.overview;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final services = AppScope.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final items = {
      Destination.overview: (Icons.dashboard_outlined, l10n.navOverview),
      Destination.backup: (Icons.backup_outlined, l10n.navBackup),
      Destination.restore: (Icons.restore, l10n.navRestore),
      Destination.keeper: (Icons.storage_outlined, l10n.navKeeper),
      Destination.settings: (Icons.settings_outlined, l10n.navSettings),
    };
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            NavigationRail(
              extended: wide,
              labelType: wide
                  ? NavigationRailLabelType.none
                  : NavigationRailLabelType.all,
              leading: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  l10n.appTitle,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              selectedIndex: _current.index,
              onDestinationSelected: (i) =>
                  setState(() => _current = Destination.values[i]),
              destinations: [
                for (final (icon, label) in items.values)
                  NavigationRailDestination(
                    icon: Icon(icon),
                    label: Text(label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: Column(
                children: [
                  ProcessBanner(
                    process: services.agent,
                    name: l10n.processAgent,
                  ),
                  Expanded(
                    child: switch (_current) {
                      Destination.overview => const OverviewScreen(),
                      Destination.backup => const BackupScreen(),
                      Destination.restore => const RestoreScreen(),
                      Destination.keeper => const KeeperScreen(),
                      Destination.settings => const SettingsScreen(),
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
