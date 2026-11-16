/// Только чтение метаданных координатора. Панель оператора ничего не
/// меняет: блокировки, отзывы и исключения по-прежнему делаются командой
/// `coordinator admin` (ADR-007, `docs/ops/admin.md`).
abstract interface class AdminReadModel {
  /// База отвечает.
  Future<bool> ping();

  /// Сводка для первого экрана.
  Future<Map<String, Object?>> overview();

  /// Учётные записи: поиск, фильтр, сортировка и страница.
  Future<Map<String, Object?>> users({
    String query = '',
    String filter = 'all',
    String sort = 'created_desc',
    int page = 1,
    int limit = 25,
  });

  /// Учётная запись целиком; `null` — не найдена.
  Future<Map<String, Object?>?> user(String accountId);

  /// Узлы-хранители.
  Future<Map<String, Object?>> nodes({
    String query = '',
    String filter = 'active',
    String sort = 'last_seen',
    String version = '',
    String country = '',
    int page = 1,
    int limit = 25,
  });

  /// Узел целиком; `null` — не найден.
  Future<Map<String, Object?>?> node(String nodeId);

  /// Сегменты бэкапов.
  Future<Map<String, Object?>> segments({
    String query = '',
    String state = 'all',
    String sort = 'allocated_desc',
    int page = 1,
    int limit = 25,
  });

  /// Сегмент и его фрагменты; `null` — не найден.
  Future<Map<String, Object?>?> segment(String accountId, String segmentId);

  /// Живые фрагменты, аудиты, ремонт, relay и трафик за [hours].
  Future<Map<String, Object?>> network({int hours = 24});

  /// Очередь и задания ремонта и переноса.
  Future<Map<String, Object?>> repairJobs({
    String state = 'open',
    String kind = 'all',
    int page = 1,
    int limit = 25,
  });

  /// Последние аудиты.
  Future<Map<String, Object?>> audits({
    bool? passed,
    int page = 1,
    int limit = 25,
  });

  /// Балансы и журнал кредитов.
  Future<Map<String, Object?>> economy({int days = 30});

  /// Журнал действий администратора.
  Future<Map<String, Object?>> journal({
    String query = '',
    int page = 1,
    int limit = 50,
  });

  /// Схема, соединение и служебные числа.
  Future<Map<String, Object?>> system();

  /// Выгрузка учётных записей для CSV.
  Future<List<Map<String, Object?>>> exportUsers({int limit = 10000});

  /// Выгрузка узлов для CSV.
  Future<List<Map<String, Object?>>> exportNodes({int limit = 10000});
}

/// Ошибка базы или запроса, понятная оператору.
final class AdminReadException implements Exception {
  const new(this.message);

  final String message;

  @override
  String toString() => 'AdminReadException: $message';
}
