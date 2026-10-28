import 'dart:async';
import 'dart:collection';
import 'dart:math';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:fixnum/fixnum.dart';
import 'package:logging/logging.dart';
import 'package:node/src/daemon/config.dart';
import 'package:node/src/daemon/log.dart';
import 'package:node/src/daemon/transfers.dart';
import 'package:node/src/storage/fragment_files.dart';
import 'package:node/src/storage/fragment_index.dart';
import 'package:node/src/storage/fragment_storage.dart';
import 'package:protocol/protocol.dart' as pb;

/// Операции с фрагментами для собеседников по каналу Noise (задачи
/// 3.4.1–3.4.3, protocol.md, разделы 3.4 и 5): соединение от транспорта
/// (TCP — задача 3.5, UDP и relay — 3.7, 3.8) проходит рукопожатие, затем
/// запросы `PutFragment`, `GetFragment`, `HasFragments`, `DeleteFragment`,
/// `Ping` выполняются параллельно.
///
/// **Талоны.** `PutFragment`, `GetFragment`, `DeleteFragment` — только по
/// талону координатора на эту операцию, этот узел, устройство собеседника
/// и этот фрагмент, в сроке и не использованному раньше
/// ([FragmentTickets.authorize]). Талон считается использованным, когда
/// операция выполнена; пока она идёт, второй запрос с тем же талоном
/// отклоняется. Удалить фрагмент может только устройство учётной записи,
/// загрузившей его (угроза К-4); `HasFragments` отвечает только про
/// фрагменты учётной записи собеседника.
///
/// **Пределы.** Соединений — всего и на собеседника, одновременных
/// запросов и запросов в секунду на собеседника ([PeerLimits]); скорость
/// приёма и отдачи — общая на все соединения ([downloadLimiter],
/// [uploadLimiter]). Узел на паузе или при остановке не начинает передачи
/// ([TransferGate]): `UNAVAILABLE`.
final class PeerService {
  new({
    required this._crypto,
    required this.local,
    required this.nodeId,
    required this.storage,
    required this.trustedKeys,
    this.revocations,
    TransferGate? gate,
    NodeStats? stats,
    this.limits = const PeerLimits(),
    BandwidthLimiter? uploadLimiter,
    BandwidthLimiter? downloadLimiter,
    this.handshakeTimeout = PeerHandshake.defaultTimeout,
    DateTime Function()? clock,
  }) : gate = gate ?? TransferGate(),
       stats = stats ?? NodeStats(),
       uploadLimiter = uploadLimiter ?? BandwidthLimiter(() => 0),
       downloadLimiter = downloadLimiter ?? BandwidthLimiter(() => 0),
       _clock = clock ?? DateTime.now;

  static final _log = Logger('peers');

  /// Пауза перед повтором, которую узел подсказывает при паузе и
  /// остановке.
  static const pausedRetryAfter = Duration(minutes: 1);

  final CryptoProvider _crypto;

  /// Своя сторона рукопожатия: `node_dh` и сертификат узла.
  final LocalPeer local;
  final Uint8List nodeId;
  final FragmentStorage storage;

  /// Ключи координатора, которым узел доверяет подпись талонов.
  final CoordinatorKeySet trustedKeys;
  final RevokedDevices? revocations;
  final TransferGate gate;
  final NodeStats stats;
  final PeerLimits limits;

  /// Общий предел отдачи фрагментов (`GetFragment`).
  final BandwidthLimiter uploadLimiter;

  /// Общий предел приёма фрагментов (`PutFragment`).
  final BandwidthLimiter downloadLimiter;
  final Duration handshakeTimeout;
  final DateTime Function() _clock;

  final _handshaking = <ByteConnection>{};
  final _sessions = <_Session>{};
  final _peers = <String, _PeerState>{};

  /// Талоны операций, которые идут сейчас.
  final _ticketsInFlight = <String>{};
  bool _closed = false;

  /// Соединений сейчас, вместе с рукопожатиями.
  int get connectionCount => _handshaking.length + _sessions.length;

  /// Собеседников с соединениями.
  int get peerCount => _peers.length;

