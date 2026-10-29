import 'package:app/l10n/app_localizations.dart';
import 'package:app/src/ui/format.dart';
import 'package:app/src/ui/restore/restore_status.dart';
import 'package:flutter/material.dart';

/// Ход задания агента (`job` в `status`, событие `progress`): доля от
/// оценки объёма, скорость и оставшееся время, если они известны
/// (задача 5.3.3); у восстановления — чего и сколько оно ждёт (5.4.2).
class JobProgress extends StatelessWidget {
  const new({required this.job, super.key});

  final Map<String, Object?> job;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = (job['progress'] as Map<String, Object?>?) ?? const {};
    final files = p['files'] as int?;
    final totalBytes = p['totalBytes'] as int?;
    final totalFiles = p['totalFiles'] as int?;
    final done = (p['bytes'] ?? p['bytesRead']) as int? ?? 0;
    final fraction = totalBytes == null || totalBytes == 0
        ? null
        : (done / totalBytes).clamp(0.0, 1.0);
    final lines = <String>[
      if (files != null && totalFiles != null && totalBytes != null)
        [
          l10n.progressOf(l10n.filesCount(files), '$totalFiles'),
          l10n.progressOf(formatSize(l10n, done), formatSize(l10n, totalBytes)),
        ].join(', ')
      else if (files != null && totalBytes != null)
        // Восстановление: число файлов заранее не известно, объём — да.
        [
          l10n.filesCount(files),
          l10n.progressOf(formatSize(l10n, done), formatSize(l10n, totalBytes)),
        ].join(', ')
      else if (files != null)
        l10n.jobProgress(
          l10n.filesCount(files),
          formatSize(l10n, (p['bytesRead'] ?? p['bytes'] ?? 0) as int),
        ),
      if (p case {'bytesPerSecond': final int rate}) ...[
        [
          l10n.progressSpeed(formatSize(l10n, rate)),
          if (p['etaMs'] case final int eta)
            l10n.progressEta(formatRemaining(l10n, eta)),
        ].join(', '),
      ] else if (p['etaMs'] case final int eta)
        l10n.progressEta(formatRemaining(l10n, eta)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (job['trigger'] == 'resume') ...[
          Text(l10n.resumedNote),
          const SizedBox(height: 8),
        ],
        LinearProgressIndicator(value: fraction),
        for (final line in lines) ...[const SizedBox(height: 8), Text(line)],
        if (job['kind'] == 'restore' &&
            (p['waitingFiles'] as int? ?? 0) > 0) ...[
          const SizedBox(height: 12),
          RestoreWaiting(progress: p),
        ],
        if (job['kind'] == 'backup' && totalBytes == null && files != null) ...[
          const SizedBox(height: 4),
          Text(
            l10n.estimating,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}
