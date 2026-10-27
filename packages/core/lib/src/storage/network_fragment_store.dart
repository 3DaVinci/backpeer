import 'dart:async';
import 'dart:typed_data';

import 'package:core/src/crypto/crypto_provider.dart';
import 'package:core/src/errors.dart';
import 'package:core/src/format/fragment.dart';
import 'package:core/src/format/ticket.dart';
import 'package:core/src/net/bandwidth_limiter.dart';
import 'package:core/src/net/peer_client.dart';
import 'package:core/src/net/transport.dart';
import 'package:core/src/storage/fragment_store.dart';
import 'package:core/src/storage/node_folders.dart';
import 'package:core/src/util/bytes.dart';
import 'package:protocol/protocol.dart' as pb;

/// Откуда [NetworkFragmentStore] берёт адреса узлов и талоны: из ответов
/// координатора ([TicketBook]) или, в тестах, от своего подписанта.
abstract interface class NodeAccess {
  /// Узлы, о которых известно, как к ним подключаться.
  List<Uint8List> get knownNodes;

  /// Адреса узла; узел неизвестен — `null`.
  NodeContact? contact(Uint8List nodeId);

  /// Действующий талон на операцию [operation] с фрагментом [fragmentId]
  /// на узле [nodeId]; нет — `null`. [fragmentSize] известен для PUT.
  Future<pb.Signed?> ticket(
    pb.TicketOperation operation,
    Uint8List nodeId,
    Uint8List fragmentId, {
    int? fragmentSize,
  });

  /// Операция выполнена: талон израсходован (protocol.md, раздел 5).
  void consumed(
    pb.TicketOperation operation,
    Uint8List nodeId,
    Uint8List fragmentId,
  );
}

/// Адреса узлов и талоны из ответов координатора: `AllocateSegment`
/// (талоны PUT), `LocateSegment` (GET), `DeleteSegment` (DELETE). Их
/// записывает `CoordinatorSegments`, берёт [NetworkFragmentStore].
///
/// Подпись талона здесь не проверяется — это дело узла; клиент только
/// разбирает тело, чтобы знать операцию, узел, фрагмент и срок. Талон, до
/// конца которого меньше [margin], считается истёкшим: операция с ним
/// может не успеть.
final class TicketBook implements NodeAccess {
  new({this.margin = const Duration(minutes: 1)});

  final Duration margin;
  final _contacts = <String, NodeContact>{};
  final _tickets = <String, (pb.Signed, int)>{};
  int _added = 0;

  @override
  List<Uint8List> get knownNodes => [
    for (final c in _contacts.values) c.nodeId,
  ];

  /// Талонов в книге (с истёкшими, пока они не убраны).
  int get ticketCount => _tickets.length;

  @override
  NodeContact? contact(Uint8List nodeId) => _contacts[bytesToHex(nodeId)];

  /// Запоминает адреса узла; новые заменяют прежние.
  void addNode(pb.NodeAddress address) {
    if (address.nodeId.length != CryptoProvider.keyLength) return;
    final contact = NodeContact.fromProto(address);
    _contacts[bytesToHex(contact.nodeId)] = contact;
  }

  /// Узлы и талоны из записей размещения.
  void addPlacements(Iterable<pb.Placement> placements) {
    for (final p in placements) {
      if (p.hasNode()) addNode(p.node);
      if (p.hasTicket()) addTicket(p.ticket);
    }
  }

  /// Запоминает талон; неразбираемый пропускается (узел его всё равно
  /// отклонит).
  void addTicket(pb.Signed signed) {
    final pb.FragmentTicket t;
    try {
      t = FragmentTickets.parse(Uint8List.fromList(signed.body));
    } on DataFormatException {
      return;
    }
    _tickets[_key(t.operation, t.nodeId, t.fragmentId)] = (
      signed,
      t.expiresAtUnixMs.toInt(),
    );
    if (++_added % 1024 == 0) _prune();
  }

  @override
  Future<pb.Signed?> ticket(
    pb.TicketOperation operation,
    Uint8List nodeId,
    Uint8List fragmentId, {
    int? fragmentSize,
  }) async {
    final key = _key(operation, nodeId, fragmentId);
    final entry = _tickets[key];
    if (entry == null) return null;
    if (entry.$2 - margin.inMilliseconds <
        DateTime.now().millisecondsSinceEpoch) {
      _tickets.remove(key);
      return null;
    }
    return entry.$1;
  }

