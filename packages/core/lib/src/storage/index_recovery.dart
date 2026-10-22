import 'dart:typed_data';

import 'package:core/src/chunking/chunk_id.dart';
import 'package:core/src/crypto/crypto_provider.dart';
import 'package:core/src/crypto/secret_bytes.dart';
import 'package:core/src/errors.dart';
import 'package:core/src/snapshot/manifest_objects.dart';
import 'package:core/src/storage/local_index.dart';
import 'package:core/src/storage/object_store.dart';
import 'package:core/src/util/bytes.dart';
import 'package:protocol/protocol.dart' as pb;

/// Запись сегмента для объекта-индекса (manifest.md, раздел 4).
pb.SegmentRecord segmentRecord(SegmentEntry segment) => pb.SegmentRecord(
  segmentId: segment.segmentId,
  k: segment.k,
  n: segment.n,
  blobLength: segment.blobLength,
  shardSize: segment.shardSize,
  fragmentIds: segment.fragmentIds,
  chunks: [
    for (final c in segment.chunks)
      pb.ChunkEntry(
        chunkId: c.chunkId.bytes,
        type: pb.ChunkType.valueOf(c.type),
        offset: c.offset,
        length: c.length,
      ),
  ],
);

/// Сегмент из записи объекта-индекса. Битая запись — [DataFormatException].
SegmentEntry segmentEntry(pb.SegmentRecord record) {
  DataFormatException bad(String detail) => DataFormatException(
    object: 'index',
    problem: FormatProblem.invalidField,
    detail: detail,
  );
  if (record.segmentId.length != 32) throw bad('segment_id');
  if (record.k < 1 || record.k >= record.n || record.n > 255) {
    throw bad('k=${record.k}, n=${record.n}');
  }
  if (record.fragmentIds.length != record.n ||
      record.fragmentIds.any((id) => id.length != 32)) {
    throw bad('fragment_ids');
  }
  return SegmentEntry(
    segmentId: Uint8List.fromList(record.segmentId),
    k: record.k,
    n: record.n,
    blobLength: record.blobLength,
    shardSize: record.shardSize,
    fragmentIds: [for (final id in record.fragmentIds) Uint8List.fromList(id)],
    chunks: [
      for (final c in record.chunks)
        if (c.chunkId.length != 32 || c.type.value < 1 || c.length < 1)
          throw bad('chunk')
        else
          SegmentChunk(
            chunkId: ChunkId(c.chunkId),
            type: c.type.value,
            offset: c.offset,
            length: c.length,
          ),
    ],
  );
}

/// Итог восстановления индекса.
final class RecoveryReport {
  int indexesRead = 0;
  int indexesSuperseded = 0;
  int segmentsAdded = 0;
  int segmentsKnown = 0;

  /// Индексы, которые не удалось прочитать: идентификатор и ошибка.
  final List<(Uint8List, CoreException)> unreadable = [];
}

/// Восстанавливает таблицы сегментов, фрагментов и чанков локального
/// индекса из объектов-индексов (задача 1.3.5, manifest.md, раздел 4),
/// например на новом устройстве или после потери базы. Сегменты из
/// индексов уже приняты координатором, поэтому записываются как
/// сохранённые. Индексы, перечисленные в `supersedes` других, пропускаются.
/// Кеш файлов не восстанавливается: первый бэкап после этого перечитает
/// файлы, но не загрузит повторно уже сохранённые чанки.
Future<RecoveryReport> recoverIndex({
  required CryptoProvider crypto,
  required SecretBytes manifestKey,
  required ObjectStore store,
  required LocalIndex index,
}) async {
  final report = RecoveryReport();
  final loaded = <pb.Index>[];
  for (final info in await store.list(ObjectKind.indexObject)) {
    try {
      final blob = await store.get(ObjectKind.indexObject, info.id);
      loaded.add(
        ManifestObjects.openIndex(
          crypto,
          manifestKey,
          blob,
          expectedId: info.id,
        ),
      );
    } on CoreException catch (e) {
      report.unreadable.add((info.id, e));
    }
  }
  final superseded = {
    for (final i in loaded)
      for (final id in i.supersedes) bytesToHex(id),
  };
  for (final object in loaded) {
    if (superseded.contains(bytesToHex(object.indexId))) {
      report.indexesSuperseded++;
      continue;
    }
    report.indexesRead++;
    try {
      final entries = [for (final r in object.segments) segmentEntry(r)];
      index.transaction(() {
        for (final segment in entries) {
          if (index.hasSegment(segment.segmentId)) {
            report.segmentsKnown++;
            continue;
          }
          index
            ..addSegment(segment)
            ..markSegmentStored(segment.segmentId);
          report.segmentsAdded++;
        }
      });
    } on CoreException catch (e) {
      report.indexesRead--;
      report.unreadable.add((Uint8List.fromList(object.indexId), e));
    }
  }
  return report;
}
