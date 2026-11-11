import 'dart:typed_data';

import 'package:core/src/chunking/chunk_id.dart';
import 'package:core/src/crypto/account_keys.dart';
import 'package:core/src/crypto/crypto_provider.dart';
import 'package:core/src/errors.dart';
import 'package:core/src/format/fragment.dart';
import 'package:core/src/pipeline/segment_reader.dart';
import 'package:core/src/snapshot/manifest_objects.dart';
import 'package:core/src/snapshot/snapshot_catalog.dart';
import 'package:core/src/storage/fragment_store.dart';
import 'package:core/src/storage/index_recovery.dart';
import 'package:core/src/storage/local_index.dart';
import 'package:core/src/storage/object_store.dart';
import 'package:core/src/storage/placement.dart';
import 'package:core/src/util/bytes.dart';
import 'package:protocol/protocol.dart' as pb;

/// Фрагмент, который нужно удалить с узла.
typedef FragmentLocation = ({String node, Uint8List fragmentId});

/// Освобождает ненужный сегмент в хранилище метаданных и говорит, какие
/// фрагменты удалить с узлов. С координатором — `DeleteSegment` и талоны
/// DELETE (protocol.md, раздел 5.2); без него — [LocalSegmentReleaser].
abstract interface class SegmentReleaser {
  Future<List<FragmentLocation>> release(SegmentEntry segment);
}

/// [SegmentReleaser] для папок-«узлов» без координатора: фрагмент ищется на
/// узле из локального индекса, а если узел неизвестен — на всех узлах.
final class LocalSegmentReleaser implements SegmentReleaser {
  new(this.index, this.store);

  final LocalIndex index;
  final FragmentStore store;

  @override
  Future<List<FragmentLocation>> release(SegmentEntry segment) async {
    final out = <FragmentLocation>[];
    final unknown = <Uint8List>[];
    for (final f in index.fragments(segment.segmentId)) {
      if (f.node case final String node) {
        out.add((node: node, fragmentId: f.fragmentId));
      } else {
        unknown.add(f.fragmentId);
      }
    }
    if (unknown.isEmpty) return out;
    for (final node in store.nodes) {
      final present = await store.has(node, unknown);
      for (var i = 0; i < unknown.length; i++) {
        if (present[i]) out.add((node: node, fragmentId: unknown[i]));
      }
    }
    return out;
  }
}

/// Итог сборки мусора.
final class GarbageReport {
  int snapshots = 0;
  int segmentsLive = 0;
  int segmentsDeleted = 0;
  int fragmentsDeleted = 0;
  int indexesRewritten = 0;

  /// Сегментов недописанного бэкапа отброшено (с [collectGarbage] и
  /// `discardInterrupted`: их фрагменты на узлы не попали или остались
  /// без ссылок).
  int discardedSegments = 0;

  /// Байт фрагментов (заголовок и тело) удалено с узлов.
  int bytesFreed = 0;

  /// Фрагменты, которые не удалось удалить: узел недоступен и т. п. Они
  /// остаются на узле без ссылок (уборка на стороне узла — этап 4).
  final List<(FragmentLocation, CoreException)> fragmentErrors = [];
}

