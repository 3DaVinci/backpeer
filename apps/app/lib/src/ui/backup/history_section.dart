import 'dart:async';

import 'package:app/l10n/app_localizations.dart';
import 'package:app/src/services/process_link.dart';
import 'package:app/src/ui/format.dart';
import 'package:app/src/ui/screens/overview_screen.dart';
import 'package:app/src/ui/widgets/section.dart';
import 'package:daemon_kit/daemon_kit.dart';
import 'package:flutter/material.dart';

/// История заданий агента (задача 5.3.3, метод `history`): бэкапы,
/// проверки и восстановления с итогом; остановленный бэкап — с пометкой,
/// что он продолжится, продолжение — с пометкой «продолжение»; ошибки и
/// пропущенные файлы с объяснением — в подробностях.
class HistorySection extends StatefulWidget {
  const new({required this.agent, super.key});

  final BackgroundProcess agent;

  @override
  State<HistorySection> createState() => _HistorySectionState();
}

class _HistorySectionState extends State<HistorySection> {
  List<Map<String, Object?>>? _jobs;
  String? _error;
  StreamSubscription<ControlEvent>? _events;
  var _wasConnected = false;

  @override
  void initState() {
    super.initState();
    _events = widget.agent.events.listen((e) {
      if (e.name == 'job_finished') unawaited(_load());
    });
    widget.agent.addListener(_onAgent);
    _onAgent();
  }

  @override
  void dispose() {
    unawaited(_events?.cancel());
    widget.agent.removeListener(_onAgent);
    super.dispose();
  }

  /// Загрузить при подключении и после переподключения.
  void _onAgent() {
    final connected = widget.agent.state == LinkState.connected;
    if (connected && !_wasConnected) unawaited(_load());
    _wasConnected = connected;
  }

  Future<void> _load() async {
    try {
      final result = await widget.agent.call('history', {'limit': 30});
      if (!mounted) return;
      setState(() {
        _jobs = [
          for (final j in (result['jobs'] as List<Object?>?) ?? const [])
            j! as Map<String, Object?>,
        ];
        _error = null;
      });
    } on ControlException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final jobs = _jobs;
    return Section(
      title: l10n.history,
      trailing: IconButton(
        tooltip: l10n.refresh,
        onPressed: widget.agent.state == LinkState.connected ? _load : null,
        icon: const Icon(Icons.refresh),
      ),
      children: [
        if (_error case final error?) Text(l10n.failed(error)),
        if (jobs != null && jobs.isEmpty) Text(l10n.noHistory),
        for (final job in jobs ?? const <Map<String, Object?>>[])
          _JobTile(job: job),
        const SizedBox(height: 8),
        Text(
          l10n.snapshotsOnRestore,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

String _trigger(AppLocalizations l10n, Object? trigger) => switch (trigger) {
  'schedule' => l10n.triggerSchedule,
  'resume' => l10n.triggerResume,
  _ => l10n.triggerManual,
};

/// Сводка итога одной строкой.
String jobSummary(AppLocalizations l10n, Map<String, Object?> job) {
  final r = (job['result'] as Map<String, Object?>?) ?? const {};
  final parts = <String>[];
  switch (job['outcome']) {
    case 'failed':
      parts.add(l10n.errorText('${job['error'] ?? ''}'));
    case 'cancelled':
      parts.add(switch (r['reason']) {
        'on_battery' => l10n.reasonOnBattery,
        'paused' => l10n.reasonPaused,
        _ => l10n.outcomeCancelled,
      });
      if (r['continues'] == true) parts.add(l10n.historyContinues);
    default:
      if (r['files'] case final int files) {
        parts.add(
          l10n.snapshotSummary(
            l10n.filesCount(files),
            formatSize(l10n, (r['bytes'] ?? 0) as int),
          ),
        );
      }
      if (r['newBytes'] case final int n when n > 0) {
        parts.add(l10n.newData(formatSize(l10n, n)));
      }
      if (r['segments'] case final int n when job['kind'] == 'verify') {
        parts.add(l10n.verifyResult(n));
      }
      if (r['skipped'] case final int n when n > 0) {
        parts.add(l10n.skippedCount(n));
      }
      if (r['retention'] case {'forgotten': final int n} when n > 0) {
        parts.add(l10n.retentionResult(n));
      }
      if (job['kind'] == 'forget') {
        if (r['snapshots'] case final int n) {
          parts.add(l10n.forgetSnapshotsDeleted(n));
        }
        if (r['bytesFreed'] case final int b when b > 0) {
          parts.add(l10n.freed(formatSize(l10n, b)));
        }
        // Снимки забыты, а мусор не убран (например, недописанный бэкап):
        // повторить удаление стоит после бэкапа.
        if (r['gcError'] case final String error) parts.add(l10n.failed(error));
      }
  }
  return parts.join(', ');
}

class _JobTile extends StatelessWidget {
  const new({required this.job});

  final Map<String, Object?> job;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final outcome = job['outcome'];
    final (icon, color) = switch (outcome) {
      'ok' => (Icons.check_circle_outline, scheme.primary),
      'partial' => (Icons.warning_amber, scheme.tertiary),
      'cancelled' => (Icons.pause_circle_outline, scheme.onSurfaceVariant),
      _ => (Icons.error_outline, scheme.error),
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: color),
      title: Text(
        '${jobName(l10n, job['kind'])} — ${outcomeName(l10n, outcome)} '
        '(${_trigger(l10n, job['trigger'])})',
      ),
      subtitle: Text(
        [
          ?formatDateTime(l10n, job['finishedAt']),
          jobSummary(l10n, job),
        ].where((s) => s.isNotEmpty).join('\n'),
      ),
      isThreeLine: true,
      trailing: IconButton(
        tooltip: l10n.details,
        onPressed: () => showDialog<void>(
          context: context,
          builder: (context) => _JobDetails(job: job),
        ),
        icon: const Icon(Icons.chevron_right),
      ),
    );
  }
}

class _JobDetails extends StatelessWidget {
  const new({required this.job});

  final Map<String, Object?> job;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final r = (job['result'] as Map<String, Object?>?) ?? const {};
    final skipped = [
      for (final s in (r['skippedFiles'] as List<Object?>?) ?? const [])
        s! as Map<String, Object?>,
    ];
    final retention = r['retention'] as Map<String, Object?>?;
    return AlertDialog(
      title: Text(
        '${jobName(l10n, job['kind'])} — ${outcomeName(l10n, job['outcome'])}',
      ),
      content: SizedBox(
        width: 560,
        child: ListView(
          shrinkWrap: true,
          children: [
            Fact(l10n.history, formatDateTime(l10n, job['startedAt']) ?? ''),
            Text(jobSummary(l10n, job)),
            if (retention case {'forgotten': final int n} when n > 0)
              Text(
                [
                  l10n.retentionResult(n),
                  if (retention['bytesFreed'] case final int b when b > 0)
                    l10n.freed(formatSize(l10n, b)),
                ].join(', '),
              ),
            if (skipped.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                l10n.skippedTitle,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(l10n.skippedExplain),
              for (final s in skipped)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.block, size: 18),
                  title: Text('${s['path']}'),
                  subtitle: Text(
                    [
                      if (s['reason'] == 'special')
                        l10n.skipReasonSpecial
                      else
                        l10n.skipReasonError,
                      if (s['detail'] case final String d) d,
                    ].join(': '),
                  ),
                ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.close),
        ),
      ],
    );
  }
}
