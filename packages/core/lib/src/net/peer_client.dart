import 'dart:async';
import 'dart:collection';
import 'dart:math';
import 'dart:typed_data';

import 'package:core/src/errors.dart';
import 'package:core/src/format/ticket.dart';
import 'package:core/src/net/bandwidth_limiter.dart';
import 'package:core/src/net/peer_identity.dart';
import 'package:core/src/net/secure_channel.dart';
import 'package:fixnum/fixnum.dart';
import 'package:protocol/protocol.dart' as pb;

/// Пределы операций с фрагментами (protocol.md, раздел 3.4).
abstract final class PeerOperations {
  /// Наибольшая часть фрагмента в `FragmentData`: помещается в один
  /// транспортный кадр вместе с заголовками.
  static const int maxChunk = 61440;

  /// Наибольшее число идентификаторов в `HasFragments`.
  static const int maxHasFragments = 1000;
}

/// Сторона, которая отправляет запросы по каналу Noise (клиент, узел при
/// ремонте): операции с фрагментами (protocol.md, раздел 3.4).
///
/// **Мультиплексирование.** Запросы идут параллельно по одному
/// соединению; у каждого свой `request_id`, номера растут с 1. Части
/// параллельных загрузок и выдач чередуются.
///
/// **Обратное давление.** Загрузка отправляет следующую часть, только
/// когда соединение приняло предыдущую. Принятые части выдачи ждут
/// потребителя в очереди; если в очередях больше [bufferBytes], чтение из
/// соединения встаёт на паузу до их разбора, и собеседник упирается в
/// TCP. Медленный потребитель задерживает соединение, но не копит память.
///
/// **Таймауты.** Ответа нет дольше [responseTimeout] после запроса (для
/// загрузки — после последней части) или очередная часть выдачи не
/// пришла за [idleTimeout] — `UNAVAILABLE` и отмена запроса. Соединение не
/// принимает данные дольше [idleTimeout] — `UNAVAILABLE`, соединение
/// закрывается.
///
/// **Отмена.** Загрузка — future `cancel`, выдача — отмена подписки на её
/// поток: собеседнику уходит `Cancel`.
final class PeerClient {
  new(
    this.channel, {
    this.responseTimeout = defaultTimeout,
    this.idleTimeout = defaultTimeout,
    this.bufferBytes = defaultBufferBytes,
    this.uploadLimiter,
    this.downloadLimiter,
  }) {
    _subscription = channel.messages.listen(
      _onMessage,
      onError: (Object e) => _closeAll(
        PeerRequestException(pb.ErrorCode.ERROR_CODE_UNAVAILABLE, '$e'),
      ),
      onDone: () => _closeAll(
        const PeerRequestException(
          pb.ErrorCode.ERROR_CODE_UNAVAILABLE,
          'соединение закрыто',
        ),
      ),
    );
  }

  static const Duration defaultTimeout = Duration(seconds: 30);
  static const int defaultBufferBytes = 1 << 20;

  final SecureChannel channel;
  final Duration responseTimeout;
  final Duration idleTimeout;
  final int bufferBytes;

  /// Предел отдачи частей фрагментов; `null` — без предела.
  final BandwidthLimiter? uploadLimiter;

  /// Предел приёма частей фрагментов; `null` — без предела.
  final BandwidthLimiter? downloadLimiter;

  late final StreamSubscription<pb.PeerMessage> _subscription;
  final _requests = <int, _Request>{};
  final _random = Random.secure();
  int _nextId = 1;
  int _buffered = 0;
  bool _readPaused = false;
  bool _throttling = false;
  int _unpaidBytes = 0;
  PeerRequestException? _closed;

  PeerIdentity get peer => channel.peer;

  /// Запросов, ещё не получивших ответа целиком.
  int get activeRequests => _requests.length;

  /// Байт частей выдачи, ждущих потребителя.
  int get bufferedBytes => _buffered;

  bool get isClosed => _closed != null;

  /// Проверка канала; возвращает время до ответа.
  Future<Duration> ping() async {
    final nonce = Int64.fromInts(
      _random.nextInt(1 << 32),
      _random.nextInt(1 << 32),
    );
    final watch = Stopwatch()..start();
    final reply = await _unary(
      pb.PeerMessage(ping: pb.Ping(nonce: nonce)),
      pb.PeerMessage_Body.pong,
    );
    if (reply.pong.nonce != nonce) {
      throw const PeerRequestException(
        pb.ErrorCode.ERROR_CODE_BAD_REQUEST,
        'Pong с чужим nonce',
      );
    }
    return watch.elapsed;
  }

