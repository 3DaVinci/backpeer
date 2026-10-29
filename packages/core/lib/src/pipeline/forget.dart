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
/// устройства своя история. Если список снимков вызывает сомнения —
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
  final plan = policy.plan(
    mine,
    (s) => DateTime.fromMillisecondsSinceEpoch(s.createdAtUnixMs.toInt()),
  );
  if (!dryRun) {
    // От старых к новым: обрыв оставляет новые снимки.
    for (final s in plan.forget.reversed) {
      await catalog.forget(Uint8List.fromList(s.snapshotId));
    }
  }
  return ForgetReport(
    kept: plan.keep,
    forgotten: plan.forget,
    other: listing.snapshots.length - mine.length,
  );
}
