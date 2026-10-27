import 'package:app/l10n/app_localizations.dart';
import 'package:app/src/app_scope.dart';
import 'package:app/src/services/process_link.dart';
import 'package:app/src/ui/format.dart';
import 'package:app/src/ui/screens/overview_screen.dart';
import 'package:app/src/ui/widgets/section.dart';
import 'package:flutter/material.dart';

/// Хранитель: состояние демона `node` (метод `status`). Макет: включение
/// роли и статистика — задачи 5.5.1, 5.5.2.
class KeeperScreen extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final node = AppScope.of(context).node;
    final l10n = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: node,
      builder: (context, _) {
        final s = node.status;
        final reachability = s?['reachability'] as Map<String, Object?>?;
        return ScreenBody(
          title: l10n.navKeeper,
          children: [
            Text(l10n.keeperExplain),
            if (node.state != LinkState.connected || s == null)
              Section(title: l10n.processNode, children: [Text(l10n.keeperOff)])
            else
              Section(
                title: l10n.processNode,
                trailing: Chip(label: Text(nodeStateName(l10n, s['state']))),
                children: [
                  Fact(
                    l10n.keeperQuota,
                    formatSize(l10n, (s['quotaBytes'] ?? 0) as int),
                  ),
                  Fact(
                    l10n.keeperUsed,
                    formatSize(l10n, (s['usedBytes'] ?? 0) as int),
                  ),
                  Fact(l10n.keeperFragments, '${s['fragments'] ?? 0}'),
                  Fact(l10n.keeperConnections, '${s['connections'] ?? 0}'),
                  Fact(
                    l10n.keeperReachability,
                    switch (reachability?['reachable']) {
                      true => l10n.keeperDirect,
                      false => l10n.keeperIndirect,
                      _ => l10n.keeperUnknown,
                    },
                  ),
                ],
              ),
          ],
        );
      },
    );
  }
}
