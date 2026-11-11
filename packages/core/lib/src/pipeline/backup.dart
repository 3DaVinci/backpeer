import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:core/src/chunking/chunk_id.dart';
import 'package:core/src/chunking/fastcdc.dart';
import 'package:core/src/crypto/account_keys.dart';
import 'package:core/src/crypto/crypto_provider.dart';
import 'package:core/src/format/durability.dart';
import 'package:core/src/pipeline/segment_encoder.dart';
import 'package:core/src/pipeline/segment_packer.dart';
import 'package:core/src/snapshot/exclude_rules.dart';
import 'package:core/src/snapshot/fs_entry.dart';
import 'package:core/src/snapshot/manifest_objects.dart';
import 'package:core/src/snapshot/snapshot_catalog.dart';
import 'package:core/src/snapshot/tree_builder.dart';
import 'package:core/src/snapshot/walker.dart';
import 'package:core/src/storage/fragment_store.dart';
import 'package:core/src/storage/index_recovery.dart';
import 'package:core/src/storage/local_index.dart';
import 'package:core/src/storage/object_store.dart';
import 'package:core/src/storage/placement.dart';
import 'package:fixnum/fixnum.dart';
import 'package:meta/meta.dart';
import 'package:protocol/protocol.dart' as pb;

/// Прогресс бэкапа.
final class BackupProgress {
  const new({
    required this.files,
    required this.bytes,
    required this.bytesRead,
    required this.newBytes,
    required this.doneBytes,
    required this.segmentsStored,
    required this.segmentsInFlight,
    required this.elapsed,
  });

  final int files;

  /// Байт в обработанных файлах, включая неизменённые (их не читают).
  final int bytes;
  final int bytesRead;

  /// Байт новых чанков (до упаковки и кодирования).
  final int newBytes;

  /// Байт, с которыми работа уже сделана: прочитаны и сохранены на узлах
  /// (или были известны по прошлому бэкапу). Считается по прочитанному, а
  /// не по обработанным файлам: обход уходит далеко вперёд загрузки, и
  /// файл на несколько гигабайт не должен держать полосу на нуле до конца.
  /// Что сейчас в пути — открытый сегмент и запечатанные без ответов
  /// узлов, — не в счёт.
  final int doneBytes;
  final int segmentsStored;
  final int segmentsInFlight;
  final Duration elapsed;

  /// Скорость чтения, байт в секунду.
  double get readRate => elapsed.inMicroseconds == 0
      ? 0
      : bytesRead / elapsed.inMicroseconds * 1e6;
}

/// Итог бэкапа.
final class BackupResult {
  const new({
    required this.snapshot,
    required this.stats,
    required this.report,
    required this.warnings,
    required this.discardedSegments,
    required this.segmentsStored,
  });

  final pb.Snapshot snapshot;
  final TreeStats stats;

  /// Пропущенные и исключённые файлы.
  final WalkReport report;

  /// Признаки отката списка снимков.
  final List<RollbackWarning> warnings;

  /// Сегментов прерванного прошлого бэкапа, отброшенных перед этим.
  final int discardedSegments;
  final int segmentsStored;
}

