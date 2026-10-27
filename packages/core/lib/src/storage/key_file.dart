import 'dart:io';
import 'dart:typed_data';

import 'package:core/src/crypto/crypto_provider.dart';
import 'package:core/src/crypto/secret_bytes.dart';
import 'package:core/src/storage/private_file.dart';

/// Ошибка с файлом ключа: сообщение для оператора.
final class KeyFileException implements Exception {
  const new(this.message);

  final String message;

  @override
  String toString() => 'KeyFileException: $message';
}

/// Файл ключа Ed25519 серверного процесса: 32 байта seed, права 0600,
/// владелец — пользователь ОС процесса. Ключ подписанта талонов и ключ
/// пропусков координатора (`docs/ops/coordinator.md`), ключ relay
/// (`docs/ops/relay.md`).
abstract final class Ed25519KeyFile {
  static const seedLength = 32;

  /// Создаёт новый ключ. Существующий файл не перезаписывается.
  static Future<Ed25519KeyPair> generate(
    String path,
    CryptoProvider crypto,
  ) async {
    _requireUnix();
    final file = File(path);
    if (file.existsSync()) {
      throw KeyFileException('$path уже существует');
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
  /// ключ мог прочитать другой процесс.
  static Future<Ed25519KeyPair> load(String path, CryptoProvider crypto) async {
    _requireUnix();
    final stat = FileStat.statSync(path);
    if (stat.type != FileSystemEntityType.file) {
      throw KeyFileException('$path: нет файла ключа');
    }
    // Биты rwx группы и остальных.
    if (stat.mode & 63 != 0) {
      throw KeyFileException(
        '$path: права ${(stat.mode & 511).toRadixString(8)}, нужно 600 '
        '(ключ доступен не только владельцу)',
      );
    }
    final Uint8List seed;
    try {
      seed = File(path).readAsBytesSync();
    } on FileSystemException catch (e) {
      throw KeyFileException('$path не читается: ${e.message}');
    }
    try {
      if (seed.length != seedLength) {
        throw KeyFileException('$path: ${seed.length} байт, нужно $seedLength');
      }
      return await crypto.ed25519FromSeed(SecretBytes(seed));
    } finally {
      seed.fillRange(0, seed.length, 0);
    }
  }

  static void _requireUnix() {
    if (Platform.isWindows) {
      throw const KeyFileException('файл ключа сервера — только на Unix');
    }
  }
}
