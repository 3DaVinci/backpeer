import 'dart:typed_data';

/// Хранилище фрагментов на узлах-хранителях — граница, за которой в этапе 3
/// будет сеть (`PutFragment`, `GetFragment`, `HasFragments`,
/// `DeleteFragment` в peer.proto). Фрагменты адресуются по `fragment_id`.
/// Ошибки — `StorageException` (узел недоступен, фрагмента нет, сбой
/// записи) и ошибки проверки фрагмента при записи.
abstract interface class FragmentStore {
  /// Узлы, доступные для размещения.
  List<String> get nodes;

  /// Записывает фрагмент целиком (заголовок и тело) на [node]. Узел
  /// проверяет фрагмент (data-format.md, раздел 5) и, если задан,
  /// ожидаемый идентификатор (в сети — из талона). Возвращает
  /// `fragment_id`. Повторная запись того же фрагмента — не ошибка.
  Future<Uint8List> put(
    String node,
    Uint8List fragment, {
    Uint8List? expectedFragmentId,
  });

  /// Фрагмент целиком. Хранителю не доверяют: проверяет читающий.
  Future<Uint8List> get(String node, Uint8List fragmentId);

  /// Есть ли фрагменты на узле, по порядку запроса.
  Future<List<bool>> has(String node, List<Uint8List> fragmentIds);

  /// Удаляет фрагмент; отсутствующий — не ошибка.
  Future<void> delete(String node, Uint8List fragmentId);
}
