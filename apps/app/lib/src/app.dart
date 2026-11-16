import 'package:app/l10n/app_localizations.dart';
import 'package:app/src/app_scope.dart';
import 'package:app/src/theme/app_theme.dart';
import 'package:app/src/ui/account/account_gate.dart';
import 'package:app/src/ui/tray_binding.dart';
import 'package:material_ui/material_ui.dart';

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
        // Делегаты — из material_ui: сгенерированный список берёт
        // GlobalMaterialLocalizations из flutter_localizations, а это
        // локализации SDK-шного Material, тогда как MaterialApp здесь и
        // виджеты — из material_ui (в Flutter 3.50 старые объявлены
        // устаревшими).
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => TrayBinding(child: child!),
        home: const AccountGate(),
      ),
    ),
  );
}
