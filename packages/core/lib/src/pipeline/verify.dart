import 'dart:typed_data';

import 'package:core/src/crypto/account_keys.dart';
import 'package:core/src/crypto/crypto_provider.dart';
import 'package:core/src/errors.dart';
import 'package:core/src/format/durability.dart';
import 'package:core/src/pipeline/segment_packer.dart';
import 'package:core/src/pipeline/segment_reader.dart';
import 'package:core/src/storage/fragment_store.dart';
import 'package:core/src/storage/local_index.dart';
import 'package:core/src/storage/placement.dart';

/// Итог проверки.
final class VerifyReport {
  int segments = 0;
  int fragments = 0;

  /// Недостающие, недоступные и испорченные фрагменты.
  final List<FragmentProblem> problems = [];

  /// Сегменты, у которых живых фрагментов не больше порога ремонта.
  final List<Uint8List> atRisk = [];

  /// Сегменты, которые нельзя восстановить (меньше k фрагментов или
  /// расшифровка и проверка чанков не прошли).
  final List<(Uint8List, CoreException)> unrecoverable = [];

  bool get isHealthy =>
      problems.isEmpty && atRisk.isEmpty && unrecoverable.isEmpty;
}

/// Проверка сохранённых сегментов (задача 1.6.4).
///
/// Быстрый режим: есть ли фрагменты на узлах (`HasFragments`). Полный
/// ([full]): каждый фрагмент читается и проверяется (заголовок, корень
/// Меркла, `fragment_id`), сегмент собирается из k фрагментов,
/// расшифровывается, каждый чанк сверяется с `chunk_id`.
Future<VerifyReport> runVerify({
  required CryptoProvider crypto,
  required AccountKeys keys,
  required LocalIndex index,
  required FragmentStore fragments,
  SegmentLocator? locator,
  bool full = false,
  DurabilityParameters? params,
  CancellationToken? cancel,
}) async {
  final token = cancel ?? CancellationToken();
  final threshold = (params ?? DurabilityParameters()).repairThreshold;
  final report = VerifyReport();
  final reader = SegmentReader(
    crypto: crypto,
    keys: keys,
    index: index,
    store: fragments,
    locator: locator,
    cacheSize: 0,
  );
  for (final segmentId in index.storedSegments()) {
    token.check();
    final entry = index.segment(segmentId)!;
    report.segments++;
    var alive = 0;
    final before = reader.problems.length;
    await reader.resolveNodes(segmentId);
    if (full) {
      for (final f in index.fragments(segmentId)) {
        report.fragments++;
        if (await reader.fetch(segmentId, f) != null) alive++;
      }
      if (alive >= entry.k) {
        // Сборка снова читает фрагменты: те же проблемы второй раз не нужны.
        final checked = reader.problems.length;
        try {
          await reader.segment(segmentId);
        } on CoreException catch (e) {
          report.unrecoverable.add((segmentId, e));
        }
        reader.problems.removeRange(checked, reader.problems.length);
      }
    } else {
      for (final f in index.fragments(segmentId)) {
        report.fragments++;
        final node = f.node;
        try {
          if (node == null) throw _notFound(f);
          if (!(await fragments.has(node, [f.fragmentId])).single) {
            throw _notFound(f);
          }
          alive++;
        } on CoreException catch (e) {
          reader.problems.add(
            FragmentProblem(
              segmentId: segmentId,
              index: f.number,
              node: node,
              error: e,
            ),
          );
        }
      }
    }
    report.problems.addAll(reader.problems.sublist(before));
    if (alive < entry.k) {
      report.unrecoverable.add((
        segmentId,
        InsufficientShardsException(
          available: alive,
          required: entry.k,
          segmentId: segmentId,
        ),
      ));
    } else if (alive <= threshold) {
      report.atRisk.add(segmentId);
    }
  }
  return report;
}

StorageException _notFound(FragmentEntry f) => StorageException(
  location: f.node ?? 'неизвестный узел',
  problem: StorageProblem.notFound,
  operation: 'has',
);
