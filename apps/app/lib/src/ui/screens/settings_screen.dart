import 'dart:async';

import 'package:app/l10n/app_localizations.dart';
import 'package:app/src/app_scope.dart';
import 'package:app/src/services/background.dart';
import 'package:app/src/services/preferences.dart';
import 'package:app/src/services/tray.dart';
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
          Section(
            title: l10n.updateTitle,
            children: [
              SwitchListTile(
                key: const ValueKey('auto-update'),
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.autoUpdate),
                value: prefs.autoUpdate,
                onChanged: (v) => prefs.autoUpdate = v,
              ),
              SwitchListTile(
                key: const ValueKey('beta-channel'),
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.betaChannel),
                value: prefs.betaChannel,
                onChanged: (v) => prefs.betaChannel = v,
              ),
              SwitchListTile(
                key: const ValueKey('crash-reports'),
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.crashReports),
                subtitle: Text(l10n.crashReportsExplain),
                value: prefs.crashReports,
                onChanged: (v) => prefs.crashReports = v,
              ),
            ],
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
        return Section(
          title: l10n.backgroundTitle,
          children: [
            Text(l10n.backgroundExplain),
            const SizedBox(height: 12),
            if (!background.available)
              Text(l10n.backgroundUnavailable)
            else ...[
              Fact(l10n.backgroundService, switch (state) {
                ServiceState.running => l10n.serviceRunning,
                ServiceState.stopped => l10n.serviceStopped,
                ServiceState.notInstalled || null => l10n.serviceNotInstalled,
              }),
              const SizedBox(height: 8),
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