  /// Какие из [fragmentIds] хранятся у собеседника и загружены этой же
  /// учётной записью.
  Future<List<bool>> hasFragments(List<Uint8List> fragmentIds) async {
    if (fragmentIds.length > PeerOperations.maxHasFragments) {
      throw ArgumentError(
        'не больше ${PeerOperations.maxHasFragments} фрагментов за запрос',
      );
    }
    final reply = await _unary(
      pb.PeerMessage(hasFragments: pb.HasFragments(fragmentIds: fragmentIds)),
      pb.PeerMessage_Body.hasFragmentsResult,
    );
    final present = reply.hasFragmentsResult.present;
    if (present.length != fragmentIds.length) {
      throw PeerRequestException(
        pb.ErrorCode.ERROR_CODE_BAD_REQUEST,
        'HasFragmentsResult: ${present.length} ответов на '
        '${fragmentIds.length}',
      );
    }
    return List.of(present);
  }

  /// Удаляет фрагмент по талону DELETE.
  Future<void> deleteFragment(pb.Signed ticket) => _unary(
    pb.PeerMessage(deleteFragment: pb.DeleteFragment(ticket: ticket)),
    pb.PeerMessage_Body.deleteFragmentResult,
  );

  /// Загружает [fragment] по талону PUT; возвращает `fragment_id` из
  /// ответа. Узел может ответить, не дождавшись всех частей (фрагмент уже
  /// у него, талон отклонён): тогда остаток не отправляется.
  /// Завершение [cancel] — отмена, [CancelledException].
  Future<Uint8List> putFragment(
    pb.Signed ticket,
    Uint8List fragment, {
    Future<void>? cancel,
  }) async {
    final id = _begin();
    final r = _Put();
    // Узел может ответить ошибкой посреди отправки частей.
    r.completer.future.ignore();
    _requests[id] = r;
    if (cancel != null) {
      unawaited(
        cancel.then((_) {
          if (r.done) return;
          _finish(id, r);
          r.completer.completeError(const CancelledException());
          _sendCancel(id);
        }),
      );
    }
    try {
      await _sendWithin(
        pb.PeerMessage(
          requestId: Int64(id),
          putFragment: pb.PutFragment(ticket: ticket),
        ),
      );
      var offset = 0;
      while (!r.done) {
        final end = min(offset + PeerOperations.maxChunk, fragment.length);
        await uploadLimiter?.acquire(end - offset);
        if (r.done) break;
        await _sendWithin(
          pb.PeerMessage(
            requestId: Int64(id),
            fragmentData: pb.FragmentData(
              data: Uint8List.sublistView(fragment, offset, end),
              last: end == fragment.length,
            ),
          ),
        );
        offset = end;
        if (end == fragment.length) break;
      }
      if (!r.done) r.timer = Timer(responseTimeout, () => _timeout(id, r));
    } on PeerRequestException catch (e) {
      _fail(id, r, e);
    }
    final reply = await r.completer.future;
    return Uint8List.fromList(reply.putFragmentResult.fragmentId);
  }

  /// Фрагмент по талону GET потоком частей. Поток завершается, когда
  /// пришли все `fragment_size` байт; ошибки собеседника и нарушения
  /// протокола — [PeerRequestException] в потоке. Отмена подписки —
  /// отмена запроса.
  Stream<Uint8List> getFragment(pb.Signed ticket) {
    late final _Get r;
    r = _Get(
      StreamController<Uint8List>(
        // Синхронная доставка: пауза потребителя сразу останавливает
        // очередь, и непрочитанное считается в [bufferedBytes].
        sync: true,
        onListen: () => _startGet(r, ticket),
        onResume: () => scheduleMicrotask(() => _deliver(r)),
        onCancel: () => _cancelGet(r),
      ),
    );
    return r.controller.stream;
  }

  /// [getFragment] целиком в память.
  Future<Uint8List> readFragment(pb.Signed ticket) async {
    final out = BytesBuilder(copy: false);
    await getFragment(ticket).forEach(out.add);
    return out.takeBytes();
  }

  /// Отменяет начатые запросы ([CancelledException]) и закрывает канал.
  Future<void> close() async {
    _closeAll(null);
    await channel.close();
    await _subscription.cancel();
  }

  // --- запросы -------------------------------------------------------------

  int _begin() {
    if (_closed case final e?) throw e;
    return _nextId++;
  }

