import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:coordinator/src/rpc/errors.dart';
import 'package:coordinator/src/signer/signer_wire.dart';
import 'package:coordinator/src/signer/ticket_signing_service.dart';
import 'package:protocol/protocol.dart' as pb;

/// Подпись талонов для веб-сервера координатора: ключа у него нет, он
/// просит подписанта (задача 2.2.1).
abstract interface class TicketSigner {
  /// Подписанные талоны в порядке [tickets]. Подписант недоступен —
  /// [RpcException] `UNAVAILABLE`; отклонил талон — `INTERNAL` (талон
  /// собрал сам координатор, значит, ошибка в его коде).
  Future<List<pb.Signed>> sign(List<pb.FragmentTicket> tickets);

  /// Открытый ключ, которым подписант подписывает сейчас. Ошибки — как у
  /// [sign].
  Future<Uint8List> publicKey();

  Future<void> close();
}

/// Ответ подписанта на [count] талонов (общая часть [SocketTicketSigner] и
/// [InProcessTicketSigner]): подписи, отказ — [RpcException], ответ не по
/// формату — `null`.
SignerSigned? _signedOrThrow(Uint8List response, int count) {
  final reply = SignerReply.decode(response, count);
  switch (reply) {
    case SignerSigned():
      return reply;
    case SignerRefused(code: pb.ErrorCode.ERROR_CODE_RATE_LIMITED):
      throw RpcException(
        pb.ErrorCode.ERROR_CODE_UNAVAILABLE,
        'подписант: предел частоты',
        retryAfter: reply.retryAfter ?? const Duration(seconds: 1),
      );
    case SignerRefused(:final code, :final index):
      throw RpcException(
        pb.ErrorCode.ERROR_CODE_INTERNAL,
        'подписант отклонил талон'
        '${index == null ? '' : ' $index'}: ${errorCodeName(code)}',
      );
    case null:
      return null;
  }
}

List<pb.Signed> _toSigned(List<Uint8List> bodies, SignerSigned signed) => [
  for (var i = 0; i < bodies.length; i++)
    pb.Signed(
      body: bodies[i],
      signer: signed.signer,
      signature: signed.signatures[i],
    ),
];

/// [TicketSigner] в том же процессе — для тестов и стенда без отдельного
/// пользователя ОС. Талоны проходят те же проверки [TicketSigningService],
/// что и через сокет, но ключ лежит в памяти веб-сервера: в бою — только
/// [SocketTicketSigner] (модель угроз, К-8).
final class InProcessTicketSigner implements TicketSigner {
  new(this.service);

  final TicketSigningService service;

  @override
  Future<List<pb.Signed>> sign(List<pb.FragmentTicket> tickets) async {
    final bodies = [for (final t in tickets) t.writeToBuffer()];
    final out = <pb.Signed>[];
    for (var i = 0; i < bodies.length; i += SignerWire.maxBatch) {
      final batch = bodies.sublist(
        i,
        (i + SignerWire.maxBatch).clamp(0, bodies.length),
      );
      final reply = _signedOrThrow(
        await service.handle(SignerWire.encodeRequest(batch)),
        batch.length,
      );
      out.addAll(_toSigned(batch, reply!));
    }
    return out;
  }

  @override
  Future<Uint8List> publicKey() async => service.publicKey;

  @override
  Future<void> close() async {}
}

/// [TicketSigner] через Unix-сокет подписанта [path]. Одно соединение,
/// запросы по очереди; после сбоя соединение открывается заново при
/// следующем запросе.
final class SocketTicketSigner implements TicketSigner {
  new(this.path, {this.timeout = const Duration(seconds: 5)});

  final String path;

  /// Предел ожидания соединения и ответа на запрос.
  final Duration timeout;

  _Connection? _connection;
  Future<void> _queue = Future.value();
  bool _closed = false;
  Uint8List? _publicKey;