  @override
  void consumed(
    pb.TicketOperation operation,
    Uint8List nodeId,
    Uint8List fragmentId,
  ) => _tickets.remove(_key(operation, nodeId, fragmentId));

  void _prune() {
    final now = DateTime.now().millisecondsSinceEpoch;
    _tickets.removeWhere((_, e) => e.$2 < now);
  }

  static String _key(
    pb.TicketOperation operation,
    List<int> nodeId,
    List<int> fragmentId,
  ) => '${operation.value}/${bytesToHex(nodeId)}/${bytesToHex(fragmentId)}';
}

/// [FragmentStore] поверх сети (задача 3.9.2): операции с фрагментами по
/// каналу Noise (`PeerClient`, protocol.md, раздел 3.4) с узлами, к
/// которым подключается [transport]. Имя узла — `node_id` в hex, как у
/// [NodeFolders]; адреса и талоны — из [access].
///
/// **Пул соединений.** Одно соединение на узел, запросы к нему идут
/// параллельно по этому соединению. Соединение без запросов дольше
/// [idleTimeout] закрывается; соединений больше [maxConnections] —
/// закрываются давно не нужные из простаивающих. Оборванное соединение
/// открывается заново при следующей операции; операция, прерванная
/// обрывом, повторяется один раз по новому соединению (прерванная
/// передача талон не расходует).
///
/// **Недоступные узлы.** Не удалось подключиться — операции с узлом
/// [failureBackoff] сразу заканчиваются `unavailable`, без новых попыток:
/// сегмент с двадцатью фрагментами не ждёт двадцать раз один и тот же
/// узел. Загрузку на остальные узлы и `CommitSegment` с загруженными
/// делает конвейер (`SegmentPacker`).
///
/// **Ошибки** — как у остальных хранилищ: `StorageException`
/// (`unavailable` — узел недоступен, нет талона или талон отклонён;
/// `notFound` — фрагмента нет; `io` — прочие отказы узла),
/// `IntegrityException` — узел не принял фрагмент при проверке,
/// `DataFormatException` — фрагмент не разбирается ещё до отправки.
///
/// Он же [NodeDirectory]: сертификат узла — из рукопожатия Noise.
final class NetworkFragmentStore implements FragmentStore, NodeDirectory {
  new({
    required this.crypto,
    required this.transport,
    required this.access,
    this.maxConnections = 64,
    this.idleTimeout = const Duration(seconds: 60),
    this.failureBackoff = const Duration(seconds: 10),
    this.uploadLimiter,
    this.downloadLimiter,
    this.responseTimeout = PeerClient.defaultTimeout,
  });

  final CryptoProvider crypto;
  final Transport transport;
  final NodeAccess access;
  final int maxConnections;
  final Duration idleTimeout;
  final Duration failureBackoff;
  final BandwidthLimiter? uploadLimiter;
  final BandwidthLimiter? downloadLimiter;
  final Duration responseTimeout;

  final _pool = <String, _Pooled>{};
  final _failedAt = <String, (DateTime, String)>{};
  Timer? _sweeper;
  bool _closed = false;

  /// Подключений с запуска (новых соединений, не операций).
  int connectionsOpened = 0;

  /// Открытых соединений.
  int get openConnections => _pool.length;

  @override
  List<String> get nodes => [for (final id in access.knownNodes) nameOf(id)];

  @override
  String nameOf(Uint8List nodeId) => bytesToHex(nodeId);

  @override
  Future<pb.Signed?> handshake(String node) async {
    try {
      return (await _client(node, 'handshake')).peer.certificate;
    } on StorageException {
      return null;
    }
  }

  @override
  Future<Uint8List> put(
    String node,
    Uint8List fragment, {
    Uint8List? expectedFragmentId,
  }) async {
    final header = FragmentHeader.parse(fragment);
    final fragmentId = header.fragmentId(crypto);
    if (expectedFragmentId != null &&
        !constantTimeEquals(fragmentId, expectedFragmentId)) {
      throw IntegrityException(
        object: 'fragment',
        check: IntegrityCheck.fragmentId,
        objectId: expectedFragmentId,
      );
    }
    final id = await _run(
      node,
      'put',
      pb.TicketOperation.TICKET_OPERATION_PUT,
      fragmentId,
      (client, ticket) => client.putFragment(ticket, fragment),
      fragmentSize: fragment.length,
    );
    if (!constantTimeEquals(id, fragmentId)) {
      throw StorageException(
        location: node,
        problem: StorageProblem.io,
        operation: 'put',
        cause: 'узел ответил другим fragment_id',
      );
    }
    return fragmentId;
  }

