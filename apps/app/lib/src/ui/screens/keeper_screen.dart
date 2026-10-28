import 'dart:async';

import 'package:app/l10n/app_localizations.dart';
import 'package:app/src/app_scope.dart';
import 'package:app/src/services/process_link.dart';
import 'package:app/src/ui/format.dart';
import 'package:app/src/ui/keeper/keeper_setup.dart';
import 'package:app/src/ui/screens/overview_screen.dart';
import 'package:app/src/ui/widgets/section.dart';
import 'package:daemon_kit/daemon_kit.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Хранитель (задачи 5.5.1, 5.5.2): включение роли через агента (ключи
/// узла и сертификат — у агента), статистика демона `node`: место, трафик,
/// как его видит координатор (доступность, репутация, аудиты), способ
/// подключения с подсказкой про порт; место под баланс бартера (этап 7);
/// выключение.
class KeeperScreen extends StatefulWidget {
  const new({super.key});

  @override
  State<KeeperScreen> createState() => _KeeperScreenState();
}

class _KeeperScreenState extends State<KeeperScreen> {
  BackgroundProcess? _agent;
  BackgroundProcess? _node;
  Map<String, Object?>? _info;
  Map<String, Object?>? _stats;
  String? _error;
  var _busy = false;
  var _loadingInfo = false;
  Timer? _poll;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = AppScope.of(context);
    if (!identical(services.agent, _agent)) {
      _agent?.removeListener(_onAgent);
      _agent = services.agent..addListener(_onAgent);
      _onAgent();
    }
    if (!identical(services.node, _node)) {
      _node = services.node;
      _poll?.cancel();
      // Трафик — метод `stats`; у `node` событий нет, поэтому опрос.
      _poll = Timer.periodic(
        const Duration(seconds: 5),
        (_) => unawaited(_loadStats()),
      );
      unawaited(_loadStats());
    }
  }

  @override
  void dispose() {
    _agent?.removeListener(_onAgent);
    _poll?.cancel();
    super.dispose();
  }

  void _onAgent() {
    if (_info == null &&
        !_loadingInfo &&
        _agent?.state == LinkState.connected &&
        _agent?.status?['configured'] == true) {
      unawaited(_loadInfo());
    }
  }

  Future<void> _loadInfo() async {
    _loadingInfo = true;
    try {
      final info = await _agent!.call('keeper.info');
      if (mounted) setState(() => _info = info);
    } on ControlException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      _loadingInfo = false;
    }
  }

  Future<void> _loadStats() async {
    final node = _node;
    if (node == null || node.state != LinkState.connected) return;
    try {
      final stats = await node.call('stats');
      if (mounted) setState(() => _stats = stats);
    } on ControlException {
      // Связь пропала — полоса сверху уже говорит об этом.
    }
  }

  Future<void> _setup() async {
    final info = _info;
    if (info == null) return;
    final params = await showKeeperSetup(context, agent: _agent!, info: info);
    if (params == null || !mounted) return;
    await _enable(params);
  }

  /// `keeper.enable`: ключи и сертификат узла, `node.yaml`, запуск.
  Future<void> _enable(Map<String, Object?> params) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final result = await _agent!.call(
        'keeper.enable',
        params,
        const Duration(minutes: 3),
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            result['started'] == true
                ? l10n.keeperEnabled
                : l10n.keeperNoBinary,
          ),
        ),
      );
    } on ControlException catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            e.code == 'no_coordinator'
                ? l10n.keeperNoCoordinator
                : l10n.failed(e.message),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
      await _loadInfo();
    }
  }

  Future<void> _disable() async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.keeperStop),
        content: Text(l10n.keeperStopConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            key: const ValueKey('keeper-stop-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.keeperStop),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    await runAction(
      context,
      () =>
          _agent!.call('keeper.disable', const {}, const Duration(minutes: 1)),
    );
    if (mounted) setState(() => _busy = false);
    await _loadInfo();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([_agent, _node]),
      builder: (context, _) {
        final node = _node!;
        final info = _info;
        final enabled = info?['enabled'] == true;
        final settings = info?['settings'] as Map<String, Object?>?;
        final running =
            node.state == LinkState.connected && node.status != null;
        final agentReady = _agent!.state == LinkState.connected && !_busy;
        return ScreenBody(
          title: l10n.navKeeper,
          children: [
            Text(l10n.keeperExplain),
            if (_busy) const LinearProgressIndicator(),
            if (_error case final error?) Text(l10n.failed(error)),
            if (!enabled && !running)
              Section(
                title: l10n.keeperEnableTitle,
                children: [
                  Text(l10n.keeperPrivacy),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    key: const ValueKey('keeper-enable'),
                    onPressed: agentReady && info != null ? _setup : null,
                    icon: const Icon(Icons.dns_outlined),
                    label: Text(l10n.keeperEnable),
                  ),
                ],
              )
            else if (!running)
              Section(
                title: l10n.processNode,
                children: [
                  Text(l10n.keeperNotRunning),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: agentReady && settings != null
                        ? () => _enable(settings)
                        : null,
                    icon: const Icon(Icons.play_arrow),
                    label: Text(l10n.keeperStart),
                  ),
                ],
              )
            else ...[
              _KeeperStats(status: node.status!, stats: _stats),
              _Standing(status: node.status!),
            ],
            Section(
              title: l10n.keeperBarter,
              children: [Text(l10n.keeperBarterSoon)],
            ),
            if (enabled || running)
              Section(
                title: l10n.keeperRole,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        key: const ValueKey('keeper-change'),
                        onPressed: agentReady && info != null ? _setup : null,
                        icon: const Icon(Icons.tune),
                        label: Text(l10n.keeperChange),
                      ),
                      if (enabled)
                        OutlinedButton.icon(
                          key: const ValueKey('keeper-stop'),
                          onPressed: agentReady ? _disable : null,
                          icon: const Icon(Icons.power_settings_new),
                          label: Text(l10n.keeperStop),
                        ),
                      Tooltip(
                        message: l10n.keeperLeaveSoon,
                        child: OutlinedButton.icon(
                          onPressed: null,
                          icon: const Icon(Icons.logout),
                          label: Text(l10n.keeperLeave),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.keeperLeaveSoon,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
          ],
        );
      },
    );
  }
}

