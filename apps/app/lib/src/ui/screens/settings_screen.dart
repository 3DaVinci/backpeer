import 'dart:async';

import 'package:agent/agent.dart' show ClientServices;
import 'package:app/l10n/app_localizations.dart';
import 'package:app/src/app_scope.dart';
import 'package:app/src/services/background.dart';
import 'package:app/src/services/preferences.dart';
import 'package:app/src/services/tray.dart';
import 'package:app/src/services/update_controller.dart';
import 'package:app/src/ui/account/account_settings.dart';
import 'package:app/src/ui/widgets/section.dart';
import 'package:core/core.dart' show appVersion;
import 'package:daemon_kit/daemon_kit.dart' show ServiceState;
import 'package:flutter/material.dart';

/// Настройки: учётная запись и устройства (5.2.3), фоновая работа (5.6),
/// язык и тема.
class SettingsScreen extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final prefs = AppScope.of(context).preferences;
    final l10n = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: prefs,
      builder: (context, _) => ScreenBody(
        title: l10n.navSettings,
        children: [
          const AccountSettings(),
          if (AppScope.of(context).background case final background?)
            BackgroundSection(
              background: background,
              preferences: prefs,
              tray: AppScope.of(context).tray,
            ),
          Section(
            title: l10n.language,
            children: [
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(value: '', label: Text(l10n.languageSystem)),
                  // Названия языков — на самих языках, не переводятся.
                  const ButtonSegment(value: 'ru', label: Text('Русский')),
                  const ButtonSegment(value: 'en', label: Text('English')),
                ],
                selected: {prefs.locale?.languageCode ?? ''},
                onSelectionChanged: (v) =>
                    prefs.locale = v.single.isEmpty ? null : Locale(v.single),
              ),
            ],
          ),
          Section(
            title: l10n.theme,
            children: [
              SegmentedButton<ThemeMode>(
                segments: [
                  ButtonSegment(
                    value: ThemeMode.system,
                    label: Text(l10n.themeSystem),
                  ),
                  ButtonSegment(
                    value: ThemeMode.light,
                    label: Text(l10n.themeLight),
                    icon: const Icon(Icons.light_mode_outlined),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    label: Text(l10n.themeDark),
                    icon: const Icon(Icons.dark_mode_outlined),
                  ),
                ],
                selected: {prefs.themeMode},
                onSelectionChanged: (v) => prefs.themeMode = v.single,
              ),
            ],
          ),
          UpdateSection(
            controller: AppScope.of(context).updates,
            preferences: prefs,
          ),
          Section(
            title: l10n.about,
            children: [Text(l10n.version(appVersion))],
          ),
        ],
      ),
    );
  }
}

/// Фоновая работа (задачи 5.6.1, 5.6.2): служба агента бэкапа и значок в
/// трее при входе.
class BackgroundSection extends StatefulWidget {
  const new({
    required this.background,
    required this.preferences,
    this.tray,
    super.key,
  });

  final BackgroundControl background;
  final Preferences preferences;
  final TrayHost? tray;

  @override
  State<BackgroundSection> createState() => _BackgroundSectionState();
}

