import 'package:protocol/protocol.dart' as pb;

/// Ошибка вызова API: уходит клиенту телом `Error` со статусом по коду
/// (protocol.md, раздел 4.4).
final class RpcException implements Exception {
  const new(this.code, this.message, {this.retryAfter, this.httpStatus});

  final pb.ErrorCode code;

  /// Для журнала и клиента; без ключей и данных запроса.
  final String message;

  /// Для `RATE_LIMITED` и `UNAVAILABLE`.
  final Duration? retryAfter;

  /// Статус вместо стандартного для кода: 405, 413, 415 при `BAD_REQUEST`.
  final int? httpStatus;

  int get status => httpStatus ?? httpStatusFor(code);

  pb.Error toProto() => pb.Error(
    code: code,
    message: message,
    retryAfterMs: retryAfter?.inMilliseconds,
  );

  @override
  String toString() => 'RpcException(${errorCodeName(code)}: $message)';
}

/// HTTP-статус по коду ошибки (protocol.md, раздел 4.4).
int httpStatusFor(pb.ErrorCode code) => switch (code) {
  pb.ErrorCode.ERROR_CODE_BAD_REQUEST ||
  pb.ErrorCode.ERROR_CODE_VERSION_UNSUPPORTED => 400,
  pb.ErrorCode.ERROR_CODE_UNAUTHENTICATED => 401,
  pb.ErrorCode.ERROR_CODE_PERMISSION_DENIED => 403,
  pb.ErrorCode.ERROR_CODE_NOT_FOUND => 404,
  pb.ErrorCode.ERROR_CODE_ALREADY_EXISTS => 409,
  pb.ErrorCode.ERROR_CODE_QUOTA_EXCEEDED => 507,
  pb.ErrorCode.ERROR_CODE_RATE_LIMITED => 429,
  pb.ErrorCode.ERROR_CODE_UNAVAILABLE => 503,
  _ => 500,
};

/// Имя кода для журнала: `BAD_REQUEST`. Не зависит от того, сохранены ли
/// в сборке имена значений enum Protobuf.
String errorCodeName(pb.ErrorCode code) => switch (code) {
  pb.ErrorCode.ERROR_CODE_UNSPECIFIED => 'UNSPECIFIED',
  pb.ErrorCode.ERROR_CODE_VERSION_UNSUPPORTED => 'VERSION_UNSUPPORTED',
  pb.ErrorCode.ERROR_CODE_BAD_REQUEST => 'BAD_REQUEST',
  pb.ErrorCode.ERROR_CODE_UNAUTHENTICATED => 'UNAUTHENTICATED',
  pb.ErrorCode.ERROR_CODE_PERMISSION_DENIED => 'PERMISSION_DENIED',
  pb.ErrorCode.ERROR_CODE_NOT_FOUND => 'NOT_FOUND',
  pb.ErrorCode.ERROR_CODE_ALREADY_EXISTS => 'ALREADY_EXISTS',
  pb.ErrorCode.ERROR_CODE_QUOTA_EXCEEDED => 'QUOTA_EXCEEDED',
  pb.ErrorCode.ERROR_CODE_INTEGRITY_FAILED => 'INTEGRITY_FAILED',
  pb.ErrorCode.ERROR_CODE_TICKET_EXPIRED => 'TICKET_EXPIRED',
  pb.ErrorCode.ERROR_CODE_RATE_LIMITED => 'RATE_LIMITED',
  pb.ErrorCode.ERROR_CODE_UNAVAILABLE => 'UNAVAILABLE',
  pb.ErrorCode.ERROR_CODE_INTERNAL => 'INTERNAL',
  _ => 'CODE_${code.value}',
};