/// Простая сборка мусора (manifest.md, раздел 7; задача 2.7.4): находит
/// сегменты, ни один чанк которых не нужен ни одному снимку, убирает их из
/// объектов-индексов, освобождает через [releaser] и удаляет их фрагменты
/// с узлов. Сегменты не уплотняются: сегмент, где нужен хоть один чанк,
/// остаётся целиком (`mvp-scope.md`).
///
/// Порядок выбран так, чтобы обрыв на любом шаге не терял данные:
///
/// 1. Локальный индекс сверяется с объектами-индексами (сегменты других
///    устройств), снимки читаются все — откат или нечитаемый объект
///    останавливают сборку: спрятанный снимок мог ссылаться на сегмент.
/// 2. Обход деревьев всех снимков даёт множество нужных чанков.
/// 3. Индексы с ненужными сегментами переписываются: новые индексы без
///    них, затем пустой индекс с `supersedes`, затем старые удаляются. До
///    удаления сегментов ни один индекс не ссылается на удалённое —
///    иначе другое устройство, восстановив индекс, сочло бы чанки
///    сохранёнными и не загрузило бы их снова.
/// 4. Сегменты освобождаются и удаляются с узлов, затем — из локального
///    индекса. Обрыв здесь оставляет сегмент в локальном индексе, и
///    следующая сборка его доберёт.
///
/// Ограничение версии 1: сборку нельзя запускать одновременно с бэкапом на
/// другом устройстве той же учётной записи — его новый снимок может
/// сослаться на чанк сегмента, который сборка сочла ненужным (блокировки
/// учётной записи — после MVP).
///
/// [discardInterrupted] — не считать недописанный бэкап препятствием:
/// недописанные сегменты (с `stored = 0`) отбрасываются, а сохранённые, но
/// не попавшие ни в один индекс, собираются как обычный мусор, если их
/// чанки не нужны ни одному снимку. Так `forget` освобождает место и после
/// неудачного бэкапа, когда завершить его нельзя (нет связи, кончился
/// суточный предел relay). Вызывающий обещает, что бэкап сейчас не идёт:
/// агент выполняет задания по одному, а CLI — отдельный процесс.
Future<GarbageReport> collectGarbage({
  required CryptoProvider crypto,
  required AccountKeys keys,
  required LocalIndex index,
  required FragmentStore fragments,
  required ObjectStore objects,
  required SegmentReleaser releaser,
  SegmentLocator? locator,
  bool dryRun = false,
  bool discardInterrupted = false,
}) async {
  final interrupted =
      index.pendingSegments().isNotEmpty ||
      index.segmentsNotInIndex().isNotEmpty;
  if (interrupted && !discardInterrupted) {
    throw const PreconditionException(
      'есть недописанный бэкап: сначала завершите backup',
    );
  }
  final report = GarbageReport();
  if (interrupted && !dryRun) {
    // Недописанные сегменты не попали на узлы (или попали частично):
    // следующий бэкап их всё равно отбрасывает. Сохранённые, но не
    // попавшие в индексы сегменты ниже соберутся как мусор, если они не
    // нужны ни одному снимку.
    report.discardedSegments = index.discardPendingSegments();
  }

  // 1. Индексы и снимки.
  final recovered = await recoverIndex(
    crypto: crypto,
    manifestKey: keys.manifestKey,
    store: objects,
    index: index,
  );
  if (recovered.unreadable.isNotEmpty) {
    throw const PreconditionException('есть нечитаемые объекты-индексы');
  }
  final indexes = await _liveIndexes(crypto, keys, objects, cleanUp: !dryRun);
  final catalog = SnapshotCatalog(
    crypto: crypto,
    manifestKey: keys.manifestKey,
    store: objects,
    index: index,
  );
  final listing = await catalog.list();
  if (listing.warnings.isNotEmpty || listing.unreadable.isNotEmpty) {
    throw const PreconditionException(
      'список снимков неполон (возможный откат или нечитаемый снимок)',
    );
  }
  report.snapshots = listing.snapshots.length;

  // 2. Нужные чанки.
  final reader = SegmentReader(
    crypto: crypto,
    keys: keys,
    index: index,
    store: fragments,
    locator: locator,
  );
  final referenced = <ChunkId>{};
  final visited = <String>{};
  Future<void> walk(List<ChunkId> treeChunks) async {
    if (!visited.add(treeChunks.map((c) => c.toString()).join())) return;
    referenced.addAll(treeChunks);
    final out = BytesBuilder(copy: false);
    for (final id in treeChunks) {
      out.add(await reader.chunk(id));
    }
    final bytes = out.takeBytes();
    final tree = ManifestObjects.parseMessage<pb.Tree>(
      'tree',
      () => pb.Tree.fromBuffer(bytes),
    );
    for (final node in tree.nodes) {
      for (final c in node.content) {
        referenced.add(ChunkId(Uint8List.fromList(c)));
      }
      if (node.subtree.isNotEmpty) {
        await walk([
          for (final c in node.subtree) ChunkId(Uint8List.fromList(c)),
        ]);
      }
    }
  }

  for (final snapshot in listing.snapshots) {
    await walk([
      for (final c in snapshot.rootTree) ChunkId(Uint8List.fromList(c)),
    ]);
  }

  // Сегменты: из индексов и из локального индекса (недобранные прошлой
  // сборкой).
  final segments = <String, List<ChunkId>>{};
  for (final (_, object) in indexes) {
    for (final r in object.segments) {
      segments[bytesToHex(r.segmentId)] = [
        for (final c in r.chunks) ChunkId(Uint8List.fromList(c.chunkId)),
      ];
    }
  }
  for (final id in index.storedSegments()) {
    segments.putIfAbsent(
      bytesToHex(id),
      () => [for (final c in index.segment(id)!.chunks) c.chunkId],
    );
  }
  final garbage = <String>{
    for (final MapEntry(:key, :value) in segments.entries)
      if (!value.any(referenced.contains)) key,
  };
  report.segmentsLive = segments.length - garbage.length;
  if (dryRun || garbage.isEmpty) {
    report.segmentsDeleted = garbage.length;
    return report;
  }

  // 3. Индексы без ненужных сегментов.
  final rewritten = <Uint8List>[];
  for (final (id, object) in indexes) {
    if (!object.segments.any(
      (r) => garbage.contains(bytesToHex(r.segmentId)),
    )) {
      continue;
    }
    final kept = [
      for (final r in object.segments)
        if (!garbage.contains(bytesToHex(r.segmentId))) r,
    ];
    if (kept.isNotEmpty) {
      await _putIndex(
        crypto,
        keys,
        objects,
        pb.Index(
          formatVersion: manifestFormatVersion,
          indexId: crypto.randomBytes(32),
          segments: kept,
        ),
      );
    }
    rewritten.add(id);
  }
  if (rewritten.isNotEmpty) {
    final tombstoneId = crypto.randomBytes(32);
    await _putIndex(
      crypto,
      keys,
      objects,
      pb.Index(
        formatVersion: manifestFormatVersion,
        indexId: tombstoneId,
        supersedes: rewritten,
      ),
    );
    for (final id in rewritten) {
      await objects.delete(ObjectKind.indexObject, id);
    }
    // Заменённых индексов больше нет — пустой индекс не нужен.
    await objects.delete(ObjectKind.indexObject, tombstoneId);
    report.indexesRewritten = rewritten.length;
  }

  // 4. Освобождение и удаление фрагментов.
  for (final hex in garbage) {
    final id = hexToBytes(hex);
    final segment = index.segment(id);
    if (segment == null) continue;
    final fragmentSize = FragmentHeader.length + segment.shardSize;
    for (final location in await releaser.release(segment)) {
      try {
        await fragments.delete(location.node, location.fragmentId);
        report
          ..fragmentsDeleted += 1
          ..bytesFreed += fragmentSize;
      } on CoreException catch (e) {
        report.fragmentErrors.add((location, e));
      }
    }
    index.removeSegment(id);
    report.segmentsDeleted++;
  }
  return report;
}

