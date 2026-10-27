import 'dart:typed_data';

import 'package:core/src/util/bytes.dart';
import 'package:protocol/protocol.dart' as pb;

/// Ошибки данных и окружения, которые `core` сообщает вызывающему: CLI
/// показывает их пользователю, конвейер решает, повторять ли операцию.
///
/// Ошибки программы (неверная длина ключа, недопустимые параметры) —
/// обычные [ArgumentError] и [StateError], сюда не входят.
///
/// Векторы различают виды `format` и `integrity` (docs/spec/test-vectors.md,
/// раздел 2): им соответствуют [DataFormatException] и [IntegrityException].
sealed class CoreException implements Exception {
  const new();

  /// Сообщение для пользователя, без секретов.
  String get message;

  @override
  String toString() => message;
}

/// Почему данные не разобрались.
enum FormatProblem {
  badMagic('неверная сигнатура'),
  unsupportedVersion('неподдерживаемая версия'),
  unknownType('неизвестный тип'),
  reservedNotZero('ненулевое зарезервированное поле'),
  truncated('данные обрезаны'),
  tooLarge('превышен допустимый размер'),
  invalidField('недопустимое значение поля');

  new(this.description);

  final String description;
}

/// Данные не разбираются по спецификации; обработка (расшифровка,
/// проверка хэшей) не начиналась. Вид `format` в векторах.
final class DataFormatException extends CoreException {
  const new({
    required this.object,
    required this.problem,
    this.detail,
    this.offset,
  });

  /// Что разбиралось: `blob`, `segment`, `fragment`, `key-bundle`, …
  final String object;

  final FormatProblem problem;

  /// Подробность, например «версия 7» или «поле k = 0».
  final String? detail;

  /// Смещение в байтах, где обнаружена ошибка, если известно.
  final int? offset;

  @override
  String get message {
    final out = StringBuffer('$object: ${problem.description}');
    if (detail != null) out.write(' ($detail)');
    if (offset != null) out.write(', смещение $offset');
    return out.toString();
  }
}

/// Какая проверка не сошлась.
enum IntegrityCheck {
  aeadTag('тег AEAD'),
  hash('хэш'),
  merkleRoot('корень Меркла'),
  fragmentId('идентификатор фрагмента'),
  checksum('контрольная сумма'),
  objectId('идентификатор объекта'),
  signature('подпись');

  new(this.description);

  final String description;
}

/// Данные разобрались, но проверка тега, хэша, корня Меркла или подписи
/// не сошлась: повреждение, подмена или неверный ключ. Вид `integrity` в
/// векторах.
final class IntegrityException extends CoreException {
  const new({required this.object, required this.check, this.objectId});

  final String object;

  final IntegrityCheck check;

  /// Идентификатор объекта (сегмента, фрагмента, снимка), если известен.
  final Uint8List? objectId;

  @override
  String get message {
    final id = objectId == null ? '' : ' ${_shortId(objectId!)}';
    return '$object$id: не сошлась проверка (${check.description})';
  }
}

/// Для восстановления сегмента не хватает фрагментов.
final class InsufficientShardsException extends CoreException {
  const new({required this.available, required this.required, this.segmentId});

  final int available;
  final int required;
  final Uint8List? segmentId;

  @override
  String get message {
    final id = segmentId == null ? '' : ' ${_shortId(segmentId!)}';
    return 'сегмент$id: доступно фрагментов $available, нужно $required';
  }
}

/// Что случилось с хранилищем.
enum StorageProblem {
  notFound('не найдено'),
  unavailable('недоступно'),
  io('ошибка ввода-вывода');

  new(this.description);

  final String description;
}

/// Ошибка хранилища фрагментов, объектов или локального индекса.
final class StorageException extends CoreException {
  const new({
    required this.location,
    required this.problem,
    this.operation,
    this.cause,
  });

  /// Где: папка-«узел», путь к файлу, адрес хранителя.
  final String location;

  final StorageProblem problem;

  /// Операция, например `put`, `get`.
  final String? operation;

  /// Исходная ошибка (например, `FileSystemException` из `dart:io`).
  final Object? cause;

  @override
  String get message {
    final out = StringBuffer(location);
    if (operation != null) out.write(' ($operation)');
    out.write(': ${problem.description}');
    if (cause != null) out.write(': $cause');
    return out.toString();
  }
}

/// Исходный файл менялся во время чтения, и повторные попытки не дали
/// согласованного снимка.
final class SourceChangedException extends CoreException {
  const new({required this.path, required this.attempts});

  final String path;
  final int attempts;

  @override
  String get message =>
      '$path: файл менялся во время чтения ($attempts попыток)';
}

