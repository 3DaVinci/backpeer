import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:core/src/net/byte_connection.dart';
import 'package:core/src/net/udp/congestion.dart';
import 'package:core/src/net/udp/udp_packets.dart';
import 'package:meta/meta.dart';

/// Настройки потока поверх UDP.
final class UdpStreamOptions {
  const new({
    this.receiveWindow = 1 << 20,
    this.sendBuffer = 1 << 20,
    this.congestion = _ledbat,
    this.keepalive = const Duration(seconds: 15),
    this.idleTimeout = const Duration(seconds: 60),
    this.connectTimeout = const Duration(seconds: 10),
    this.deadTimeout = const Duration(seconds: 30),
    this.minRto = const Duration(milliseconds: 200),
    this.ackDelay = const Duration(milliseconds: 5),
  });

  /// Сколько байт получатель держит непрочитанными (принятые по порядку и
  /// вне порядка); столько он объявляет собеседнику окном.
  final int receiveWindow;

  /// `flush` ждёт, пока неотправленного и неподтверждённого станет не
  /// больше этого.
  final int sendBuffer;

  /// Управление перегрузкой; по умолчанию — «вежливое» [Ledbat].
  final CongestionControl Function() congestion;

  /// Пакет, если ничего не отправлялось столько времени: держит
  /// отображение в NAT (обычный срок UDP в домашних роутерах — от 30 с).
  final Duration keepalive;

  /// Нет пакетов от собеседника столько времени — поток оборван.
  final Duration idleTimeout;

  /// Сколько ждать ответа на SYN.
  final Duration connectTimeout;

  /// Данные не подтверждаются столько времени — поток оборван.
  final Duration deadTimeout;

  /// Наименьший таймаут повторной отправки.
  final Duration minRto;

  /// Задержка подтверждения, если не набралось двух пакетов.
  final Duration ackDelay;

  static CongestionControl _ledbat() => Ledbat();
}

/// Поток оборван: собеседник молчит или не подтверждает данные.
final class UdpStreamException extends SocketException {
  const new(super.message);
}

/// Надёжный упорядоченный поток байт поверх UDP (задача 3.7.3;
/// protocol.md, раздел 3.5) — [ByteConnection] для канала Noise после
/// сведения узлов.
///
/// - Пакеты нумеруются; получатель подтверждает наибольший номер,
///   принятый по порядку, и битовой картой SACK — до 256 пакетов за ним.
/// - Потеря: пакет не подтверждён, а подтверждены три пакета, отправленные
///   после него; или истёк таймаут повторной отправки (RFC 6298, не меньше
///   [UdpStreamOptions.minRto]).
/// - Окно: в пути не больше окна перегрузки ([CongestionControl], по
///   умолчанию [Ledbat]) и свободного места у получателя. Пауза подписки
///   на [input] не даёт освобождать место: отправитель упирается в окно,
///   его `flush` — в [UdpStreamOptions.sendBuffer].
/// - Пакет каждые [UdpStreamOptions.keepalive] без отправок держит
///   отображение в NAT; молчание дольше [UdpStreamOptions.idleTimeout] —
///   поток оборван.
/// - [close] отправляет остаток и FIN, чтение продолжается до FIN
///   собеседника; [destroy] отправляет RST, и у собеседника чтение
///   кончается, как при закрытии сокета TCP.
///
/// Создаёт и разбирает входящие пакеты `UdpEndpoint`.
final class UdpStream implements ByteConnection {
  /// Для `UdpEndpoint`: [initiator] отправляет SYN с номером сведения
  /// `punchId`.
  @internal
  new attach({
    required this.remoteAddress,
    required this.remotePort,
    required this.connectionId,
    required this.initiator,
    required this._send,
    required this._writable,
    required this._onClosed,
    this.options = const UdpStreamOptions(),
    Uint8List? punchId,
  }) : _cc = options.congestion(),
       _peerWindow = options.receiveWindow {
    _rto = initiator ? 500000 : 1000000;
    _input = StreamController<Uint8List>(
      sync: true,
      onListen: () => scheduleMicrotask(_deliver),
      onResume: () => scheduleMicrotask(_deliver),
      onCancel: () {
        // Читать больше некому: принятое отбрасывается, окно открыто.
        _discardInput = true;
        _readQueue.clear();
        _unread = 0;
      },
    );
    final now = _now();
    _lastReceived = now;
    _lastProgress = now;
    if (initiator) {
      final syn = _Out(0, UdpPackets.syn, punchId ?? Uint8List(0));
      _unacked.add(syn);
      _sndNxt = 1;
      _transmit(syn, now);
      _armTimer();
    } else {
      _sndUna = 1;
      _sndNxt = 1;
      _established = true;
      _ready.complete();
      _ackNow = true;
      _flushAck();
    }
  }