/// Действующие объекты-индексы (не заменённые другими) с идентификаторами.
/// С [cleanUp] убираются следы прерванной сборки или уплотнения: заменённые
/// индексы (заменяющие записаны раньше, чем индекс с `supersedes`) и пустые
/// индексы, чьих заменённых уже нет.
Future<List<(Uint8List, pb.Index)>> _liveIndexes(
  CryptoProvider crypto,
  AccountKeys keys,
  ObjectStore objects, {
  required bool cleanUp,
}) async {
  final all = <(Uint8List, pb.Index)>[];
  for (final info in await objects.list(ObjectKind.indexObject)) {
    final blob = await objects.get(ObjectKind.indexObject, info.id);
    all.add((
      info.id,
      ManifestObjects.openIndex(
        crypto,
        keys.manifestKey,
        blob,
        expectedId: info.id,
      ),
    ));
  }
  final superseded = {
    for (final (_, i) in all)
      for (final s in i.supersedes) bytesToHex(s),
  };
  final remaining = <(Uint8List, pb.Index)>[];
  for (final (id, object) in all) {
    if (!superseded.contains(bytesToHex(id))) {
      remaining.add((id, object));
    } else if (cleanUp) {
      await objects.delete(ObjectKind.indexObject, id);
    }
  }
  final ids = {for (final (id, _) in cleanUp ? remaining : all) bytesToHex(id)};
  final live = <(Uint8List, pb.Index)>[];
  for (final (id, object) in remaining) {
    final stale =
        object.segments.isEmpty &&
        !object.supersedes.any((s) => ids.contains(bytesToHex(s)));
    if (stale && cleanUp) {
      await objects.delete(ObjectKind.indexObject, id);
    } else {
      live.add((id, object));
    }
  }
  return live;
}

Future<void> _putIndex(
  CryptoProvider crypto,
  AccountKeys keys,
  ObjectStore objects,
  pb.Index object,
) => objects.put(
  ObjectKind.indexObject,
  Uint8List.fromList(object.indexId),
  ManifestObjects.sealIndex(crypto, keys.manifestKey, object),
);
