import 'package:app/src/services/folder_picker.dart';
import 'package:app/src/services/preferences.dart';
import 'package:app/src/services/process_link.dart';
import 'package:flutter/widgets.dart';

/// Что приложение получает снаружи: связи с двумя фоновыми процессами
/// (ADR-008) и свои настройки. В тестах — подделки.
final class AppServices {
  new({
    required this.agent,
    required this.node,
    required this.preferences,
    this.coordinator = '',
    this.pickFolder = pickFolderWithDialog,
  });

  /// Агент бэкапа.
  final BackgroundProcess agent;

  /// Демон хранителя `node`.
  final BackgroundProcess node;
  final Preferences preferences;

  /// Адрес координатора, предлагаемый для новой учётной записи; пусто —
  /// без координатора (папки на этом компьютере, для проверки).
  final String coordinator;

  /// Выбор папки диалогом ОС.
  final FolderPicker pickFolder;
}

/// Доступ к [AppServices] из любого экрана.
final class AppScope extends InheritedWidget {
  const new({required this.services, required super.child, super.key});

  final AppServices services;

  static AppServices of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.services;

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      !identical(services, oldWidget.services);
}
