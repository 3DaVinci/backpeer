import 'dart:math';
import 'dart:typed_data';

import 'package:core/src/coordinator/coordinator_client.dart';
import 'package:core/src/crypto/account_keys.dart';
import 'package:core/src/crypto/crypto_provider.dart';
import 'package:core/src/errors.dart';
import 'package:core/src/format/durability.dart';
import 'package:core/src/pipeline/segment_packer.dart';
import 'package:core/src/pipeline/segment_reader.dart';
import 'package:core/src/storage/fragment_store.dart';
import 'package:core/src/storage/local_index.dart';
import 'package:core/src/storage/placement.dart';
import 'package:core/src/util/bytes.dart';
import 'package:fixnum/fixnum.dart';
import 'package:protocol/protocol.dart' as pb;

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

  /// Проверка по аудитам: сегменты, ни один живой фрагмент которых не
  /// прошёл аудит с границы (новые или давно не проверенные). Не ошибка.
  final List<Uint8List> unaudited = [];

  /// Проверка по аудитам: сегменты, которые сейчас ремонтируются.
  int repairing = 0;

  bool get isHealthy =>
      problems.isEmpty && atRisk.isEmpty && unrecoverable.isEmpty;

  /// Итог для истории проверок локального индекса.
  VerifyRecord toRecord(VerifyMode mode, DateTime at) => VerifyRecord(
    mode: mode,
    at: at,
    segments: segments,
    atRisk: atRisk.length,
    unrecoverable: unrecoverable.length,
    problems: problems.length,
  );
}

/// Проверка сохранённых сегментов (задача 1.6.4).
///
/// Быстрый режим: есть ли фрагменты на узлах (`HasFragments`). Полный
/// ([full]): каждый фрагмент читается и проверяется (заголовок, корень
/// Меркла, `fragment_id`), сегмент собирается из k фрагментов,
/// расшифровывается, каждый чанк сверяется с `chunk_id`.
///
/// [segments] — проверить только эти сохранённые сегменты (тестовое
/// восстановление выборки, задача 4.5.2), иначе все.
Future<VerifyReport> runVerify({
  required CryptoProvider crypto,
  required AccountKeys keys,
  required LocalIndex index,
  required FragmentStore fragments,
  SegmentLocator? locator,
  bool full = false,
  List<Uint8List>? segments,
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
  for (final segmentId in segments ?? index.storedSegments()) {
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

/// Быстрая проверка по данным координатора (задача 4.5.2; protocol.md,
/// раздел 4.16): ни один узел не опрашивается и ничего не скачивается.
///
/// Для каждого сохранённого сегмента индекса координатор сообщает число
/// живых фрагментов и сколько из них прошли аудит после [auditedSince]
/// (по умолчанию — за 30 суток). Сегмент, которого координатор не знает,
/// или с живыми меньше k — невосстановим, с живыми не больше порога
/// ремонта — в риске. Порог — из ответа координатора: он мог быть задан
/// другим устройством.
Future<VerifyReport> runAuditVerify({
  required LocalIndex index,
  required CoordinatorClient client,
  DateTime? auditedSince,
  CancellationToken? cancel,
}) async {
  final token = cancel ?? CancellationToken();
  final report = VerifyReport();
  final ids = index.storedSegments();
  for (var from = 0; from < ids.length; from += maxHealthBatch) {
    token.check();
    final batch = ids.sublist(from, min(from + maxHealthBatch, ids.length));
    final response = await client.getBackupHealth(
      pb.GetBackupHealthRequest(
        segmentIds: batch,
        auditedSinceUnixMs: auditedSince == null
            ? null
            : Int64(auditedSince.millisecondsSinceEpoch),
      ),
    );
    final known = {
      for (final h in response.segments) bytesToHex(h.segmentId): h,
    };
    for (final segmentId in batch) {
      report.segments++;
      final h = known[bytesToHex(segmentId)];
      if (h == null) {
        report.unrecoverable.add((
          segmentId,
          const StorageException(
            location: 'координатор',
            problem: StorageProblem.notFound,
            operation: 'GetBackupHealth',
            cause: 'координатор не знает сегмент',
          ),
        ));
        continue;
      }
      report.fragments += h.live;
      if (h.repairing) report.repairing++;
      if (h.audited == 0) report.unaudited.add(segmentId);
      if (h.live < h.k) {
        report.unrecoverable.add((
          segmentId,
          InsufficientShardsException(
            available: h.live,
            required: h.k,
            segmentId: segmentId,
          ),
        ));
      } else if (h.live <= h.repairThreshold) {
        report.atRisk.add(segmentId);
      }
    }
  }
  return report;
}

/// Сегментов в одном запросе `GetBackupHealth`.
const maxHealthBatch = 1000;

StorageException _notFound(FragmentEntry f) => StorageException(
  location: f.node ?? 'неизвестный узел',
  problem: StorageProblem.notFound,
  operation: 'has',
);
