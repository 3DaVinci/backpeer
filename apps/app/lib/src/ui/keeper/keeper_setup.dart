import 'dart:async';

import 'package:app/l10n/app_localizations.dart';
import 'package:app/src/app_scope.dart';
import 'package:app/src/services/process_link.dart';
import 'package:app/src/ui/format.dart';
import 'package:daemon_kit/daemon_kit.dart';
import 'package:flutter/material.dart';

/// Пределы скорости на выбор, байт в секунду; 0 — без предела.
const List<int> speedChoices = [0, 1 << 20, 5 << 20, 10 << 20, 50 << 20];

/// Рабочие часы, в которые можно ограничить скорость сильнее
/// (правило `limits.schedule` узла).
const String workHours = 'mon-fri 09:00-18:00';

/// Предел из правила рабочих часов, которое пишет [showKeeperSetup];
/// нет правила — 0.
int workHoursLimit(List<Object?> schedule) {
  for (final rule in schedule) {
    final m = RegExp('^$workHours upload=(\\d+) download=(\\d+)\$')
        .firstMatch('$rule');
    if (m != null) return int.parse(m[1]!);
  }
  return 0;
}

/// Включение роли хранителя или изменение её настроек (задача 5.5.1):
/// папка (диск), сколько места отдать, пределы скорости и рабочие часы;
/// объяснение, что хранитель не видит содержимого. Возвращает параметры
/// метода агента `keeper.enable` или `null`.
Future<Map<String, Object?>?> showKeeperSetup(
  BuildContext context, {
  required BackgroundProcess agent,
  required Map<String, Object?> info,
}) => showDialog<Map<String, Object?>>(
  context: context,
  builder: (context) => _KeeperSetup(agent: agent, info: info),
);

class _KeeperSetup extends StatefulWidget {
  const new({required this.agent, required this.info});

  final BackgroundProcess agent;

  /// Ответ `keeper.info`.
  final Map<String, Object?> info;

  @override
  State<_KeeperSetup> createState() => _KeeperSetupState();
}

class _KeeperSetupState extends State<_KeeperSetup> {
  static const int _gb = 1000 * 1000 * 1000;

  final _folder = TextEditingController();
  final _quota = TextEditingController();
  var _upload = 0;
  var _download = 0;
  var _daytime = 0;
  int? _available;

  Map<String, Object?>? get _current =>
      widget.info['settings'] as Map<String, Object?>?;

  @override
  void initState() {
    super.initState();
    final s = _current;
    _folder.text =
        (s?['storageDir'] ?? widget.info['defaultStorageDir'] ?? '') as String;
    if (s != null) {
      _quota.text = '${(s['quotaBytes']! as int) ~/ _gb}';
      _upload = s['uploadBytesPerSecond'] as int? ?? 0;
      _download = s['downloadBytesPerSecond'] as int? ?? 0;
      _daytime = workHoursLimit((s['schedule'] as List<Object?>?) ?? const []);
    }
    unawaited(_checkDisk());
  }

  @override
  void dispose() {
    _folder.dispose();
    _quota.dispose();
    super.dispose();
  }

  Future<void> _checkDisk() async {
    try {
      final disk = await widget.agent.call('keeper.disk', {
        'path': _folder.text,
      });
      if (!mounted) return;
      setState(() {
        _available = disk['availableBytes'] as int?;
        // Сразу — половина свободного, но не больше 500 ГБ.
        if (_quota.text.isEmpty && _available != null) {
          final half = _available! ~/ 2 ~/ _gb;
          _quota.text = '${half.clamp(1, 500)}';
        }
      });
    } on ControlException {
      if (mounted) setState(() => _available = null);
    }
  }

  Future<void> _pick() async {
    final folder = await AppScope.of(context)
        .pickFolder(initialDirectory: _folder.text);
    if (folder == null || !mounted) return;
    setState(() => _folder.text = folder);
    await _checkDisk();
  }

  int? get _quotaBytes {
    final gb = int.tryParse(_quota.text.trim());
    return gb == null || gb <= 0 ? null : gb * _gb;
  }

  String? _quotaError(AppLocalizations l10n) {
    final bytes = _quotaBytes;
    if (bytes == null) return l10n.keeperQuotaInvalid;
    final min = widget.info['minQuotaBytes'] as int? ?? 0;
    if (bytes < min) return l10n.keeperQuotaInvalid;
    // Уже занятое хранителем место тоже можно отдать.
    final used = _current == null ? 0 : (_current!['quotaBytes']! as int);
    if (_available case final free? when bytes > free + used) {
      return l10n.keeperQuotaTooBig;
    }
    return null;
  }

  void _submit() {
    Navigator.of(context).pop(<String, Object?>{
      'storageDir': _folder.text.trim(),
      'quotaBytes': _quotaBytes,
      'uploadBytesPerSecond': _upload,
      'downloadBytesPerSecond': _download,
      'schedule': [
        if (_daytime > 0) '$workHours upload=$_daytime download=$_daytime',
      ],
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final error = _quotaError(l10n);
    Widget speed(String label, int value, void Function(int) onChanged) => Row(
      children: [
        SizedBox(width: 220, child: Text(label)),
        DropdownButton<int>(
          key: ValueKey('speed-$label'),
          value: speedChoices.contains(value) ? value : 0,
          onChanged: (v) => setState(() => onChanged(v!)),
          items: [
            for (final v in speedChoices)
              DropdownMenuItem(
                value: v,
                child: Text(
                  v == 0
                      ? l10n.speedUnlimited
                      : l10n.speedValue(formatSize(l10n, v)),
                ),
              ),
          ],
        ),
      ],
    );
    return AlertDialog(
      title: Text(
        _current == null ? l10n.keeperEnableTitle : l10n.keeperEditTitle,
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.lock_outline),
                  const SizedBox(width: 12),
                  Expanded(child: Text(l10n.keeperPrivacy)),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('keeper-folder'),
                      controller: _folder,
                      readOnly: true,
                      decoration: InputDecoration(
                        labelText: l10n.keeperFolder,
                        border: const OutlineInputBorder(),
                        helperText: switch (_available) {
                          final free? => l10n.keeperFree(
                            formatSize(l10n, free),
                          ),
                          null => null,
                        },
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
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('keeper-quota'),
                controller: _quota,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: l10n.keeperQuotaLabel,
                  border: const OutlineInputBorder(),
                  errorText: _quota.text.isEmpty ? null : error,
                  helperText: l10n.keeperQuotaMin,
                ),
              ),
              const SizedBox(height: 16),
              speed(l10n.keeperUpload, _upload, (v) => _upload = v),
              speed(l10n.keeperDownload, _download, (v) => _download = v),
              speed(l10n.keeperWorkHours, _daytime, (v) => _daytime = v),
              const SizedBox(height: 8),
              Text(
                l10n.keeperBackgroundNote,
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
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
          key: const ValueKey('keeper-submit'),
          onPressed: error == null ? _submit : null,
          child: Text(_current == null ? l10n.keeperEnable : l10n.save),
        ),
      ],
    );
  }
}
