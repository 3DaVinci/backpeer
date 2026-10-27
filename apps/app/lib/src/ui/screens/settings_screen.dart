import 'package:app/l10n/app_localizations.dart';
import 'package:app/src/app_scope.dart';
import 'package:app/src/ui/widgets/section.dart';
import 'package:core/core.dart' show appVersion;
import 'package:flutter/material.dart';

/// Настройки приложения: язык и тема.
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
            title: l10n.about,
            children: [Text(l10n.version(appVersion))],
          ),
        ],
      ),
    );
  }
}