  /// Обслуживает соединение [connection] до его закрытия. Не бросает:
  /// отказ собеседнику и сбои — в журнал.
  Future<void> serve(ByteConnection connection) async {
    if (_closed || gate.closed || connectionCount >= limits.maxConnections) {
      connection.destroy();
      _log.info(
        LogEvent('peer_connection_refused', {
          'reason': _closed || gate.closed ? 'stopping' : 'max_connections',
          'connections': connectionCount,
        }),
      );
      return;
    }
    _handshaking.add(connection);
    final SecureChannel channel;
    try {
      channel = await PeerHandshake.respond(
        _crypto,
        connection,
        local: local,
        policy: PeerPolicy.anyone(revoked: revocations),
        timeout: handshakeTimeout,
      );
    } on PeerRejectedException catch (e) {
      _log.info(
        LogEvent('peer_rejected', {
          'reason': e.reason.name,
          'detail': ?e.detail,
        }),
      );
      return;
    } on Object catch (e) {
      connection.destroy();
      _log.warning(LogEvent('peer_rejected', {'reason': '${e.runtimeType}'}));
      return;
    } finally {
      _handshaking.remove(connection);
    }
    if (_closed) {
      channel.destroy();
      return;
    }
    final peer = channel.peer;
    final key = bytesToHex(peer.signKey);
    final state = _peers.putIfAbsent(key, () => _PeerState(limits));
    if (state.connections >= limits.maxConnectionsPerPeer) {
      if (state.connections == 0) _peers.remove(key);
      _log.info(
        LogEvent('peer_connection_refused', {
          'reason': 'max_connections_per_peer',
          'peer': _short(peer.signKey),
        }),
      );
      await _sendQuietly(
        channel,
        _error(
          0,
          pb.ErrorCode.ERROR_CODE_RATE_LIMITED,
          'слишком много соединений',
          retryAfter: const Duration(seconds: 1),
        ),
      );
      await channel.close();
      return;
    }
    state.connections++;
    final session = _Session(this, channel, state);
    _sessions.add(session);
    _log.fine(
      LogEvent('peer_connected', {
        'peer': _short(peer.signKey),
        'role': peer.isClient ? 'client' : 'node',
        'software': peer.software,
      }),
    );
    try {
      session.start();
      await session.done;
    } finally {
      _sessions.remove(session);
      state.connections--;
      if (state.connections == 0) _peers.remove(key);
      _log.fine(
        LogEvent('peer_disconnected', {
          'peer': _short(peer.signKey),
          'requests': session.requests,
        }),
      );
    }
  }

  /// Закрывает все соединения; начатые операции прерываются (принимаемые
  /// фрагменты отбрасываются). Вызывать после [TransferGate.close].
  Future<void> close() async {
    _closed = true;
    for (final c in _handshaking.toList()) {
      c.destroy();
    }
    final sessions = _sessions.toList();
    for (final s in sessions) {
      s.end();
    }
    await Future.wait([for (final s in sessions) s.done]);
  }

  // --- операции ------------------------------------------------------------

  Future<void> _put(_Session s, int id, pb.PutFragment request, _Op op) async {
    Transfer? transfer;
    IncomingFragment? incoming;
    String? claimed;
    try {
      transfer = _beginTransfer();
      final ticket = await _authorize(
        s.peer,
        request.ticket,
        pb.TicketOperation.TICKET_OPERATION_PUT,
      );
      claimed = _claim(ticket);
      final owner = _owner(s.peer, ticket);
      final fragmentId = Uint8List.fromList(ticket.fragmentId);
      if (storage.record(fragmentId) case final r?) {
        // Повтор загрузки (ответ потерялся): успех для той же учётной
        // записи, остаток частей не нужен.
        if (r.state == FragmentState.stored &&
            constantTimeEquals(r.accountId, owner)) {
          _useTicket(ticket);
          await s.reply(
            pb.PeerMessage(
              requestId: Int64(id),
              putFragmentResult: pb.PutFragmentResult(fragmentId: fragmentId),
            ),
          );
          return;
        }
        throw const _Rejected(
          pb.ErrorCode.ERROR_CODE_ALREADY_EXISTS,
          'фрагмент уже хранится',
        );
      }
      incoming = await storage.beginPut(
        fragmentId: fragmentId,
        size: ticket.fragmentSize,
        accountId: owner,
      );
      while (true) {
        final chunk = await op.next(limits.transferTimeout);
        if (chunk.data.length > PeerOperations.maxChunk) {
          throw _Rejected(
            pb.ErrorCode.ERROR_CODE_BAD_REQUEST,
            'часть фрагмента ${chunk.data.length} байт, наибольшая '
            '${PeerOperations.maxChunk}',
          );
        }
        await downloadLimiter.acquire(chunk.data.length);
        if (op.cancelled) throw const _Cancelled();
        await incoming.add(chunk.data);
        stats.bytesReceived += chunk.data.length;
        if (chunk.last) break;
      }
      await incoming.commit();
      _useTicket(ticket);
      stats.fragmentsReceived++;
      _log.fine(
        LogEvent('fragment_received', {
          'fragment': _short(fragmentId),
          'bytes': ticket.fragmentSize,
          'peer': _short(s.peer.signKey),
        }),
      );
      op.close();
      await s.reply(
        pb.PeerMessage(
          requestId: Int64(id),
          putFragmentResult: pb.PutFragmentResult(fragmentId: fragmentId),
        ),
      );
    } on Object catch (e, st) {
      op.close();
      await incoming?.abort();
      await _replyFailure(s, id, e, st);
    } finally {
      if (claimed != null) _ticketsInFlight.remove(claimed);
      transfer?.end();
    }
  }