  final InternetAddress remoteAddress;
  final int remotePort;
  final int connectionId;
  final bool initiator;
  final UdpStreamOptions options;

  final bool Function(Uint8List) _send;
  final Future<void> Function() _writable;
  final void Function(UdpStream) _onClosed;
  final CongestionControl _cc;

  /// Управление перегрузкой этого потока.
  CongestionControl get congestion => _cc;

  // --- Отправка ---

  final _sendQueue = Queue<Uint8List>();
  int _headOffset = 0;
  int _queuedBytes = 0;

  /// Отправленные и не подтверждённые по порядку, с номера [_sndUna].
  final _unacked = ListQueue<_Out>();
  final _lostQueue = Queue<_Out>();
  int _sndUna = 0;
  int _sndNxt = 0;
  int _unackedBytes = 0;
  int _inFlight = 0;
  int _peerWindow;
  int _order = 0;
  int _highestAckedOrder = -1;
  int _recoveryOrder = 0;
  bool _blocked = false;
  bool _pumpScheduled = false;
  bool _closing = false;
  bool _finSent = false;
  bool _finAcked = false;
  final _flushWaiters = <Completer<void>>[];
  final _closed = Completer<void>();

  // RTO (RFC 6298), микросекунды.
  int? _srtt;
  int _rttvar = 0;
  late int _rto;
  int? _rtoDeadline;
  int? _persistDeadline;
  int _persistBackoff = 0;
  int _lastProgress = 0;
  int _lastSent = 0;

  // --- Приём ---

  late final StreamController<Uint8List> _input;
  final _readQueue = Queue<Uint8List>();
  int _unread = 0;
  final _ooo = <int, StreamPacket>{};
  int _oooBytes = 0;
  int _rcvNxt = 1;
  bool _peerFin = false;
  bool _discardInput = false;
  int _ackPending = 0;
  bool _ackNow = false;
  int? _ackDeadline;
  int _advertised = 0;
  int _lastReceived = 0;
  int _lastDelay = 0;

  bool _established = false;
  final _ready = Completer<void>();
  bool _terminated = false;
  int? _lingerDeadline;
  Timer? _timer;
  int? _timerAt;

  // --- Статистика ---

  int packetsSent = 0;
  int packetsReceived = 0;
  int retransmissions = 0;
  int bytesSent = 0;
  int bytesReceived = 0;

  /// Завершается, когда собеседник ответил на SYN; ошибка — не ответил
  /// за [UdpStreamOptions.connectTimeout].
  Future<void> get ready => _ready.future;

  /// Поток закрыт и убран из `UdpEndpoint`.
  bool get isClosed => _terminated;

  /// Сглаженное время в пути; `null` — ещё не измерено.
  Duration? get smoothedRtt =>
      _srtt == null ? null : Duration(microseconds: _srtt!);

  Map<String, Object?> toJson() => {
    'remote': '${remoteAddress.address}:$remotePort',
    'rttMs': _srtt == null ? null : _srtt! / 1000,
    'packetsSent': packetsSent,
    'packetsReceived': packetsReceived,
    'retransmissions': retransmissions,
    'bytesSent': bytesSent,
    'bytesReceived': bytesReceived,
    'congestion': _cc.toJson(),
  };

  static final _clock = Stopwatch()..start();
  static int _now() => _clock.elapsedMicroseconds;

  // --- ByteConnection ---

  @override
  Stream<Uint8List> get input => _input.stream;

  @override
  void add(Uint8List data) {
    if (_closing || _terminated || data.isEmpty) return;
    _sendQueue.add(data);
    _queuedBytes += data.length;
    _schedulePump();
  }

  @override
  Future<void> flush() {
    if (_terminated || _queuedBytes + _unackedBytes <= options.sendBuffer) {
      return Future.value();
    }
    final w = Completer<void>();
    _flushWaiters.add(w);
    return w.future;
  }

  @override
  Future<void> close() {
    if (!_closing && !_terminated) {
      _closing = true;
      _schedulePump();
    }
    return _closed.future;
  }

