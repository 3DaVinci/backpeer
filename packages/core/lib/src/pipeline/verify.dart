import 'dart:async';
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

  /// Недостающие и испорченные фрагменты: их точно нет или они не
  /// разбираются.
  final List<FragmentProblem> problems = [];

  /// Сегменты, которые не удалось проверить: подтверждённых фрагментов
  /// меньше k, но часть фрагментов на недоступных узлах — возможно, их
  /// хватает. Это не потеря данных, а неполная проверка (нет связи с
  /// хранителями, исчерпан суточный предел relay и т. п.).
  final List<(Uint8List, CoreException)> unchecked = [];

  /// Сколько фрагментов не удалось проверить ([unchecked]).
  int uncheckedFragments = 0;

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
      problems.isEmpty &&
      atRisk.isEmpty &&
      unrecoverable.isEmpty &&
      unchecked.isEmpty;

  /// Итог для истории проверок локального индекса.
  VerifyRecord toRecord(VerifyMode mode, DateTime at) => VerifyRecord(
    mode: mode,
    at: at,
    segments: segments,
    atRisk: atRisk.length,
    unrecoverable: unrecoverable.length,
    problems: problems.length,
    unchecked: unchecked.length,
  );
}

/// Что проверка делает сейчас.
enum VerifyStage {
  /// Считает сегменты и фрагменты, готовится к проходу.
  preparing,

  /// Быстрая проверка: спрашивает узлы, на месте ли фрагменты.
  checking,

  /// Полная проверка: читает и проверяет каждый фрагмент.
  reading,

  /// Полная проверка: собирает сегмент из уже прочитанных фрагментов.
  assembling,

  /// Проверка закончена.
  done,
}

/// Ход проверки — для события `progress` и полосы в приложении.
final class VerifyProgress {
  const new({
    required this.stage,
    required this.segments,
    required this.totalSegments,
    required this.fragments,
    required this.totalFragments,
    required this.problems,
    required this.elapsed,
    this.currentSegment,
    this.currentFragment,
    this.currentSegmentFragments,
    this.currentFragmentElapsed = Duration.zero,
  });

  final VerifyStage stage;

  /// Проверено сегментов.
  final int segments;

  /// Всего сегментов.
  final int totalSegments;

  /// Проверено фрагментов.
  final int fragments;

  /// Всего фрагментов.
  final int totalFragments;

  /// Найдено недостающих или испорченных фрагментов.
  final int problems;

  final Duration elapsed;

  /// Номер проверяемого сегмента, с 1; `null` — между сегментами.
  final int? currentSegment;

  /// Номер проверяемого фрагмента в сегменте, с 1; `null` — между
  /// фрагментами или идёт сборка.
  final int? currentFragment;

  /// Сколько фрагментов в текущем сегменте.
  final int? currentSegmentFragments;

  /// Сколько длится проверка текущего фрагмента: по нему видно, что
  /// проверка ждёт ответа узла, а не встала.
  final Duration currentFragmentElapsed;

  /// Доля проверенного по фрагментам; `0` — фрагментов нет.
  double get fraction =>
      totalFragments == 0 ? 0 : (fragments / totalFragments).clamp(0.0, 1.0);

  /// Осталось по средней скорости проверки фрагментов; `null` — ещё не из
  /// чего считать.
  Duration? get eta {
    if (totalFragments == 0 || fragments == 0) return null;
    final left = totalFragments - fragments;
    if (left <= 0) return Duration.zero;
    if (elapsed < const Duration(seconds: 1)) return null;
    return Duration(microseconds: elapsed.inMicroseconds * left ~/ fragments);
  }
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
  void Function(VerifyProgress)? onProgress,
  Duration progressInterval = const Duration(milliseconds: 500),
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
  final ids = segments ?? index.storedSegments();
  final totalSegments = ids.length;
  final totalFragments = segments == null
      ? index.storedFragmentsCount()
      : ids.fold<int>(0, (total, id) {
          return total + (index.segment(id)?.n ?? 0);
        });
  final watch = Stopwatch()..start();
  var stage = VerifyStage.preparing;
  var segmentsDone = 0;
  int? currentSegment;
  int? currentFragment;
  int? currentSegmentFragments;
  var fragmentStarted = Duration.zero;
  var lastProgress = Duration.zero;

