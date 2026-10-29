import 'dart:async';

import 'package:app/l10n/app_localizations.dart';
import 'package:app/src/app_scope.dart';
import 'package:app/src/services/process_link.dart';
import 'package:app/src/services/tray.dart';
import 'package:app/src/ui/screens/overview_screen.dart' show agentStatusName;
import 'package:daemon_kit/daemon_kit.dart';
import 'package:flutter/widgets.dart';

/// Меню значка в трее по состоянию агента (задача 5.6.2): строка
/// состояния, «Сделать бэкап сейчас», пауза или продолжение, открыть окно,
/// закрыть значок.
List<TrayItem> trayItems(AppLocalizations l10n, BackgroundProcess agent) {
  final connected = agent.state == LinkState.connected;
  final status = agent.status?['status'];
  final configured = agent.status?['configured'] == true;
  final paused = status == 'paused';
  return [
    TrayItem(
      'backup',
      l10n.trayBackupNow,
      enabled: connected && configured && status != 'working' && !paused,
    ),
    TrayItem(
      paused ? 'resume' : 'pause',
      paused ? l10n.trayResume : l10n.trayPause,
      enabled: connected && configured,
    ),
    const TrayItem.separator(),
    TrayItem('open', l10n.trayOpen),
    TrayItem('quit', l10n.trayQuit),
  ];
}

String trayStatus(AppLocalizations l10n, BackgroundProcess agent) =>
    agent.state == LinkState.connected
    ? '${l10n.processAgent}: ${agentStatusName(l10n, agent.status?['status'])}'
    : l10n.linkUnavailable(l10n.processAgent);

/// Держит меню значка в согласии с агентом и выполняет его команды. Стоит
/// под `MaterialApp`: строкам меню нужен язык интерфейса.
class TrayBinding extends StatefulWidget {
  const new({required this.child, super.key});

  final Widget child;

  @override
  State<TrayBinding> createState() => _TrayBindingState();
}

class _TrayBindingState extends State<TrayBinding> {
  TrayHost? _host;
  BackgroundProcess? _agent;
  StreamSubscription<String>? _actions;
  bool _available = false;
  String? _lastStatus;
  List<TrayItem>? _lastItems;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = AppScope.of(context);
    if (_host == null && services.tray != null) {
      _host = services.tray;
      _agent = services.agent..addListener(_update);
      _actions = _host!.actions.listen(_onAction);
      unawaited(
        _host!.available().then((available) {
          _available = available;
          _update();
        }),
      );
    }
    _update();
  }

  @override
  void dispose() {
    _agent?.removeListener(_update);
    unawaited(_actions?.cancel());
    super.dispose();
  }

  void _update() {
    final host = _host;
    final agent = _agent;
    if (!_available || host == null || agent == null || !mounted) return;
    final l10n = AppLocalizations.of(context);
    final status = trayStatus(l10n, agent);
    final items = trayItems(l10n, agent);
    if (status == _lastStatus && _sameItems(items)) return;
    _lastStatus = status;
    _lastItems = items;
    unawaited(host.setMenu(status, items));
  }

  bool _sameItems(List<TrayItem> items) {
    final last = _lastItems;
    if (last == null || last.length != items.length) return false;
    for (var i = 0; i < items.length; i++) {
      if (last[i] != items[i]) return false;
    }
    return true;
  }

  Future<void> _onAction(String id) async {
    final agent = _agent;
    if (agent == null) return;
    final method = switch (id) {
      'backup' => 'backup',
      'pause' => 'pause',
      'resume' => 'resume',
      _ => null,
    };
    if (method == null) return;
    try {
      await agent.call(method);
    } on ControlException {
      // Ошибку покажет окно: состояние агента обновится событием.
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