  @override
  void destroy() {
    if (_terminated) return;
    _sendControl(UdpPackets.reset);
    _terminate();
  }

  // --- Входящие пакеты (передаёт UdpEndpoint) ---

  @internal
  void receive(StreamPacket p) {
    if (_terminated) return;
    final now = _now();
    _lastReceived = now;
    packetsReceived++;
    _lastDelay = (now - p.timestamp) & 0xffffffff;
    if (p.type == UdpPackets.reset) {
      // Как закрытие сокета собеседником в TCP: чтение просто кончается.
      _terminate();
      return;
    }
    _onAck(p, now);
    if (_terminated) return;
    switch (p.type) {
      case UdpPackets.data || UdpPackets.fin:
        _onData(p, now);
      case UdpPackets.syn:
        // Повтор SYN: наш ответ потерялся.
        _ackNow = true;
    }
    _flushAck();
    _pump();
  }

  void _onAck(StreamPacket p, int now) {
    final ack = expandSequence(p.ack, _sndUna - 1);
    if (ack < _sndUna - 1 || ack >= _sndNxt) return;
    _peerWindow = p.window;
    final flightBefore = _inFlight;
    var acked = 0;
    var newestSent = -1;
    var advanced = false;
    while (_sndUna <= ack) {
      final o = _unacked.removeFirst();
      _sndUna++;
      advanced = true;
      _unackedBytes -= o.payload.length;
      o.acked = true;
      if (o.inFlight) {
        _inFlight -= o.payload.length;
        o.inFlight = false;
      }
      if (!o.sacked) {
        acked += o.payload.length;
        if (o.transmissions == 1) newestSent = math.max(newestSent, o.sentAt);
        if (o.order > _highestAckedOrder) _highestAckedOrder = o.order;
      }
      if (o.type == UdpPackets.syn) {
        _established = true;
        if (!_ready.isCompleted) _ready.complete();
      } else if (o.type == UdpPackets.fin) {
        _finAcked = true;
      }
    }
    var highestSacked = -1;
    final sack = p.sack;
    for (var j = 0; j < sack.length; j++) {
      final byte = sack[j];
      if (byte == 0) continue;
      for (var i = 0; i < 8; i++) {
        if (byte & (1 << i) == 0) continue;
        final index = ack + 2 + 8 * j + i - _sndUna;
        if (index < 0 || index >= _unacked.length) continue;
        final o = _unacked.elementAt(index);
        highestSacked = index;
        if (o.sacked) continue;
        o
          ..sacked = true
          ..lost = false;
        if (o.inFlight) {
          _inFlight -= o.payload.length;
          o.inFlight = false;
        }
        acked += o.payload.length;
        if (o.transmissions == 1) newestSent = math.max(newestSent, o.sentAt);
        if (o.order > _highestAckedOrder) _highestAckedOrder = o.order;
      }
    }
    // Пакет потерян, если подтверждены три отправленных после него.
    var lossOrder = -1;
    for (var index = 0; index < highestSacked; index++) {
      final o = _unacked.elementAt(index);
      if (!o.inFlight || o.order + 3 > _highestAckedOrder) continue;
      o
        ..inFlight = false
        ..lost = true;
      _inFlight -= o.payload.length;
      _lostQueue.add(o);
      lossOrder = math.max(lossOrder, o.order);
    }
    if (lossOrder >= _recoveryOrder) {
      _cc.onLoss();
      _recoveryOrder = _order;
    }
    if (newestSent >= 0) _updateRtt(now - newestSent);
    if (acked > 0 || advanced) {
      _cc.onAck(
        ackedBytes: acked,
        flightBytes: flightBefore,
        delaySample: p.timestampDiff == 0 ? null : p.timestampDiff,
        rtt: newestSent >= 0 ? Duration(microseconds: now - newestSent) : null,
      );
    }
    if (advanced) {
      _lastProgress = now;
      _rtoDeadline = _hasOutstanding ? now + _rto : null;
      _wakeWriters();
      _maybeFinish();
    }
    if (_peerWindow >= StreamPacket.maxPayload) _persistDeadline = null;
  }

  bool get _hasOutstanding => _inFlight > 0 || _unacked.any((o) => o.inFlight);

