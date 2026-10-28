import 'dart:async';
import 'dart:typed_data';

import 'package:coordinator/src/db/database.dart';
import 'package:coordinator/src/log.dart';
import 'package:coordinator/src/repair/live_fragments.dart';
import 'package:core/core.dart';
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';

/// Настройки ремонта (`repair.*`, `docs/ops/coordinator.md`).
final class RepairPolicy {
  const new({
    this.enabled = true,
    this.offline = const Duration(hours: 72),
    this.tick = const Duration(seconds: 30),
  });

  final bool enabled;

  /// Узел не в сети дольше — потерян, его фрагменты не живые
  /// (durability.md, раздел 2: 72 ч ожидания и сутки на ремонт — окно
  /// ремонта модели в 4 суток).
  final Duration offline;

  /// Как часто планировщик ищет работу.
  final Duration tick;
}

/// Ремонт сегментов (группа 4.3; protocol.md, раздел 4.14).
///
/// **Потерянные узлы.** Раз в [RepairPolicy.tick] узлы без heartbeat
/// дольше [RepairPolicy.offline] отмечаются потерянными (`lost_at`), и
/// число живых фрагментов их сегментов пересчитывается
/// ([LiveFragments]); heartbeat вернувшегося узла снимает отметку
/// (`NodeService`).
final class RepairService {
  new(
    this._db, {
    this.policy = const RepairPolicy(),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Database _db;
  final RepairPolicy policy;
  final DateTime Function() _clock;

  static final _log = Logger('repair');

  /// Узлов, отмечаемых потерянными за проход: каждый — своя транзакция.
  static const _lostBatch = 100;

  Timer? _timer;
  Future<void>? _round;
  bool _closed = false;

  /// Запускает планировщик, если ремонт включён.
  void start() {
    if (!policy.enabled || _timer != null || _closed) return;
    _timer = Timer.periodic(policy.tick, (_) {
      if (_round != null) return;
      _round = runOnce()
          .catchError((Object e, StackTrace stack) {
            _log.severe(const LogEvent('repair_round_failed'), e, stack);
          })
          .whenComplete(() => _round = null);
    });
  }

  Future<void> close() async {
    _closed = true;
    _timer?.cancel();
    _timer = null;
    await _round;
  }

  /// Один проход планировщика.
  Future<void> runOnce() async {
    await markLost();
  }

  /// Отмечает потерянными узлы без heartbeat дольше
  /// [RepairPolicy.offline] и пересчитывает их сегменты. Возвращает число
  /// отмеченных узлов.
  Future<int> markLost() async {
    final now = _clock();
    final cutoff = now.subtract(policy.offline);
    final rows = await _db.run(
      (s) => s.execute(
        Sql.named('''
          SELECT node_id FROM nodes
            WHERE removed_at IS NULL AND lost_at IS NULL
              AND last_heartbeat_at < @c:timestamptz
            ORDER BY last_heartbeat_at
            LIMIT @l:int4'''),
        parameters: {'c': cutoff, 'l': _lostBatch},
      ),
    );
    var marked = 0;
    for (final [id as List<int>] in rows) {
      final nodeId = Uint8List.fromList(id);
      final segments = await _db.transaction((tx) async {
        // Условие повторяется: узел мог прислать heartbeat после выборки.
        final updated = await tx.execute(
          Sql.named('''
            UPDATE nodes SET lost_at = @t:timestamptz
              WHERE node_id = @n:bytea AND lost_at IS NULL
                AND last_heartbeat_at < @c:timestamptz
              RETURNING 1'''),
          parameters: {'n': nodeId, 't': now, 'c': cutoff},
        );
        if (updated.isEmpty) return null;
        return await LiveFragments.recountNode(tx, nodeId, now);
      });
      if (segments == null) continue;
      marked++;
      _log.warning(
        LogEvent('node_lost', {
          'node_id': bytesToHex(nodeId),
          'segments': segments,
        }),
      );
    }
    return marked;
  }
}