  Future<pb.PeerMessage> _unary(
    pb.PeerMessage request,
    pb.PeerMessage_Body expected,
  ) async {
    final id = _begin();
    final r = _Unary(expected);
    // Ответ может прийти раньше, чем закончится отправка запроса.
    r.completer.future.ignore();
    _requests[id] = r;
    r.timer = Timer(responseTimeout, () => _timeout(id, r));
    try {
      await _sendWithin(request..requestId = Int64(id));
    } on PeerRequestException catch (e) {
      _fail(id, r, e);
    }
    return await r.completer.future;
  }

  void _startGet(_Get r, pb.Signed ticket) {
    final int id;
    try {
      id = _begin();
    } on PeerRequestException catch (e) {
      r
        ..done = true
        ..controller.addError(e);
      unawaited(r.controller.close());
      return;
    }
    r.id = id;
    _requests[id] = r;
    _restartIdle(r);
    unawaited(
      _sendWithin(
        pb.PeerMessage(
          requestId: Int64(id),
          getFragment: pb.GetFragment(ticket: ticket),
        ),
      ).catchError((Object e) {
        if (e is PeerRequestException) _fail(id, r, e);
      }),
    );
  }

  void _cancelGet(_Get r) {
    _drop(r);
    if (r.done) return;
    _finish(r.id, r);
    _sendCancel(r.id);
  }

  /// Отправка с таймаутом: соединение, которое не принимает данные
  /// дольше [idleTimeout], закрывается.
  Future<void> _sendWithin(pb.PeerMessage message) async {
    try {
      await channel.send(message).timeout(idleTimeout);
    } on TimeoutException {
      channel.destroy();
      throw const PeerRequestException(
        pb.ErrorCode.ERROR_CODE_UNAVAILABLE,
        'собеседник не принимает данные',
      );
      // SecureChannel.send: канал закрыт.
      // ignore: avoid_catching_errors
    } on StateError {
      throw _closed ??
          const PeerRequestException(
            pb.ErrorCode.ERROR_CODE_UNAVAILABLE,
            'соединение закрыто',
          );
    }
  }

  void _sendCancel(int id) {
    if (isClosed) return;
    unawaited(
      channel
          .send(pb.PeerMessage(requestId: Int64(id), cancel: pb.Cancel()))
          .catchError((Object _) {}),
    );
  }

  // --- ответы --------------------------------------------------------------

  void _onMessage(pb.PeerMessage m) {
    final id = m.requestId.toInt();
    if (id == 0) {
      // Ошибка соединения целиком (нет общей версии, предел соединений):
      // собеседник сейчас закроет его.
      if (m.hasError()) _closeAll(_errorOf(m.error));
      return;
    }
    // Ответы на отменённые и завершённые запросы пропускаются.
    final r = _requests[id];
    if (r == null) return;
    if (m.hasError()) {
      _fail(id, r, _errorOf(m.error));
      return;
    }
    switch (r) {
      case _Unary():
        if (m.whichBody() != r.expected) {
          _fail(id, r, _violation('ответ ${m.whichBody().name}'));
        } else {
          _finish(id, r);
          r.completer.complete(m);
        }
      case _Put():
        if (!m.hasPutFragmentResult()) {
          _fail(id, r, _violation('ответ ${m.whichBody().name}'));
        } else {
          _finish(id, r);
          r.completer.complete(m);
        }
      case _Get():
        _onGet(r, m);
    }
  }

  void _onGet(_Get r, pb.PeerMessage m) {
    _restartIdle(r);
    switch (m.whichBody()) {
      case pb.PeerMessage_Body.getFragmentResult:
        final size = m.getFragmentResult.fragmentSize;
        if (r.size != null ||
            size < FragmentTickets.minFragmentSize ||
            size > FragmentTickets.maxFragmentSize) {
          _failGet(r, _violation('GetFragmentResult: размер $size'));
          return;
        }
        r.size = size;
      case pb.PeerMessage_Body.fragmentData:
        final size = r.size;
        final data = m.fragmentData.data;
        if (size == null) {
          _failGet(r, _violation('FragmentData до GetFragmentResult'));
          return;
        }
        if (data.length > PeerOperations.maxChunk ||
            r.received + data.length > size ||
            (m.fragmentData.last && r.received + data.length != size)) {
          _failGet(r, _violation('части фрагмента не сходятся с размером'));
          return;
        }
        r.received += data.length;
        r.queue.add(data is Uint8List ? data : Uint8List.fromList(data));
        _buffered += data.length;
        _unpaidBytes += data.length;
        unawaited(_throttleRead());
        if (m.fragmentData.last) {
          _finish(r.id, r);
          r.complete = true;
        }
        _deliver(r);
      case final other:
        _failGet(r, _violation('ответ ${other.name}'));
    }
  }

