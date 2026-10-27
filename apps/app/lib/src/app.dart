import 'package:app/l10n/app_localizations.dart';
import 'package:app/src/app_scope.dart';
import 'package:app/src/theme/app_theme.dart';
import 'package:app/src/ui/shell.dart';
import 'package:flutter/material.dart';

/// Приложение — только интерфейс (задача 5.1.1): вся работа в фоновых
/// процессах (ADR-008), экраны читают их состояние через [AppServices].
class App extends StatelessWidget {
  const new({required this.services, super.key});

  final AppServices services;

  @override
  Widget build(BuildContext context) => AppScope(
    services: services,
    child: ListenableBuilder(
      listenable: services.preferences,
      builder: (context, _) => MaterialApp(
        onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: services.preferences.themeMode,
        locale: services.preferences.locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Shell(),
      ),
    ),
  );
}
