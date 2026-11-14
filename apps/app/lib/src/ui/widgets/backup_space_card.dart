import 'dart:async';

import 'package:app/l10n/app_localizations.dart';
import 'package:app/src/services/process_link.dart';
import 'package:app/src/ui/format.dart';
import 'package:app/src/ui/widgets/section.dart';
import 'package:daemon_kit/daemon_kit.dart';
import 'package:flutter/material.dart';

/// Сколько места занимают бэкапы учётной записи (метод агента `usage`):
/// объём самих данных и место фрагментов на дисках хранителей. Числа — от
/// координатора (`GetBackupHealth`): только он знает все сегменты учётной
/// записи, включая снимки других компьютеров.
class BackupSpaceCard extends StatefulWidget {
  const new({required this.agent, super.key});

  final BackgroundProcess agent;

  @override
  State<BackupSpaceCard> createState() => _BackupSpaceCardState();
}

class _BackupSpaceCardState extends State<BackupSpaceCard> {
  Map<String, Object?>? _usage;
  String? _error;
  var _noCoordinator = false;
  StreamSubscription<ControlEvent>? _events;
  var _wasConnected = false;

  @override
  void initState() {
    super.initState();
    // Бэкап, проверка и удаление меняют занятое место.
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
      final result = await widget.agent.call('usage');
      if (!mounted) return;
      setState(() {
        _usage = result;
        _error = null;
        _noCoordinator = false;
      });
    } on ControlException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.code == 'no_coordinator' ? null : e.message;
        _noCoordinator = e.code == 'no_coordinator';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final usage = _usage;
    if (_noCoordinator) {
      return Section(
        title: l10n.spaceTitle,
        children: [Text(l10n.spaceNoCoordinator)],
      );
    }
    final data = usage?['dataBytes'] as int?;
    final disks = usage?['fragmentBytes'] as int?;
    final segments = usage?['segments'] as int?;
    final loaded = data != null || disks != null || segments != null;
    return Section(
      title: l10n.spaceTitle,
      trailing: IconButton(
        tooltip: l10n.refresh,
        onPressed: widget.agent.state == LinkState.connected ? _load : null,
        icon: const Icon(Icons.refresh),
      ),
      children: [
        if (_error case final error?) Text(l10n.failed(error)),
        if (!loaded && _error == null) Text(l10n.loadingItem),
        if (data != null) Fact(l10n.spaceData, formatSize(l10n, data)),
        if (disks != null) Fact(l10n.spaceOnDisks, formatSize(l10n, disks)),
        if (segments != null)
          Fact(l10n.spaceSegments, formatCount(l10n, segments)),
        if (data != null && disks != null && disks > data) ...[
          const SizedBox(height: 8),
          Text(
            l10n.spaceRedundancy,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}
