import 'dart:typed_data';

import 'package:coordinator/src/db/database.dart';
import 'package:coordinator/src/log.dart';
import 'package:coordinator/src/nodes/node_service.dart';
import 'package:coordinator/src/placement/placement.dart';
import 'package:coordinator/src/placement/placement_policy.dart';
import 'package:coordinator/src/rpc/call_context.dart';
import 'package:coordinator/src/rpc/errors.dart';
import 'package:coordinator/src/signer/ticket_signer.dart';
import 'package:core/core.dart';
import 'package:fixnum/fixnum.dart';
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:protocol/protocol.dart' as pb;

/// Состояние сегмента в таблице `segments`.
enum SegmentState {
  /// Размещён, ждёт `CommitSegment`.
  allocated,

  /// Сохранён: загружено больше t фрагментов.
  stored,

  /// Сохранён, но фрагментов не больше порога ремонта t — помечен для
  /// ремонта (этап 4).
  needsRepair,
}

/// Размещение сегментов и талоны (задачи 2.7.1–2.7.4; protocol.md,
/// разделы 5, 5.2).
///
/// Учёт места: фрагмент «занимает» место на узле и в учётной записи, пока
/// сегмент размещён и не подтверждён или пока фрагмент сохранён.
/// Подтверждение освобождает место незагруженных фрагментов, удаление
/// сегмента — всё его место.
final class SegmentService {
  new(
    this._db,
    this._nodes, {
    required this.crypto,
    this._signer,
    this.policy = const PlacementPolicy(),
    Placement? placement,
    DateTime Function()? clock,
  }) : _placement =
           placement ?? Placement(minAvailability: policy.minAvailability),
       _clock = clock ?? DateTime.now;

  final Database _db;
  final NodeService _nodes;
  final CryptoProvider crypto;
  final TicketSigner? _signer;
  final PlacementPolicy policy;
  final Placement _placement;
  final DateTime Function() _clock;

  static final _log = Logger('segments');

  static const _idLength = 32;

