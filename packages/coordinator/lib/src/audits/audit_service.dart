import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:coordinator/src/db/database.dart';
import 'package:coordinator/src/log.dart';
import 'package:coordinator/src/nodes/node_channels.dart';
import 'package:coordinator/src/repair/live_fragments.dart';
import 'package:coordinator/src/reputation/reputation.dart';
import 'package:core/core.dart';
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:protocol/protocol.dart' as pb;

/// Настройки аудитов (`audits.*`, `docs/ops/coordinator.md`).
final class AuditPolicy {
  const new({
    this.enabled = true,
    this.interval = const Duration(hours: 6),
    this.newNodeInterval = const Duration(hours: 1),
    this.newNodeAge = const Duration(days: 7),
    this.suspectInterval = const Duration(minutes: 15),
    this.recheckDelay = const Duration(minutes: 10),
    this.offlineRetry = const Duration(minutes: 10),
    this.window = 20,
    this.excludeFailures = 4,
    this.maxPerSecond = 20,
    this.maxConcurrent = 32,
    this.tick = const Duration(seconds: 5),
    this.retention = const Duration(days: 90),
  });

  final bool enabled;

  /// Пауза между аудитами узла старше [newNodeAge] без провалов в окне.
  final Duration interval;

  /// Пауза между аудитами узла моложе [newNodeAge]: новые узлы
  /// проверяются чаще (модель угроз, Х-1).
  final Duration newNodeInterval;
  final Duration newNodeAge;

  /// Пауза между аудитами узла с провалом в окне [window].
  final Duration suspectInterval;

  /// Через сколько повторить аудит фрагмента, который его провалил.
  final Duration recheckDelay;

  /// Через сколько снова попробовать узел без канала команд.
  final Duration offlineRetry;

  /// Сколько последних итогов узла учитывать и сколько провалов среди
  /// них исключают узел из размещения.
  final int window;
  final int excludeFailures;

  /// Аудитов в секунду на координатор и одновременно: потолок нагрузки
  /// на базу и каналы.
  final int maxPerSecond;
  final int maxConcurrent;

  /// Как часто планировщик ищет узлы, которым пора.
  final Duration tick;

  /// Сколько хранить журнал аудитов.
  final Duration retention;
}

/// Отправка команды узлу; реализация — [NodeChannels].
abstract interface class NodeCommands {
  bool isConnected(List<int> nodeId);

  /// Ответ узла; `null` — канала нет или он закрылся до ответа; нет
  /// ответа вовремя — [TimeoutException].
  Future<pb.NodeChannelMessage?> send(
    List<int> nodeId,
    pb.CoordinatorChannelMessage command,
  );
}

/// Что проверяется: фрагмент на узле.
final class AuditTarget {
  const new({
    required this.nodeId,
    required this.fragmentId,
    required this.bodyRoot,
    required this.fragmentSize,
    required this.recheck,
  });

  final Uint8List nodeId;
  final Uint8List fragmentId;
  final Uint8List bodyRoot;

  /// Размер фрагмента с заголовком (`segments.fragment_size`).
  final int fragmentSize;

  /// Повторная проверка фрагмента, уже провалившего аудит.
  final bool recheck;

  int get bodyLength => fragmentSize - FragmentHeader.length;
}

/// Итог одного аудита.
final class AuditOutcome {
  const new passed() : passed = true, reason = null;
  const new failed(String this.reason) : passed = false;

  final bool passed;

  /// Почему провален: `proof` — блок или путь не сходятся, `timeout`,
  /// `error:<код>` — узел ответил ошибкой, `bad_reply` — ответ без тела
  /// аудита.
  final String? reason;
}

/// Наибольшая длина пути: дерево фрагмента до 16 МиБ + 4 КиБ — 257
/// листьев, 9 уровней; запас — на случай больших фрагментов в будущем.
const int maxAuditPathLength = 32;

