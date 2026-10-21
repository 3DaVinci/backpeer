import 'dart:typed_data';

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
