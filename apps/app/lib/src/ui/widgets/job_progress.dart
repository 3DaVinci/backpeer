import 'package:app/l10n/app_localizations.dart';
import 'package:app/src/ui/format.dart';
import 'package:app/src/ui/restore/restore_status.dart';
import 'package:flutter/material.dart';

/// Ход задания агента (`job` в `status`, событие `progress`): доля от
/// оценки объёма, скорость и оставшееся время, если они известны
/// (задача 5.3.3); у восстановления — чего и сколько оно ждёт (5.4.2),
/// у проверки — сколько сегментов и фрагментов проверено и что делается
/// сейчас.
class JobProgress extends StatelessWidget {
  const new({required this.job, super.key});

  final Map<String, Object?> job;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isVerify = job['kind'] == 'verify';
    final isForget = job['kind'] == 'forget';
    final p = (job['progress'] as Map<String, Object?>?) ?? const {};
    final files = p['files'] as int?;
    final totalBytes = p['totalBytes'] as int?;
    final totalFiles = p['totalFiles'] as int?;
    final segments = p['segments'] as int?;
    final totalSegments = p['totalSegments'] as int?;
    final verifyDone = p['fragments'] as int?;
    final verifyTotal = p['totalFragments'] as int?;
    // Доля — по сделанному (`doneBytes`), а не по обработанным файлам:
    // агент считает `bytes` по обходу, который уходит вперёд загрузки.
    final done = (p['doneBytes'] ?? p['bytes'] ?? p['bytesRead']) as int? ?? 0;
    final fraction = isForget
        ? _forgetFraction(p)
        : isVerify
        ? verifyTotal == null || verifyTotal == 0
              ? null
              : ((verifyDone ?? 0) / verifyTotal).clamp(0.0, 1.0)
        : totalBytes == null || totalBytes == 0
        ? null
        : (done / totalBytes).clamp(0.0, 1.0);
    final percent = fraction == null ? null : (fraction * 100).round();
    final lines = <String>[
      if (isForget)
        ..._forgetLines(l10n, p, percent)
      else if (isVerify) ...[
        if (segments != null && totalSegments != null)
          [
            l10n.verifySegments(segments, totalSegments),
            if (verifyDone != null && verifyTotal != null)
              l10n.verifyFragments(verifyDone, verifyTotal),
            if (percent != null) l10n.progressPercent(percent),
          ].join(', '),
        if (p['etaMs'] case final int eta when eta > 0)
          [
            l10n.progressEta(formatRemaining(l10n, eta)),
            if (p['elapsedMs'] case final int elapsed)
              l10n.progressElapsed(formatRemaining(l10n, elapsed)),
          ].join(', ')
        else if (p['elapsedMs'] case final int elapsed)
          l10n.progressElapsed(formatRemaining(l10n, elapsed)),
        if (p['problems'] case final int problems when problems > 0)
          l10n.verifyProblems(problems),
      ] else ...[
        if (files != null && totalFiles != null && totalBytes != null)
          [
            l10n.progressOf(l10n.filesCount(files), '$totalFiles'),
            l10n.progressOf(
              formatSize(l10n, done),
              formatSize(l10n, totalBytes),
            ),
            if (percent != null) l10n.progressPercent(percent),
          ].join(', ')
        else if (files != null && totalBytes != null)
          // Восстановление: число файлов заранее не известно, объём — да.
          [
            l10n.filesCount(files),
            l10n.progressOf(
              formatSize(l10n, done),
              formatSize(l10n, totalBytes),
            ),
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
      ],
    ];
    final detail = switch (job['kind']) {
      'backup' => _backupDetail(l10n, p),
      'verify' => _verifyDetail(l10n, p),
      'forget' => _forgetDetail(l10n, p),
      _ => null,
    };
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
        if (detail != null) ...[
          const SizedBox(height: 8),
          Text(
            detail,
            maxLines: job['kind'] == 'verify' ? 3 : 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  /// Что бэкап делает сейчас: читает файл или уже отправляет сегменты
  /// (этап `stage`, файл — `currentFile` в `progress`).
  static String? _backupDetail(AppLocalizations l10n, Map<String, Object?> p) {
    final file = p['currentFile'] as String?;
    final segments = p['segmentsStored'] as int?;
    return switch (p['stage']) {
      'walking' =>
        file == null ? l10n.backupReadingFiles : l10n.backupReading(file),
      'storing' =>
        segments == null
            ? l10n.backupStoring
            : l10n.backupStoringSegments(segments),
      'cleaning' => l10n.backupCleaning,
      _ => file == null ? null : l10n.backupReading(file),
    };
  }

  /// Что проверка делает сейчас, на каком сегменте и фрагменте она
  /// остановилась и не ждёт ли ответа узла.
  static String? _verifyDetail(AppLocalizations l10n, Map<String, Object?> p) {
    final stage = switch (p['stage']) {
      'preparing' => l10n.verifyStagePreparing,
      'checking' => l10n.verifyStageChecking,
      'reading' => l10n.verifyStageReading,
      'assembling' => l10n.verifyStageAssembling,
      'done' => l10n.verifyStageDone,
      _ => null,
    };
    final totalSegments = p['totalSegments'] as int? ?? 0;
    final fragmentTotal = p['currentSegmentFragments'] as int? ?? 0;
    final current = <String>[
      if (p['currentSegment'] case final int segment when totalSegments > 0)
        l10n.verifyCurrentSegment(segment, totalSegments),
      if (p['currentFragment'] case final int fragment when fragmentTotal > 0)
        l10n.verifyCurrentFragment(fragment, fragmentTotal),
    ];
    // Фрагмент проверяется дольше пяти секунд — скорее всего, ждём ответа
    // узла; без этой строки кажется, что проверка встала.
    final waiting =
        (p['currentFragmentMs'] as int? ?? 0) >=
        const Duration(seconds: 5).inMilliseconds;
    final parts = <String>[
      ?stage,
      if (current.isNotEmpty) current.join(', '),
      if (waiting) l10n.verifyWaitingNode,
    ];
    return parts.isEmpty ? null : parts.join(' — ');
  }

  /// Доля удаления: по снимкам, пока они удаляются или читаются, и по
  /// сегментам, когда сборка мусора убирает их с узлов.
  static double? _forgetFraction(Map<String, Object?> p) {
    final stage = p['stage'];
    if (stage == 'done') return 1;
    if (stage == 'forgetting' || stage == 'reading') {
      final done = p['snapshots'] as int?;
      final total = p['totalSnapshots'] as int?;
      if (done != null && total != null && total > 0) {
        return (done / total).clamp(0.0, 1.0);
      }
    }
    if (stage == 'deleting') {
      final done = p['segments'] as int?;
      final total = p['totalSegments'] as int?;
      if (done != null && total != null && total > 0) {
        return (done / total).clamp(0.0, 1.0);
      }
    }
    return null;
  }

  /// Строки хода удаления: снимки, сегменты, фрагменты, освобождённое
  /// место, оставшееся и прошедшее время.
  static List<String> _forgetLines(
    AppLocalizations l10n,
    Map<String, Object?> p,
    int? percent,
  ) {
    final stage = p['stage'];
    final lines = <String>[];
    final totalSnapshots = p['totalSnapshots'] as int? ?? 0;
    if ((stage == 'forgetting' || stage == 'reading') && totalSnapshots > 0) {
      final done = p['snapshots'] as int? ?? 0;
      lines.add(
        [
          l10n.forgetSnapshotsProgress(done, totalSnapshots),
          if (percent != null) l10n.progressPercent(percent),
        ].join(', '),
      );
    }
    final totalSegments = p['totalSegments'] as int? ?? 0;
    if ((stage == 'deleting' || stage == 'done') && totalSegments > 0) {
      final done = p['segments'] as int? ?? 0;
      lines.add(
        [
          l10n.forgetSegmentsProgress(done, totalSegments),
          if (percent != null) l10n.progressPercent(percent),
        ].join(', '),
      );
    }
    final fragments = p['fragmentsDeleted'] as int? ?? 0;
    if (fragments > 0) lines.add(l10n.forgetFragmentsDeleted(fragments));
    final bytes = p['bytesFreed'] as int? ?? 0;
    if (bytes > 0) lines.add(l10n.freed(formatSize(l10n, bytes)));
    if (p['etaMs'] case final int eta when eta > 0) {
      lines.add(
        [
          l10n.progressEta(formatRemaining(l10n, eta)),
          if (p['elapsedMs'] case final int elapsed)
            l10n.progressElapsed(formatRemaining(l10n, elapsed)),
        ].join(', '),
      );
    } else if (p['elapsedMs'] case final int elapsed) {
      lines.add(l10n.progressElapsed(formatRemaining(l10n, elapsed)));
    }
    if (p['problems'] case final int problems when problems > 0) {
      lines.add(l10n.forgetErrors(problems));
    }
    return lines;
  }

  /// Что удаление делает сейчас; для снимков — дату последнего удалённого.
  static String? _forgetDetail(AppLocalizations l10n, Map<String, Object?> p) {
    final stage = switch (p['stage']) {
      'preparing' => l10n.forgetStagePreparing,
      'forgetting' => l10n.forgetStageForgetting,
      'reading' => l10n.forgetStageReading,
      'scanning' => l10n.forgetStageScanning,
      'rewriting' => l10n.forgetStageRewriting,
      'cleaning' => l10n.forgetStageCleaning,
      'deleting' => l10n.forgetStageDeleting,
      'done' => l10n.forgetStageDone,
      _ => null,
    };
    final current = p['currentSnapshot'];
    final date = current is String ? formatDateTime(l10n, current) : null;
    final parts = <String>[
      ?stage,
      if (date != null) l10n.forgetCurrentSnapshot(date),
    ];
    return parts.isEmpty ? null : parts.join(' — ');
  }
}
