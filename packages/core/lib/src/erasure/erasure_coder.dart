import 'dart:typed_data';

/// Erasure coding k из n (ADR-003). Реализации обязаны давать те же байты,
/// что и Rust-крейт reed-solomon-erasure (проверяется векторами
/// test-vectors/erasure/reed-solomon.json).
///
/// Неверное число буферов или буферы разной длины — [ArgumentError]
/// (ошибка программы). Нехватка фрагментов при [reconstruct] —
/// `InsufficientShardsException`.
abstract interface class ErasureCoder {
  /// Число фрагментов данных, k.
  int get dataShards;

  /// Число фрагментов чётности, n − k.
  int get parityShards;

  /// Общее число фрагментов, n.
  int get totalShards;

  /// [shards]: n буферов одинаковой длины, первые k заполнены данными.
  /// Заполняет фрагменты чётности на месте.
  void encode(List<Uint8List> shards);

  /// [shards]: n элементов, отсутствующие равны null, присутствует не меньше
  /// k. Восстанавливает все отсутствующие фрагменты на месте.
  void reconstruct(List<Uint8List?> shards);
}
