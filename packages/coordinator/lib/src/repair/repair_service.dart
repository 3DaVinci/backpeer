import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:coordinator/src/audits/audit_service.dart';
import 'package:coordinator/src/db/database.dart';
import 'package:coordinator/src/log.dart';
import 'package:coordinator/src/nodes/node_service.dart';
import 'package:coordinator/src/placement/placement.dart';
import 'package:coordinator/src/placement/placement_policy.dart';
import 'package:coordinator/src/repair/live_fragments.dart';
import 'package:coordinator/src/repair/repair_jobs.dart';
import 'package:coordinator/src/rpc/call_context.dart';
import 'package:coordinator/src/rpc/errors.dart';
import 'package:coordinator/src/signer/ticket_signer.dart';
import 'package:core/core.dart';
import 'package:fixnum/fixnum.dart';
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:protocol/protocol.dart' as pb;

/// Настройки ремонта (`repair.*`, `docs/ops/coordinator.md`).
final class RepairPolicy {
  const new({
    this.enabled = true,
    this.offline = const Duration(hours: 72),
    this.lazyMargin = 0,
    this.lazyDelay = const Duration(hours: 12),
    this.maxJobs = 16,
    this.maxBytesPerHour = 50 * 1000 * 1000 * 1000,
    this.retryDelay = const Duration(minutes: 10),
    this.jobTimeout = const Duration(minutes: 30),
    this.executorMinReputation = 0.5,
    this.verifyTimeout = const Duration(hours: 2),
    this.suspend = const Duration(hours: 24),
    this.maxRelocations = 64,
    this.relocationsPerNode = 4,
    this.tick = const Duration(seconds: 30),
  });

  final bool enabled;

  /// Узел не в сети дольше — потерян, его фрагменты не живые
  /// (durability.md, раздел 2: 72 ч ожидания и сутки на ремонт — окно
  /// ремонта модели в 4 суток).
  final Duration offline;

  /// Ленивый ремонт (durability.md, раздел 5): сегмент, у которого живых
  /// не меньше `t − lazyMargin` (по умолчанию ровно t — запас t − k
  /// фрагментов), ремонтируется не раньше [lazyDelay] после попадания в
  /// очередь: потерянный узел может вернуться, и ремонт не понадобится.
  /// [lazyDelay] = 0 — без ленивого ремонта.
  final int lazyMargin;
  final Duration lazyDelay;

  /// Заданий одновременно на координатор.
  final int maxJobs;

  /// Предел трафика ремонта по сети: сумма оценок новых заданий за
  /// последний час (`planned_bytes`: k фрагментов скачать и новые
  /// разослать). Защищает исходящие каналы хранителей при массовом уходе
  /// узлов: ремонты встают в очередь по приоритету.
  final int maxBytesPerHour;

  /// Через сколько снова пробовать сегмент, задание для которого не
  /// удалось создать или провалилось.
  final Duration retryDelay;

  /// Срок задания: отчёт исполнителя не позже, талоны действуют до него
  /// (не больше часа, `FragmentTickets.maxLifetime`).
  final Duration jobTimeout;

  /// Порог репутации исполнителя (`docs/spec/reputation.md`).
  final double executorMinReputation;

  /// Сколько после отчёта ждать, пока новый узел выйдет на связь для
  /// проверки фрагмента аудитом; потом номер провален без вины
  /// исполнителя.
  final Duration verifyTimeout;

  /// На сколько отстраняется от ремонта исполнитель, чей новый фрагмент
  /// не прошёл проверку.
  final Duration suspend;

  /// Заданий переноса (задачи 4.4.1, 4.4.2) одновременно на координатор;
  /// 0 — перенос выключен. Предел [maxBytesPerHour] на перенос не
  /// распространяется: фрагмент отдаёт сам уходящий узел, одной загрузкой.
  final int maxRelocations;

  /// Заданий переноса одновременно на один узел.
  final int relocationsPerNode;

  /// Как часто планировщик ищет работу.
  final Duration tick;
}

/// Сегмент в очереди ремонта.
final class RepairCandidate {
  const new({
    required this.accountId,
    required this.segmentId,
    required this.k,
    required this.n,
    required this.threshold,
    required this.fragmentSize,
    required this.live,
    required this.since,
  });

  final Uint8List accountId;
  final Uint8List segmentId;
  final int k;
  final int n;
  final int threshold;
  final int fragmentSize;

  /// Живых фрагментов.
  final int live;

  /// С какого времени в очереди.
  final DateTime since;
}

/// Фрагмент сегмента и его узел для задания.
typedef _SegmentFragment = ({
  int index,
  Uint8List fragmentId,
  Uint8List nodeId,
  String owner,
  String? subnet,
  List<String> endpoints,
  bool live,
  bool online,
  bool probation,
});

