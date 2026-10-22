import 'dart:typed_data';

import 'package:coordinator/src/limits/rate_limiter.dart';
import 'package:coordinator/src/log.dart';
import 'package:coordinator/src/rpc/errors.dart';
import 'package:coordinator/src/signer/signer_wire.dart';
import 'package:core/core.dart';
import 'package:logging/logging.dart';
import 'package:protocol/protocol.dart' as pb;

/// Логика подписанта: проверяет талоны из запроса веб-сервера и
/// подписывает их ключом координатора (protocol.md, раздел 5; задача
/// 2.2.1). Веб-сервер считается возможно взломанным: всё, что он прислал,
/// проверяется как недоверенный ввод.
final class TicketSigningService {
  new({
    required this.crypto,
    required this.key,
    required this.limiter,
    this.maxLifetime = FragmentTickets.maxLifetime,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    if (maxLifetime <= Duration.zero ||
        maxLifetime > FragmentTickets.maxLifetime) {
      throw ArgumentError.value(
        maxLifetime,
        'maxLifetime',
        'нужно больше нуля и не больше ${FragmentTickets.maxLifetime}',
      );
    }
    if (limiter.burst < SignerWire.maxBatch) {
      throw ArgumentError('запас ведра меньше ${SignerWire.maxBatch} талонов');
    }
  }

  final CryptoProvider crypto;
  final Ed25519KeyPair key;

  /// Предел частоты выдачи талонов: взломанный веб-сервер не получит их
  /// быстрее.
  final RateLimiter limiter;
  final DateTime Function() _clock;

  /// Предел срока жизни талона; подписант может быть строже спецификации.
  final Duration maxLifetime;

  static final _log = Logger('signer');

  Uint8List get publicKey => key.publicKey;

  /// Тело ответа на тело запроса (`SignerWire`).
  Future<Uint8List> handle(Uint8List request) async {
    final bodies = SignerWire.decodeRequest(request);
    if (bodies == null) {
      return _refuse(
        pb.ErrorCode.ERROR_CODE_BAD_REQUEST,
        'запрос не по формату',
      );
    }
    final now = _clock();
    final counts = <pb.TicketOperation, int>{};
    for (var i = 0; i < bodies.length; i++) {
      final pb.FragmentTicket ticket;
      try {
        ticket = FragmentTickets.parse(bodies[i]);
      } on DataFormatException catch (e) {
        return _refuse(
          pb.ErrorCode.ERROR_CODE_BAD_REQUEST,
          e.message,
          index: i,
        );
      }
      final time = FragmentTickets.checkTime(
        ticket,
        now,
        skew: Duration.zero,
        lifetime: maxLifetime,
      );
      if (time != null) {
        return _refuse(
          pb.ErrorCode.ERROR_CODE_BAD_REQUEST,
          time == TicketTimeProblem.expired
              ? 'срок талона истёк'
              : 'срок талона больше ${maxLifetime.inMinutes} мин',
          index: i,
        );
      }
      counts.update(ticket.operation, (c) => c + 1, ifAbsent: () => 1);
    }
    // Предел — на все талоны сразу: веб-сервер у подписанта один.
    final wait = limiter.take('tickets', cost: bodies.length);
    if (wait != null) {
      return _refuse(
        pb.ErrorCode.ERROR_CODE_RATE_LIMITED,
        'предел частоты',
        retryAfter: wait,
      );
    }
    final signatures = [
      for (final body in bodies)
        await crypto.ed25519Sign(
          key,
          signingInput(FragmentTickets.signingContext, body),
        ),
    ];
    _log.fine(
      LogEvent('signed', {
        'tickets': bodies.length,
        for (final MapEntry(:key, :value) in counts.entries)
          _operationName(key): value,
      }),
    );
    return SignerWire.encodeSigned(key.publicKey, signatures);
  }

  Uint8List _refuse(
    pb.ErrorCode code,
    String reason, {
    int index = SignerWire.noIndex,
    Duration? retryAfter,
  }) {
    // Отказ — либо ошибка в коде координатора, либо признак взлома
    // веб-сервера: в журнал на уровне warning.
    _log.warning(
      LogEvent('refused', {
        'code': errorCodeName(code),
        'reason': reason,
        if (index != SignerWire.noIndex) 'index': index,
      }),
    );
    return SignerWire.encodeError(code, retryAfter: retryAfter, index: index);
  }

  static String _operationName(pb.TicketOperation op) => switch (op) {
    pb.TicketOperation.TICKET_OPERATION_PUT => 'put',
    pb.TicketOperation.TICKET_OPERATION_GET => 'get',
    pb.TicketOperation.TICKET_OPERATION_DELETE => 'delete',
    _ => 'op_${op.value}',
  };
}