  void _updateRtt(int sample) {
    final srtt = _srtt;
    if (srtt == null) {
      _srtt = sample;
      _rttvar = sample ~/ 2;
    } else {
      _rttvar = (3 * _rttvar + (srtt - sample).abs()) ~/ 4;
      _srtt = (7 * srtt + sample) ~/ 8;
    }
    _rto = math.max(
      options.minRto.inMicroseconds,
      _srtt! + math.max(1000, 4 * _rttvar),
    );
    _rto = math.min(_rto, 60 * 1000 * 1000);
  }

  void _onData(StreamPacket p, int now) {
    final seq = expandSequence(p.seq, _rcvNxt);
    if (seq < _rcvNxt || _peerFin || _ooo.containsKey(seq)) {
      _ackNow = true;
      return;
    }
    final cost = _discardInput ? 0 : p.payload.length;
    if (seq - _rcvNxt > 65536 ||
        _unread + _oooBytes + cost > options.receiveWindow ||
        (seq != _rcvNxt && _ooo.length >= _maxOutOfOrder)) {
      // Нет места: собеседник повторит, когда окно откроется.
      _ackNow = true;
      return;
    }
    bytesReceived += p.payload.length;
    if (seq != _rcvNxt) {
      _ooo[seq] = p;
      _oooBytes += cost;
      _ackNow = true;
      return;
    }
    _accept(p);
    _rcvNxt++;
    if (_ooo.isNotEmpty) {
      _ackNow = true;
      while (true) {
        final next = _ooo.remove(_rcvNxt);
        if (next == null) break;
        _oooBytes -= _discardInput ? 0 : next.payload.length;
        _accept(next);
        _rcvNxt++;
      }
      if (_ooo.isEmpty) _oooBytes = 0;
    }
    if (++_ackPending >= 2) {
      _ackNow = true;
    } else {
      _ackDeadline ??= now + options.ackDelay.inMicroseconds;
    }
    _deliver();
  }

  void _accept(StreamPacket p) {
    if (p.type == UdpPackets.fin) {
      _peerFin = true;
      return;
    }
    if (_discardInput || p.payload.isEmpty) return;
    _readQueue.add(p.payload);
    _unread += p.payload.length;
  }

  void _deliver() {
    while (_readQueue.isNotEmpty && _input.hasListener && !_input.isPaused) {
      Uint8List chunk;
      if (_readQueue.length == 1) {
        chunk = _readQueue.removeFirst();
      } else {
        // Части подряд — одним событием, до 64 КиБ.
        final builder = BytesBuilder(copy: false);
        while (_readQueue.isNotEmpty &&
            builder.length + _readQueue.first.length <= 65536) {
          builder.add(_readQueue.removeFirst());
        }
        if (builder.isEmpty) builder.add(_readQueue.removeFirst());
        chunk = builder.takeBytes();
      }
      _unread -= chunk.length;
      _input.add(chunk);
    }
    if (_terminated) return;
    if (_peerFin && _readQueue.isEmpty && !_input.isClosed) {
      unawaited(_input.close());
      _maybeFinish();
    }
    // Окно открылось после паузы читателя: сказать отправителю сразу.
    if (_advertised < options.receiveWindow ~/ 4 &&
        _freeWindow >= options.receiveWindow ~/ 2) {
      _ackNow = true;
      _flushAck();
    }
  }

  /// Пакетов вне порядка: мелкие пакеты не должны занять память сверх
  /// окна заголовками.
  int get _maxOutOfOrder => options.receiveWindow ~/ 256 + 64;

  int get _freeWindow =>
      math.max(0, options.receiveWindow - _unread - _oooBytes);

  // --- Отправка пакетов ---

  void _schedulePump() {
    if (_pumpScheduled) return;
    _pumpScheduled = true;
    scheduleMicrotask(() {
      _pumpScheduled = false;
      _pump();
    });
  }

  void _pump() {
    if (_terminated || _blocked) return;
    final now = _now();
    final cwnd = _cc.window;
    while (_lostQueue.isNotEmpty) {
      final o = _lostQueue.first;
      if (o.acked || o.sacked || !o.lost) {
        _lostQueue.removeFirst();
        continue;
      }
      if (_inFlight > 0 && _inFlight + o.payload.length > cwnd) break;
      _lostQueue.removeFirst();
      retransmissions++;
      if (!_transmit(o, now)) return;
    }
    while (_established && _queuedBytes > 0) {
      final size = math.min(StreamPacket.maxPayload, _queuedBytes);
      final window = math.min(cwnd, _peerWindow);
      if (_inFlight + size > window) {
        if (_peerWindow < size && _inFlight == 0 && _persistDeadline == null) {
          _persistBackoff = _rto;
          _persistDeadline = now + _persistBackoff;
        }
        break;
      }
      final o = _Out(_sndNxt++, UdpPackets.data, _take(size));
      _unacked.add(o);
      _unackedBytes += size;
      if (!_transmit(o, now)) return;
    }
    if (_closing && _established && !_finSent && _queuedBytes == 0) {
      _finSent = true;
      final o = _Out(_sndNxt++, UdpPackets.fin, Uint8List(0));
      _unacked.add(o);
      if (!_transmit(o, now)) return;
    }
    _armTimer();
  }

