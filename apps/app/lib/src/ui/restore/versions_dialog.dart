import 'dart:async';

import 'package:app/l10n/app_localizations.dart';
import 'package:app/src/services/process_link.dart';
import 'package:app/src/ui/format.dart';
import 'package:daemon_kit/daemon_kit.dart';
import 'package:flutter/material.dart';

/// Версии файла во всех снимках (метод агента `versions`, задача 5.4.1):
/// когда менялся, когда его не было. Возвращает снимок, версию из
/// которого пользователь решил восстановить, или `null`.
Future<String?> showVersionsDialog(
  BuildContext context, {
  required BackgroundProcess agent,
  required List<String> path,
}) => showDialog<String>(
  context: context,
  builder: (context) => _VersionsDialog(agent: agent, path: path),
);

class _VersionsDialog extends StatefulWidget {
  const new({required this.agent, required this.path});

  final BackgroundProcess agent;
  final List<String> path;

  @override
  State<_VersionsDialog> createState() => _VersionsDialogState();
}

class _VersionsDialogState extends State<_VersionsDialog> {
  List<Map<String, Object?>>? _versions;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final result = await widget.agent.call('versions', {
        'path': widget.path,
      }, const Duration(minutes: 5));
      if (!mounted) return;
      setState(
        () => _versions = [
          // Новые сверху.
          for (final v in (result['versions']! as List<Object?>).reversed)
            v! as Map<String, Object?>,
        ],
      );
    } on ControlException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final versions = _versions;
    return AlertDialog(
      title: Text(l10n.versionsTitle(widget.path.last)),
      content: SizedBox(
        width: 520,
        child: switch ((versions, _error)) {
          (_, final String error) => Text(l10n.failed(error)),
          (null, _) => const Center(
            heightFactor: 2,
            child: CircularProgressIndicator(),
          ),
          (final List<Map<String, Object?>> list, _) => ListView(
            shrinkWrap: true,
            children: [
              for (final v in list)
                ListTile(
                  key: ValueKey('version-${v['snapshot']}'),
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    v['present'] != true
                        ? Icons.remove_circle_outline
                        : v['changed'] == true
                        ? Icons.edit_note
                        : Icons.check,
                    color: v['changed'] == true
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  title: Text(formatDateTime(l10n, v['createdAt']) ?? ''),
                  subtitle: Text(
                    v['present'] != true
                        ? l10n.versionAbsent
                        : [
                            if (v['changed'] == true)
                              l10n.versionChanged
                            else
                              l10n.versionSame,
                            formatSize(l10n, (v['size'] ?? 0) as int),
                            ?formatDateTime(l10n, v['mtime']),
                          ].join(' · '),
                  ),
                  trailing: v['present'] == true
                      ? TextButton(
                          onPressed: () =>
                              Navigator.of(context).pop(v['snapshot']),
                          child: Text(l10n.restoreThisVersion),
                        )
                      : null,
                ),
            ],
          ),
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.close),
        ),
      ],
    );
  }
}