  Future<void> _get(_Session s, int id, pb.GetFragment request, _Op op) async {
    Transfer? transfer;
    String? claimed;
    try {
      transfer = _beginTransfer();
      final ticket = await _authorize(
        s.peer,
        request.ticket,
        pb.TicketOperation.TICKET_OPERATION_GET,
      );
      claimed = _claim(ticket);
      final fragmentId = Uint8List.fromList(ticket.fragmentId);
      final record = storage.record(fragmentId);
      if (record == null || record.state != FragmentState.stored) {
        throw const _Rejected(
          pb.ErrorCode.ERROR_CODE_NOT_FOUND,
          'фрагмента нет',
        );
      }
      if (record.size != ticket.fragmentSize) {
        throw const _Rejected(
          pb.ErrorCode.ERROR_CODE_PERMISSION_DENIED,
          'талон: fragment_size',
        );
      }
      final data = storage.openRead(fragmentId);
      await s.send(
        pb.PeerMessage(
          requestId: Int64(id),
          getFragmentResult: pb.GetFragmentResult(fragmentSize: record.size),
        ),
      );
      var sent = 0;
      await for (final chunk in _chunks(data, PeerOperations.maxChunk)) {
        if (op.cancelled) throw const _Cancelled();
        await uploadLimiter.acquire(chunk.length);
        if (op.cancelled) throw const _Cancelled();
        await s.send(
          pb.PeerMessage(
            requestId: Int64(id),
            fragmentData: pb.FragmentData(
              data: chunk,
              last: sent + chunk.length >= record.size,
            ),
          ),
        );
        sent += chunk.length;
        stats.bytesSent += chunk.length;
        if (sent >= record.size) break;
      }
      if (sent != record.size) {
        throw _Rejected(
          pb.ErrorCode.ERROR_CODE_INTERNAL,
          'фрагмент на диске: $sent байт из ${record.size}',
        );
      }
      _useTicket(ticket);
      stats.fragmentsSent++;
      _log.fine(
        LogEvent('fragment_sent', {
          'fragment': _short(fragmentId),
          'bytes': record.size,
          'peer': _short(s.peer.signKey),
        }),
      );
    } on Object catch (e, st) {
      await _replyFailure(s, id, e, st);
    } finally {
      if (claimed != null) _ticketsInFlight.remove(claimed);
      transfer?.end();
    }
  }

  Future<void> _has(_Session s, int id, pb.HasFragments request) async {
    try {
      final ids = request.fragmentIds;
      if (ids.length > PeerOperations.maxHasFragments) {
        throw const _Rejected(
          pb.ErrorCode.ERROR_CODE_BAD_REQUEST,
          'больше ${PeerOperations.maxHasFragments} фрагментов',
        );
      }
      if (ids.any((f) => f.length != FragmentTickets.fragmentIdLength)) {
        throw const _Rejected(
          pb.ErrorCode.ERROR_CODE_BAD_REQUEST,
          'fragment_id — 32 байта',
        );
      }
      await s.reply(
        pb.PeerMessage(
          requestId: Int64(id),
          hasFragmentsResult: pb.HasFragmentsResult(
            present: storage.has(s.peer.accountId, ids),
          ),
        ),
      );
    } on Object catch (e, st) {
      await _replyFailure(s, id, e, st);
    }
  }

