import 'dart:async';

import 'package:app/l10n/app_localizations.dart';
import 'package:app/src/app_scope.dart';
import 'package:app/src/services/process_link.dart';
import 'package:app/src/ui/format.dart';
import 'package:app/src/ui/widgets/section.dart';
import 'package:daemon_kit/daemon_kit.dart';
import 'package:flutter/material.dart';

/// Восстановление: список снимков (метод агента `snapshots`). Макет:
/// дерево снимка и восстановление — задачи 5.4.1, 5.4.2.
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
          for (final s in result['snapshots']! as List<Object?>)
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final snapshots = _snapshots;
    return ScreenBody(
      title: l10n.navRestore,
      children: [
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
            if (snapshots != null && snapshots.isEmpty) Text(l10n.noSnapshots),
            for (final s in snapshots ?? const <Map<String, Object?>>[])
              _SnapshotTile(snapshot: s),
          ],
        ),
      ],
    );
  }
}

class _SnapshotTile extends StatelessWidget {
  const new({required this.snapshot});

  final Map<String, Object?> snapshot;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final s = snapshot;
    final summary = l10n.snapshotSummary(
      l10n.filesCount(s['files']! as int),
      formatSize(l10n, s['bytes']! as int),
    );
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.history),
      title: Text(formatDateTime(l10n, s['createdAt']) ?? ''),
      subtitle: Text('${(s['paths']! as List<Object?>).join(', ')}\n$summary'),
      isThreeLine: true,
      trailing: Tooltip(
        message: l10n.comingSoon,
        child: const IconButton(
          onPressed: null,
          icon: Icon(Icons.chevron_right),
        ),
      ),
    );
  }
}
