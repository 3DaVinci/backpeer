import 'dart:io';

import 'package:app/l10n/app_localizations.dart';
import 'package:app/src/app_scope.dart';
import 'package:app/src/ui/restore/snapshot_browser.dart';
import 'package:flutter/material.dart';

/// Куда и как восстановить (задача 5.4.2): на исходное место или в другую
/// папку, что делать с существующими файлами, сколько ждать узлы не в
/// сети. Возвращает параметры метода агента `restore` или `null`.
Future<Map<String, Object?>?> showRestoreDialog(
  BuildContext context, {
  required String snapshot,
  required List<List<String>> paths,
}) => showDialog<Map<String, Object?>>(
  context: context,
  builder: (context) => _RestoreDialog(snapshot: snapshot, paths: paths),
);

/// Папка по умолчанию — «Восстановлено» в домашней, на языке интерфейса.
String defaultRestoreFolder(AppLocalizations l10n) {
  final env = Platform.environment;
  final home = env['HOME'] ?? env['USERPROFILE'] ?? '';
  return '$home${Platform.pathSeparator}${l10n.restoredFolder}';
}

enum _Where { original, folder }

class _RestoreDialog extends StatefulWidget {
  const new({required this.snapshot, required this.paths});

  final String snapshot;
  final List<List<String>> paths;

  @override
  State<_RestoreDialog> createState() => _RestoreDialogState();
}

class _RestoreDialogState extends State<_RestoreDialog> {
  _Where _where = _Where.original;
  var _existing = 'keepBoth';
  var _waitMinutes = 60;
  final _folder = TextEditingController();
  var _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _folder.text = defaultRestoreFolder(AppLocalizations.of(context));
  }

  @override
  void dispose() {
    _folder.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final folder = await AppScope.of(context)
        .pickFolder(initialDirectory: _folder.text);
    if (folder != null && mounted) {
      setState(() {
        _folder.text = folder;
        _where = _Where.folder;
      });
    }
  }

  bool get _valid =>
      _where == _Where.original || Directory(_folder.text.trim()).isAbsolute;

  void _submit() {
    final l10n = AppLocalizations.of(context);
    Navigator.of(context).pop(<String, Object?>{
      'snapshot': widget.snapshot,
      if (widget.paths.isNotEmpty)
        'paths': [for (final p in widget.paths) sourcePath(p)],
      if (_where == _Where.original)
        'originalLocation': true
      else
        'target': _folder.text.trim(),
      'existing': _existing,
      'renameSuffix': l10n.restoredSuffix,
      'waitMinutes': _waitMinutes,
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final what = widget.paths.isEmpty
        ? l10n.restoreWholeSnapshot
        : widget.paths.length == 1
        ? sourcePath(widget.paths.single)
        : l10n.selectedCount(widget.paths.length);
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 4),
      child: Text(text, style: theme.textTheme.titleSmall),
    );
    return AlertDialog(
      title: Text(l10n.jobRestore),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.restoreWhat(what)),
              heading(l10n.restoreWhere),
              RadioGroup<_Where>(
                groupValue: _where,
                onChanged: (v) => setState(() => _where = v!),
                child: Column(
                  children: [
                    RadioListTile(
                      key: const ValueKey('where-original'),
                      contentPadding: EdgeInsets.zero,
                      value: _Where.original,
                      title: Text(l10n.restoreOriginal),
                      subtitle: Text(l10n.restoreOriginalHint),
                    ),
                    RadioListTile(
                      key: const ValueKey('where-folder'),
                      contentPadding: EdgeInsets.zero,
                      value: _Where.folder,
                      title: Text(l10n.restoreToFolder),
                    ),
                  ],
                ),
              ),
              if (_where == _Where.folder)
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const ValueKey('restore-folder'),
                        controller: _folder,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          labelText: l10n.restoreTarget,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: l10n.chooseFolder,
                      onPressed: _pick,
                      icon: const Icon(Icons.folder_open),
                    ),
                  ],
                ),
              heading(l10n.restoreExisting),
              RadioGroup<String>(
                groupValue: _existing,
                onChanged: (v) => setState(() => _existing = v!),
                child: Column(
                  children: [
                    for (final (value, label) in [
                      ('keepBoth', l10n.existingKeepBoth),
                      ('skip', l10n.existingSkip),
                      ('overwrite', l10n.existingOverwrite),
                    ])
                      RadioListTile(
                        key: ValueKey('existing-$value'),
                        contentPadding: EdgeInsets.zero,
                        value: value,
                        title: Text(label),
                      ),
                  ],
                ),
              ),
              heading(l10n.restoreWait),
              DropdownButton<int>(
                key: const ValueKey('wait'),
                isExpanded: true,
                value: _waitMinutes,
                onChanged: (v) => setState(() => _waitMinutes = v!),
                items: [
                  DropdownMenuItem(value: 0, child: Text(l10n.waitNone)),
                  DropdownMenuItem(value: 60, child: Text(l10n.waitHour)),
                  DropdownMenuItem(value: 24 * 60, child: Text(l10n.waitDay)),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const ValueKey('restore-start'),
          onPressed: _valid ? _submit : null,
          child: Text(l10n.restoreStart),
        ),
      ],
    );
  }
}