  Future<void> _delete(_Session s, int id, pb.DeleteFragment request) async {
    String? claimed;
    try {
      if (!s.peer.isClient) {
        throw const _Rejected(
          pb.ErrorCode.ERROR_CODE_PERMISSION_DENIED,
          'удаляет только устройство учётной записи-владельца',
        );
      }
      final ticket = await _authorize(
        s.peer,
        request.ticket,
        pb.TicketOperation.TICKET_OPERATION_DELETE,
      );
      claimed = _claim(ticket);
      final fragmentId = Uint8List.fromList(ticket.fragmentId);
      final record = storage.record(fragmentId);
      if (record == null || record.state == FragmentState.pending) {
        throw const _Rejected(
          pb.ErrorCode.ERROR_CODE_NOT_FOUND,
          'фрагмента нет',
        );
      }
      if (record.size != ticket.fragmentSize) {
        throw const _Rejected(
          pb.ErrorCode.ERROR_CODE_PERMISSION_DENIED,
          'талон: fragment_size',
        );
      }
      if (!constantTimeEquals(record.accountId, s.peer.accountId)) {
        // Талон есть, а фрагмент чужой: так выглядит удаление по воле
        // взломанного координатора (угроза К-4).
        _log.warning(
          LogEvent('delete_denied', {
            'fragment': _short(fragmentId),
            'peer': _short(s.peer.signKey),
            'account': _short(s.peer.accountId),
          }),
        );
        throw const _Rejected(
          pb.ErrorCode.ERROR_CODE_PERMISSION_DENIED,
          'фрагмент загружен другой учётной записью',
        );
      }
      _useTicket(ticket);
      storage.delete(fragmentId);
      stats.fragmentsDeleted++;
      _log.fine(
        LogEvent('fragment_deleted', {
          'fragment': _short(fragmentId),
          'peer': _short(s.peer.signKey),
        }),
      );
      await s.reply(
        pb.PeerMessage(
          requestId: Int64(id),
          deleteFragmentResult: pb.DeleteFragmentResult(),
        ),
      );
    } on Object catch (e, st) {
      await _replyFailure(s, id, e, st);
    } finally {
      if (claimed != null) _ticketsInFlight.remove(claimed);
    }
  }

  // --- проверки ------------------------------------------------------------

  /// Учётная запись-владелец загружаемого фрагмента (protocol.md,
  /// разделы 4.14, 5): у клиента — его собственная, у узла-исполнителя
  /// ремонта — `owner_account` из талона. Удалить фрагмент сможет только
  /// устройство владельца.
  static Uint8List _owner(PeerIdentity peer, pb.FragmentTicket ticket) {
    final owner = ticket.ownerAccount;
    if (peer.isClient) {
      if (owner.isNotEmpty) {
        throw const _Rejected(
          pb.ErrorCode.ERROR_CODE_PERMISSION_DENIED,
          'талон: owner_account — только для узла-исполнителя ремонта',
        );
      }
      return peer.accountId;
    }
    if (owner.isEmpty) {
      throw const _Rejected(
        pb.ErrorCode.ERROR_CODE_PERMISSION_DENIED,
        'узел загружает фрагменты только при ремонте: нужен owner_account',
      );
    }
    return Uint8List.fromList(owner);
  }

  Transfer _beginTransfer() =>
      gate.tryBegin() ??
      (throw _Rejected(
        pb.ErrorCode.ERROR_CODE_UNAVAILABLE,
        gate.closed ? 'узел останавливается' : 'узел на паузе',
        retryAfter: pausedRetryAfter,
      ));