/// Ремонт сегментов (группа 4.3; protocol.md, раздел 4.14).
///
/// **Потерянные узлы.** Раз в [RepairPolicy.tick] узлы без heartbeat
/// дольше [RepairPolicy.offline] отмечаются потерянными (`lost_at`), и
/// число живых фрагментов их сегментов пересчитывается
/// ([LiveFragments]); heartbeat вернувшегося узла снимает отметку
/// (`NodeService`).
///
/// **Очередь** ([queue]) — сегменты с живыми не больше порога t, сначала
/// с меньшим числом живых, при равенстве — дольше ждущие. Сегменты с
/// запасом ждут [RepairPolicy.lazyDelay] (ленивый ремонт). Новые задания
/// не начинаются сверх [RepairPolicy.maxJobs] одновременно и сверх
/// [RepairPolicy.maxBytesPerHour] оценённого трафика за час ([budget]).
///
/// **Задание** (задача 4.3.4, protocol.md, раздел 4.14): источники —
/// живые фрагменты на узлах в сети; новые узлы для недостающих номеров —
/// по правилам размещения с учётом уже занятых владельцев и подсетей;
/// исполнитель — узел с каналом команд и репутацией не ниже
/// [RepairPolicy.executorMinReputation]; талоны GET и PUT на исполнителя
/// (у PUT — `owner_account`). Задание записывается с местом на новых
/// узлах и уходит командой канала `repair`; отказ или молчание
/// исполнителя — задание провалено, сегмент пробует другой исполнитель.
/// Отчёт [report] (`ReportRepair`) отмечает загруженные номера; новый
/// фрагмент становится живым ([RepairJobs.acceptTarget]) только после
/// аудита на своём узле ([settle], задача 4.3.5). Нет отчёта к сроку —
/// задание провалено.
///
/// **Перенос** (задачи 4.4.1, 4.4.2; protocol.md, раздел 4.15): с узла,
/// объявившего выход ([leave]) или хранящего больше своей ёмкости,
/// фрагменты переносятся заданиями того же журнала (`kind` = 1) по
/// одному: исполнитель — сам узел, команда канала `relocate`, отчёт и
/// проверка — как у ремонта ([startRelocations]). Узел, с которого
/// переносить больше нечего, удаляется, и [leave] отвечает `done`.
///
/// **Сверка** (задача 4.4.3): фрагменты, которые координатор перестал
/// учитывать на узле, узел находит запросом [reconcile] и удаляет после
/// карантина; heartbeat просит сверить (`reconcile`), когда такие
/// фрагменты появились ([RepairJobs.requestReconcile]).
final class RepairService {
  new(
    this._db, {
    required this.crypto,
    required this.nodes,
    this._signer,
    this.policy = const RepairPolicy(),
    this.placementPolicy = const PlacementPolicy(),
    DateTime Function()? clock,
    Random? random,
  }) : _clock = clock ?? DateTime.now,
       _random = random ?? Random.secure(),
       _placement = Placement(
         minAvailability: placementPolicy.minAvailability,
         minReputation: placementPolicy.minReputation,
         random: random,
       );

  final Database _db;
  final CryptoProvider crypto;
  final NodeService nodes;
  final TicketSigner? _signer;
  final RepairPolicy policy;
  final PlacementPolicy placementPolicy;
  final DateTime Function() _clock;
  final Random _random;
  final Placement _placement;

  /// Каналы команд; без них задания не создаются. Передаёт сервер.
  NodeCommands? channels;

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

  /// Один проход планировщика: потерянные узлы, просроченные задания,
  /// приём отчитанных фрагментов, новые задания ремонта и переноса.
  /// Возвращает число начатых заданий.
  Future<int> runOnce() async {
    await markLost();
    await expire();
    final commands = channels;
    if (commands == null) return 0;
    await settle(commands);
    return await startJobs(commands) + await startRelocations(commands);
  }

  // --- задания ---------------------------------------------------------------

  /// Начинает задания для сегментов из очереди в пределах [budget].
  Future<int> startJobs(NodeCommands commands) async {
    final signer = _signer;
    if (signer == null) return 0;
    var (:jobs, :bytes) = await budget();
    if (jobs == 0 || bytes == 0) return 0;
    var started = 0;
    for (final c in await queue(limit: jobs * 4)) {
      if (started >= jobs || _closed) break;
      final result = await _startJob(commands, signer, c, bytes);
      if (result == null) break; // трафик часа исчерпан
      if (result > 0) {
        started++;
        bytes -= result;
      }
    }
    return started;
  }

  /// Задание для сегмента [c]: оценка трафика, если начато; 0 — не
  /// начато (сегмент ждёт повтора); `null` — не хватает [bytesLeft].
  Future<int?> _startJob(
    NodeCommands commands,
    TicketSigner signer,
    RepairCandidate c,
    int bytesLeft,
  ) async {
    final now = _clock();
    final fields = {'segment': _segmentLabel(c), 'live': c.live};
    final fragments = await _segmentFragments(c, now);
    final sources = [
      for (final f in fragments)
        if (f.live && f.online) f,
    ];
    if (sources.length < c.k) {
      await _retryLater(c, now);
      _log.warning(
        LogEvent('repair_no_sources', {...fields, 'online': sources.length}),
      );
      return 0;
    }
    final liveIndexes = {
      for (final f in fragments)
        if (f.live) f.index,
    };
    final missing = [
      for (var i = 0; i < c.n; i++)
        if (!liveIndexes.contains(i)) i,
    ];
    final segmentNodes = {for (final f in fragments) bytesToHex(f.nodeId)};

    final executor = await _chooseExecutor(commands, c, segmentNodes);
    if (executor == null) {
      await _retryLater(c, now);
      _log.warning(LogEvent('repair_no_executor', fields));
      return 0;
    }
    final targets = await _chooseTargets(
      c,
      missing,
      fragments
          .where((f) => f.live)
          .map(
            (f) => (owner: f.owner, subnet: f.subnet, probation: f.probation),
          ),
      {...segmentNodes, bytesToHex(executor.nodeId)},
    );
    if (targets.isEmpty) {
      await _retryLater(c, now);
      _log.warning(LogEvent('repair_no_targets', fields));
      return 0;
    }
    final planned = plannedBytes(c.k, targets.length, c.fragmentSize);
    if (planned > bytesLeft) return null;

    final byIndex = {for (final f in fragments) f.index: f};
    final deadline = now.add(policy.jobTimeout);
    final jobId = crypto.randomBytes(16);
    final tickets = await signer.sign([
      for (final s in sources)
        _ticket(
          pb.TicketOperation.TICKET_OPERATION_GET,
          node: s.nodeId,
          executor: executor.nodeId,
          fragmentId: s.fragmentId,
          size: c.fragmentSize,
          expires: deadline,
        ),
      for (final (index, node) in targets)
        _ticket(
          pb.TicketOperation.TICKET_OPERATION_PUT,
          node: node.nodeId,
          executor: executor.nodeId,
          fragmentId: byIndex[index]!.fragmentId,
          size: c.fragmentSize,
          expires: deadline,
          owner: c.accountId,
        ),
    ]);
    final created = await _createJob(
      jobId,
      c,
      kind: _repairKind,
      executor: executor.nodeId,
      planned: planned,
      now: now,
      deadline: deadline,
      targets: [
        for (final (i, n) in targets) (i, n.nodeId, byIndex[i]!.fragmentId),
      ],
    );
    if (!created) return 0;
    final command = pb.RepairCommand(
      jobId: jobId,
      k: c.k,
      n: c.n,
      fragmentSize: c.fragmentSize,
      sources: [
        for (var i = 0; i < sources.length; i++)
          pb.Placement(
            index: sources[i].index,
            node: _address(sources[i].nodeId, sources[i].endpoints),
            ticket: tickets[i],
          ),
      ],
      targets: [
        for (var i = 0; i < targets.length; i++)
          pb.Placement(
            index: targets[i].$1,
            node: _address(targets[i].$2.nodeId, targets[i].$2.endpoints),
            ticket: tickets[sources.length + i],
          ),
      ],
      deadlineUnixMs: Int64(deadline.millisecondsSinceEpoch),
    );
    final jobFields = {
      ...fields,
      'job': bytesToHex(jobId),
      'executor': bytesToHex(executor.nodeId),
      'targets': [for (final (i, _) in targets) i],
    };
    final refused = await _dispatch(
      commands,
      executor.nodeId,
      pb.CoordinatorChannelMessage(repair: command),
    );
    if (refused != null) {
      // Повтор сразу: исполнитель этого задания для сегмента не выбирается
      // сутки.
      await _db.transaction(
        (tx) => RepairJobs.failJob(tx, jobId, refused, now: now, retryAt: now),
      );
      _log.warning(
        LogEvent('repair_job_refused', {...jobFields, 'reason': refused}),
      );
      return 0;
    }
    _log.info(LogEvent('repair_job_started', jobFields));
    return planned;
  }

