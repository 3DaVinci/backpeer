import 'dart:typed_data';

import 'package:core/src/errors.dart';
import 'package:core/src/snapshot/retention.dart';
import 'package:core/src/snapshot/snapshot_catalog.dart';
import 'package:core/src/util/bytes.dart';
import 'package:protocol/protocol.dart' as pb;

/// Итог очистки по политике хранения.
final class ForgetReport {
  new({required this.kept, required this.forgotten, required this.other});

  /// Снимки устройства, которые держит политика, с правилами.
  final List<(pb.Snapshot, Set<RetentionRule>)> kept;

  /// Удалённые снимки (при `dryRun` — те, что были бы удалены).
  final List<pb.Snapshot> forgotten;

  /// Снимков других устройств: политика их не трогает.
  final int other;
}

/// Удаляет снимки устройства [deviceId], которые не держит [policy]
/// (задача 5.3.5). Место освобождает сборка мусора после (`collectGarbage`).
///
/// Снимки других устройств учётной записи не трогаются: у каждого
/// устройства своя история. История своя и у каждого набора папок: бэкап
/// одной папки с экрана «Бэкап» не вытесняет снимки остальных — иначе
/// политика «последний один» удалила бы данные другой папки, а сборка
/// мусора — их сегменты. Если список снимков вызывает сомнения —
/// признаки отката или нечитаемые объекты, — ничего не удаляется
/// ([PreconditionException]): по неполному списку политика могла бы
/// удалить снимок, который держит. Удаление идёт по одному снимку; обрыв
/// посреди очистки оставляет все снимки, которые держит политика, — план
/// устойчив ([RetentionPolicy.plan]), следующая очистка доделает остальное.
Future<ForgetReport> forgetByPolicy({
  required SnapshotCatalog catalog,
  required RetentionPolicy policy,
  required Uint8List deviceId,
  bool dryRun = false,
}) async {
  final listing = await catalog.list();
  if (listing.warnings.isNotEmpty) {
    throw PreconditionException(
      'признаки отката списка снимков '
      '(${listing.warnings.map((w) => w.name).join(', ')}): '
      'очистка по политике отложена',
    );
  }
  if (listing.unreadable.isNotEmpty) {
    throw PreconditionException(
      'не читаются снимки: ${listing.unreadable.length}; '
      'очистка по политике отложена',
    );
  }
  final mine = [
    for (final s in listing.snapshots)
      if (constantTimeEquals(Uint8List.fromList(s.deviceId), deviceId)) s,
  ];
  // Политика — на каждый набор папок отдельно: у бэкапа одной папки своя
  // история снимков.
  final groups = <String, List<pb.Snapshot>>{};
  for (final s in mine) {
    groups.putIfAbsent(_pathsKey(s.paths), () => []).add(s);
  }
  final kept = <(pb.Snapshot, Set<RetentionRule>)>[];
  final forgotten = <pb.Snapshot>[];
  for (final group in groups.values) {
    final plan = policy.plan(
      group,
      (s) => DateTime.fromMillisecondsSinceEpoch(s.createdAtUnixMs.toInt()),
    );
    kept.addAll(plan.keep);
    forgotten.addAll(plan.forget);
  }
  if (!dryRun) {
    // От старых к новым: обрыв оставляет новые снимки.
    forgotten.sort((a, b) => a.createdAtUnixMs.compareTo(b.createdAtUnixMs));
    for (final s in forgotten) {
      await catalog.forget(Uint8List.fromList(s.snapshotId));
    }
  }
  return ForgetReport(
    kept: kept,
    forgotten: forgotten,
    other: listing.snapshots.length - mine.length,
  );
}

/// Ключ набора папок снимка: пути без учёта порядка.
String _pathsKey(List<String> paths) => ([...paths]..sort()).join('\x00');