  /// Талон [signed] на [operation] для собеседника [peer] (protocol.md,
  /// раздел 5); фрагмент — из самого талона, его размер сверяет
  /// вызывающий.
  Future<pb.FragmentTicket> _authorize(
    PeerIdentity peer,
    pb.Signed signed,
    pb.TicketOperation operation,
  ) async {
    final pb.FragmentTicket fields;
    try {
      fields = FragmentTickets.parse(Uint8List.fromList(signed.body));
    } on DataFormatException catch (e) {
      throw _Rejected(
        pb.ErrorCode.ERROR_CODE_BAD_REQUEST,
        'талон: ${e.detail}',
      );
    }
    try {
      return await FragmentTickets.authorize(
        _crypto,
        signed,
        trustedKeys,
        now: _clock(),
        operation: operation,
        nodeId: nodeId,
        deviceSign: peer.signKey,
        fragmentId: fields.fragmentId,
      );
    } on TicketRejectedException catch (e) {
      final code = switch (e.reason) {
        TicketRejection.untrusted ||
        TicketRejection.signature => pb.ErrorCode.ERROR_CODE_UNAUTHENTICATED,
        TicketRejection.format => pb.ErrorCode.ERROR_CODE_BAD_REQUEST,
        TicketRejection.expired => pb.ErrorCode.ERROR_CODE_TICKET_EXPIRED,
        TicketRejection.tooLong ||
        TicketRejection.mismatch => pb.ErrorCode.ERROR_CODE_PERMISSION_DENIED,
      };
      final detail = e.detail == null ? '' : ': ${e.detail}';
      throw _Rejected(code, 'талон: ${e.reason.name}$detail');
    }
  }

  /// Занимает талон на время операции: использованный или занятый другим
  /// запросом — отказ.
  String _claim(pb.FragmentTicket ticket) {
    final key = bytesToHex(ticket.ticketId);
    if (_ticketsInFlight.contains(key) ||
        storage.isTicketUsed(Uint8List.fromList(ticket.ticketId))) {
      throw const _Rejected(
        pb.ErrorCode.ERROR_CODE_PERMISSION_DENIED,
        'талон уже использован',
      );
    }
    _ticketsInFlight.add(key);
    return key;
  }

  void _useTicket(pb.FragmentTicket ticket) => storage.useTicket(
    Uint8List.fromList(ticket.ticketId),
    DateTime.fromMillisecondsSinceEpoch(ticket.expiresAtUnixMs.toInt()),
  );

  Future<void> _replyFailure(
    _Session s,
    int id,
    Object error,
    StackTrace stack,
  ) async {
    switch (error) {
      case _Cancelled():
        return;
      case _Rejected(:final code, :final message, :final retryAfter):
        stats.requestsRejected++;
        _log.fine(
          LogEvent('request_rejected', {
            'code': errorCodeName(code),
            'detail': message,
            'peer': _short(s.peer.signKey),
          }),
        );
        await s.reply(_error(id, code, message, retryAfter: retryAfter));
      case FragmentStorageException(:final code, :final message):
        stats.requestsRejected++;
        _log.fine(
          LogEvent('request_rejected', {
            'code': errorCodeName(code),
            'detail': message,
            'peer': _short(s.peer.signKey),
          }),
        );
        await s.reply(_error(id, code, message));
      case _ when s.closed:
        // Соединение оборвалось посреди операции.
        return;
      case _:
        _log.severe(
          LogEvent('request_failed', {'error': '${error.runtimeType}'}),
          null,
          stack,
        );
        await s.reply(
          _error(id, pb.ErrorCode.ERROR_CODE_INTERNAL, 'внутренняя ошибка'),
        );
    }
  }

  static pb.PeerMessage _error(
    int id,
    pb.ErrorCode code,
    String message, {
    Duration? retryAfter,
  }) => pb.PeerMessage(
    requestId: Int64(id),
    error: pb.Error(
      code: code,
      message: message,
      retryAfterMs: retryAfter?.inMilliseconds,
    ),
  );

  static Future<void> _sendQuietly(SecureChannel c, pb.PeerMessage m) =>
      c.send(m).catchError((Object _) {});

  /// Поток [data] частями по [size] байт (последняя короче).
  static Stream<Uint8List> _chunks(Stream<List<int>> data, int size) async* {
    final buffer = BytesBuilder(copy: false);
    await for (final piece in data) {
      buffer.add(piece);
      while (buffer.length >= size) {
        final all = buffer.takeBytes();
        yield Uint8List.sublistView(all, 0, size);
        if (all.length > size) buffer.add(Uint8List.sublistView(all, size));
      }
    }
    if (buffer.isNotEmpty) yield buffer.takeBytes();
  }

  static String _short(List<int> id) => bytesToHex(id).substring(0, 16);
}

/// Отказ в запросе: ответ `PeerMessage.error`.
final class _Rejected implements Exception {
  const new(this.code, this.message, {this.retryAfter});

  final pb.ErrorCode code;
  final String message;
  final Duration? retryAfter;
}

/// Запрос отменён собеседником или соединение закрылось: ответа нет.
final class _Cancelled implements Exception {
  const new();
}

