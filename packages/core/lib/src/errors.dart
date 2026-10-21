import 'dart:typed_data';

import 'package:core/src/util/bytes.dart';

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

String _shortId(Uint8List id) =>
    bytesToHex(id.length > 8 ? Uint8List.sublistView(id, 0, 8) : id);
