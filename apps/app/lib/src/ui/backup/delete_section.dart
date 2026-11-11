import 'dart:async';

import 'package:app/l10n/app_localizations.dart';
import 'package:app/src/services/process_link.dart';
import 'package:app/src/ui/screens/overview_screen.dart';
import 'package:app/src/ui/widgets/section.dart';
import 'package:daemon_kit/daemon_kit.dart';
import 'package:flutter/material.dart';

/// Удаление данных бэкапа этого компьютера: все снимки и их фрагменты на
/// узлах (метод агента `forget` с `all`: снимки забываются, затем сборка
/// мусора освобождает сегменты). Снимки других компьютеров учётной записи
/// не трогаются.
class DeleteSection extends StatefulWidget {
  const new({required this.agent, super.key});

  final BackgroundProcess agent;

  @override
  State<DeleteSection> createState() => _DeleteSectionState();
}

class _DeleteSectionState extends State<DeleteSection> {
  StreamSubscription<ControlEvent>? _events;

  /// Удаление уже запущено: кнопка не ждёт `job` в `status` (он появляется
  /// после ответа агента), иначе второй клик успел бы уйти и получить
  /// `busy`.
  var _deleting = false;

  @override
  void initState() {
    super.initState();
    widget.agent.addListener(_onAgent);
    _events = widget.agent.events.listen((e) {
      if (e.name == 'job_finished' && e.data['kind'] == 'forget') {
        if (mounted) setState(() => _deleting = false);
      }
    });
  }

  @override
  void dispose() {
    widget.agent.removeListener(_onAgent);
    unawaited(_events?.cancel());
    super.dispose();
  }

  void _onAgent() {
    // Связь пропала посреди удаления — снимаем блокировку, дальше решает
    // `job` в `status`.
    if (_deleting && widget.agent.state != LinkState.connected) {
      setState(() => _deleting = false);
    }
  }

  Future<void> _deleteAll(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteAllSnapshotsTitle),
        content: Text(l10n.deleteAllSnapshotsNote),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            key: const ValueKey('delete-all-confirm'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.deleteAllSnapshots),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    setState(() => _deleting = true);
    await runAction(context, () async {
      try {
        final result = await widget.agent.call('forget', const {'all': true});
        if (result['started'] == true) {
          messenger.showSnackBar(SnackBar(content: Text(l10n.deleteStarted)));
        } else if (mounted) {
          // Ключей нет — задание не началось.
          setState(() => _deleting = false);
        }
        return result;
      } on ControlException {
        if (mounted) setState(() => _deleting = false);
        rethrow;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final status = widget.agent.status;
    final job = status?['job'] as Map<String, Object?>?;
    final forgetting = job?['kind'] == 'forget' || _deleting;
    final busy = job != null;
    return Section(
      title: l10n.deleteBackup,
      children: [
        Text(l10n.deleteBackupHint),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const ValueKey('delete-all'),
          onPressed:
              widget.agent.state == LinkState.connected && !busy && !_deleting
              ? () => _deleteAll(context)
              : null,
          icon: const Icon(Icons.delete_outline),
          label: Text(l10n.deleteAllSnapshots),
          style: OutlinedButton.styleFrom(foregroundColor: scheme.error),
        ),
        if (forgetting) ...[
          const SizedBox(height: 16),
          const LinearProgressIndicator(),
          const SizedBox(height: 8),
          Text(l10n.jobForget),
        ],
      ],
    );
  }
}