/// Собеседник по ключу из сертификата: соединения, запросы и их частота
/// по всем соединениям.
final class _PeerState {
  new(this._limits) : _tokens = _limits.requestsPerSecond * 2.0;

  final PeerLimits _limits;
  final _watch = Stopwatch()..start();
  int connections = 0;
  int requests = 0;
  double _tokens;
  int _lastMicros = 0;

  /// Можно ли начать ещё один запрос.
  Duration? admit() {
    if (requests >= _limits.maxRequestsPerPeer) {
      return const Duration(milliseconds: 100);
    }
    final rate = _limits.requestsPerSecond;
    final now = _watch.elapsedMicroseconds;
    _tokens = min(
      rate * 2.0,
      _tokens + (now - _lastMicros) * rate / Duration.microsecondsPerSecond,
    );
    _lastMicros = now;
    if (_tokens < 1) {
      return Duration(milliseconds: ((1 - _tokens) * 1000 / rate).ceil());
    }
    _tokens -= 1;
    requests++;
    return null;
  }
}

/// Одно соединение: разбор входящих сообщений по `request_id`.
final class _Session {
  new(this.service, this.channel, this.state);

  final PeerService service;
  final SecureChannel channel;
  final _PeerState state;
  late final StreamSubscription<pb.PeerMessage> _subscription;
  final _active = <int, _Op>{};
  final _done = Completer<void>();
  int _lastId = 0;
  int _buffered = 0;
  bool _paused = false;
  bool _ended = false;
  final _running = <Future<void>>{};
  Timer? _idle;

  /// Запросов за время соединения.
  int requests = 0;

  PeerIdentity get peer => channel.peer;
  Future<void> get done => _done.future;
  bool get closed => _ended;

  void start() {
    _subscription = channel.messages.listen(
      _onMessage,
      onError: (Object _) => end(),
      onDone: end,
    );
    _restartIdle();
  }

  /// Закрывает соединение и отменяет запросы; [done] завершается, когда
  /// их обработчики вышли.
  void end() {
    if (_ended) return;
    _ended = true;
    _idle?.cancel();
    channel.destroy();
    unawaited(_subscription.cancel());
    for (final op in _active.values) {
      op.cancel();
    }
    unawaited(
      Future.wait(_running).whenComplete(() {
        if (!_done.isCompleted) _done.complete();
      }),
    );
  }

  /// Нарушение протокола: закрытие без ответа (protocol.md, раздел 3.4).
  void _violation(String detail) {
    PeerService._log.info(
      LogEvent('peer_protocol_violation', {
        'detail': detail,
        'peer': PeerService._short(peer.signKey),
      }),
    );
    end();
  }

  void _onMessage(pb.PeerMessage m) {
    if (closed) return;
    final id = m.requestId.toInt();
    switch (m.whichBody()) {
      case pb.PeerMessage_Body.putFragment ||
          pb.PeerMessage_Body.getFragment ||
          pb.PeerMessage_Body.hasFragments ||
          pb.PeerMessage_Body.deleteFragment ||
          pb.PeerMessage_Body.ping:
        if (id <= _lastId) {
          _violation('request_id $id не больше предыдущего $_lastId');
          return;
        }
        _lastId = id;
        _startRequest(id, m);
      case pb.PeerMessage_Body.fragmentData:
        final op = _active[id];
        if (op != null && op.isPut) {
          op.enqueue(m.fragmentData);
        } else if (op != null || id <= 0 || id > _lastId) {
          _violation('FragmentData без PutFragment');
        }
      // Иначе — остаток отменённой или отклонённой загрузки: пропускается.
      case pb.PeerMessage_Body.cancel:
        _active[id]?.cancel();
      // Ответы и ошибки от собеседника узлу не нужны; неизвестные
      // сообщения более новых версий пропускаются.
      case _:
    }
  }