  @override
  Future<List<pb.Signed>> sign(List<pb.FragmentTicket> tickets) async {
    final bodies = [for (final t in tickets) t.writeToBuffer()];
    final out = <pb.Signed>[];
    for (var i = 0; i < bodies.length; i += SignerWire.maxBatch) {
      final batch = bodies.sublist(
        i,
        (i + SignerWire.maxBatch).clamp(0, bodies.length),
      );
      out.addAll(_toSigned(batch, await _serialized(() => _signBatch(batch))));
    }
    return out;
  }

  /// Ключ запрашивается у подписанта и запоминается; меняется он только
  /// с перезапуском подписанта — тогда его обновит следующая пачка талонов.
  @override
  Future<Uint8List> publicKey() async =>
      _publicKey ?? (await _serialized(() => _signBatch(const []))).signer;

  @override
  Future<void> close() async {
    _closed = true;
    await _queue;
    _connection?.destroy();
    _connection = null;
  }

  Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<SignerSigned> _signBatch(List<Uint8List> bodies) async {
    if (_closed) throw StateError('SocketTicketSigner закрыт');
    final request = SignerWire.frame(SignerWire.encodeRequest(bodies));
    final Uint8List response;
    try {
      final connection = _connection ??= await _Connection.open(path, timeout);
      response = await connection.request(request).timeout(timeout);
    } on Exception {
      _connection?.destroy();
      _connection = null;
      throw const RpcException(
        pb.ErrorCode.ERROR_CODE_UNAVAILABLE,
        'подписант недоступен',
        retryAfter: Duration(seconds: 1),
      );
    }
    final signed = _signedOrThrow(response, bodies.length);
    if (signed == null) {
      _connection?.destroy();
      _connection = null;
      throw const RpcException(
        pb.ErrorCode.ERROR_CODE_UNAVAILABLE,
        'подписант: ответ не по формату',
        retryAfter: Duration(seconds: 1),
      );
    }
    _publicKey = signed.signer;
    return signed;
  }
}

/// Соединение с подписантом: запрос — ответ, по одному за раз.
final class _Connection {
  new _(this._socket) {
    _socket.listen(
      (chunk) {
        _reader.add(chunk);
        _deliver();
      },
      onError: _fail,
      onDone: () => _fail(const SocketException('подписант закрыл соединение')),
      cancelOnError: true,
    );
    // Ошибка записи (подписант закрыл сокет) приходит в done, а не в
    // listen: без обработчика она стала бы необработанной ошибкой зоны.
    unawaited(_socket.done.then((_) {}, onError: _fail));
  }

  static Future<_Connection> open(String path, Duration timeout) async =>
      _Connection._(
        await Socket.connect(
          InternetAddress(path, type: InternetAddressType.unix),
          0,
          timeout: timeout,
        ),
      );

  final Socket _socket;
  final _reader = FrameReader();
  Completer<Uint8List>? _pending;
  Object? _error;

  Future<Uint8List> request(Uint8List frame) {
    if (_error case final e?) return Future.error(e);
    final pending = _pending = Completer<Uint8List>();
    _socket.add(frame);
    return pending.future;
  }

  void destroy() => _socket.destroy();

  void _deliver() {
    final Uint8List? frame;
    try {
      // Ответ с подписями длиннее запроса: свой предел.
      frame = _reader.next(maxLength: _maxResponseLength);
    } on FormatException catch (e) {
      _fail(e);
      return;
    }
    if (frame == null) return;
    final pending = _pending;
    _pending = null;
    if (pending == null) {
      _fail(const FormatException('ответ без запроса'));
    } else {
      pending.complete(frame);
    }
  }

  void _fail(Object error) {
    _error ??= error;
    final pending = _pending;
    _pending = null;
    pending?.completeError(error);
    _socket.destroy();
  }

  static const int _maxResponseLength =
      1 +
      SignerWire.keyLength +
      SignerWire.maxBatch * SignerWire.signatureLength;
}
