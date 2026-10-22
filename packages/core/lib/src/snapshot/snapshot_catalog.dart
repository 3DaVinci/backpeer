import 'dart:typed_data';

import 'package:core/src/crypto/crypto_provider.dart';
import 'package:core/src/crypto/secret_bytes.dart';
import 'package:core/src/errors.dart';
import 'package:core/src/snapshot/manifest_objects.dart';
import 'package:core/src/storage/local_index.dart';
import 'package:core/src/storage/object_store.dart';
import 'package:core/src/util/bytes.dart';
import 'package:protocol/protocol.dart' as pb;

/// Список снимков учётной записи.
final class SnapshotListing {
  const new({
    required this.snapshots,
    required this.warnings,
    required this.unreadable,
  });

  /// По возрастанию `sequence`.
  final List<pb.Snapshot> snapshots;

  /// Признаки отката или сокрытия снимков (manifest.md, раздел 6).
  final List<RollbackWarning> warnings;

  /// Объекты, которые не удалось открыть: идентификатор и ошибка.
  final List<(Uint8List, CoreException)> unreadable;
}

/// Снимки в хранилище объектов: сохранение, список, удаление
/// (задачи 1.5.3, 1.5.4). Удаляется только объект снимка; сегменты,
/// на которые больше никто не ссылается, собирает сборщик мусора
/// (вне версии 1, manifest.md, раздел 7).
final class SnapshotCatalog {
  new({
    required this.crypto,
    required SecretBytes manifestKey,
    required this.store,
    required this.index,
  }) : _key = manifestKey;

  final CryptoProvider crypto;
  final SecretBytes _key;
  final ObjectStore store;
  final LocalIndex index;

  /// Сохраняет снимок этого устройства и запоминает его в локальном
  /// состоянии.
  Future<void> save(pb.Snapshot snapshot) async {
    final blob = ManifestObjects.sealSnapshot(crypto, _key, snapshot);
    final id = Uint8List.fromList(snapshot.snapshotId);
    final sequence = snapshot.sequence.toInt();
    await store.put(ObjectKind.snapshot, id, blob, sequence: sequence);
    index.recordOwnSnapshot(id, sequence);
  }

  Future<pb.Snapshot> get(Uint8List id) async => ManifestObjects.openSnapshot(
    crypto,
    _key,
    await store.get(ObjectKind.snapshot, id),
    expectedId: id,
  );

  /// Все снимки с проверкой на откат. Увиденные `sequence` запоминаются,
  /// чтобы следующий список нельзя было незаметно откатить.
  Future<SnapshotListing> list() async {
    final infos = await store.list(ObjectKind.snapshot);
    final listed = [for (final i in infos) (id: i.id, sequence: i.sequence)];
    final warnings = checkRollback(
      listed,
      knownMaxSequence: index.maxSequence,
      lastOwnSnapshot: index.lastOwnSnapshot,
    );
    final snapshots = <pb.Snapshot>[];
    final unreadable = <(Uint8List, CoreException)>[];
    for (final info in infos) {
      try {
        final snapshot = await get(info.id);
        if (snapshot.sequence.toInt() != info.sequence) {
          // Открытый номер у координатора и номер внутри снимка расходятся.
          throw IntegrityException(
            object: 'snapshot',
            check: IntegrityCheck.objectId,
            objectId: info.id,
          );
        }
        snapshots.add(snapshot);
        index.observeSequence(info.sequence);
      } on CoreException catch (e) {
        unreadable.add((info.id, e));
      }
    }
    snapshots.sort((a, b) => a.sequence.compareTo(b.sequence));
    return SnapshotListing(
      snapshots: snapshots,
      warnings: warnings,
      unreadable: unreadable,
    );
  }

  /// Снимки, идентификатор которых начинается с [prefix] (hex, любой
  /// регистр). Префикс не из hex-символов — пустой список.
  Future<List<Uint8List>> matching(String prefix) async {
    final p = prefix.toLowerCase();
    if (p.isEmpty || !RegExp(r'^[0-9a-f]+$').hasMatch(p)) return const [];
    return [
      for (final info in await store.list(ObjectKind.snapshot))
        if (bytesToHex(info.id).startsWith(p)) info.id,
    ];
  }

  /// Удаляет снимок. Чтобы удаление не выглядело потом как откат: если
  /// это снимок с наибольшим номером, известный максимум опускается до
  /// наибольшего из оставшихся; если это последний снимок устройства,
  /// последним становится его родитель (если он ещё есть).
  Future<void> forget(Uint8List id) async {
    final snapshot = await get(id);
    await store.delete(ObjectKind.snapshot, id);
    final remaining = await store.list(ObjectKind.snapshot);
    if (snapshot.sequence.toInt() >= index.maxSequence) {
      index.lowerMaxSequence(
        remaining.fold(0, (m, i) => i.sequence > m ? i.sequence : m),
      );
    }
    final last = index.lastOwnSnapshot;
    if (last == null || !constantTimeEquals(last, id)) return;
    final parent = Uint8List.fromList(snapshot.parentSnapshotId);
    final parentKept =
        parent.isNotEmpty &&
        remaining.any((i) => constantTimeEquals(i.id, parent));
    index.setLastOwnSnapshot(parentKept ? parent : null);
  }
}