  void _startRequest(int id, pb.PeerMessage m) {
    requests++;
    final wait = state.admit();
    if (wait != null) {
      service.stats.requestsRejected++;
      unawaited(
        reply(
          PeerService._error(
            id,
            pb.ErrorCode.ERROR_CODE_RATE_LIMITED,
            'слишком много запросов',
            retryAfter: wait,
          ),
        ),
      );
      return;
    }
    _idle?.cancel();
    final op = _Op(this, isPut: m.hasPutFragment());
    _active[id] = op;
    final run = switch (m.whichBody()) {
      pb.PeerMessage_Body.putFragment => service._put(
        this,
        id,
        m.putFragment,
        op,
      ),
      pb.PeerMessage_Body.getFragment => service._get(
        this,
        id,
        m.getFragment,
        op,
      ),
      pb.PeerMessage_Body.hasFragments => service._has(
        this,
        id,
        m.hasFragments,
      ),
      pb.PeerMessage_Body.deleteFragment => service._delete(
        this,
        id,
        m.deleteFragment,
      ),
      _ => reply(
        pb.PeerMessage(
          requestId: Int64(id),
          pong: pb.Pong(nonce: m.ping.nonce),
        ),
      ),
    };
    late final Future<void> tracked;
    tracked = run.whenComplete(() {
      op.close();
      _active.remove(id);
      _running.remove(tracked);
      state.requests--;
      if (_active.isEmpty) _restartIdle();
    });
    _running.add(tracked);
  }

  void _restartIdle() {
    _idle?.cancel();
    if (closed) return;
    _idle = Timer(service.limits.idleTimeout, () {
      if (_active.isEmpty) unawaited(channel.close().whenComplete(end));
    });
  }

  /// Отправка с ожиданием собеседника не дольше `transfer_timeout`: кто не
  /// читает, тот теряет соединение.
  Future<void> send(pb.PeerMessage m) async {
    if (closed) throw const _Cancelled();
    try {
      await channel.send(m).timeout(service.limits.transferTimeout);
    } on TimeoutException {
      PeerService._log.info(
        LogEvent('peer_stalled', {'peer': PeerService._short(peer.signKey)}),
      );
      end();
      throw const _Cancelled();
      // SecureChannel.send: канал закрыт.
      // ignore: avoid_catching_errors
    } on StateError {
      end();
      throw const _Cancelled();
    }
  }

  /// Ответ, который можно потерять вместе с соединением.
  Future<void> reply(pb.PeerMessage m) async {
    try {
      await send(m);
    } on _Cancelled {
      // Соединение закрыто: ответ некому отправить.
    }
  }

  // Принятые части загрузок ждут записи в очередях операций; больше
  // [PeerLimits.bufferBytes] — чтение встаёт на паузу до половины.
  void _buffer(int delta) {
    _buffered += delta;
    final limit = service.limits.bufferBytes;
    final want =
        !closed && (_buffered > limit || (_paused && _buffered > limit ~/ 2));
    if (want == _paused) return;
    _paused = want;
    if (want) {
      _subscription.pause();
    } else {
      _subscription.resume();
    }
  }
}

/// Идущий запрос: отмена и, для загрузки, очередь принятых частей.
final class _Op {
  new(this._session, {required this.isPut});

  final _Session _session;

  /// Загрузка: принимает `FragmentData`.
  final bool isPut;
  bool _open = true;
  final _queue = Queue<pb.FragmentData>();
  Completer<void>? _wake;
  bool cancelled = false;

  void enqueue(pb.FragmentData data) {
    if (!_open) return;
    _queue.add(data);
    _session._buffer(data.data.length);
    _signal();
  }

  /// Следующая часть загрузки; не пришла за [timeout] —
  /// `UNAVAILABLE`, отмена — [_Cancelled].
  Future<pb.FragmentData> next(Duration timeout) async {
    while (_queue.isEmpty) {
      if (cancelled) throw const _Cancelled();
      final wake = _wake = Completer<void>();
      try {
        await wake.future.timeout(timeout);
      } on TimeoutException {
        throw const _Rejected(
          pb.ErrorCode.ERROR_CODE_UNAVAILABLE,
          'часть фрагмента не пришла вовремя',
        );
      }
    }
    if (cancelled) throw const _Cancelled();
    final data = _queue.removeFirst();
    _session._buffer(-data.data.length);
    return data;
  }

  void cancel() {
    cancelled = true;
    _signal();
  }

  /// Запрос завершён: остаток очереди выбрасывается, новые части
  /// пропускаются.
  void close() {
    _open = false;
    var bytes = 0;
    for (final d in _queue) {
      bytes += d.data.length;
    }
    _queue.clear();
    if (bytes > 0) _session._buffer(-bytes);
  }

  void _signal() {
    final wake = _wake;
    _wake = null;
    if (wake != null && !wake.isCompleted) wake.complete();
  }
}