  // --- перенос, выход узла и сверка (задачи 4.4.1–4.4.3) ------------------

  /// Начинает задания переноса (protocol.md, раздел 4.15): с узла,
  /// объявившего выход, переносятся все сохранённые фрагменты
  /// подтверждённых сегментов, с узла, которому выдано больше его ёмкости
  /// из heartbeat (уменьшили квоту, кончается место на диске), — сколько
  /// нужно, чтобы выданное не превышало ёмкость с учётом уже идущих
  /// переносов. Исполнитель — сам узел, он отдаёт свой фрагмент новому
  /// узлу; узел без канала команд ждёт. Возвращает число начатых заданий.
  Future<int> startRelocations(NodeCommands commands) async {
    final signer = _signer;
    if (signer == null || policy.maxRelocations == 0) return 0;
    final now = _clock();
    final active =
        (await _db.run(
              (s) => s.execute('''
        SELECT count(*) FROM repair_jobs WHERE state IN (0, 1) AND kind = 1'''),
            )).single.single!
            as int;
    var left = policy.maxRelocations - active;
    if (left <= 0) return 0;
    final rows = await _db.run(
      (s) => s.execute(
        Sql.named('''
          SELECT n.node_id, n.leaving_at IS NOT NULL,
                 n.assigned_bytes - n.capacity_bytes,
                 coalesce(j.jobs, 0)::int4, coalesce(j.bytes, 0)::int8
            FROM nodes n
              LEFT JOIN (SELECT executor, count(*) AS jobs,
                                sum(planned_bytes) AS bytes
                           FROM repair_jobs
                           WHERE state IN (0, 1) AND kind = 1
                           GROUP BY executor) j ON j.executor = n.node_id
            WHERE n.removed_at IS NULL AND n.lost_at IS NULL
              AND n.last_heartbeat_at >= @online:timestamptz
              AND (n.leaving_at IS NOT NULL
                   OR n.assigned_bytes > n.capacity_bytes)
            ORDER BY n.leaving_at NULLS LAST, n.node_id'''),
        parameters: {'online': now.subtract(nodes.policy.onlineWindow)},
      ),
    );
    var started = 0;
    for (final [
          id as List<int>,
          leaving as bool,
          excess as int,
          jobs as int,
          moving as int,
        ]
        in rows) {
      if (left <= 0 || _closed) break;
      final nodeId = Uint8List.fromList(id);
      if (!commands.isConnected(nodeId)) continue;
      final slots = min(policy.relocationsPerNode - jobs, left);
      if (slots <= 0) continue;
      // Сколько ещё перенести с узла сверх ёмкости; при выходе — всё.
      var need = leaving ? null : excess - moving;
      if (need != null && need <= 0) continue;
      for (final (c, index) in await _relocatable(nodeId, now, slots)) {
        if (need != null && need <= 0) break;
        if (_closed) break;
        if (await _startRelocation(commands, signer, nodeId, c, index, now)) {
          started++;
          left--;
          if (need != null) need -= c.fragmentSize;
        }
      }
    }
    return started;
  }

  /// До [limit] фрагментов узла [nodeId], которые можно переносить:
  /// сохранённые, не повреждённые, подтверждённых сегментов без
  /// действующего задания и паузы повтора. Порядок — по `fragment_id`
  /// (индекс `fragments_audit`): без сортировки всех фрагментов узла.
  Future<List<(RepairCandidate, int)>> _relocatable(
    Uint8List nodeId,
    DateTime now,
    int limit,
  ) async {
    final rows = await _db.run(
      (s) => s.execute(
        Sql.named('''
          SELECT g.account_id, g.segment_id, g.k, g.n, g.repair_threshold,
                 g.fragment_size, g.live,
                 coalesce(g.repair_since, g.committed_at, g.allocated_at),
                 f.idx
            FROM fragments f JOIN segments g USING (account_id, segment_id)
            WHERE f.node_id = @n:bytea AND f.stored AND f.damaged_at IS NULL
              AND g.state <> 0
              AND (g.repair_retry_at IS NULL
                   OR g.repair_retry_at <= @now:timestamptz)
              AND NOT EXISTS (
                SELECT 1 FROM repair_jobs j
                  WHERE j.account_id = g.account_id
                    AND j.segment_id = g.segment_id AND j.state IN (0, 1))
            ORDER BY f.fragment_id
            LIMIT @l:int4'''),
        parameters: {'n': nodeId, 'now': now, 'l': limit},
      ),
    );
    return [
      for (final [
            account as List<int>,
            segment as List<int>,
            k as int,
            n as int,
            t as int,
            size as int,
            live as int,
            since as DateTime,
            index as int,
          ]
          in rows)
        (
          RepairCandidate(
            accountId: Uint8List.fromList(account),
            segmentId: Uint8List.fromList(segment),
            k: k,
            n: n,
            threshold: t,
            fragmentSize: size,
            live: live,
            since: since,
          ),
          index,
        ),
    ];
  }