  Uint8List _take(int size) {
    final out = Uint8List(size);
    var filled = 0;
    while (filled < size) {
      final head = _sendQueue.first;
      final n = math.min(size - filled, head.length - _headOffset);
      out.setRange(filled, filled + n, head, _headOffset);
      filled += n;
      _headOffset += n;
      if (_headOffset == head.length) {
        _sendQueue.removeFirst();
        _headOffset = 0;
      }
    }
    _queuedBytes -= size;
    return out;
  }

  /// Отправляет [o]; `false` — буфер ОС полон, отправка продолжится,
  /// когда он освободится.
  bool _transmit(_Out o, int now) {
    final datagram = _packet(o.type, o.seq, o.payload, now).encode();
    if (!_send(datagram)) {
      // Не ушёл: отправить снова без признака перегрузки.
      o.lost = true;
      _lostQueue.addFirst(o);
      _block();
      return false;
    }
    o
      ..sentAt = now
      ..order = _order++
      ..transmissions += 1
      ..lost = false
      ..inFlight = true;
    _inFlight += o.payload.length;
    _rtoDeadline ??= now + _rto;
    _noteSent(now, datagram.length);
    return true;
  }

  void _block() {
    _blocked = true;
    unawaited(
      _writable().then((_) {
        _blocked = false;
        _pump();
      }),
    );
  }

  void _noteSent(int now, int length) {
    packetsSent++;
    bytesSent += length;
    _lastSent = now;
    _ackPending = 0;
    _ackNow = false;
    _ackDeadline = null;
    _advertised = _freeWindow;
  }

  StreamPacket _packet(int type, int seq, Uint8List payload, int now) =>
      StreamPacket(
        type: type,
        connectionId: connectionId,
        seq: seq,
        ack: _rcvNxt - 1,
        timestamp: now,
        timestampDiff: _lastDelay,
        window: _freeWindow,
        sack: _sack(),
        payload: payload,
      );

  Uint8List? _sack() {
    if (_ooo.isEmpty) return null;
    var last = -1;
    final bits = Uint8List(StreamPacket.maxSackBytes);
    for (final seq in _ooo.keys) {
      final i = seq - _rcvNxt - 1;
      if (i < 0 || i >= StreamPacket.maxSackBytes * 8) continue;
      bits[i >> 3] |= 1 << (i & 7);
      if (i > last) last = i;
    }
    if (last < 0) return null;
    return Uint8List.sublistView(bits, 0, (last >> 3) + 1);
  }

  void _flushAck() {
    if (_ackNow && !_terminated) _sendControl(UdpPackets.state);
  }

  void _sendControl(int type) {
    final now = _now();
    final datagram = _packet(type, _sndNxt, Uint8List(0), now).encode();
    if (_send(datagram)) _noteSent(now, datagram.length);
  }

  // --- Таймеры ---

  void _armTimer() {
    if (_terminated) return;
    final now = _now();
    var at = _lastReceived + options.idleTimeout.inMicroseconds;
    at = math.min(at, _lastSent + options.keepalive.inMicroseconds);
    if (_rtoDeadline case final d?) at = math.min(at, d);
    if (_ackDeadline case final d?) at = math.min(at, d);
    if (_persistDeadline case final d?) at = math.min(at, d);
    if (_lingerDeadline case final d?) at = math.min(at, d);
    if (_timer != null && _timerAt! <= at) return;
    _timer?.cancel();
    _timerAt = at;
    _timer = Timer(Duration(microseconds: math.max(0, at - now)), _onTimer);
  }

