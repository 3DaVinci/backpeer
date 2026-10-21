import 'dart:typed_data';

/// Вид объекта манифеста (`ObjectKind` в coordinator.proto).
enum ObjectKind { snapshot, indexObject }

/// Сведения об объекте в списке (`ObjectInfo`).
final class ObjectInfo {
  const new({
    required this.id,
    required this.size,
    required this.storedAtMs,
    required this.sequence,
  });

  final Uint8List id;
  final int size;
  final int storedAtMs;

  /// Для снимка — открытый `Snapshot.sequence`, для индекса — 0.
  final int sequence;
}

/// Хранилище объектов манифеста — граница, за которой в этапе 2 будет
/// координатор (`PutObject`, `ListObjects`, `GetObject`, `DeleteObject`,
/// docs/spec/protocol.md). Объекты — непрозрачные блобы. Ошибки —
/// `StorageException`.
abstract interface class ObjectStore {
  /// Сохраняет объект; повторная запись того же идентификатора заменяет.
  Future<void> put(
    ObjectKind kind,
    Uint8List id,
    Uint8List blob, {
    int sequence = 0,
  });

  /// Все объекты вида, по возрастанию идентификатора.
  Future<List<ObjectInfo>> list(ObjectKind kind);

  /// Блоб; нет такого — `StorageException` с `StorageProblem.notFound`.
  Future<Uint8List> get(ObjectKind kind, Uint8List id);

  /// Удаляет объект; отсутствующий — не ошибка.
  Future<void> delete(ObjectKind kind, Uint8List id);
}