/// Место, трафик, способ подключения (`status` и `stats` демона `node`).
class _KeeperStats extends StatelessWidget {
  const new({required this.status, required this.stats});

  final Map<String, Object?> status;
  final Map<String, Object?>? stats;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final s = status;
    String size(Object? v) => v is int ? formatSize(l10n, v) : l10n.unknown;
    final listen = s['listen'] as Map<String, Object?>?;
    final direct =
        (s['reachability'] as Map<String, Object?>?)?['reachable'] == true;
    final mapping = s['portMapping'] as Map<String, Object?>?;
    return Section(
      title: l10n.keeperStats,
      trailing: Chip(label: Text(nodeStateName(l10n, s['state']))),
      children: [
        Fact(l10n.keeperQuota, size(s['quotaBytes'])),
        Fact(l10n.keeperUsed, size(s['usedBytes'] ?? 0)),
        Fact(l10n.keeperFreeQuota, size(s['freeBytes'])),
        Fact(l10n.keeperDisk, size(s['diskAvailableBytes'])),
        if (s['storageDir'] case final String dir) Fact(l10n.keeperFolder, dir),
        Fact(l10n.keeperFragments, '${s['fragments'] ?? 0}'),
        if (stats case final st?)
          Fact(
            l10n.keeperTraffic,
            l10n.keeperTrafficValue(
              size(st['bytesSent'] ?? 0),
              size(st['bytesReceived'] ?? 0),
            ),
          ),
        Fact(l10n.keeperConnections, '${s['connections'] ?? 0}'),
        Fact(l10n.keeperReachability, connectionModes(l10n, s)),
        if (listen?['port'] case final int port when !direct) ...[
          const SizedBox(height: 8),
          Text(l10n.keeperPortHint(port), key: const ValueKey('port-hint')),
          if (mapping?['lastError'] case final String error)
            Text(
              l10n.keeperPortMappingError(error),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ],
    );
  }
}

/// Как к узлу подключаются: напрямую, по UDP после сведения, через relay.
String connectionModes(AppLocalizations l10n, Map<String, Object?> s) {
  final reachability = s['reachability'] as Map<String, Object?>?;
  if (reachability?['reachable'] == true) return l10n.keeperDirect;
  final udp = s['udp'] as Map<String, Object?>?;
  final relay = s['relay'] as Map<String, Object?>?;
  final modes = [
    if (udp != null && udp['symmetricNat'] != true) l10n.keeperUdp,
    if (relay?['connected'] == true) l10n.keeperRelay,
  ];
  if (modes.isNotEmpty) return modes.join('; ');
  if (reachability == null || reachability['checkedAt'] == null) {
    return l10n.keeperUnknown;
  }
  return l10n.keeperNoIncoming;
}

/// Как узел видит координатор (`coordinator.standing` в `status` узла,
/// из ответа на heartbeat).
class _Standing extends StatelessWidget {
  const new({required this.status});

  final Map<String, Object?> status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final link = status['coordinator'] as Map<String, Object?>?;
    final standing = link?['standing'] as Map<String, Object?>?;
    final percent = NumberFormat.percentPattern(l10n.localeName);
    return Section(
      title: l10n.keeperCoordinator,
      children: [
        Fact(l10n.keeperState, switch (link) {
          null => l10n.keeperNoCoordinatorShort,
          {'registered': true} => l10n.keeperRegistered,
          {'lastError': final String error} => l10n.keeperNotRegistered(error),
          _ => l10n.keeperWaitingCoordinator,
        }),
        if (standing != null) ...[
          Fact(
            l10n.keeperAvailability,
            percent.format(standing['availability'] as num? ?? 0),
          ),
          Fact(
            l10n.keeperReputation,
            [
              percent.format(standing['reputation'] as num? ?? 0),
              if (standing['onProbation'] == true)
                l10n.keeperProbation(
                  formatDateTime(l10n, standing['probationEndsAt']) ?? '',
                ),
            ].join(', '),
          ),
          Fact(
            l10n.keeperAudits,
            l10n.keeperAuditsValue(
              standing['auditsPassed'] as int? ?? 0,
              standing['auditsFailed'] as int? ?? 0,
            ),
          ),
          if (standing['excluded'] == true)
            Text(
              l10n.keeperExcluded,
              style: TextStyle(color: theme.colorScheme.error),
            ),
        ] else if (link?['registered'] == true)
          Text(l10n.keeperStandingSoon),
      ],
    );
  }
}