  /// Задание переноса фрагмента номера [index] сегмента [c] с узла
  /// [nodeId] на новый узел. `false` — не начато (сегмент ждёт повтора).
  Future<bool> _startRelocation(
    NodeCommands commands,
    TicketSigner signer,
    Uint8List nodeId,
    RepairCandidate c,
    int index,
    DateTime now,
  ) async {
    final fields = {
      'segment': _segmentLabel(c),
      'index': index,
      'node_id': bytesToHex(nodeId),
    };
    final fragments = await _segmentFragments(c, now);
    final moving = fragments
        .where((f) => f.index == index && constantTimeEquals(f.nodeId, nodeId))
        .firstOrNull;
    if (moving == null) return false;
    // Новый узел — как при ремонте, но владелец и подсеть уходящего узла
    // не заняты: его фрагмент заменяется.
    final targets = await _chooseTargets(
      c,
      [index],
      fragments
          .where((f) => f.live && f.index != index)
          .map(
            (f) => (owner: f.owner, subnet: f.subnet, probation: f.probation),
          ),
      {for (final f in fragments) bytesToHex(f.nodeId)},
    );
    if (targets.isEmpty) {
      await _retryLater(c, now);
      _log.warning(LogEvent('relocation_no_target', fields));
      return false;
    }
    final (_, target) = targets.single;
    final deadline = now.add(policy.jobTimeout);
    final jobId = crypto.randomBytes(16);
    final [ticket] = await signer.sign([
      _ticket(
        pb.TicketOperation.TICKET_OPERATION_PUT,
        node: target.nodeId,
        executor: nodeId,
        fragmentId: moving.fragmentId,
        size: c.fragmentSize,
        expires: deadline,
        owner: c.accountId,
      ),
    ]);
    final created = await _createJob(
      jobId,
      c,
      kind: _relocationKind,
      executor: nodeId,
      planned: c.fragmentSize,
      now: now,
      deadline: deadline,
      targets: [(index, target.nodeId, moving.fragmentId)],
    );
    if (!created) return false;
    final jobFields = {
      ...fields,
      'job': bytesToHex(jobId),
      'target': bytesToHex(target.nodeId),
    };
    final refused = await _dispatch(
      commands,
      nodeId,
      pb.CoordinatorChannelMessage(
        relocate: pb.RelocateCommand(
          jobId: jobId,
          target: pb.Placement(
            index: index,
            node: _address(target.nodeId, target.endpoints),
            ticket: ticket,
          ),
          deadlineUnixMs: Int64(deadline.millisecondsSinceEpoch),
        ),
      ),
    );
    if (refused != null) {
      // Исполнитель переноса — всегда этот узел: повтор после паузы.
      await _db.transaction(
        (tx) => RepairJobs.failJob(
          tx,
          jobId,
          refused,
          now: now,
          retryAt: now.add(policy.retryDelay),
        ),
      );
      _log.warning(
        LogEvent('relocation_refused', {...jobFields, 'reason': refused}),
      );
      return false;
    }
    _log.info(LogEvent('relocation_started', jobFields));
    return true;
  }

  /// `LeaveNetwork` (задача 4.4.1; protocol.md, раздел 4.15): узел
  /// объявляет выход из сети — новых фрагментов, заданий ремонта и
  /// размещений он больше не получает, его фрагменты переносятся
  /// ([startRelocations]). Повторный запрос сообщает, сколько осталось.
  /// Когда на узле нет сохранённых фрагментов подтверждённых сегментов и
  /// новых фрагментов действующих заданий, узел удаляется (`removed_at`) и
  /// ответ — `done`: его фрагменты координатор больше не учитывает.
  /// `cancel` — выход отменяется, перенесённое остаётся на новых узлах.
  Future<pb.LeaveNetworkResponse> leave(
    CallContext context,
    pb.LeaveNetworkRequest request,
  ) async {
    final nodeId = context.caller!.publicKey;
    final now = _clock();
    final result = await _db.transaction((tx) async {
      final updated = await tx.execute(
        Sql.named(
          request.cancel
              ? '''
                UPDATE nodes SET leaving_at = NULL
                  WHERE node_id = @n:bytea AND removed_at IS NULL
                  RETURNING false'''
              : '''
                UPDATE nodes SET leaving_at = coalesce(leaving_at,
                                                       @t:timestamptz)
                  WHERE node_id = @n:bytea AND removed_at IS NULL
                  RETURNING leaving_at = @t:timestamptz''',
        ),
        parameters: {'n': nodeId, if (!request.cancel) 't': now},
      );
      if (updated.isEmpty) throw _nodeNotFound;
      final [count as int, bytes as int, incoming as int] = (await tx.execute(
        Sql.named('''
          SELECT count(*)::int4, coalesce(sum(g.fragment_size), 0)::int8,
                 (SELECT count(*)::int4 FROM repair_targets t
                    WHERE t.node_id = @n:bytea AND t.state IN (0, 1))
            FROM fragments f JOIN segments g USING (account_id, segment_id)
            WHERE f.node_id = @n:bytea AND f.stored AND f.damaged_at IS NULL
              AND g.state <> 0'''),
        parameters: {'n': nodeId},
      )).single;
      final done = !request.cancel && count == 0 && incoming == 0;
      if (done) {
        await tx.execute(
          Sql.named('''
            UPDATE nodes SET removed_at = @t:timestamptz
              WHERE node_id = @n:bytea'''),
          parameters: {'n': nodeId, 't': now},
        );
      }
      return (
        started: updated.single.single! as bool,
        count: count,
        bytes: bytes,
        done: done,
      );
    });
    final fields = {
      'rid': context.requestId,
      'node_id': bytesToHex(nodeId),
      'fragments': result.count,
    };
    if (request.cancel) {
      _log.info(LogEvent('node_leave_cancelled', fields));
    } else if (result.done) {
      _log.info(LogEvent('node_left', fields));
    } else if (result.started) {
      _log.info(LogEvent('node_leaving', fields));
    }
    return pb.LeaveNetworkResponse(
      remainingFragments: Int64(result.count),
      remainingBytes: Int64(result.bytes),
      done: result.done,
    );
  }