  void emit({bool force = false}) {
    final callback = onProgress;
    if (callback == null) return;
    final elapsed = watch.elapsed;
    if (!force && elapsed - lastProgress < progressInterval) return;
    lastProgress = elapsed;
    callback(
      VerifyProgress(
        stage: stage,
        segments: segmentsDone,
        totalSegments: totalSegments,
        fragments: report.fragments,
        totalFragments: totalFragments,
        problems: report.problems.length,
        elapsed: elapsed,
        currentSegment: currentSegment,
        currentFragment: currentFragment,
        currentSegmentFragments: currentSegmentFragments,
        currentFragmentElapsed: currentFragment == null
            ? Duration.zero
            : elapsed - fragmentStarted,
      ),
    );
  }

  emit(force: true);
  final timer = onProgress == null || progressInterval <= Duration.zero
      ? null
      : Timer.periodic(progressInterval, (_) => emit(force: true));
  try {
    for (final segmentId in ids) {
      token.check();
      final entry = index.segment(segmentId)!;
      report.segments++;
      currentSegment = segmentsDone + 1;
      currentSegmentFragments = entry.n;
      var alive = 0;
      var unknown = 0;
      CoreException? firstUnknown;
      final before = reader.problems.length;
      stage = full ? VerifyStage.reading : VerifyStage.checking;
      emit(force: true);
      await reader.resolveNodes(segmentId);
      if (full) {
        var number = 0;
        for (final f in index.fragments(segmentId)) {
          token.check();
          report.fragments++;
          currentFragment = ++number;
          fragmentStarted = watch.elapsed;
          emit();
          final beforeFetch = reader.problems.length;
          if (await reader.fetch(segmentId, f) != null) {
            alive++;
          } else if (_unreachable(reader.problems[beforeFetch].error)) {
            unknown++;
            firstUnknown ??= reader.problems[beforeFetch].error;
          }
          emit();
        }
        if (alive >= entry.k) {
          // Сборка снова читает фрагменты: те же проблемы второй раз не нужны.
          stage = VerifyStage.assembling;
          currentFragment = null;
          emit(force: true);
          final checked = reader.problems.length;
          try {
            await reader.segment(segmentId);
          } on CoreException catch (e) {
            report.unrecoverable.add((segmentId, e));
          }
          reader.problems.removeRange(checked, reader.problems.length);
        }
      } else {
        var number = 0;
        for (final f in index.fragments(segmentId)) {
          token.check();
          report.fragments++;
          currentFragment = ++number;
          fragmentStarted = watch.elapsed;
          emit();
          final node = f.node;
          try {
            if (node == null) throw _notFound(f);
            if (!(await fragments.has(node, [f.fragmentId])).single) {
              throw _notFound(f);
            }
            alive++;
          } on CoreException catch (e) {
            if (_unreachable(e)) {
              unknown++;
              firstUnknown ??= e;
            }
            reader.problems.add(
              FragmentProblem(
                segmentId: segmentId,
                index: f.number,
                node: node,
                error: e,
              ),
            );
          }
          emit();
        }
      }
      report.problems.addAll(
        reader.problems.sublist(before).where((p) => !_unreachable(p.error)),
      );
      if (alive < entry.k) {
        if (alive + unknown >= entry.k) {
          // Часть фрагментов не удалось проверить: данных может хватать.
          report.unchecked.add((
            segmentId,
            firstUnknown ??
                InsufficientShardsException(
                  available: alive,
                  required: entry.k,
                  segmentId: segmentId,
                ),
          ));
          report.uncheckedFragments += unknown;
        } else {
          report.unrecoverable.add((
            segmentId,
            InsufficientShardsException(
              available: alive,
              required: entry.k,
              segmentId: segmentId,
            ),
          ));
        }
      } else if (alive <= threshold) {
        report.atRisk.add(segmentId);
      }
      segmentsDone++;
      currentSegment = null;
      currentFragment = null;
      currentSegmentFragments = null;
      emit(force: true);
    }
  } finally {
    timer?.cancel();
  }
  stage = VerifyStage.done;
  currentSegment = null;
  currentFragment = null;
  currentSegmentFragments = null;
  emit(force: true);
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

/// Фрагмент не удалось проверить: узел недоступен (нет связи, исчерпан
/// суточный предел relay) или не ответил координатор. Это не значит, что
/// фрагмента нет.
bool _unreachable(CoreException e) =>
    e is CoordinatorException ||
    (e is StorageException && e.problem == StorageProblem.unavailable);