/// Недопустимое значение в конфигурации.
final class ConfigException extends CoreException {
  const new({required this.key, required this.reason});

  final String key;
  final String reason;

  @override
  String get message => 'конфигурация, $key: $reason';
}

/// Операцию сейчас выполнять нельзя: состояние небезопасно (например,
/// сборка мусора при недописанном бэкапе или признаках отката).
final class PreconditionException extends CoreException {
  const new(this.reason);

  final String reason;

  @override
  String get message => 'операция невозможна: $reason';
}

/// Координатор дважды подряд предложил размещение, нарушающее правила
/// (protocol.md, раздел 5, «Проверка размещения клиентом»; угроза К-5).
final class PlacementRejectedException extends CoreException {
  const new(this.reason, {this.segmentId});

  final String reason;
  final Uint8List? segmentId;

  @override
  String get message {
    final id = segmentId == null ? '' : ' ${_shortId(segmentId!)}';
    return 'размещение сегмента$id отклонено: $reason';
  }
}

/// Операция отменена пользователем.
final class CancelledException extends CoreException {
  const new();

  @override
  String get message => 'операция отменена';
}

/// Координатор ответил ошибкой или недоступен (protocol.md, раздел 4.4).
final class CoordinatorException extends CoreException {
  const new(this.code, this.detail, {this.retryAfter, this.httpStatus});

  final pb.ErrorCode code;

  /// `Error.message` координатора или описание сбоя связи: для журнала.
  final String detail;

  /// Для `RATE_LIMITED` и `UNAVAILABLE`.
  final Duration? retryAfter;

  /// HTTP-статус ответа; `null` — ответа не было (сбой связи).
  final int? httpStatus;

  @override
  String get message => 'координатор: ${errorCodeName(code)}: $detail';
}

/// Почему собеседник по каналу Noise не принят (protocol.md, раздел 3.2).
enum PeerRejection {
  handshake('рукопожатие Noise не удалось'),
  hello('Hello не разбирается'),
  role('недопустимая роль'),
  certificate('сертификат не прошёл проверку'),
  keyMismatch('ключ Noise не совпадает с ключом из сертификата'),
  unexpectedNode('сертификат другого узла'),
  revoked('устройство отозвано'),
  versionUnsupported('нет общей версии протокола'),
  timeout('истекло время рукопожатия');

  new(this.description);

  final String description;
}

/// Рукопожатие с собеседником не удалось или он не прошёл проверку.
/// Соединение к этому моменту закрыто.
final class PeerRejectedException extends CoreException {
  const new(this.reason, {this.detail});

  final PeerRejection reason;

  /// Подробность для журнала, без секретов.
  final String? detail;

  @override
  String get message {
    final tail = detail == null ? '' : ' ($detail)';
    return 'собеседник отклонён: ${reason.description}$tail';
  }
}

/// Собеседник по каналу Noise ответил на запрос ошибкой, не ответил
/// вовремя или соединение оборвалось (protocol.md, раздел 3.4).
final class PeerRequestException extends CoreException {
  const new(this.code, this.detail, {this.retryAfter});

  /// Код из `PeerMessage.error`; таймаут и обрыв соединения —
  /// `UNAVAILABLE`, нарушение протокола собеседником — `BAD_REQUEST`.
  final pb.ErrorCode code;

  /// `Error.message` собеседника или описание сбоя: для журнала.
  final String detail;

  /// Для `RATE_LIMITED` и `UNAVAILABLE`.
  final Duration? retryAfter;

  @override
  String get message => 'собеседник: ${errorCodeName(code)}: $detail';
}

/// К узлу не удалось подключиться ни одним способом (стратегия
/// подключения, задача 3.9.1).
final class PeerUnreachableException extends CoreException {
  const new(this.nodeId, this.attempts);

  final Uint8List nodeId;

  /// Неудачные попытки по порядку завершения: способ (`direct`, `udp`,
  /// `relay`), адрес для прямого TCP и причина.
  final List<({String method, String? endpoint, String error})> attempts;

  @override
  String get message {
    final node = bytesToHex(nodeId).substring(0, 16);
    if (attempts.isEmpty) return 'узел $node: нет способов подключения';
    final tried = attempts
        .map(
          (a) =>
              '${a.method}${a.endpoint == null ? '' : ' ${a.endpoint}'}: '
              '${a.error}',
        )
        .join('; ');
    return 'узел $node недоступен ($tried)';
  }
}

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

String _shortId(Uint8List id) =>
    bytesToHex(id.length > 8 ? Uint8List.sublistView(id, 0, 8) : id);