  /// Наибольшая пачка `ReconcileFragments`.
  static const maxReconcileBatch = 1000;

  /// `ReconcileFragments` (задача 4.4.3; protocol.md, раздел 4.15): какие
  /// из перечисленных фрагментов координатор не учитывает на этом узле —
  /// ни как фрагмент сегмента, ни как новый фрагмент действующего задания.
  /// Такие узел удаляет после карантина. `first` снимает отметку «пора
  /// сверить» до проверки: события после неё поставят отметку снова.
  Future<pb.ReconcileFragmentsResponse> reconcile(
    CallContext context,
    pb.ReconcileFragmentsRequest request,
  ) async {
    final ids = request.fragmentIds;
    if (ids.isEmpty || ids.length > maxReconcileBatch) {
      throw _bad('fragment_ids: от 1 до $maxReconcileBatch');
    }
    if (ids.any((id) => id.length != 32)) {
      throw _bad('fragment_ids: по 32 байта');
    }
    if ({for (final id in ids) bytesToHex(id)}.length != ids.length) {
      throw _bad('fragment_ids повторяются');
    }
    final nodeId = context.caller!.publicKey;
    final rows = await _db.transaction((tx) async {
      if (request.first) {
        await tx.execute(
          Sql.named(
            'UPDATE nodes SET reconcile_at = NULL WHERE node_id = @n:bytea',
          ),
          parameters: {'n': nodeId},
        );
      }
      return await tx.execute(
        Sql.named('''
          SELECT id FROM unnest(@ids:_bytea) id
            WHERE NOT EXISTS (
                SELECT 1 FROM fragments f
                  WHERE f.node_id = @n:bytea AND f.fragment_id = id)
              AND NOT EXISTS (
                SELECT 1 FROM repair_targets t
                  WHERE t.node_id = @n:bytea AND t.fragment_id = id
                    AND t.state IN (0, 1))'''),
        parameters: {
          'n': nodeId,
          'ids': [for (final id in ids) Uint8List.fromList(id)],
        },
      );
    });
    if (rows.isNotEmpty) {
      _log.info(
        LogEvent('fragments_unknown', {
          'rid': context.requestId,
          'node_id': bytesToHex(nodeId),
          'checked': ids.length,
          'unknown': rows.length,
        }),
      );
    }
    return pb.ReconcileFragmentsResponse(
      unknown: [for (final [id as List<int>] in rows) id],
    );
  }

  static const _nodeNotFound = RpcException(
    pb.ErrorCode.ERROR_CODE_NOT_FOUND,
    'узел не зарегистрирован',
  );

  /// `repair_jobs.kind`: ремонт и перенос (задачи 4.3.4, 4.4.1).
  static const _repairKind = 0;
  static const _relocationKind = 1;

  /// Фрагменты сегмента [c] с узлами: живой ли, в сети ли узел, на
  /// испытательном ли сроке; сначала узлы с большей доступностью.
  Future<List<_SegmentFragment>> _segmentFragments(
    RepairCandidate c,
    DateTime now,
  ) async {
    final rows = await _db.run(
      (s) => s.execute(
        Sql.named('''
          SELECT f.idx, f.fragment_id, f.node_id, n.account_id, n.subnet,
                 n.endpoints, (${LiveFragments.condition}) AS live,
                 n.last_heartbeat_at >= @online:timestamptz AS online,
                 n.registered_at > @probation:timestamptz AS probation
            FROM fragments f JOIN nodes n USING (node_id)
            WHERE f.account_id = @a:bytea AND f.segment_id = @g:bytea
            ORDER BY n.availability DESC, f.idx'''),
        parameters: {
          'a': c.accountId,
          'g': c.segmentId,
          'online': now.subtract(nodes.policy.onlineWindow),
          'probation': now.subtract(placementPolicy.probation),
        },
      ),
    );
    return [
      for (final [
            idx as int,
            fid as List<int>,
            node as List<int>,
            owner as List<int>,
            subnet as String?,
            endpoints as List<Object?>,
            live as bool,
            online as bool,
            probation as bool,
          ]
          in rows)
        (
          index: idx,
          fragmentId: Uint8List.fromList(fid),
          nodeId: Uint8List.fromList(node),
          owner: bytesToHex(owner),
          subnet: subnet,
          endpoints: [for (final e in endpoints) e! as String],
          live: live,
          online: online,
          probation: probation,
        ),
    ];
  }

  /// Записывает задание [jobId] вида [kind] с новыми фрагментами
  /// [targets] (номер, узел, `fragment_id`) и занимает место на их узлах.
  /// `false` — у сегмента уже есть действующее задание.
  Future<bool> _createJob(
    Uint8List jobId,
    RepairCandidate c, {
    required int kind,
    required Uint8List executor,
    required int planned,
    required DateTime now,
    required DateTime deadline,
    required List<(int, Uint8List, Uint8List)> targets,
  }) async {
    try {
      await _db.transaction((tx) async {
        await tx.execute(
          Sql.named('''
            INSERT INTO repair_jobs
              (job_id, account_id, segment_id, executor, kind, live,
               planned_bytes, state, created_at, deadline)
            VALUES (@j:bytea, @a:bytea, @g:bytea, @e:bytea, @kind:int2,
                    @l:int2, @b:int8, 0, @t:timestamptz, @d:timestamptz)'''),
          parameters: {
            'j': jobId,
            'a': c.accountId,
            'g': c.segmentId,
            'e': executor,
            'kind': kind,
            'l': c.live,
            'b': planned,
            't': now,
            'd': deadline,
          },
        );
        await tx.execute(
          Sql.named('''
            INSERT INTO repair_targets (job_id, idx, node_id, fragment_id,
                                        state)
            SELECT @j:bytea, idx, decode(node, 'hex'), decode(fid, 'hex'), 0
              FROM unnest(@idx:_int4, @nodes:_text, @fids:_text)
                AS t(idx, node, fid)'''),
          parameters: {
            'j': jobId,
            'idx': [for (final (i, _, _) in targets) i],
            'nodes': [for (final (_, n, _) in targets) bytesToHex(n)],
            'fids': [for (final (_, _, f) in targets) bytesToHex(f)],
          },
        );
        await RepairJobs.addNodeBytes(tx, [
          for (final (_, n, _) in targets) n,
        ], c.fragmentSize);
      });
    } on ServerException catch (e) {
      // Другой проход уже начал задание этого сегмента.
      if (e.code == '23505') return false;
      rethrow;
    }
    nodes.noteAssigned([for (final (_, n, _) in targets) n], c.fragmentSize);
    return true;
  }

