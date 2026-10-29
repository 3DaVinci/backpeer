import 'package:core/src/snapshot/exclude_rules.dart';

/// Готовые наборы правил исключения (задача 5.3.1) в синтаксисе
/// [ExcludeRules]. Пользователь включает набор по имени, правила набора
/// действуют вместе с его собственными.
enum ExcludePreset {
  /// Временные файлы редакторов, браузеров и офисных программ.
  temporary([
    '*.tmp',
    '*.temp',
    '*~',
    '.~lock.*#',
    r'~$*',
    '*.swp',
    '*.swo',
    '*.part',
    '*.crdownload',
    '*.partial',
    'Thumbs.db',
    'desktop.ini',
    '.DS_Store',
  ]),

  /// Кеши программ: их можно пересоздать.
  caches([
    '.cache/',
    'Cache/',
    'Caches/',
    'cache2/',
    'GPUCache/',
    'Code Cache/',
    '__pycache__/',
    '*.pyc',
    '.thumbnails/',
  ]),

  /// Корзина.
  trash(['.Trash/', '.Trash-*/', 'Trash/', r'$RECYCLE.BIN/']),

  /// Зависимости и результаты сборки программ: восстанавливаются сборкой.
  development([
    'node_modules/',
    '.dart_tool/',
    '.gradle/',
    '.venv/',
    'venv/',
    '.tox/',
    'target/debug/',
    'target/release/',
  ]);

  new(this.rules);

  final List<String> rules;

  /// Наборы для новой настройки бэкапа.
  static const List<ExcludePreset> defaults = [temporary, caches, trash];

  /// Набор по имени; нет такого — `null`.
  static ExcludePreset? byName(String name) {
    for (final p in values) {
      if (p.name == name) return p;
    }
    return null;
  }
}