  @override
  Future<Uint8List> get(String node, Uint8List fragmentId) => _run(
    node,
    'get',
    pb.TicketOperation.TICKET_OPERATION_GET,
    fragmentId,
    (client, ticket) => client.readFragment(ticket),
  );

  @override
  Future<List<bool>> has(String node, List<Uint8List> fragmentIds) async {
    final out = <bool>[];
    for (
      var i = 0;
      i < fragmentIds.length;
      i += PeerOperations.maxHasFragments
    ) {
      final part = fragmentIds.sublist(
        i,
        (i + PeerOperations.maxHasFragments).clamp(0, fragmentIds.length),
      );
      out.addAll(
        await _withClient(node, 'has', (client) => client.hasFragments(part)),
      );
    }
    return out;
  }

  @override
  Future<void> delete(String node, Uint8List fragmentId) async {
    try {
      await _run(
        node,
        'delete',
        pb.TicketOperation.TICKET_OPERATION_DELETE,
        fragmentId,
        (client, ticket) => client.deleteFragment(ticket),
      );
    } on StorageException catch (e) {
      // Отсутствующий фрагмент — не ошибка, как у остальных хранилищ.
      if (e.problem != StorageProblem.notFound) rethrow;
    }
  }

  /// Закрывает соединения и [transport].
  Future<void> close() async {
    _closed = true;
    _sweeper?.cancel();
    final pooled = _pool.values.toList();
    _pool.clear();
    for (final p in pooled) {
      p.close();
    }
    await transport.close();
  }

  /// Операция по талону: талон из [access], запрос, расход талона.
  Future<T> _run<T>(
    String node,
    String operation,
    pb.TicketOperation ticketOperation,
    Uint8List fragmentId,
    Future<T> Function(PeerClient client, pb.Signed ticket) request, {
    int? fragmentSize,
  }) async {
    final nodeId = _nodeId(node, operation);
    final ticket = await access.ticket(
      ticketOperation,
      nodeId,
      fragmentId,
      fragmentSize: fragmentSize,
    );
    if (ticket == null) {
      throw StorageException(
        location: node,
        problem: StorageProblem.unavailable,
        operation: operation,
        cause: 'нет действующего талона',
      );
    }
    final result = await _withClient(
      node,
      operation,
      (client) => request(client, ticket),
    );
    access.consumed(ticketOperation, nodeId, fragmentId);
    return result;
  }

  /// Запрос по соединению из пула с одним повтором после обрыва.
  Future<T> _withClient<T>(
    String node,
    String operation,
    Future<T> Function(PeerClient client) request,
  ) async {
    for (var attempt = 1; ; attempt++) {
      final client = await _client(node, operation);
      final pooled = _pool[node];
      pooled?.active++;
      try {
        return await request(client);
      } on PeerRequestException catch (e) {
        final broken =
            e.code == pb.ErrorCode.ERROR_CODE_UNAVAILABLE && client.isClosed;
        if (broken) _drop(node, client);
        if (broken && attempt == 1) continue;
        throw _translate(e, node, operation);
      } finally {
        pooled?.active--;
        pooled?.lastUsed = DateTime.now();
      }
    }
  }

  Future<PeerClient> _client(String node, String operation) async {
    if (_closed) throw StateError('хранилище закрыто');
    final existing = _pool[node];
    if (existing != null) {
      final client = await _await(node, existing);
      if (!client.isClosed) return client;
      _drop(node, client);
    }
    final failed = _failedAt[node];
    if (failed != null) {
      if (DateTime.now().difference(failed.$1) < failureBackoff) {
        throw _unavailable(node, operation, failed.$2);
      }
      _failedAt.remove(node);
    }
    final nodeId = _nodeId(node, operation);
    final contact = access.contact(nodeId) ?? NodeContact(nodeId: nodeId);
    final pooled = _Pooled(_connect(node, operation, contact));
    _pool[node] = pooled;
    final client = await _await(node, pooled);
    connectionsOpened++;
    _limit();
    _sweeper ??= Timer.periodic(idleTimeout ~/ 2, (_) => _sweep());
    return client;
  }

