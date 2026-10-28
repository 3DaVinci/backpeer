import 'package:app/l10n/app_localizations.dart';
import 'package:app/src/ui/format.dart';
import 'package:app/src/ui/widgets/section.dart';
import 'package:flutter/material.dart';

/// Восстановление ждёт узлы (задачи 3.9.3, 5.4.2): сколько файлов и
/// какие, почему, когда следующая попытка и сколько ещё готовы ждать.
/// Поля — из `progress` задания `restore`.
class RestoreWaiting extends StatelessWidget {
  const new({required this.progress, super.key});

  final Map<String, Object?> progress;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final count = progress['waitingFiles'] as int? ?? 0;
    final paths = [
      for (final p in (progress['waitingPaths'] as List<Object?>?) ?? const [])
        '$p',
    ];
    final muted = TextStyle(color: theme.colorScheme.onSurfaceVariant);
    return Container(
      key: const ValueKey('restore-waiting'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Semantics(
        liveRegion: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.hourglass_top, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.waitingTitle(count),
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(l10n.waitingExplain),
            const SizedBox(height: 6),
            for (final p in paths)
              Text('• $p', overflow: TextOverflow.ellipsis, style: muted),
            if (count > paths.length && paths.isNotEmpty)
              Text(l10n.andMore(count - paths.length), style: muted),
            const SizedBox(height: 6),
            if (progress['nextRetryMs'] case final int ms)
              Text(l10n.waitingRetry(formatRemaining(l10n, ms))),
            if (progress['waitLeftMs'] case final int ms)
              Text(l10n.waitingLeft(formatRemaining(l10n, ms))),
            if (progress['waitingReason'] case final String reason)
              Text(l10n.waitingReason(reason), style: muted),
          ],
        ),
      ),
    );
  }
}

/// Итог последнего восстановления (`lastRestore` в `status` агента).
class LastRestore extends StatelessWidget {
  const new({required this.record, super.key});

  final Map<String, Object?> record;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final result = (record['result'] as Map<String, Object?>?) ?? const {};
    final skipped = result['skippedExisting'] as int? ?? 0;
    final renamed = result['renamedCount'] as int? ?? 0;
    final errors = (result['errors'] as List<Object?>?) ?? const [];
    return Section(
      title: l10n.lastRestore,
      children: [
        Fact(
          l10n.restoreWhen,
          '${formatDateTime(l10n, record['finishedAt']) ?? ''} — '
          '${switch (record['outcome']) {
            'ok' => l10n.outcomeOk,
            'partial' => l10n.outcomePartial,
            'cancelled' => l10n.outcomeCancelled,
            _ => l10n.outcomeFailed,
          }}',
        ),
        if (record['error'] case final String error)
          Fact(l10n.restoreProblem, error),
        if (result.isNotEmpty) ...[
          Fact(
            l10n.restoreWhereLabel,
            result['originalLocation'] == true
                ? l10n.restoreOriginal
                : '${result['target'] ?? ''}',
          ),
          Fact(
            l10n.restoreRestored,
            l10n.snapshotSummary(
              l10n.filesCount(result['files'] as int? ?? 0),
              formatSize(l10n, result['bytes'] as int? ?? 0),
            ),
          ),
          if (skipped > 0) Fact(l10n.restoreSkippedLabel, '$skipped'),
          if (renamed > 0) Fact(l10n.restoreRenamedLabel, '$renamed'),
          if (errors.isNotEmpty) ...[
            Fact(l10n.restoreErrorsLabel, '${errors.length}'),
            for (final e in errors.take(5))
              if (e case {'path': final String path, 'reason': final reason})
                Text(
                  '• $path — $reason',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
          ],
        ],
      ],
    );
  }
}