  /// Отправляет команду задания исполнителю; причина отказа или `null` —
  /// принята.
  Future<String?> _dispatch(
    NodeCommands commands,
    Uint8List executor,
    pb.CoordinatorChannelMessage message,
  ) async {
    try {
      final reply = await commands.send(executor, message);
      if (reply == null) return 'исполнитель: канал закрыт';
      if (reply.hasError()) {
        return 'исполнитель: ${errorCodeName(reply.error.code)}';
      }
      if (!reply.hasDone()) return 'исполнитель: ответ без done';
      return null;
    } on TimeoutException {
      return 'исполнитель: нет ответа';
    }
  }

  /// Исполнитель: узел в сети с каналом команд, не исключённый, вне
  /// испытательного срока, с репутацией не ниже порога, без фрагментов
  /// сегмента, без действующего задания, не отстранённый и не
  /// проваливший задание этого сегмента за сутки; выбор — случайный с
  /// весом-репутацией.
  Future<NodeCandidate?> _chooseExecutor(
    NodeCommands commands,
    RepairCandidate c,
    Set<String> segmentNodes,
  ) async {
    final now = _clock();
    final busy = await _db.run(
      (s) => s.execute(
        Sql.named('''
          SELECT node_id FROM nodes
            WHERE repair_suspended_until > @t:timestamptz
          UNION
          SELECT executor FROM repair_jobs WHERE state IN (0, 1)
          UNION
          SELECT executor FROM repair_jobs
            WHERE account_id = @a:bytea AND segment_id = @g:bytea
              AND state = 3 AND created_at > @day:timestamptz'''),
        parameters: {
          't': now,
          'a': c.accountId,
          'g': c.segmentId,
          'day': now.subtract(const Duration(days: 1)),
        },
      ),
    );
    final excluded = {
      ...segmentNodes,
      for (final [id as List<int>] in busy) bytesToHex(id),
    };
    final pool = await nodes.candidates(
      fragmentSize: 0,
      minAvailability: placementPolicy.minAvailability,
      probation: placementPolicy.probation,
      cacheFor: placementPolicy.candidatesCache,
    );
    final eligible = [
      for (final n in pool)
        if (!n.onProbation &&
            n.weight >= policy.executorMinReputation &&
            !excluded.contains(bytesToHex(n.nodeId)) &&
            commands.isConnected(n.nodeId))
          n,
    ];
    try {
      return _placement
          .choose(eligible, n: 1, fragmentSize: 0, distinctSubnets: false)
          .single;
    } on PlacementException {
      return null;
    }
  }

  /// Новые узлы для номеров [missing] (по возрастанию: сначала данные) по
  /// правилам размещения: владельцы и подсети живых фрагментов заняты,
  /// узлы [excluded] не выбираются, узлов на испытательном сроке с учётом
  /// уже имеющихся — не больше доли сегмента, и только на чётности. Не
  /// хватает на все номера — на столько, сколько нашлось.
  Future<List<(int, NodeCandidate)>> _chooseTargets(
    RepairCandidate c,
    List<int> missing,
    Iterable<({String owner, String? subnet, bool probation})> live,
    Set<String> excluded,
  ) async {
    final pool = await nodes.candidates(
      fragmentSize: c.fragmentSize,
      minAvailability: placementPolicy.minAvailability,
      exceptOwner: c.accountId,
      probation: placementPolicy.probation,
      probationMaxBytes: placementPolicy.probationMaxBytes,
      cacheFor: placementPolicy.candidatesCache,
    );
    final owners = {for (final f in live) f.owner};
    final subnets = {
      for (final f in live)
        if (f.subnet != null) f.subnet!,
    };
    final probation = live.where((f) => f.probation).length;
    final maxProbation = max(
      0,
      placementPolicy.maxProbation(c.n, c.k) - probation,
    );
    var m = missing.length;
    while (m > 0) {
      final indexes = missing.sublist(0, m);
      try {
        final chosen = _placement.choose(
          pool,
          n: m,
          fragmentSize: c.fragmentSize,
          segmentOwner: c.accountId,
          maxProbation: maxProbation,
          parityFrom: indexes.where((i) => i < c.k).length,
          distinctSubnets: placementPolicy.distinctSubnets,
          takenOwners: owners,
          takenSubnets: placementPolicy.distinctSubnets ? subnets : const {},
          excludedNodes: excluded,
        );
        return [for (var i = 0; i < m; i++) (indexes[i], chosen[i])];
      } on PlacementException catch (e) {
        if (e.found >= m) return const [];
        m = e.found;
      }
    }
    return const [];
  }

  pb.FragmentTicket _ticket(
    pb.TicketOperation operation, {
    required List<int> node,
    required List<int> executor,
    required List<int> fragmentId,
    required int size,
    required DateTime expires,
    List<int>? owner,
  }) => pb.FragmentTicket(
    operation: operation,
    nodeId: node,
    deviceSign: executor,
    fragmentId: fragmentId,
    fragmentSize: size,
    expiresAtUnixMs: Int64(expires.millisecondsSinceEpoch),
    ticketId: crypto.randomBytes(FragmentTickets.ticketIdLength),
    ownerAccount: owner,
  );

  static pb.NodeAddress _address(List<int> nodeId, List<String> endpoints) =>
      pb.NodeAddress(
        nodeId: nodeId,
        endpoints: endpoints,
        needsRelay: endpoints.isEmpty,
      );

  Future<void> _retryLater(RepairCandidate c, DateTime now) => _db.run(
    (s) => s.execute(
      Sql.named('''
        UPDATE segments SET repair_retry_at = @t:timestamptz
          WHERE account_id = @a:bytea AND segment_id = @g:bytea'''),
      parameters: {
        'a': c.accountId,
        'g': c.segmentId,
        't': now.add(policy.retryDelay),
      },
    ),
  );

