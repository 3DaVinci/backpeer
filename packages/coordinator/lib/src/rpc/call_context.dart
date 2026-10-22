import 'package:coordinator/src/auth/request_verifier.dart';

/// Сведения о вызове для обработчика метода.
final class CallContext {
  const new({required this.method, required this.requestId, this.caller});

  /// Имя метода: `PutObject`.
  final String method;

  /// Идентификатор запроса для журнала (заголовок ответа `FS-Request-Id`).
  final String requestId;

  /// Кто подписал запрос; `null` — метод без подписи.
  final Caller? caller;
}