class _BackgroundSectionState extends State<BackgroundSection> {
  bool? _trayAvailable;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(widget.background.refresh());
    unawaited(
      (widget.tray?.available() ?? Future.value(false)).then((available) {
        if (mounted) setState(() => _trayAvailable = available);
      }),
    );
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.serviceRemove),
        content: Text(l10n.serviceRemoveConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            key: const ValueKey('service-remove-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.serviceRemove),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    widget.preferences.backgroundService = false;
    await _run(widget.background.uninstallAgent);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final background = widget.background;
    return ListenableBuilder(
      listenable: background,
      builder: (context, _) {
        final state = background.agentState;
        final nodeState = background.nodeState;
        const agent = ClientServices.agentName;
        const keeper = ClientServices.nodeName;
        return Section(
          title: l10n.backgroundTitle,
          children: [
            Text(l10n.backgroundExplain),
            if (_busy) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(),
            ],
            const SizedBox(height: 12),
            if (!background.available)
              Text(l10n.backgroundUnavailable)
            else ...[
              Text(
                l10n.backgroundServices,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              _ServiceRow(
                title: l10n.serviceAgent,
                state: state,
                prefix: 'agent',
                enabled: !_busy,
                onStart: () => _run(() => background.startService(agent)),
                onStop: () => _run(() => background.stopService(agent)),
                onRestart: () => _run(() => background.restartService(agent)),
              ),
              const SizedBox(height: 4),
              if (state == ServiceState.notInstalled)
                FilledButton(
                  key: const ValueKey('service-install'),
                  onPressed: _busy
                      ? null
                      : () {
                          widget.preferences.backgroundService = true;
                          unawaited(_run(background.installAgent));
                        },
                  child: Text(l10n.serviceInstall),
                )
              else if (state != null)
                OutlinedButton(
                  key: const ValueKey('service-remove'),
                  onPressed: _busy ? null : _remove,
                  child: Text(l10n.serviceRemove),
                ),
              _ServiceRow(
                title: l10n.serviceKeeper,
                state: nodeState,
                prefix: 'node',
                enabled: !_busy,
                onStart: () => _run(() => background.startService(keeper)),
                onStop: () => _run(() => background.stopService(keeper)),
                onRestart: () => _run(() => background.restartService(keeper)),
              ),
              if (nodeState == ServiceState.notInstalled)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    l10n.serviceKeeperOff,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
            if (_trayAvailable == true)
              SwitchListTile(
                key: const ValueKey('tray-at-login'),
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.trayAtLogin),
                value: background.autostart,
                onChanged: _busy
                    ? null
                    : (enabled) {
                        widget.preferences.trayAtLogin = enabled;
                        unawaited(
                          _run(() => background.setAutostart(enabled: enabled)),
                        );
                      },
              )
            else if (_trayAvailable == false)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(l10n.trayUnavailable),
              ),
            if (background.problem case final problem?)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  l10n.failed(problem),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Строка службы: название, состояние и кнопки «запустить», «остановить»,
/// «перезапустить» (задача 5.6.1).
class _ServiceRow extends StatelessWidget {
  const new({
    required this.title,
    required this.state,
    required this.prefix,
    required this.enabled,
    required this.onStart,
    required this.onStop,
    required this.onRestart,
  });

  final String title;
  final ServiceState? state;

  /// `agent` или `node` — для ключей виджетов.
  final String prefix;
  final bool enabled;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final installed = state != null && state != ServiceState.notInstalled;
    final running = state == ServiceState.running;
    final stopped = state == ServiceState.stopped;
    final stateText = switch (state) {
      ServiceState.running => l10n.serviceRunning,
      ServiceState.stopped => l10n.serviceStopped,
      ServiceState.notInstalled || null => l10n.serviceNotInstalled,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                Text(
                  stateText,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            key: ValueKey('service-$prefix-start'),
            tooltip: l10n.serviceStart,
            onPressed: enabled && stopped ? onStart : null,
            icon: const Icon(Icons.play_arrow_outlined),
          ),
          IconButton(
            key: ValueKey('service-$prefix-stop'),
            tooltip: l10n.serviceStop,
            onPressed: enabled && running ? onStop : null,
            icon: const Icon(Icons.stop_outlined),
          ),
          IconButton(
            key: ValueKey('service-$prefix-restart'),
            tooltip: l10n.serviceRestart,
            onPressed: enabled && installed ? onRestart : null,
            icon: const Icon(Icons.restart_alt),
          ),
        ],
      ),
    );
  }
}

/// Обновления (задача 5.8.2): версия, проверка, установка и настройки
/// автообновления. Без настроенных обновлений в сборке остаются только
/// переключатели.
class UpdateSection extends StatelessWidget {
  const new({required this.controller, required this.preferences, super.key});

  final UpdateController? controller;
  final Preferences preferences;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final updates = controller;
    return Section(
      title: l10n.updateTitle,
      children: [
        Text(l10n.version(appVersion)),
        if (updates != null) ...[
          const SizedBox(height: 8),
          ListenableBuilder(
            listenable: updates,
            builder: (context, _) => _UpdateStatus(controller: updates),
          ),
        ],
        const SizedBox(height: 8),
        SwitchListTile(
          key: const ValueKey('auto-update'),
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.autoUpdate),
          value: preferences.autoUpdate,
          onChanged: (v) => preferences.autoUpdate = v,
        ),
        SwitchListTile(
          key: const ValueKey('beta-channel'),
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.betaChannel),
          value: preferences.betaChannel,
          onChanged: (v) => preferences.betaChannel = v,
        ),
        SwitchListTile(
          key: const ValueKey('crash-reports'),
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.crashReports),
          subtitle: Text(l10n.crashReportsExplain),
          value: preferences.crashReports,
          onChanged: (v) => preferences.crashReports = v,
        ),
      ],
    );
  }
}

class _UpdateStatus extends StatelessWidget {
  const new({required this.controller});

  final UpdateController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final state = controller.state;
    final manifest = controller.manifest;
    final outcome = controller.outcome;
    final Widget content;
    switch (state) {
      case UpdateState.checking:
        content = _ProgressLine(text: l10n.updateChecking);
      case UpdateState.applying:
        content = _ProgressLine(text: l10n.updateApplying);
      case UpdateState.available:
        content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.updateAvailable('${manifest?.version ?? ''}')),
            if (controller.waitingForBackup) ...[
              const SizedBox(height: 4),
              Text(
                l10n.updateWaitingBackup,
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 8),
            FilledButton.icon(
              key: const ValueKey('update-install'),
              onPressed: () => unawaited(controller.applyNow()),
              icon: const Icon(Icons.download_outlined),
              label: Text(l10n.updateInstall),
            ),
          ],
        );
      case UpdateState.done:
        final url = outcome?.url;
        content = Text(
          outcome?.restartRequired == true
              ? l10n.updateRestarting
              : url == null
              ? l10n.updateUpToDate
              : l10n.updateManual(url),
        );
      case UpdateState.failed:
        content = Text(
          l10n.updateFailed(controller.error ?? ''),
          style: TextStyle(color: theme.colorScheme.error),
        );
      case UpdateState.idle:
        content = Text(
          controller.checked ? l10n.updateUpToDate : l10n.updateNeverChecked,
        );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        content,
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const ValueKey('update-check'),
          onPressed: controller.busy
              ? null
              : () => unawaited(controller.checkNow()),
          icon: const Icon(Icons.refresh),
          label: Text(l10n.updateCheck),
        ),
      ],
    );
  }
}

class _ProgressLine extends StatelessWidget {
  const new({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      const SizedBox(width: 8),
      Expanded(child: Text(text)),
    ],
  );
}