  static String _segmentLabel(RepairCandidate c) =>
      bytesToHex(c.segmentId).substring(0, 16);

  /// Наибольшая длина причины и ошибки в отчёте.
  static const maxReasonLength = 200;

  /// `ReportRepair` (protocol.md, раздел 4.14): исполнитель задания
  /// сообщает, какие новые фрагменты приняты узлами.
  Future<pb.ReportRepairResponse> report(
    CallContext context,
    pb.ReportRepairRequest request,
  ) async {
    final caller = context.caller!.publicKey;
    if (request.jobId.length != 16) throw _notFound;
    final stored = request.storedIndexes;
    final failed = [for (final f in request.failures) f.index];
    if ({...stored}.length != stored.length ||
        {...failed}.length != failed.length ||
        stored.toSet().intersection(failed.toSet()).isNotEmpty) {
      throw _bad('номера повторяются');
    }
    if (request.error.length > maxReasonLength ||
        request.failures.any((f) => f.reason.length > maxReasonLength)) {
      throw _bad('причина длиннее $maxReasonLength символов');
    }
    final jobId = Uint8List.fromList(request.jobId);
    final now = _clock();
    final result = await _db.transaction((tx) async {
      final jobs = await tx.execute(
        Sql.named('''
          SELECT state, deadline FROM repair_jobs
            WHERE job_id = @j:bytea AND executor = @e:bytea FOR UPDATE'''),
        parameters: {'j': jobId, 'e': caller},
      );
      if (jobs.isEmpty) throw _notFound;
      final [state as int, deadline as DateTime] = jobs.single;
      final targets = await tx.execute(
        Sql.named('SELECT idx FROM repair_targets WHERE job_id = @j:bytea'),
        parameters: {'j': jobId},
      );
      final known = {for (final [i as int] in targets) i};
      if ([...stored, ...failed].any((i) => !known.contains(i))) {
        throw _bad('номер не из задания');
      }
      // Повторный или опоздавший отчёт ничего не меняет.
      if (state != RepairJobState.running.index || now.isAfter(deadline)) {
        return null;
      }
      await tx.execute(
        Sql.named('''
          UPDATE repair_jobs
            SET state = 1, reported_at = @t:timestamptz,
                bytes_downloaded = @down:int8, bytes_uploaded = @up:int8,
                reason = nullif(@err:text, '')
            WHERE job_id = @j:bytea'''),
        parameters: {
          'j': jobId,
          't': now,
          'down': request.bytesDownloaded.toInt(),
          'up': request.bytesUploaded.toInt(),
          'err': request.error,
        },
      );
      await tx.execute(
        Sql.named('''
          UPDATE repair_targets SET state = 1
            WHERE job_id = @j:bytea AND idx = ANY(@idx:_int4)'''),
        parameters: {'j': jobId, 'idx': stored},
      );
      for (final f in request.failures) {
        await RepairJobs.failTargets(tx, jobId, f.reason, indexes: [f.index]);
      }
      final silent = known.difference({...stored, ...failed}).toList();
      if (silent.isNotEmpty) {
        await RepairJobs.failTargets(
          tx,
          jobId,
          request.error.isEmpty ? 'нет в отчёте' : request.error,
          indexes: silent,
        );
      }
      await RepairJobs.finishIfDone(
        tx,
        jobId,
        now: now,
        retryAt: now.add(policy.retryDelay),
      );
      return (stored: stored.length, failed: known.length - stored.length);
    });
    if (result != null) {
      _log.info(
        LogEvent('repair_reported', {
          'rid': context.requestId,
          'job': bytesToHex(jobId),
          'stored': result.stored,
          'failed': result.failed,
          'error': ?(request.error.isEmpty ? null : request.error),
        }),
      );
    }
    return pb.ReportRepairResponse();
  }

  /// Проверка результата (задача 4.3.5): каждый новый фрагмент, о
  /// котором отчитался исполнитель, проверяется аудитом на своём узле
  /// (случайный блок, `body_root` размещения) и только тогда становится
  /// живым. Провал — номер провален, место освобождено, исполнитель
  /// отстранён от ремонта на [RepairPolicy.suspend]: он отчитался о
  /// работе, которой нет. Узел без канала проверяется, когда подключится,
  /// но не дольше [RepairPolicy.verifyTimeout] после отчёта. Возвращает
  /// число засчитанных фрагментов.
  Future<int> settle(NodeCommands commands) async {
    final rows = await _db.run(
      (s) => s.execute('''
        SELECT t.job_id, t.idx, t.node_id, t.fragment_id, f.body_root,
               g.fragment_size, j.account_id, j.segment_id, j.executor,
               j.reported_at
          FROM repair_targets t
            JOIN repair_jobs j USING (job_id)
            JOIN segments g USING (account_id, segment_id)
            JOIN fragments f ON f.account_id = j.account_id
              AND f.segment_id = j.segment_id AND f.idx = t.idx
          WHERE t.state = 1
          ORDER BY j.reported_at
          LIMIT 100'''),
    );
    var accepted = 0;
    for (final [
          job as List<int>,
          idx as int,
          node as List<int>,
          fid as List<int>,
          root as List<int>,
          size as int,
          account as List<int>,
          segment as List<int>,
          executor as List<int>,
          reported as DateTime,
        ]
        in rows) {
      if (_closed) break;
      final jobId = Uint8List.fromList(job);
      final nodeId = Uint8List.fromList(node);
      final fields = {
        'job': bytesToHex(jobId),
        'index': idx,
        'node_id': bytesToHex(nodeId),
      };
      AuditOutcome? outcome;
      if (commands.isConnected(nodeId)) {
        final target = AuditTarget(
          nodeId: nodeId,
          fragmentId: Uint8List.fromList(fid),
          bodyRoot: Uint8List.fromList(root),
          fragmentSize: size,
          recheck: false,
        );
        final block = _random.nextInt(merkleLeafCount(target.bodyLength));
        try {
          final reply = await commands.send(
            nodeId,
            pb.CoordinatorChannelMessage(
              audit: pb.AuditCommand(fragmentId: fid, blockIndex: block),
            ),
          );
          if (reply != null) {
            outcome = checkAuditReply(crypto, target, block, reply);
          }
        } on TimeoutException {
          outcome = const AuditOutcome.failed('timeout');
        }
      }
      final now = _clock();
      if (outcome == null) {
        // Узел не на связи: ждём, но не дольше verifyTimeout.
        if (now.difference(reported) < policy.verifyTimeout) continue;
        await _db.transaction((tx) async {
          await RepairJobs.failTargets(
            tx,
            jobId,
            'не проверен: узел не на связи',
            indexes: [idx],
          );
          await _finish(tx, jobId, now);
        });
        _log.warning(LogEvent('repair_fragment_unverified', fields));
        continue;
      }
      if (!outcome.passed) {
        final reason = outcome.reason;
        await _db.transaction((tx) async {
          await RepairJobs.failTargets(
            tx,
            jobId,
            'аудит: $reason',
            indexes: [idx],
          );
          await tx.execute(
            Sql.named('''
              UPDATE nodes SET repair_suspended_until = @t:timestamptz
                WHERE node_id = @n:bytea'''),
            parameters: {'n': executor, 't': now.add(policy.suspend)},
          );
          await _finish(tx, jobId, now);
        });
        _log.warning(
          LogEvent('repair_report_false', {
            ...fields,
            'executor': bytesToHex(executor),
            'reason': reason,
          }),
        );
        continue;
      }
      await _db.transaction((tx) async {
        await RepairJobs.acceptTarget(
          tx,
          jobId: jobId,
          accountId: Uint8List.fromList(account),
          segmentId: Uint8List.fromList(segment),
          index: idx,
          nodeId: nodeId,
          now: now,
        );
        await _finish(tx, jobId, now);
      });
      accepted++;
      _log.info(LogEvent('repair_fragment_restored', fields));
    }
    return accepted;
  }