  Future<pb.AllocateSegmentResponse> allocate(
    CallContext context,
    pb.AllocateSegmentRequest request,
  ) async {
    final segmentId = _segmentId(request.segmentId);
    final k = request.k;
    final n = request.n;
    final t = request.repairThreshold;
    if (k < 1 || k >= n || n > 255) throw _bad('нужно 1 ≤ k < n ≤ 255');
    if (t < k || t >= n) throw _bad('нужно k ≤ repair_threshold < n');
    final size = request.fragmentSize;
    if (size < FragmentTickets.minFragmentSize ||
        size > FragmentTickets.maxFragmentSize) {
      throw _bad('fragment_size вне пределов');
    }
    _ids(request.fragmentIds, n, 'fragment_ids');
    _ids(request.bodyRoots, n, 'body_roots');
    final signer = _signer ?? (throw _noSigner);
    final accountId = _account(context);

    // Узлы и талоны — до транзакции: подпись не держит блокировки. Если
    // запись потом не удастся, талоны просто не дойдут до клиента.
    await _ensureNotCommitted(accountId, segmentId);
    final candidates = await _nodes.candidates(
      fragmentSize: size,
      minAvailability: policy.minAvailability,
      exceptOwner: accountId,
      probation: policy.probation,
    );
    final List<NodeCandidate> chosen;
    try {
      chosen = _placement.choose(
        candidates,
        n: n,
        fragmentSize: size,
        segmentOwner: accountId,
        maxProbation: policy.maxProbation(n),
        distinctSubnets: policy.distinctSubnets,
      );
    } on PlacementException catch (e) {
      throw RpcException(
        pb.ErrorCode.ERROR_CODE_UNAVAILABLE,
        'подходящих узлов ${e.found}, нужно ${e.needed}',
        retryAfter: const Duration(minutes: 1),
      );
    }
    final tickets = await signer.sign([
      for (var i = 0; i < n; i++)
        _ticket(
          pb.TicketOperation.TICKET_OPERATION_PUT,
          node: chosen[i].nodeId,
          device: context.caller!.publicKey,
          fragmentId: request.fragmentIds[i],
          size: size,
        ),
    ]);

    await _write(() async {
      await _db.transaction((tx) async {
        await _lockAccount(tx, accountId);
        final state = await _state(tx, accountId, segmentId);
        if (state != null) {
          if (state != SegmentState.allocated) throw _committed;
          // Повторное размещение неподтверждённого сегмента (например,
          // после сбоя загрузки): прежние узлы освобождаются.
          await _release(tx, accountId, segmentId);
          await _delete(tx, accountId, segmentId);
        }
        await tx.execute(
          Sql.named('''
            INSERT INTO segments
              (account_id, segment_id, k, n, repair_threshold, fragment_size,
               state, allocated_at)
            VALUES (@a:bytea, @g:bytea, @k:int2, @n:int2, @t:int2, @s:int4,
                    0, @now:timestamptz)'''),
          parameters: {
            'a': accountId,
            'g': segmentId,
            'k': k,
            'n': n,
            't': t,
            's': size,
            'now': _clock(),
          },
        );
        await tx.execute(
          Sql.named('''
            INSERT INTO fragments
              (account_id, segment_id, idx, fragment_id, body_root, node_id)
            SELECT @a:bytea, @g:bytea, idx, decode(fid, 'hex'),
                   decode(root, 'hex'), decode(node, 'hex')
              FROM unnest(@idx:_int4, @fids:_text, @roots:_text, @nodes:_text)
                AS f(idx, fid, root, node)'''),
          parameters: {
            'a': accountId,
            'g': segmentId,
            'idx': [for (var i = 0; i < n; i++) i],
            'fids': [for (final id in request.fragmentIds) bytesToHex(id)],
            'roots': [for (final r in request.bodyRoots) bytesToHex(r)],
            'nodes': [for (final c in chosen) bytesToHex(c.nodeId)],
          },
        );
        await _addAssigned(tx, accountId, [
          for (final c in chosen) c.nodeId,
        ], size);
      });
    });
    _log.info(
      LogEvent('segment_allocated', {'rid': context.requestId, 'n': n}),
    );
    return pb.AllocateSegmentResponse(
      placements: [
        for (var i = 0; i < n; i++)
          pb.Placement(
            index: i,
            node: _address(chosen[i].nodeId, chosen[i].endpoints),
            ticket: tickets[i],
          ),
      ],
    );
  }

  Future<pb.CommitSegmentResponse> commit(
    CallContext context,
    pb.CommitSegmentRequest request,
  ) async {
    final segmentId = _segmentId(request.segmentId);
    final indexes = request.storedIndexes;
    if (indexes.toSet().length != indexes.length) {
      throw _bad('номера фрагментов повторяются');
    }
    final accountId = _account(context);
    final state = await _write(
      () => _db.transaction((tx) async {
        await _lockAccount(tx, accountId);
        final rows = await tx.execute(
          Sql.named('''
            SELECT k, n, repair_threshold, fragment_size, state FROM segments
              WHERE account_id = @a:bytea AND segment_id = @g:bytea
              FOR UPDATE'''),
          parameters: {'a': accountId, 'g': segmentId},
        );
        if (rows.isEmpty) throw _notFound;
        final [k as int, n as int, t as int, size as int, state as int] =
            rows.single;
        if (indexes.any((i) => i >= n)) throw _bad('номер фрагмента ≥ n');
        final fragments = await tx.execute(
          Sql.named('''
            SELECT idx, node_id, stored FROM fragments
              WHERE account_id = @a:bytea AND segment_id = @g:bytea'''),
          parameters: {'a': accountId, 'g': segmentId},
        );
        final requested = indexes.toSet();
        final stored = {
          for (final [idx as int, _, s as bool] in fragments)
            if (s || requested.contains(idx)) idx,
        };
        if (stored.length < k) {
          throw _bad('сохранено ${stored.length} фрагментов, меньше k = $k');
        }
        final first = state == SegmentState.allocated.index;
        // Место: при первом подтверждении освобождается место
        // незагруженных фрагментов, при повторном — занимается место
        // догруженных.
        final changed = <Uint8List>[
          for (final [idx as int, node as List<int>, s as bool] in fragments)
            if (first ? !stored.contains(idx) : !s && stored.contains(idx))
              Uint8List.fromList(node),
        ];
        if (changed.isNotEmpty) {
          await _addAssigned(tx, accountId, changed, first ? -size : size);
        }
        await tx.execute(
          Sql.named('''
            UPDATE fragments SET stored = true
              WHERE account_id = @a:bytea AND segment_id = @g:bytea
                AND idx = ANY(@idx:_int4)'''),
          parameters: {'a': accountId, 'g': segmentId, 'idx': stored.toList()},
        );
        final next = stored.length <= t
            ? SegmentState.needsRepair
            : SegmentState.stored;
        await tx.execute(
          Sql.named('''
            UPDATE segments
              SET state = @s:int2,
                  committed_at = coalesce(committed_at, @now:timestamptz)
              WHERE account_id = @a:bytea AND segment_id = @g:bytea'''),
          parameters: {
            'a': accountId,
            'g': segmentId,
            's': next.index,
            'now': _clock(),
          },
        );
        return next;
      }),
    );
    _log.info(
      LogEvent('segment_committed', {
        'rid': context.requestId,
        'repair': state == SegmentState.needsRepair,
      }),
    );
    return pb.CommitSegmentResponse();
  }

