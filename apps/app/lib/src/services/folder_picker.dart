import 'package:file_selector/file_selector.dart';

/// Выбор папки (задача 5.3.1): путь или `null`, если пользователь
/// передумал. В тестах — подделка.
typedef FolderPicker = Future<String?> Function({String? initialDirectory});

/// Диалог выбора папки ОС (`file_selector`).
Future<String?> pickFolderWithDialog({String? initialDirectory}) =>
    getDirectoryPath(initialDirectory: initialDirectory);