  Future<RepairJobState?> _finish(
    TxSession tx,
    Uint8List jobId,
    DateTime now,
  ) => RepairJobs.finishIfDone(
    tx,
    jobId,
    now: now,
    retryAt: now.add(policy.retryDelay),
  );

  /// Задания без отчёта к сроку проваливаются; сегмент ждёт повтора.
  Future<int> expire() async {
    final now = _clock();
    final rows = await _db.run(
      (s) => s.execute(
        Sql.named('''
          SELECT job_id FROM repair_jobs
            WHERE state = 0 AND deadline < @t:timestamptz'''),
        parameters: {'t': now},
      ),
    );
    var expired = 0;
    for (final [job as List<int>] in rows) {
      final jobId = Uint8List.fromList(job);
      final failed = await _db.transaction(
        (tx) => RepairJobs.failJob(
          tx,
          jobId,
          'нет отчёта к сроку',
          now: now,
          retryAt: now.add(policy.retryDelay),
        ),
      );
      if (!failed) continue;
      expired++;
      _log.warning(LogEvent('repair_job_expired', {'job': bytesToHex(jobId)}));
    }
    return expired;
  }

  static const _notFound = RpcException(
    pb.ErrorCode.ERROR_CODE_NOT_FOUND,
    'задание ремонта не найдено',
  );

  static RpcException _bad(String message) =>
      RpcException(pb.ErrorCode.ERROR_CODE_BAD_REQUEST, message);

  /// Сегменты, которым пора в ремонт, по приоритету: живых не больше
  /// порога, нет действующего задания, не ждут повтора, ленивые — после
  /// [RepairPolicy.lazyDelay]. Порядок — по индексу `segments_live`.
  Future<List<RepairCandidate>> queue({int limit = 100}) async {
    final now = _clock();
    final rows = await _db.run(
      (s) => s.execute(
        Sql.named('''
          SELECT g.account_id, g.segment_id, g.k, g.n, g.repair_threshold,
                 g.fragment_size, g.live, g.repair_since
            FROM segments g
            WHERE g.state = 2
              AND (g.repair_retry_at IS NULL
                   OR g.repair_retry_at <= @now:timestamptz)
              AND (g.live < g.repair_threshold - @margin:int4
                   OR g.repair_since <= @lazy:timestamptz)
              AND NOT EXISTS (
                SELECT 1 FROM repair_jobs j
                  WHERE j.account_id = g.account_id
                    AND j.segment_id = g.segment_id AND j.state IN (0, 1))
            ORDER BY g.live, g.repair_since
            LIMIT @limit:int4'''),
        parameters: {
          'now': now,
          'margin': policy.lazyMargin,
          'lazy': now.subtract(policy.lazyDelay),
          'limit': limit,
        },
      ),
    );
    return [
      for (final [
            account as List<int>,
            segment as List<int>,
            k as int,
            n as int,
            t as int,
            size as int,
            live as int,
            since as DateTime,
          ]
          in rows)
        RepairCandidate(
          accountId: Uint8List.fromList(account),
          segmentId: Uint8List.fromList(segment),
          k: k,
          n: n,
          threshold: t,
          fragmentSize: size,
          live: live,
          since: since,
        ),
    ];
  }

  /// Сколько заданий ремонта и байт трафика можно начать сейчас: остаток
  /// [RepairPolicy.maxJobs] и [RepairPolicy.maxBytesPerHour]. Задания
  /// переноса сюда не входят: у них свои пределы.
  Future<({int jobs, int bytes})> budget() async {
    final now = _clock();
    final [active as int, recent as int] = (await _db.run(
      (s) => s.execute(
        Sql.named('''
          SELECT (SELECT count(*) FROM repair_jobs
                    WHERE state IN (0, 1) AND kind = 0),
                 (SELECT coalesce(sum(planned_bytes), 0)::int8
                    FROM repair_jobs
                    WHERE created_at > @h:timestamptz AND kind = 0)'''),
        parameters: {'h': now.subtract(const Duration(hours: 1))},
      ),
    )).single;
    return (
      jobs: max(0, policy.maxJobs - active),
      bytes: max(0, policy.maxBytesPerHour - recent),
    );
  }

  /// Оценка трафика ремонта сегмента: скачать k фрагментов и разослать
  /// [targets] новых (durability.md, раздел 2).
  static int plannedBytes(int k, int targets, int fragmentSize) =>
      (k + targets) * fragmentSize;

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
