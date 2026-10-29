import 'dart:async';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:logging/logging.dart';
import 'package:node/src/daemon/log.dart';
import 'package:node/src/storage/fragment_storage.dart';

/// Сверка фрагментов узла с координатором (задача 4.4.3; protocol.md,
/// раздел 4.15): какие из хранимых фрагментов координатор больше не
/// учитывает на этом узле — ремонт перенёс их на другие узлы, пока узел
/// был потерян, сегмент удалён, загрузка не засчитана, перенос завершён.
///
/// Проход: все сохранённые и повреждённые фрагменты пачками по [batch] по
/// возрастанию `fragment_id` уходят в [query] (`ReconcileFragments`).
/// Неучтённый фрагмент отмечается (`orphaned_at`) и удаляется, только
/// если и через [quarantine] после отметки координатор его не признал;
/// признанный снова — отметка снимается. Карантин даёт время заметить
/// ошибку или взлом координатора, пока данные ещё на узле (модель угроз,
/// К-4): удаление без запроса владельца — только так.
///
/// Проход нужен ([due]), когда его просит координатор ([request],
/// `HeartbeatResponse.reconcile`), прошло [interval] с прошлого или истёк
/// карантин отмеченных. Одновременные вызовы [run] ждут один проход.
final class FragmentReconciler {
  new({
    required this.storage,
    required this.query,
    this.quarantine = const Duration(hours: 24),
    this.interval = const Duration(days: 7),
    this.batch = maxBatch,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// Наибольшая пачка `ReconcileFragments`.
  static const maxBatch = 1000;

  final FragmentStorage storage;

  /// `ReconcileFragments`: неучтённые из `ids`; `first` — первая пачка
  /// прохода. Сбой — исключение, проход прерывается.
  final Future<List<List<int>>> Function(
    List<Uint8List> ids, {
    required bool first,
  })
  query;
  final Duration quarantine;
  final Duration interval;
  final int batch;
  final DateTime Function() _clock;

  static final _log = Logger('reconcile');

  /// Время прошлого прохода в `sync_state`.
  static const _lastPass = 'reconciled_at';

  bool _requested = false;
  Future<int>? _running;
  int _passes = 0;
  int _deleted = 0;
  int _deletedBytes = 0;
  String? _lastError;

  /// Идёт проход.
  bool get running => _running != null;

  DateTime? get lastPassAt => switch (storage.index.syncValue(_lastPass)) {
    final int ms => DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true),
    null => null,
  };

  /// Координатор просит сверить фрагменты.
  void request() => _requested = true;

  bool get due {
    if (_requested) return true;
    final now = _clock();
    final last = lastPassAt;
    if (last == null || !now.isBefore(last.add(interval))) return true;
    final oldest = storage.index.orphans().oldest;
    return oldest != null && !now.isBefore(oldest.add(quarantine));
  }

  /// Состояние для `cli node status`.
  Map<String, Object?> toJson() {
    final o = storage.index.orphans();
    return {
      'running': running,
      'lastPassAt': lastPassAt?.toIso8601String(),
      'requested': _requested,
      'orphans': o.count,
      'orphanBytes': o.bytes,
      'oldestOrphanAt': o.oldest?.toIso8601String(),
      'passes': _passes,
      'deleted': _deleted,
      'deletedBytes': _deletedBytes,
      'lastError': _lastError,
    };
  }

  /// Проход сверки; возвращает число удалённых фрагментов. Сбой связи —
  /// исключение, отметки уже сверенных пачек остаются.
  Future<int> run() => _running ??= _pass().whenComplete(() => _running = null);

  Future<int> _pass() async {
    _requested = false;
    final now = _clock();
    List<int>? after;
    var first = true;
    var checked = 0;
    var unknownTotal = 0;
    var deleted = 0;
    var deletedBytes = 0;
    try {
      while (true) {
        final ids = storage.index.idsAfter(after, limit: batch);
        if (ids.isEmpty) break;
        final answer = {
          for (final id in await query(ids, first: first)) bytesToHex(id),
        };
        first = false;
        // Учитываются только идентификаторы из запроса.
        final unknown = [
          for (final id in ids)
            if (answer.contains(bytesToHex(id))) id,
        ];
        storage.index.markOrphaned(
          unknown: unknown,
          known: [
            for (final id in ids)
              if (!answer.contains(bytesToHex(id))) id,
          ],
          at: now,
        );
        for (final id in unknown) {
          final since = storage.index.orphanedAt(id);
          if (since == null || now.isBefore(since.add(quarantine))) continue;
          final size = storage.record(id)?.size ?? 0;
          if (storage.delete(id)) {
            deleted++;
            deletedBytes += size;
          }
        }
        checked += ids.length;
        unknownTotal += unknown.length;
        after = ids.last;
        if (ids.length < batch) break;
      }
    } on Object catch (e) {
      // Координатор мог уже снять отметку первой пачкой: повтор — в
      // следующий раз, когда узел спросит, нужен ли проход.
      _requested = true;
      _lastError = '$e';
      _log.warning(
        LogEvent('reconcile_failed', {'checked': checked, 'reason': '$e'}),
      );
      rethrow;
    }
    storage.index.setSyncValue(_lastPass, now.millisecondsSinceEpoch);
    _passes++;
    _deleted += deleted;
    _deletedBytes += deletedBytes;
    _lastError = null;
    _log.info(
      LogEvent('reconciled', {
        'checked': checked,
        'unknown': unknownTotal,
        'deleted': deleted,
        'deleted_bytes': deletedBytes,
      }),
    );
    return deleted;
  }
}