  Future<pb.LocateSegmentResponse> locate(
    CallContext context,
    pb.LocateSegmentRequest request,
  ) async {
    final segmentId = _segmentId(request.segmentId);
    final signer = _signer ?? (throw _noSigner);
    final accountId = _account(context);
    final segment = await _db.run(
      (s) => s.execute(
        Sql.named('''
          SELECT fragment_size FROM segments
            WHERE account_id = @a:bytea AND segment_id = @g:bytea
              AND state <> 0'''),
        parameters: {'a': accountId, 'g': segmentId},
      ),
    );
    if (segment.isEmpty) throw _notFound;
    final size = segment.single.single! as int;
    // Сохранённые фрагменты на неудалённых узлах; узлы в сети — первыми.
    final rows = await _db.run(
      (s) => s.execute(
        Sql.named('''
          SELECT f.idx, f.fragment_id, n.node_id, n.endpoints
            FROM fragments f JOIN nodes n USING (node_id)
            WHERE f.account_id = @a:bytea AND f.segment_id = @g:bytea
              AND f.stored AND n.removed_at IS NULL
            ORDER BY n.last_heartbeat_at >= @online:timestamptz DESC,
                     n.availability DESC, f.idx'''),
        parameters: {
          'a': accountId,
          'g': segmentId,
          'online': _clock().subtract(_nodes.policy.onlineWindow),
        },
      ),
    );
    final tickets = await signer.sign([
      for (final [_, fid as List<int>, node as List<int>, _] in rows)
        _ticket(
          pb.TicketOperation.TICKET_OPERATION_GET,
          node: node,
          device: context.caller!.publicKey,
          fragmentId: fid,
          size: size,
        ),
    ]);
    return pb.LocateSegmentResponse(
      placements: [
        for (var i = 0; i < rows.length; i++)
          pb.Placement(
            index: rows[i][0]! as int,
            node: _address(rows[i][2]! as List<int>, [
              for (final e in rows[i][3]! as List<Object?>) e! as String,
            ]),
            ticket: tickets[i],
          ),
      ],
    );
  }