/// Проверка ответа узла на аудит блока [blockIndex] (protocol.md,
/// раздел 4.13): длина блока, путь не длиннее [maxAuditPathLength] с
/// элементами по 32 байта, корень по пути равен `body_root`.
AuditOutcome checkAuditReply(
  CryptoProvider crypto,
  AuditTarget target,
  int blockIndex,
  pb.NodeChannelMessage reply,
) {
  if (reply.hasError()) {
    return AuditOutcome.failed('error:${errorCodeName(reply.error.code)}');
  }
  if (!reply.hasAudit()) return const AuditOutcome.failed('bad_reply');
  final audit = reply.audit;
  final leafCount = merkleLeafCount(target.bodyLength);
  if (blockIndex >= leafCount ||
      audit.block.length != merkleBlockLength(target.bodyLength, blockIndex) ||
      audit.path.length > maxAuditPathLength ||
      !verifyMerkleAuditPath(
        crypto,
        root: target.bodyRoot,
        leafCount: leafCount,
        index: blockIndex,
        block: audit.block,
        path: audit.path,
      )) {
    return const AuditOutcome.failed('proof');
  }
  return const AuditOutcome.passed();
}

/// Аудиты хранения (задачи 4.1.3, 4.1.4; protocol.md, раздел 4.13).
///
/// **Планировщик.** Раз в [AuditPolicy.tick] выбирает узлы, у которых
/// подошло `audit_next_at`, не больше [AuditPolicy.maxPerSecond] на
/// секунду паузы, и проверяет их по [AuditPolicy.maxConcurrent] сразу.
/// Фрагмент — повторная проверка, если она ждёт, иначе случайный
/// сохранённый неповреждённый фрагмент узла (по индексу, без обхода);
/// блок — случайный. Следующий аудит узла — через паузу по возрасту и
/// итогам ([AuditPolicy.interval], [AuditPolicy.newNodeInterval],
/// [AuditPolicy.suspectInterval]) со случайной долей ±50 %: проверки
/// расходятся во времени. Узел без канала команд пропускается до
/// [AuditPolicy.offlineRetry]: недоступность учитывает доступность, а
/// не аудит.
///
/// **Провал** — неверный блок или путь, ошибка или нет ответа за срок
/// команды канала. Первый провал фрагмента — повторная проверка через
/// [AuditPolicy.recheckDelay] (другой случайный блок); второй — фрагмент
/// потерян: `damaged_at`, не выдаётся в `LocateSegment`, число живых
/// фрагментов сегмента пересчитывается (`LiveFragments`), ремонт его
/// досоздаёт.
/// Итоги копятся в журнале `audits` и счётчиках узла, время ответа на
/// пройденные — в сглаженном `audit_latency_ms`, провалы в окне — в
/// `audit_window_failures` (репутация, 4.2.1);
/// [AuditPolicy.excludeFailures] провалов среди последних
/// [AuditPolicy.window] итогов исключают узел из размещения
/// (`excluded_at`, причина «аудит: …»); вернуть узел может оператор
/// (`coordinator admin node include`).
final class AuditService {
  new(
    this._db, {
    required this._crypto,
    this.policy = const AuditPolicy(),
    DateTime Function()? clock,
    Random? random,
  }) : _clock = clock ?? DateTime.now,
       _random = random ?? Random.secure();

  final Database _db;
  final CryptoProvider _crypto;
  final AuditPolicy policy;
  final DateTime Function() _clock;
  final Random _random;

  /// Каналы команд; без них аудиты не идут. Передаёт сервер.
  NodeCommands? channels;

  static final _log = Logger('audits');

  Timer? _timer;
  Future<void>? _round;
  bool _closed = false;
  DateTime? _cleanedAt;

