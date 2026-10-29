import 'dart:async';

import 'package:app/l10n/app_localizations.dart';
import 'package:app/src/app_scope.dart';
import 'package:app/src/services/process_link.dart';
import 'package:app/src/ui/keeper/keeper_setup.dart';
import 'package:daemon_kit/daemon_kit.dart';
import 'package:flutter/material.dart';

/// Первое, что настраивается после создания учётной записи с сервером, —
/// роль хранителя: те же настройки, что на экране «Хранитель»
/// ([showKeeperSetup]), или «Позже». Бэкап настраивается после.
class KeeperOnboarding extends StatefulWidget {
  const new({required this.onDone, super.key});

  final VoidCallback onDone;

  @override
  State<KeeperOnboarding> createState() => _KeeperOnboardingState();
}

class _KeeperOnboardingState extends State<KeeperOnboarding> {
  /// Ответ `keeper.info`.
  Map<String, Object?>? _info;
  String? _error;
  var _busy = false;
  var _requested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_requested) {
      _requested = true;
      unawaited(_loadInfo(AppScope.of(context).agent));
    }
  }

  Future<void> _loadInfo(BackgroundProcess agent) async {
    try {
      final info = await agent.call('keeper.info');
      if (mounted) setState(() => _info = info);
    } on ControlException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _setup() async {
    final agent = AppScope.of(context).agent;
    final params = await showKeeperSetup(context, agent: agent, info: _info!);
    if (params == null || !mounted) return;
    setState(() => _busy = true);
    final enabled = await enableKeeper(context, agent, params);
    if (!mounted) return;
    setState(() => _busy = false);
    if (enabled) widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(32),
      shrinkWrap: true,
      children: [
        Semantics(
          header: true,
          child: Text(
            l10n.onboardKeeperTitle,
            style: theme.textTheme.headlineSmall,
          ),
        ),
        const SizedBox(height: 16),
        Text(l10n.onboardKeeperBody),
        const SizedBox(height: 16),
        Row(
          children: [
            const Icon(Icons.lock_outline),
            const SizedBox(width: 12),
            Expanded(child: Text(l10n.keeperPrivacy)),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          l10n.onboardKeeperLater,
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        ),
        if (_busy) ...[
          const SizedBox(height: 16),
          const LinearProgressIndicator(),
        ],
        if (_error case final error?) ...[
          const SizedBox(height: 16),
          Text(
            l10n.failed(error),
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ],
        const SizedBox(height: 24),
        Row(
          children: [
            TextButton(
              key: const ValueKey('keeper-later'),
              onPressed: _busy ? null : widget.onDone,
              child: Text(l10n.later),
            ),
            const Spacer(),
            FilledButton.icon(
              key: const ValueKey('keeper-enable'),
              onPressed: _busy || _info == null ? null : _setup,
              icon: const Icon(Icons.dns_outlined),
              label: Text(l10n.keeperEnable),
            ),
          ],
        ),
      ],
    );
  }
}