  /// Сборка мусора (manifest.md, раздел 7): координатор забывает сегмент,
  /// освобождает его место и выдаёт талоны DELETE на все его фрагменты
  /// на неудалённых узлах — и на незагруженные: клиент мог загрузить их,
  /// не успев сообщить. Удаляет фрагменты с узлов клиент.
  Future<pb.DeleteSegmentResponse> delete(
    CallContext context,
    pb.DeleteSegmentRequest request,
  ) async {
    final segmentId = _segmentId(request.segmentId);
    final signer = _signer ?? (throw _noSigner);
    final accountId = _account(context);
    final rows = await _db.run(
      (s) => s.execute(
        Sql.named('''
          SELECT f.idx, f.fragment_id, n.node_id, n.endpoints, g.fragment_size
            FROM fragments f
              JOIN segments g USING (account_id, segment_id)
              JOIN nodes n USING (node_id)
            WHERE f.account_id = @a:bytea AND f.segment_id = @g:bytea
              AND n.removed_at IS NULL
            ORDER BY f.idx'''),
        parameters: {'a': accountId, 'g': segmentId},
      ),
    );
    // Талоны — до удаления: если подписант недоступен, сегмент остаётся,
    // и клиент повторит запрос.
    final tickets = await signer.sign([
      for (final [_, fid as List<int>, node as List<int>, _, size as int]
          in rows)
        _ticket(
          pb.TicketOperation.TICKET_OPERATION_DELETE,
          node: node,
          device: context.caller!.publicKey,
          fragmentId: fid,
          size: size,
        ),
    ]);
    final existed = await _write(
      () => _db.transaction((tx) async {
        await _lockAccount(tx, accountId);
        if (await _state(tx, accountId, segmentId) == null) return false;
        await _release(tx, accountId, segmentId);
        await _delete(tx, accountId, segmentId);
        return true;
      }),
    );
    if (!existed) throw _notFound;
    _log.info(LogEvent('segment_deleted', {'rid': context.requestId}));
    return pb.DeleteSegmentResponse(
      placements: [
        for (var i = 0; i < rows.length; i++)
          pb.Placement(
            index: rows[i][0]! as int,
            node: _address(rows[i][2]! as List<int>, [
              for (final e in rows[i][3]! as List<Object?>) e! as String,
            ]),
            ticket: tickets[i],
          ),
      ],
    );
  }

  /// Место под фрагменты учётной записи.
  Future<int> accountBytes(Uint8List accountId) async {
    final rows = await _db.run(
      (s) => s.execute(
        Sql.named(
          'SELECT fragment_bytes FROM accounts WHERE account_id = @a:bytea',
        ),
        parameters: {'a': accountId},
      ),
    );
    return rows.isEmpty ? 0 : rows.single.single! as int;
  }

  pb.FragmentTicket _ticket(
    pb.TicketOperation operation, {
    required List<int> node,
    required List<int> device,
    required List<int> fragmentId,
    required int size,
  }) => pb.FragmentTicket(
    operation: operation,
    nodeId: node,
    deviceSign: device,
    fragmentId: fragmentId,
    fragmentSize: size,
    expiresAtUnixMs: Int64(
      _clock().add(policy.ticketLifetime).millisecondsSinceEpoch,
    ),
    ticketId: crypto.randomBytes(FragmentTickets.ticketIdLength),
  );

  static pb.NodeAddress _address(List<int> nodeId, List<String> endpoints) =>
      pb.NodeAddress(
        nodeId: nodeId,
        endpoints: endpoints,
        needsRelay: endpoints.isEmpty,
      );

  Future<void> _ensureNotCommitted(
    Uint8List accountId,
    Uint8List segmentId,
  ) async {
    final state = await _db.transaction(
      (tx) => _state(tx, accountId, segmentId),
    );
    if (state != null && state != SegmentState.allocated) throw _committed;
  }

  static Future<SegmentState?> _state(
    TxSession tx,
    Uint8List accountId,
    Uint8List segmentId,
  ) async {
    final rows = await tx.execute(
      Sql.named('''
        SELECT state FROM segments
          WHERE account_id = @a:bytea AND segment_id = @g:bytea
          FOR UPDATE'''),
      parameters: {'a': accountId, 'g': segmentId},
    );
    return rows.isEmpty
        ? null
        : SegmentState.values[rows.single.single! as int];
  }

  /// Все операции с местом учётной записи идут под её блокировкой: так
  /// они не пересекаются, а узлы блокируются по порядку ([_addAssigned]).
  static Future<void> _lockAccount(TxSession tx, Uint8List accountId) =>
      tx.execute(
        Sql.named(
          'SELECT 1 FROM accounts WHERE account_id = @a:bytea FOR UPDATE',
        ),
        parameters: {'a': accountId},
      );

