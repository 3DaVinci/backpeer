import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';

/// Ошибка с файлом ключа подписанта: сообщение для оператора.
final class SignerKeyException implements Exception {
  const new(this.message);

  final String message;

  @override
  String toString() => 'SignerKeyException: $message';
}

/// Файл ключа подписи координатора: 32 байта seed Ed25519, права 0600,
/// владелец — пользователь ОС подписанта (`docs/ops/coordinator.md`).
abstract final class SignerKeyFile {
  static const seedLength = 32;

  /// Создаёт новый ключ. Существующий файл не перезаписывается.
  static Future<Ed25519KeyPair> generate(
    String path,
    CryptoProvider crypto,
  ) async {
    _requireUnix();
    final file = File(path);
    if (file.existsSync()) {
      throw SignerKeyException('$path уже существует');
    }
    final seed = crypto.randomBytes(seedLength);
    try {
      writePrivateFileAtomic(file, seed);
      return await crypto.ed25519FromSeed(SecretBytes(seed));
    } finally {
      seed.fillRange(0, seed.length, 0);
    }
  }

  /// Читает ключ. Файл, доступный группе или остальным, — ошибка: такой
  /// ключ мог прочитать веб-сервер.
  static Future<Ed25519KeyPair> load(String path, CryptoProvider crypto) async {
    _requireUnix();
    final stat = FileStat.statSync(path);
    if (stat.type != FileSystemEntityType.file) {
      throw SignerKeyException('$path: нет файла ключа');
    }
    // Биты rwx группы и остальных.
    if (stat.mode & 63 != 0) {
      throw SignerKeyException(
        '$path: права ${(stat.mode & 511).toRadixString(8)}, нужно 600 '
        '(ключ доступен не только владельцу)',
      );
    }
    final Uint8List seed;
    try {
      seed = File(path).readAsBytesSync();
    } on FileSystemException catch (e) {
      throw SignerKeyException('$path не читается: ${e.message}');
    }
    try {
      if (seed.length != seedLength) {
        throw SignerKeyException(
          '$path: ${seed.length} байт, нужно $seedLength',
        );
      }
      return await crypto.ed25519FromSeed(SecretBytes(seed));
    } finally {
      seed.fillRange(0, seed.length, 0);
    }
  }

  static void _requireUnix() {
    if (Platform.isWindows) {
      throw const SignerKeyException('подписант работает только на Unix');
    }
  }
}
