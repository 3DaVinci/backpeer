import 'package:app/l10n/app_localizations.dart';
import 'package:app/src/app_scope.dart';
import 'package:app/src/services/process_link.dart';
import 'package:app/src/ui/format.dart';
import 'package:app/src/ui/widgets/section.dart';
import 'package:app/src/ui/widgets/unlock_dialog.dart';
import 'package:daemon_kit/daemon_kit.dart';
import 'package:flutter/material.dart';

/// Обзор: состояние агента бэкапа и хранителя, бэкап сейчас, пауза.
class OverviewScreen extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final l10n = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([services.agent, services.node]),
      builder: (context, _) => ScreenBody(
        title: l10n.navOverview,
        children: [
          if (services.agent.status?['status'] == 'waitingForKeys')
            _KeysCard(agent: services.agent),
          _AgentCard(agent: services.agent),
          _NodeSummary(node: services.node),
        ],
      ),
    );
  }
}

String jobName(AppLocalizations l10n, Object? kind) => switch (kind) {
  'verify' => l10n.jobVerify,
  'restore' => l10n.jobRestore,
  _ => l10n.jobBackup,
};

String outcomeName(AppLocalizations l10n, Object? outcome) => switch (outcome) {
  'ok' => l10n.outcomeOk,
  'partial' => l10n.outcomePartial,
  'cancelled' => l10n.outcomeCancelled,
  _ => l10n.outcomeFailed,
};

String agentStatusName(AppLocalizations l10n, Object? status) =>
    switch (status) {
      'working' => l10n.agentStatusWorking,
      'paused' => l10n.agentStatusPaused,
      'waitingForKeys' => l10n.agentStatusWaitingForKeys,
      'stopping' => l10n.agentStatusStopping,
      _ => l10n.agentStatusIdle,
    };

/// Вызов метода с сообщением об ошибке внизу экрана.
Future<void> runAction(
  BuildContext context,
  Future<Object?> Function() action,
) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action();
  } on ControlException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(l10n.failed(e.message))));
  }
}

class _KeysCard extends StatelessWidget {
  const new({required this.agent});

  final BackgroundProcess agent;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(Icons.key_outlined, color: scheme.onPrimaryContainer),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.keysRequired,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(l10n.keysRequiredHint),
                ],
              ),
            ),
            const SizedBox(width: 16),
            FilledButton(
              onPressed: () => UnlockDialog.show(context, agent),
              child: Text(l10n.enterPassword),
            ),
          ],
        ),
      ),
    );
  }
}

class _AgentCard extends StatelessWidget {
  const new({required this.agent});

  final BackgroundProcess agent;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = agent.status;
    final connected = agent.state == LinkState.connected;
    if (status != null && status['configured'] == false) {
      return Section(
        title: l10n.processAgent,
        children: [Text(l10n.notConfigured)],
      );
    }
    final job = status?['job'] as Map<String, Object?>?;
    final last = status?['lastBackup'] as Map<String, Object?>?;
    final paused = status?['status'] == 'paused';
    final progress = job?['progress'] as Map<String, Object?>?;
    return Section(
      title: l10n.processAgent,
      trailing: status == null
          ? null
          : Chip(label: Text(agentStatusName(l10n, status['status']))),
      children: [
        if (job != null) ...[
          Text(jobName(l10n, job['kind'])),
          const SizedBox(height: 8),
          const LinearProgressIndicator(),
          if (progress != null && progress['files'] is int) ...[
            const SizedBox(height: 8),
            Text(
              l10n.jobProgress(
                l10n.filesCount(progress['files']! as int),
                formatSize(
                  l10n,
                  (progress['bytesRead'] ?? progress['bytes'] ?? 0) as int,
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
        ],
        Fact(
          l10n.lastBackup,
          last == null
              ? l10n.never
              : '${formatDateTime(l10n, last['finishedAt'])} — '
                    '${outcomeName(l10n, last['outcome'])}',
        ),
        Fact(l10n.nextBackup, switch (status?['nextBackupAt']) {
          final String at when DateTime.parse(at).isBefore(DateTime.now()) =>
            l10n.now,
          final String at => formatDateTime(l10n, at)!,
          _ => l10n.notScheduled,
        }),
        if (status?['interrupted'] == true && job == null) ...[
          const SizedBox(height: 8),
          Text(l10n.interruptedNote),
        ],
        const SizedBox(height: 16),
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
            OutlinedButton.icon(
              onPressed: connected
                  ? () => runAction(
                      context,
                      () => agent.call(paused ? 'resume' : 'pause'),
                    )
                  : null,
              icon: Icon(paused ? Icons.play_arrow : Icons.pause),
              label: Text(paused ? l10n.resume : l10n.pause),
            ),
          ],
        ),
      ],
    );
  }
}

class _NodeSummary extends StatelessWidget {
  const new({required this.node});

  final BackgroundProcess node;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = node.status;
    if (node.state != LinkState.connected || status == null) {
      return Section(title: l10n.navKeeper, children: [Text(l10n.keeperOff)]);
    }
    return Section(
      title: l10n.navKeeper,
      children: [
        Fact(l10n.keeperState, nodeStateName(l10n, status['state'])),
        Fact(
          l10n.keeperUsed,
          '${formatSize(l10n, (status['usedBytes'] ?? 0) as int)} / '
          '${formatSize(l10n, (status['quotaBytes'] ?? 0) as int)}',
        ),
      ],
    );
  }
}

String nodeStateName(AppLocalizations l10n, Object? state) => switch (state) {
  'paused' => l10n.nodePaused,
  'stopping' => l10n.nodeStopping,
  _ => l10n.nodeRunning,
};