  /// Меняет место на узлах [nodes] на [delta] за каждый фрагмент и место
  /// учётной записи — на сумму. Узлы блокируются по возрастанию
  /// идентификатора, чтобы одновременные размещения разных учётных
  /// записей не взаимоблокировались.
  static Future<void> _addAssigned(
    TxSession tx,
    Uint8List accountId,
    List<Uint8List> nodes,
    int delta,
  ) async {
    final hex = [for (final n in nodes) bytesToHex(n)]..sort();
    await tx.execute(
      Sql.named('''
        SELECT 1 FROM nodes
          WHERE node_id IN (SELECT decode(h, 'hex') FROM unnest(@ids:_text) h)
          ORDER BY node_id FOR UPDATE'''),
      parameters: {'ids': hex},
    );
    await tx.execute(
      Sql.named(
        '''
        UPDATE nodes SET assigned_bytes = greatest(assigned_bytes + @d:int8, 0)
          WHERE node_id IN (SELECT decode(h, 'hex') FROM unnest(@ids:_text) h)''',
      ),
      parameters: {'ids': hex, 'd': delta},
    );
    await tx.execute(
      Sql.named('''
        UPDATE accounts
          SET fragment_bytes = greatest(fragment_bytes + @d:int8, 0)
          WHERE account_id = @a:bytea'''),
      parameters: {'a': accountId, 'd': delta * nodes.length},
    );
  }

  /// Освобождает место, которое занимает сегмент.
  static Future<void> _release(
    TxSession tx,
    Uint8List accountId,
    Uint8List segmentId,
  ) async {
    final rows = await tx.execute(
      Sql.named('''
        SELECT f.node_id, g.fragment_size
          FROM fragments f JOIN segments g USING (account_id, segment_id)
          WHERE f.account_id = @a:bytea AND f.segment_id = @g:bytea
            AND (f.stored OR g.state = 0)'''),
      parameters: {'a': accountId, 'g': segmentId},
    );
    if (rows.isEmpty) return;
    await _addAssigned(tx, accountId, [
      for (final [node as List<int>, _] in rows) Uint8List.fromList(node),
    ], -(rows.first[1]! as int));
  }

  static Future<void> _delete(
    TxSession tx,
    Uint8List accountId,
    Uint8List segmentId,
  ) => tx.execute(
    Sql.named(
      'DELETE FROM segments '
      'WHERE account_id = @a:bytea AND segment_id = @g:bytea',
    ),
    parameters: {'a': accountId, 'g': segmentId},
  );

  /// Взаимоблокировка в PostgreSQL — `UNAVAILABLE`: запрос можно повторить.
  static Future<T> _write<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on ServerException catch (e) {
      if (e.code != '40P01' && e.code != '40001') rethrow;
      throw const RpcException(
        pb.ErrorCode.ERROR_CODE_UNAVAILABLE,
        'конфликт транзакций',
        retryAfter: Duration(milliseconds: 200),
      );
    }
  }

  static Uint8List _account(CallContext context) =>
      context.caller!.info!.accountId;

  static Uint8List _segmentId(List<int> id) {
    if (id.length != _idLength) throw _bad('segment_id — 32 байта');
    return Uint8List.fromList(id);
  }

  static void _ids(List<List<int>> ids, int n, String field) {
    if (ids.length != n || ids.any((id) => id.length != _idLength)) {
      throw _bad('$field — $n по 32 байта');
    }
  }

  static const _noSigner = RpcException(
    pb.ErrorCode.ERROR_CODE_UNAVAILABLE,
    'подписант талонов не настроен',
    retryAfter: Duration(minutes: 1),
  );

  static const _committed = RpcException(
    pb.ErrorCode.ERROR_CODE_ALREADY_EXISTS,
    'сегмент уже сохранён',
  );

  static const _notFound = RpcException(
    pb.ErrorCode.ERROR_CODE_NOT_FOUND,
    'сегмент не найден',
  );

  static RpcException _bad(String message) =>
      RpcException(pb.ErrorCode.ERROR_CODE_BAD_REQUEST, message);
}
