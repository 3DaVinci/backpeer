import 'package:core/core.dart';

/// Ошибка с файлом ключа подписанта: сообщение для оператора.
typedef SignerKeyException = KeyFileException;

/// Файл ключа подписи координатора: 32 байта seed Ed25519, права 0600,
/// владелец — пользователь ОС подписанта (`docs/ops/coordinator.md`).
typedef SignerKeyFile = Ed25519KeyFile;