  /// Клиент соединения пула; не подключилось — соединение убирается.
  Future<PeerClient> _await(String node, _Pooled pooled) async {
    try {
      return await pooled.client;
    } on StorageException {
      if (identical(_pool[node], pooled)) _pool.remove(node);
      rethrow;
    }
  }

  Future<PeerClient> _connect(
    String node,
    String operation,
    NodeContact contact,
  ) async {
    final PeerConnection connection;
    try {
      connection = await transport.connect(contact);
    } on Exception catch (e) {
      final cause = e is CoreException ? e.message : '$e';
      _failedAt[node] = (DateTime.now(), cause);
      throw _unavailable(node, operation, cause);
    }
    return PeerClient(
      connection.channel,
      responseTimeout: responseTimeout,
      uploadLimiter: uploadLimiter,
      downloadLimiter: downloadLimiter,
    );
  }

  void _drop(String node, PeerClient client) {
    final pooled = _pool[node];
    if (pooled != null && identical(pooled.ready, client)) {
      _pool.remove(node);
      pooled.close();
    }
  }

  /// Закрывает простаивающие давно не нужные соединения сверх предела.
  void _limit() {
    if (_pool.length <= maxConnections) return;
    final idle = _pool.entries.where((e) => e.value.idle).toList()
      ..sort((a, b) => a.value.lastUsed.compareTo(b.value.lastUsed));
    for (final e in idle.take(_pool.length - maxConnections)) {
      _pool.remove(e.key);
      e.value.close();
    }
  }

  void _sweep() {
    final now = DateTime.now();
    _pool.removeWhere((_, p) {
      final stale = p.idle && now.difference(p.lastUsed) >= idleTimeout;
      if (stale) p.close();
      return stale;
    });
    _failedAt.removeWhere((_, f) => now.difference(f.$1) >= failureBackoff);
    if (_pool.isEmpty) {
      _sweeper?.cancel();
      _sweeper = null;
    }
  }

  Uint8List _nodeId(String node, String operation) {
    if (RegExp(r'^[0-9a-f]{64}$').hasMatch(node)) return hexToBytes(node);
    throw StorageException(
      location: node,
      problem: StorageProblem.unavailable,
      operation: operation,
      cause: 'имя узла — не node_id',
    );
  }

  static StorageException _unavailable(
    String node,
    String operation,
    String cause,
  ) => StorageException(
    location: node,
    problem: StorageProblem.unavailable,
    operation: operation,
    cause: cause,
  );

  static CoreException _translate(
    PeerRequestException e,
    String node,
    String operation,
  ) => switch (e.code) {
    pb.ErrorCode.ERROR_CODE_INTEGRITY_FAILED => const IntegrityException(
      object: 'fragment',
      check: IntegrityCheck.merkleRoot,
    ),
    pb.ErrorCode.ERROR_CODE_NOT_FOUND => StorageException(
      location: node,
      problem: StorageProblem.notFound,
      operation: operation,
      cause: e.detail,
    ),
    pb.ErrorCode.ERROR_CODE_UNAVAILABLE ||
    pb.ErrorCode.ERROR_CODE_RATE_LIMITED ||
    pb.ErrorCode.ERROR_CODE_TICKET_EXPIRED ||
    pb.ErrorCode.ERROR_CODE_PERMISSION_DENIED ||
    pb.ErrorCode.ERROR_CODE_UNAUTHENTICATED ||
    pb.ErrorCode.ERROR_CODE_QUOTA_EXCEEDED => StorageException(
      location: node,
      problem: StorageProblem.unavailable,
      operation: operation,
      cause: e.message,
    ),
    _ => StorageException(
      location: node,
      problem: StorageProblem.io,
      operation: operation,
      cause: e.message,
    ),
  };
}

/// Соединение пула: пока подключается — future, потом клиент.
final class _Pooled {
  new(this.client) {
    unawaited(client.then((c) => ready = c, onError: (Object _) => null));
  }

  final Future<PeerClient> client;
  PeerClient? ready;
  int active = 0;
  DateTime lastUsed = DateTime.now();

  bool get idle => ready != null && active == 0;

  void close() {
    final c = ready;
    if (c != null) {
      unawaited(c.close());
    } else {
      client.then((c) => c.close(), onError: (Object _) {}).ignore();
    }
  }
}
