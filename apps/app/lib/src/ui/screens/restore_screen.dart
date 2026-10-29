import 'dart:async';

import 'package:app/l10n/app_localizations.dart';
import 'package:app/src/app_scope.dart';
import 'package:app/src/services/process_link.dart';
import 'package:app/src/ui/format.dart';
import 'package:app/src/ui/restore/restore_dialog.dart';
import 'package:app/src/ui/restore/restore_status.dart';
import 'package:app/src/ui/restore/snapshot_browser.dart';
import 'package:app/src/ui/screens/overview_screen.dart';
import 'package:app/src/ui/widgets/job_progress.dart';
import 'package:app/src/ui/widgets/section.dart';
import 'package:daemon_kit/daemon_kit.dart';
import 'package:flutter/material.dart';

/// Восстановление (задачи 5.4.1, 5.4.2): список снимков, дерево снимка с
/// поиском и версиями файла, восстановление выбранного с выбором места и
/// поведения с существующими файлами, ход с ожиданием узлов, итог.
class RestoreScreen extends StatefulWidget {
  const new({super.key});

  @override
  State<RestoreScreen> createState() => _RestoreScreenState();
}

class _RestoreScreenState extends State<RestoreScreen> {
  List<Map<String, Object?>>? _snapshots;
  String? _error;
  var _loading = false;
  BackgroundProcess? _agent;

  /// Открытый снимок; `null` — список снимков.
  Map<String, Object?>? _open;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final agent = AppScope.of(context).agent;
    if (!identical(agent, _agent)) {
      _agent?.removeListener(_onAgent);
      _agent = agent..addListener(_onAgent);
      _onAgent();
    }
  }

  @override
  void dispose() {
    _agent?.removeListener(_onAgent);
    super.dispose();
  }

  /// Первая загрузка — как только агент на связи.
  void _onAgent() {
    if (_snapshots == null &&
        !_loading &&
        _error == null &&
        _agent?.state == LinkState.connected) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _agent!.call(
        'snapshots',
        const {},
        const Duration(minutes: 1),
      );
      if (!mounted) return;
      setState(() {
        _snapshots = [
          // Новые сверху.
          for (final s in (result['snapshots']! as List<Object?>).reversed)
            s! as Map<String, Object?>,
        ];
        _loading = false;
      });
    } on ControlException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _restore(String snapshot, List<List<String>> paths) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final params = await showRestoreDialog(
      context,
      snapshot: snapshot,
      paths: paths,
    );
    if (params == null || !mounted) return;
    await runAction(context, () async {
      final result = await _agent!.call('restore', params);
      if (result['started'] == true) {
        messenger.showSnackBar(SnackBar(content: Text(l10n.restoreStarted)));
      }
      return result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final agent = _agent!;
    return ListenableBuilder(
      listenable: agent,
      builder: (context, _) {
        final status = agent.status;
        final job = status?['job'] as Map<String, Object?>?;
        final restoring = job != null && job['kind'] == 'restore';
        final current = restoring
            ? Section(
                title: l10n.restoreCurrent,
                children: [
                  JobProgress(job: job),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () =>
                        runAction(context, () => agent.call('cancel')),
                    icon: const Icon(Icons.stop),
                    label: Text(l10n.cancel),
                  ),
                ],
              )
            : null;
        if (_open case final snapshot?) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (current != null) ...[current, const SizedBox(height: 16)],
                Expanded(
                  child: SnapshotBrowser(
                    key: ValueKey(snapshot['id']),
                    agent: agent,
                    snapshot: snapshot,
                    onClose: () => setState(() => _open = null),
                    onRestore: _restore,
                  ),
                ),
              ],
            ),
          );
        }
        final snapshots = _snapshots;
        final last = status?['lastRestore'] as Map<String, Object?>?;
        return ScreenBody(
          title: l10n.navRestore,
          children: [
            ?current,
            if (!restoring && last != null) LastRestore(record: last),
            Section(
              title: l10n.snapshots,
              trailing: IconButton(
                tooltip: l10n.refresh,
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh),
              ),
              children: [
                if (_loading) const LinearProgressIndicator(),
                if (_error case final error?) Text(l10n.failed(error)),
                if (snapshots != null && snapshots.isEmpty)
                  Text(l10n.noSnapshots),
                for (final s in snapshots ?? const <Map<String, Object?>>[])
                  _SnapshotTile(
                    snapshot: s,
                    onOpen: () => setState(() => _open = s),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _SnapshotTile extends StatelessWidget {
  const new({required this.snapshot, required this.onOpen});

  final Map<String, Object?> snapshot;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final s = snapshot;
    final summary = l10n.snapshotSummary(
      l10n.filesCount(s['files']! as int),
      formatSize(l10n, s['bytes']! as int),
    );
    return ListTile(
      key: ValueKey('snapshot-${s['id']}'),
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.history),
      title: Text(formatDateTime(l10n, s['createdAt']) ?? ''),
      subtitle: Text('${(s['paths']! as List<Object?>).join(', ')}\n$summary'),
      isThreeLine: true,
      onTap: onOpen,
      trailing: IconButton(
        tooltip: l10n.restoreOpenSnapshot,
        onPressed: onOpen,
        icon: const Icon(Icons.chevron_right),
      ),
    );
  }
}
