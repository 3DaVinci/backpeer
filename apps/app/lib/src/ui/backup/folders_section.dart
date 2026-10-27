import 'package:app/l10n/app_localizations.dart';
import 'package:app/src/app_scope.dart';
import 'package:app/src/services/process_link.dart';
import 'package:app/src/ui/format.dart';
import 'package:app/src/ui/screens/backup_screen.dart';
import 'package:app/src/ui/widgets/section.dart';
import 'package:daemon_kit/daemon_kit.dart';
import 'package:flutter/material.dart';

/// Готовые наборы исключений агента (`ExcludePreset` в `core`).
const excludePresets = ['temporary', 'caches', 'trash', 'development'];

String presetName(AppLocalizations l10n, String preset) => switch (preset) {
  'temporary' => l10n.presetTemporary,
  'caches' => l10n.presetCaches,
  'trash' => l10n.presetTrash,
  _ => l10n.presetDevelopment,
};

/// Папки, исключения и оценка объёма до бэкапа (задача 5.3.1).
class FoldersSection extends StatefulWidget {
  const new({required this.agent, required this.settings, super.key});

  final BackgroundProcess agent;
  final Map<String, Object?> settings;

  @override
  State<FoldersSection> createState() => _FoldersSectionState();
}

class _FoldersSectionState extends State<FoldersSection> {
  Map<String, Object?>? _estimate;
  String? _error;
  var _estimating = false;

  List<String> _strings(String key) => [
    for (final v in (widget.settings[key] as List<Object?>?) ?? const []) '$v',
  ];

  @override
  void didUpdateWidget(FoldersSection old) {
    super.didUpdateWidget(old);
    // Папки или исключения изменились — прежняя оценка уже не та.
    for (final key in ['paths', 'excludes', 'excludePresets']) {
      if ('${old.settings[key]}' != '${widget.settings[key]}') {
        _estimate = null;
      }
    }
  }

  Future<void> _addFolder() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final paths = _strings('paths');
    final String? folder;
    try {
      folder = await AppScope.of(context)
          .pickFolder(initialDirectory: paths.isEmpty ? null : paths.last);
    } on Exception {
      messenger.showSnackBar(SnackBar(content: Text(l10n.folderPickerFailed)));
      return;
    }
    if (folder == null || paths.contains(folder) || !mounted) return;
    await changeSettings(context, {
      'paths': [...paths, folder],
    });
  }

  Future<void> _addRule() async {
    final rule = await showDialog<String>(
      context: context,
      builder: (context) => const _RuleDialog(),
    );
    final trimmed = rule?.trim() ?? '';
    if (trimmed.isEmpty || !mounted) return;
    await changeSettings(context, {
      'excludes': [..._strings('excludes'), trimmed],
    });
  }

  Future<void> _runEstimate() async {
    setState(() {
      _estimating = true;
      _error = null;
    });
    try {
      // Обход большой папки может идти минуты.
      final result = await widget.agent.call(
        'estimate',
        const {},
        const Duration(minutes: 10),
      );
      if (mounted) setState(() => _estimate = result);
    } on ControlException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _estimating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final connected = widget.agent.state == LinkState.connected;
    final paths = _strings('paths');
    final presets = _strings('excludePresets');
    final rules = _strings('excludes');
    final estimate = _estimate;
    final muted = TextStyle(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return Section(
      title: l10n.backupFolders,
      trailing: TextButton.icon(
        onPressed: connected ? _addFolder : null,
        icon: const Icon(Icons.create_new_folder_outlined),
        label: Text(l10n.addFolder),
      ),
      children: [
        if (paths.isEmpty) Text(l10n.noFolders),
        for (final p in paths)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.folder_outlined),
            title: Text(p),
            trailing: IconButton(
              tooltip: l10n.removeFolder,
              onPressed: connected
                  ? () => changeSettings(context, {
                      'paths': [...paths]..remove(p),
                    })
                  : null,
              icon: const Icon(Icons.remove_circle_outline),
            ),
          ),
        const SizedBox(height: 16),
        Text(l10n.excludes, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final preset in excludePresets)
              FilterChip(
                label: Text(presetName(l10n, preset)),
                selected: presets.contains(preset),
                onSelected: connected
                    ? (on) => changeSettings(context, {
                        'excludePresets': [
                          for (final p in excludePresets)
                            if (p == preset ? on : presets.contains(p)) p,
                        ],
                      })
                    : null,
              ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: Text(l10n.customRules, style: muted)),
            TextButton.icon(
              onPressed: connected ? _addRule : null,
              icon: const Icon(Icons.add),
              label: Text(l10n.addRule),
            ),
          ],
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final rule in rules)
              InputChip(
                label: Text(rule),
                deleteButtonTooltipMessage: l10n.removeRule,
                onDeleted: connected
                    ? () => changeSettings(context, {
                        'excludes': [...rules]..remove(rule),
                      })
                    : null,
              ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: connected && paths.isNotEmpty && !_estimating
                  ? _runEstimate
                  : null,
              icon: const Icon(Icons.data_usage),
              label: Text(l10n.estimate),
            ),
            const SizedBox(width: 12),
            if (_estimating)
              const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (_error case final error?)
          Text(l10n.failed(error))
        else if (estimate == null)
          Text(l10n.estimateHint, style: muted)
        else ...[
          Text(
            l10n.estimateResult(
              l10n.filesCount(estimate['files']! as int),
              formatSize(l10n, estimate['bytes']! as int),
            ),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (estimate['excluded'] case final int n when n > 0)
            Text(l10n.estimateExcluded(n)),
          if (estimate['skipped'] case final int n when n > 0)
            Text(l10n.estimateSkipped(n)),
          if (estimate['truncated'] == true) Text(l10n.estimateTruncated),
          const SizedBox(height: 4),
          Text(l10n.estimateNetwork, style: muted),
        ],
      ],
    );
  }
}

/// Новое правило исключения.
class _RuleDialog extends StatefulWidget {
  const new();

  @override
  State<_RuleDialog> createState() => _RuleDialogState();
}

class _RuleDialogState extends State<_RuleDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.addRule),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(hintText: l10n.ruleHint),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: Text(l10n.addRule),
        ),
      ],
    );
  }
}