  /// Запускает планировщик, если аудиты включены.
  void start() {
    if (!policy.enabled || _timer != null || _closed) return;
    _timer = Timer.periodic(policy.tick, (_) {
      if (_round != null) return;
      _round = runOnce()
          .catchError((Object e, StackTrace stack) {
            _log.severe(const LogEvent('audit_round_failed'), e, stack);
            return 0;
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

  /// Один проход планировщика: проверяет узлы, которым пора, и
  /// возвращает число проведённых аудитов.
  Future<int> runOnce() async {
    final commands = channels;
    if (commands == null) return 0;
    final now = _clock();
    await _cleanup(now);
    final batch = max(
      1,
      policy.maxPerSecond * policy.tick.inMilliseconds ~/ 1000,
    );
    final rows = await _db.run(
      (s) => s.execute(
        Sql.named('''
          SELECT node_id, registered_at FROM nodes
            WHERE removed_at IS NULL
              AND (audit_next_at IS NULL OR audit_next_at <= @now:timestamptz)
            ORDER BY audit_next_at NULLS FIRST
            LIMIT @limit:int4'''),
        parameters: {'now': now, 'limit': batch},
      ),
    );
    final due = [
      for (final [id as List<int>, registered as DateTime] in rows)
        (nodeId: Uint8List.fromList(id), registeredAt: registered),
    ];
    var done = 0;
    var next = 0;
    Future<void> worker() async {
      while (next < due.length && !_closed) {
        final node = due[next++];
        if (await _auditNode(commands, node.nodeId, node.registeredAt)) {
          done++;
        }
      }
    }

    await Future.wait([
      for (var i = 0; i < min(policy.maxConcurrent, due.length); i++) worker(),
    ]);
    return done;
  }

  /// Аудит узла; `false` — не проводился (нет канала или фрагментов).
  Future<bool> _auditNode(
    NodeCommands commands,
    Uint8List nodeId,
    DateTime registeredAt,
  ) async {
    final now = _clock();
    if (!commands.isConnected(nodeId)) {
      await _postpone(nodeId, now.add(policy.offlineRetry));
      return false;
    }
    final target = await _pickTarget(nodeId, now);
    if (target == null) {
      await _postpone(nodeId, now.add(_jitter(_baseInterval(registeredAt))));
      return false;
    }
    final blockIndex = _random.nextInt(merkleLeafCount(target.bodyLength));
    final started = Stopwatch()..start();
    final AuditOutcome outcome;
    try {
      final reply = await commands.send(
        nodeId,
        pb.CoordinatorChannelMessage(
          audit: pb.AuditCommand(
            fragmentId: target.fragmentId,
            blockIndex: blockIndex,
          ),
        ),
      );
      if (reply == null) {
        // Канал закрылся до ответа: узел ушёл из сети, это не провал.
        await _postpone(nodeId, now.add(policy.offlineRetry));
        return false;
      }
      outcome = checkAuditReply(_crypto, target, blockIndex, reply);
    } on TimeoutException {
      return await _record(
        target,
        blockIndex,
        registeredAt,
        const AuditOutcome.failed('timeout'),
        started.elapsed,
      );
    }
    return await _record(
      target,
      blockIndex,
      registeredAt,
      outcome,
      started.elapsed,
    );
  }

  /// Фрагмент для аудита: ждущая повторная проверка или случайный.
  Future<AuditTarget?> _pickTarget(Uint8List nodeId, DateTime now) =>
      _db.run((s) async {
        final recheck = await s.execute(
          Sql.named('''
            SELECT f.fragment_id, f.body_root, g.fragment_size
              FROM fragments f JOIN segments g USING (account_id, segment_id)
              WHERE f.node_id = @n:bytea AND f.audit_failed_at IS NOT NULL
                AND f.audit_failed_at <= @due:timestamptz
                AND f.stored AND f.damaged_at IS NULL
              ORDER BY f.audit_failed_at
              LIMIT 1'''),
          parameters: {'n': nodeId, 'due': now.subtract(policy.recheckDelay)},
        );
        if (recheck.isNotEmpty) return _target(nodeId, recheck.single, true);
        final from = _crypto.randomBytes(32);
        for (final bound in [from, Uint8List(0)]) {
          final rows = await s.execute(
            Sql.named('''
              SELECT f.fragment_id, f.body_root, g.fragment_size
                FROM fragments f JOIN segments g USING (account_id, segment_id)
                WHERE f.node_id = @n:bytea AND f.stored
                  AND f.damaged_at IS NULL AND f.fragment_id >= @r:bytea
                ORDER BY f.fragment_id
                LIMIT 1'''),
            parameters: {'n': nodeId, 'r': bound},
          );
          if (rows.isNotEmpty) return _target(nodeId, rows.single, false);
        }
        return null;
      });

  static AuditTarget _target(Uint8List nodeId, ResultRow row, bool recheck) {
    final [id as List<int>, root as List<int>, size as int] = row;
    return AuditTarget(
      nodeId: nodeId,
      fragmentId: Uint8List.fromList(id),
      bodyRoot: Uint8List.fromList(root),
      fragmentSize: size,
      recheck: recheck,
    );
  }

  /// Записывает итог, отмечает фрагмент, исключает узел при систематических
  /// провалах и назначает следующий аудит.
  Future<bool> _record(
    AuditTarget target,
    int blockIndex,
    DateTime registeredAt,
    AuditOutcome outcome,
    Duration latency,
  ) async {
    final now = _clock();
    final nodeId = target.nodeId;
    final result = await _db.transaction((tx) async {
      await tx.execute(
        Sql.named('''
          INSERT INTO audits (node_id, fragment_id, block_index, at, passed,
                              recheck, reason, latency_ms)
            VALUES (@n:bytea, @f:bytea, @b:int4, @t:timestamptz, @p:boolean,
                    @rc:boolean, @r:text, @ms:int4)'''),
        parameters: {
          'n': nodeId,
          'f': target.fragmentId,
          'b': blockIndex,
          't': now,
          'p': outcome.passed,
          'rc': target.recheck,
          'r': outcome.reason,
          'ms': latency.inMilliseconds,
        },
      );
      var lost = false;
      if (outcome.passed) {
        if (target.recheck) await _setFailed(tx, target, null);
      } else if (target.recheck) {
        lost = true;
        await tx.execute(
          Sql.named('''
            UPDATE fragments
              SET damaged_at = coalesce(damaged_at, @t:timestamptz),
                  audit_failed_at = NULL
              WHERE node_id = @n:bytea AND fragment_id = @f:bytea'''),
          parameters: {'n': nodeId, 'f': target.fragmentId, 't': now},
        );
        // Потерянный фрагмент не живой: ремонт его досоздаст (4.3.1).
        await LiveFragments.recount(
          tx,
          scope:
              'SELECT account_id, segment_id FROM fragments '
              'WHERE node_id = @n:bytea AND fragment_id = @f:bytea',
          parameters: {'n': nodeId, 'f': target.fragmentId},
          now: now,
        );
      } else {
        await _setFailed(tx, target, now);
      }
      final window = await tx.execute(
        Sql.named('''
          SELECT count(*) FILTER (WHERE NOT passed), count(*) FROM (
            SELECT passed FROM audits WHERE node_id = @n:bytea
              ORDER BY at DESC, id DESC LIMIT @w:int4) w'''),
        parameters: {'n': nodeId, 'w': policy.window},
      );
      final [failures as int, total as int] = window.single;
      var excluded = false;
      if (failures >= policy.excludeFailures) {
        final rows = await tx.execute(
          Sql.named('''
            UPDATE nodes SET excluded_at = @t:timestamptz,
                             excluded_reason = @r:text
              WHERE node_id = @n:bytea AND excluded_at IS NULL
              RETURNING 1'''),
          parameters: {
            'n': nodeId,
            't': now,
            'r': 'аудит: $failures из последних $total проверок провалены',
          },
        );
        excluded = rows.isNotEmpty;
      }
      final recheckPending = await tx.execute(
        Sql.named('''
          SELECT min(audit_failed_at) FROM fragments
            WHERE node_id = @n:bytea AND audit_failed_at IS NOT NULL'''),
        parameters: {'n': nodeId},
      );
      var next = now.add(
        _jitter(
          failures > 0 ? policy.suspectInterval : _baseInterval(registeredAt),
        ),
      );
      // Ждёт повторная проверка — следующий аудит узла в её срок.
      if (recheckPending.single.single case final DateTime failedAt) {
        next = failedAt.add(policy.recheckDelay);
      }
      await tx.execute(
        Sql.named('''
          UPDATE nodes
            SET audit_next_at = @next:timestamptz,
                last_audit_at = @t:timestamptz,
                audits_passed = audits_passed + @p:int4,
                audits_failed = audits_failed + @f:int4,
                audit_window_failures = @wf:int4,
                audit_latency_ms = CASE WHEN @f:int4 = 1 THEN audit_latency_ms
                  ELSE coalesce(audit_latency_ms +
                                @k:float8 * (@ms:float8 - audit_latency_ms),
                                @ms:float8) END
            WHERE node_id = @n:bytea'''),
        parameters: {
          'n': nodeId,
          'next': next,
          't': now,
          'p': outcome.passed ? 1 : 0,
          'f': outcome.passed ? 0 : 1,
          'k': Reputation.latencySmoothing,
          'ms': latency.inMicroseconds / 1000,
          'wf': failures,
        },
      );
      return (lost: lost, excluded: excluded, failures: failures);
    });
    final fields = {
      'node_id': bytesToHex(nodeId),
      'fragment_id': bytesToHex(target.fragmentId),
      'block': blockIndex,
      'recheck': target.recheck,
      'ms': latency.inMilliseconds,
      'reason': ?outcome.reason,
    };
    if (outcome.passed) {
      _log.fine(LogEvent('audit_passed', fields));
    } else {
      _log.warning(LogEvent('audit_failed', {...fields, 'lost': result.lost}));
    }
    if (result.excluded) {
      _log.warning(
        LogEvent('node_excluded_by_audits', {
          'node_id': bytesToHex(nodeId),
          'failures': result.failures,
          'window': policy.window,
        }),
      );
    }
    return true;
  }

  static Future<void> _setFailed(
    TxSession tx,
    AuditTarget target,
    DateTime? at,
  ) => tx.execute(
    Sql.named('''
      UPDATE fragments SET audit_failed_at = @t:timestamptz
        WHERE node_id = @n:bytea AND fragment_id = @f:bytea'''),
    parameters: {'n': target.nodeId, 'f': target.fragmentId, 't': at},
  );

  Future<void> _postpone(Uint8List nodeId, DateTime next) => _db.run(
    (s) => s.execute(
      Sql.named(
        'UPDATE nodes SET audit_next_at = @t:timestamptz '
        'WHERE node_id = @n:bytea',
      ),
      parameters: {'n': nodeId, 't': next},
    ),
  );

  Duration _baseInterval(DateTime registeredAt) =>
      _clock().difference(registeredAt) < policy.newNodeAge
      ? policy.newNodeInterval
      : policy.interval;

  /// [d] со случайной долей ±50 %.
  Duration _jitter(Duration d) => Duration(
    microseconds:
        d.inMicroseconds ~/ 2 +
        (d.inMicroseconds * _random.nextDouble()).floor(),
  );

  /// Раз в час удаляет журнал старше [AuditPolicy.retention].
  Future<void> _cleanup(DateTime now) async {
    final last = _cleanedAt;
    if (last != null && now.difference(last) < const Duration(hours: 1)) {
      return;
    }
    _cleanedAt = now;
    await _db.run(
      (s) => s.execute(
        Sql.named('DELETE FROM audits WHERE at < @t:timestamptz'),
        parameters: {'t': now.subtract(policy.retention)},
      ),
    );
  }
}
