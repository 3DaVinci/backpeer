import 'dart:typed_data';

import 'package:core/src/storage/fragment_store.dart';
import 'package:protocol/protocol.dart' as pb;

/// Размещение фрагментов сегмента по узлам — заглушка алгоритма
/// координатора (`AllocateSegment`): n разных узлов, по одному фрагменту на
/// узел. Начало обхода списка сдвигается по `segment_id`, чтобы сегменты
/// распределялись по узлам равномерно. Порядок результата — по номерам
/// фрагментов.
List<String> placeFragments(Uint8List segmentId, List<String> nodes, int n) {
  if (nodes.toSet().length != nodes.length) {
    throw ArgumentError('Повторяющиеся узлы');
  }
  if (nodes.length < n) {
    throw ArgumentError(
      'Узлов ${nodes.length}, нужно не меньше $n: '
      'два фрагмента сегмента на одном узле недопустимы',
    );
  }
  final start =
      ByteData.sublistView(segmentId, 0, 4).getUint32(0) % nodes.length;
  return [for (var i = 0; i < n; i++) nodes[(start + i) % nodes.length]];
}

/// Закодированный сегмент, которому нужны узлы (поля `AllocateSegment`,
/// protocol.md, раздел 5.2).
final class SegmentAllocation {
  const new({
    required this.segmentId,
    required this.k,
    required this.n,
    required this.repairThreshold,
    required this.fragmentSize,
    required this.fragmentIds,
    required this.bodyRoots,
  });

  final Uint8List segmentId;
  final int k;
  final int n;
  final int repairThreshold;

  /// Заголовок и тело одного фрагмента, байт.
  final int fragmentSize;
  final List<Uint8List> fragmentIds;
  final List<Uint8List> bodyRoots;
}

/// Куда записать фрагмент [index] сегмента.
final class FragmentTarget {
  const new({required this.index, required this.node, this.ticket});

  final int index;

  /// Имя узла в [FragmentStore].
  final String node;

  /// Талон PUT координатора; узлу его передаёт сеть (этап 3).
  final pb.Signed? ticket;
}

/// Выбор узлов под фрагменты сегмента и подтверждение загрузки — граница,
/// за которой координатор (`AllocateSegment`, `CommitSegment`, protocol.md,
/// раздел 5.2); без него — [LocalPlacer].
abstract interface class SegmentPlacer {
  /// Узлы под n фрагментов, по номерам. `null` — фрагмент не записывать
  /// (например, узел не прошёл проверку); он считается незагруженным.
  /// Повторный вызов для того же неподтверждённого сегмента — переразмещение
  /// (protocol.md, раздел 5.2): координатор освобождает прежние узлы и
  /// выдаёт новые талоны.
  Future<List<FragmentTarget?>> allocate(SegmentAllocation segment);

  /// Сообщает, какие фрагменты загружены.
  Future<void> commit(Uint8List segmentId, List<int> storedIndexes);
}

/// Где лежат фрагменты сохранённого сегмента — граница `LocateSegment`
/// (protocol.md, раздел 5.2). Нужна, когда локальный индекс не знает узлов
/// (восстановлен из объектов-индексов на новом устройстве).
abstract interface class SegmentLocator {
  /// Номер фрагмента → узел; сегмента нет — пусто.
  Future<Map<int, String>> locate(Uint8List segmentId);
}

/// [SegmentPlacer] без координатора: [placeFragments] по узлам [store].
final class LocalPlacer implements SegmentPlacer {
  new(this.store);

  final FragmentStore store;

  @override
  Future<List<FragmentTarget?>> allocate(SegmentAllocation segment) async {
    final nodes = placeFragments(segment.segmentId, store.nodes, segment.n);
    return [
      for (var i = 0; i < segment.n; i++)
        FragmentTarget(index: i, node: nodes[i]),
    ];
  }

  @override
  Future<void> commit(Uint8List segmentId, List<int> storedIndexes) async {}
}