  void _deliver(_Get r) {
    final c = r.controller;
    if (r.delivering) return;
    r.delivering = true;
    try {
      while (r.queue.isNotEmpty && c.hasListener && !c.isPaused) {
        final chunk = r.queue.removeFirst();
        _buffered -= chunk.length;
        c.add(chunk);
      }
    } finally {
      r.delivering = false;
    }
    if (r.complete && r.queue.isEmpty && !c.isClosed) unawaited(c.close());
    _applyReadPause();
  }

  /// Предел приёма: принятые байты оплачиваются у [downloadLimiter],
  /// чтение соединения стоит, пока он не разрешит.
  Future<void> _throttleRead() async {
    final limiter = downloadLimiter;
    if (limiter == null || _throttling || _unpaidBytes == 0) return;
    final bytes = _unpaidBytes;
    _unpaidBytes = 0;
    _throttling = true;
    _applyReadPause();
    await limiter.acquire(bytes);
    _throttling = false;
    _applyReadPause();
    unawaited(_throttleRead());
  }

  /// Чтение соединения стоит, пока ждёт предел приёма или пока в очередях
  /// выдачи больше [bufferBytes] (возобновляется ниже половины).
  void _applyReadPause() {
    final want =
        !isClosed &&
        (_throttling ||
            _buffered > bufferBytes ||
            (_readPaused && _buffered > bufferBytes ~/ 2));
    if (want == _readPaused) return;
    _readPaused = want;
    if (want) {
      _subscription.pause();
    } else {
      _subscription.resume();
    }
  }

  void _failGet(_Get r, PeerRequestException e) {
    final violation = e.code == pb.ErrorCode.ERROR_CODE_BAD_REQUEST;
    _fail(r.id, r, e);
    if (violation) _sendCancel(r.id);
  }

  void _restartIdle(_Get r) {
    r.timer?.cancel();
    r.timer = Timer(idleTimeout, () {
      if (r.done) return;
      // Ждём своего потребителя, а не собеседника: таймаут не считается.
      if (_readPaused || r.controller.isPaused) {
        _restartIdle(r);
        return;
      }
      _timeout(r.id, r);
    });
  }

  void _timeout(int id, _Request r) {
    if (r.done) return;
    _fail(
      id,
      r,
      const PeerRequestException(
        pb.ErrorCode.ERROR_CODE_UNAVAILABLE,
        'собеседник не ответил вовремя',
      ),
    );
    _sendCancel(id);
  }

  void _finish(int id, _Request r) {
    r
      ..done = true
      ..timer?.cancel();
    _requests.remove(id);
  }

  void _fail(int id, _Request r, Object error) {
    if (r.done) return;
    _finish(id, r);
    switch (r) {
      case _Unary(:final completer):
        completer.completeError(error);
      case _Put(:final completer):
        completer.completeError(error);
      case _Get(:final controller):
        _drop(r);
        if (!controller.isClosed) {
          controller.addError(error);
          unawaited(controller.close());
        }
    }
  }

  /// Выбрасывает очередь выдачи.
  void _drop(_Get r) {
    for (final chunk in r.queue) {
      _buffered -= chunk.length;
    }
    r.queue.clear();
    _applyReadPause();
  }

  /// Канал закрыт или сломан: все запросы завершаются ошибкой [error];
  /// `null` — закрыт нами ([CancelledException]).
  void _closeAll(PeerRequestException? error) {
    _closed ??=
        error ??
        const PeerRequestException(
          pb.ErrorCode.ERROR_CODE_UNAVAILABLE,
          'соединение закрыто',
        );
    for (final MapEntry(key: id, value: r) in _requests.entries.toList()) {
      _fail(id, r, error ?? const CancelledException());
    }
  }

  static PeerRequestException _errorOf(pb.Error e) => PeerRequestException(
    e.code,
    e.message,
    retryAfter: e.retryAfterMs == 0
        ? null
        : Duration(milliseconds: e.retryAfterMs),
  );

  static PeerRequestException _violation(String detail) =>
      PeerRequestException(pb.ErrorCode.ERROR_CODE_BAD_REQUEST, detail);
}

sealed class _Request {
  bool done = false;
  Timer? timer;
}

final class _Unary extends _Request {
  new(this.expected);

  final pb.PeerMessage_Body expected;
  final completer = Completer<pb.PeerMessage>();
}

final class _Put extends _Request {
  final completer = Completer<pb.PeerMessage>();
}

final class _Get extends _Request {
  new(this.controller);

  final StreamController<Uint8List> controller;
  final queue = Queue<Uint8List>();
  late int id;
  int? size;
  int received = 0;
  bool complete = false;
  bool delivering = false;
}