  void _onTimer() {
    _timer = null;
    _timerAt = null;
    if (_terminated) return;
    final now = _now();
    if (_lingerDeadline case final d? when now >= d) {
      _terminate();
      return;
    }
    if (now - _lastReceived >= options.idleTimeout.inMicroseconds) {
      _terminate(const UdpStreamException('собеседник не отвечает'));
      return;
    }
    if (_rtoDeadline case final d? when now >= d) {
      if (!_onRto(now)) return;
    }
    if (_persistDeadline case final d? when now >= d) _probeWindow(now);
    if (_ackDeadline case final d? when now >= d) {
      _ackDeadline = null;
      _ackNow = true;
      _flushAck();
    }
    if (now - _lastSent >= options.keepalive.inMicroseconds) {
      // Не ушёл — следующая попытка через тот же срок.
      _lastSent = now;
      _ackNow = true;
      _flushAck();
    }
    _pump();
    _armTimer();
  }

  /// Таймаут повторной отправки; `false` — поток оборван.
  bool _onRto(int now) {
    _rtoDeadline = null;
    final outstanding = [
      for (final o in _unacked)
        if (o.inFlight) o,
    ];
    if (outstanding.isEmpty) return true;
    final limit = _established ? options.deadTimeout : options.connectTimeout;
    if (now - _lastProgress >= limit.inMicroseconds) {
      _terminate(
        UdpStreamException(
          _established
              ? 'собеседник не подтверждает данные'
              : 'собеседник не ответил на SYN',
        ),
      );
      return false;
    }
    for (final o in outstanding) {
      o
        ..inFlight = false
        ..lost = true;
      _lostQueue.add(o);
    }
    _inFlight = 0;
    _cc.onTimeout();
    _recoveryOrder = _order;
    _rto = math.min(_rto * 2, 60 * 1000 * 1000);
    return true;
  }

  /// Окно получателя закрыто, а сообщение о его открытии могло
  /// потеряться: пустой пакет данных с уже подтверждённым номером, на
  /// который получатель сразу отвечает подтверждением с окном. Повтор —
  /// с удвоением паузы до 5 секунд.
  void _probeWindow(int now) {
    if (_queuedBytes == 0 || _inFlight > 0 || !_established) {
      _persistDeadline = null;
      return;
    }
    final datagram = _packet(
      UdpPackets.data,
      _sndUna - 1,
      Uint8List(0),
      now,
    ).encode();
    if (_send(datagram)) _noteSent(now, datagram.length);
    _persistBackoff = math.min(_persistBackoff * 2, 5 * 1000 * 1000);
    _persistDeadline = now + _persistBackoff;
  }

  // --- Завершение ---

  void _wakeWriters() {
    if (_queuedBytes + _unackedBytes > options.sendBuffer) return;
    for (final w in _flushWaiters) {
      w.complete();
    }
    _flushWaiters.clear();
  }

  /// Обе стороны отправили FIN и получили подтверждение: подождать,
  /// пока не перестанут приходить повторы FIN собеседника, и убрать поток.
  void _maybeFinish() {
    if (_finAcked && !_closed.isCompleted) _closed.complete();
    if (_finAcked && _peerFin && _lingerDeadline == null) {
      _lingerDeadline = _now() + math.max(2 * _rto, 1000000);
      _armTimer();
    }
  }

  void _terminate([UdpStreamException? error]) {
    if (_terminated) return;
    _terminated = true;
    _timer?.cancel();
    _timer = null;
    // До закрытия чтения: его подписчики могут продолжиться синхронно.
    _onClosed(this);
    if (!_ready.isCompleted) {
      _ready.completeError(
        error ?? const UdpStreamException('поток закрыт до соединения'),
      );
      // Ошибку ждут через ready; без подписчика она не должна стать
      // необработанной.
      unawaited(_ready.future.catchError((Object _) {}));
    }
    if (!_input.isClosed) {
      if (error != null && _input.hasListener) _input.addError(error);
      unawaited(_input.close());
    }
    _readQueue.clear();
    _sendQueue.clear();
    _queuedBytes = 0;
    _unackedBytes = 0;
    for (final w in _flushWaiters) {
      w.complete();
    }
    _flushWaiters.clear();
    if (!_closed.isCompleted) _closed.complete();
  }
}

/// Отправленный пакет до подтверждения.
final class _Out {
  new(this.seq, this.type, this.payload);

  final int seq;
  final int type;
  final Uint8List payload;
  int sentAt = 0;
  int order = 0;
  int transmissions = 0;
  bool inFlight = false;
  bool lost = false;
  bool sacked = false;
  bool acked = false;
}
