import 'dart:typed_data';

import 'package:core/src/chunking/chunk_id.dart';
import 'package:core/src/format/segment.dart';

/// Куда построитель снимка отдаёт чанки. Реализация конвейера (1.6.3)
/// дедуплицирует по локальному индексу и упаковывает новые чанки в
/// сегменты; построитель о хранилищах не знает.
abstract interface class ChunkSink {
  /// Известен ли чанк (уже сохранён или ждёт упаковки).
  bool contains(ChunkId id);

  /// Добавляет чанк, если он новый. `true` — чанк новый и будет
  /// сохранён; `false` — уже был. Возвращённый `Future` даёт обратное
  /// давление: упаковщик может притормозить чтение файлов.
  Future<bool> add(ChunkId id, ChunkType type, Uint8List data);
}

/// [ChunkSink] в памяти — для тестов и пробных прогонов.
final class MemoryChunkSink implements ChunkSink {
  final Map<ChunkId, (ChunkType, Uint8List)> chunks = {};

  @override
  bool contains(ChunkId id) => chunks.containsKey(id);

  @override
  Future<bool> add(ChunkId id, ChunkType type, Uint8List data) async {
    if (chunks.containsKey(id)) return false;
    chunks[id] = (type, data);
    return true;
  }
}