/// Бэкап папок (задача 1.6.3): обход → нарезка → дедупликация →
/// упаковка → шифрование → кодирование → запись фрагментов → индексы →
/// снимок.
///
/// Продолжение прерванного бэкапа: сохранённые сегменты повторно не
/// отправляются (их чанки известны индексу), недописанные отбрасываются
/// и упаковываются заново; сегменты, сохранённые до обрыва, попадают в
/// объекты-индексы этого запуска. Неизменённые файлы не читаются.
Future<BackupResult> runBackup({
  required CryptoProvider crypto,
  required AccountKeys keys,
  required LocalIndex index,
  required FragmentStore fragments,
  required ObjectStore objects,
  required List<String> paths,
  required Uint8List deviceId,
  ExcludeRules excludes = ExcludeRules.none,
  DurabilityParameters? params,
  SegmentEncoder? encoder,
  SegmentPlacer? placer,
  int maxInFlight = 2,
  String? hostname,
  List<String> tags = const [],
  CancellationToken? cancel,
  void Function(BackupProgress)? onProgress,
  Duration progressInterval = const Duration(milliseconds: 250),
  @visibleForTesting FileSystemReader? fs,
}) async {
  if (paths.isEmpty) throw ArgumentError('Нет путей для бэкапа');
  final token = cancel ?? CancellationToken();
  final watch = Stopwatch()..start();
  final discarded = index.discardPendingSegments();
  final catalog = SnapshotCatalog(
    crypto: crypto,
    manifestKey: keys.manifestKey,
    store: objects,
    index: index,
  );
  final listing = await catalog.list();
  final ownEncoder = encoder == null;
  final codec = encoder ?? InlineSegmentEncoder(crypto);
  final durability = params ?? DurabilityParameters();
  final packer = SegmentPacker(
    crypto: crypto,
    keys: keys,
    index: index,
    store: fragments,
    encoder: codec,
    params: durability,
    placer: placer,
    maxInFlight: maxInFlight,
    cancel: token,
  );
  final walker = TreeWalker(excludes: excludes, fs: fs);
  final builder = TreeBuilder(
    walker: walker,
    cdc: FastCdc(GearTable.derive(crypto, keys.gearKey)),
    hasher: ChunkIdHasher(crypto, keys.chunkIdKey),
    sink: packer,
    index: index,
  );
  void progress() => onProgress?.call(
    BackupProgress(
      files: builder.stats.files,
      bytes: builder.stats.bytes,
      bytesRead: builder.stats.bytesRead,
      newBytes: builder.stats.newBytes,
      doneBytes: _doneBytes(builder.stats, packer),
      segmentsStored: packer.segmentsStored,
      segmentsInFlight: packer.segmentsInFlight,
      elapsed: watch.elapsed,
    ),
  );
  final timer = onProgress == null
      ? null
      : Timer.periodic(progressInterval, (_) => progress());
  try {
    final List<ChunkId> root;
    try {
      root = await builder.buildRoot(paths);
      await packer.flush();
    } on Object {
      await packer.abandon();
      rethrow;
    }
    token.check();
    await _writeIndexes(crypto, keys, index, objects);

    final mine = [
      for (final s in listing.snapshots)
        if (_sameBytes(s.deviceId, deviceId) && _samePaths(s.paths, paths)) s,
    ];
    final snapshot = pb.Snapshot(
      formatVersion: manifestFormatVersion,
      snapshotId: crypto.randomBytes(32),
      sequence: Int64(
        nextSequence([
          for (final s in listing.snapshots)
            (
              id: Uint8List.fromList(s.snapshotId),
              sequence: s.sequence.toInt(),
            ),
        ], index.maxSequence),
      ),
      parentSnapshotId: mine.isEmpty ? null : mine.last.snapshotId,
      createdAtUnixMs: Int64(DateTime.now().millisecondsSinceEpoch),
      hostname: hostname ?? Platform.localHostname,
      deviceId: deviceId,
      paths: paths,
      rootTree: root.map((c) => c.bytes),
      tags: tags,
      stats: builder.stats.toProto(),
    );
    await catalog.save(snapshot);
    progress();
    return BackupResult(
      snapshot: snapshot,
      stats: builder.stats,
      report: walker.report,
      warnings: listing.warnings,
      discardedSegments: discarded,
      segmentsStored: packer.segmentsStored,
    );
  } finally {
    timer?.cancel();
    if (ownEncoder) await codec.close();
  }
}

/// Объекты-индексы для всех сохранённых сегментов, которых ещё нет ни в
/// одном индексе, — в том числе сохранённых прерванным бэкапом.
Future<void> _writeIndexes(
  CryptoProvider crypto,
  AccountKeys keys,
  LocalIndex index,
  ObjectStore objects,
) async {
  final segments = index.segmentsNotInIndex();
  if (segments.isEmpty) return;
  final builder = IndexBuilder(() => crypto.randomBytes(32));
  segments.map(segmentRecord).forEach(builder.add);
  for (final object in builder.finish()) {
    await objects.put(
      ObjectKind.indexObject,
      Uint8List.fromList(object.indexId),
      ManifestObjects.sealIndex(crypto, keys.manifestKey, object),
    );
    index.markInIndex([
      for (final r in object.segments) Uint8List.fromList(r.segmentId),
    ]);
  }
}

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Сделано байт: прочитанное и известное из кеша за вычетом того, что ещё
/// в пути, но не больше суммы размеров обработанных файлов (оценка объёма
/// считается отдельно).
int _doneBytes(TreeStats stats, SegmentPacker packer) {
  final done = stats.knownBytes + stats.bytesRead - packer.pendingBytes;
  if (done < 0) return 0;
  return done > stats.bytes ? stats.bytes : done;
}

bool _samePaths(List<String> a, List<String> b) =>
    a.length == b.length && a.toSet().containsAll(b);
