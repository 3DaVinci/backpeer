import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:protocol/protocol.dart' as pb;

/// Ошибка ключей или сертификата узла: сообщение для владельца.
final class NodeIdentityException implements Exception {
  const new(this.message);

  final String message;

  @override
  String toString() => 'NodeIdentityException: $message';
}

/// Ключи и сертификат узла в папке данных (`crypto.md`, раздел 3.4):
///
/// - `node.key` — seed `node_sign` (Ed25519) и закрытый `node_dh` (X25519),
///   64 байта, права 0600. Без пароля: демон запускается без человека,
///   защита — права файла и отдельный пользователь ОС;
/// - `node.cert` — `fs.v1.Signed` с `NodeCertificate`, выпущенный владельцем
///   командой `cli node-cert`.
final class NodeIdentity {
  new _(this.keys, this.certificate, this.owner);

  static const keyFile = 'node.key';
  static const certificateFile = 'node.cert';

  /// Ключи узла; затирает [dispose].
  final DeviceKeys keys;

  /// Сертификат; `null` — ещё не импортирован (`node import-cert`).
  final pb.Signed? certificate;

  /// Учётная запись владельца из сертификата.
  final Uint8List? owner;

  Uint8List get nodeId => keys.sign.publicKey;
  Uint8List get nodeDh => keys.dh.publicKey;

  /// Создаёт ключи в [dataDir], если их нет; возвращает `true`, если
  /// создал.
  static Future<bool> ensureKeys(
    Directory dataDir,
    CryptoProvider crypto,
  ) async {
    final file = File('${dataDir.path}/$keyFile');
    if (file.existsSync()) return false;
    createPrivateDir(dataDir);
    final keys = await DeviceKeys.generate(crypto);
    final secret = keys.toSecret();
    try {
      writePrivateFileAtomic(file, secret.bytes);
    } finally {
      secret.dispose();
      keys.dispose();
    }
    return true;
  }

  /// Ключи и сертификат из [dataDir]. Нет ключей, права шире 0600, битый
  /// или чужой сертификат — [NodeIdentityException].
  static Future<NodeIdentity> load(
    Directory dataDir,
    CryptoProvider crypto,
  ) async {
    final file = File('${dataDir.path}/$keyFile');
    if (!file.existsSync()) {
      throw NodeIdentityException(
        'нет ключей узла ${file.path}: сначала node init',
      );
    }
    checkPrivate(file);
    final secret = SecretBytes(file.readAsBytesSync());
    final DeviceKeys keys;
    try {
      if (secret.length != DeviceKeys.secretLength) {
        throw NodeIdentityException(
          '${file.path}: ожидается ${DeviceKeys.secretLength} байта',
        );
      }
      keys = await DeviceKeys.fromSecret(crypto, secret);
    } finally {
      secret.dispose();
    }
    try {
      final certFile = File('${dataDir.path}/$certificateFile');
      if (!certFile.existsSync()) return NodeIdentity._(keys, null, null);
      final signed = _parse(certFile.readAsBytesSync(), certFile.path);
      final cert = await _check(crypto, signed, keys, certFile.path);
      return NodeIdentity._(keys, signed, Uint8List.fromList(cert.accountId));
    } on Object {
      keys.dispose();
      rethrow;
    }
  }

  /// Проверяет сертификат [bytes] (выпущен на ключи этого узла, подпись
  /// владельца) и кладёт его в папку данных поверх прежнего. Возвращает
  /// учётную запись владельца.
  static Future<Uint8List> importCertificate(
    Directory dataDir,
    CryptoProvider crypto,
    Uint8List bytes, {
    String source = 'сертификат',
  }) async {
    final identity = await load(dataDir, crypto);
    try {
      final signed = _parse(bytes, source);
      final cert = await _check(crypto, signed, identity.keys, source);
      final file = File('${dataDir.path}/$certificateFile');
      File('${file.path}.tmp-$pid')
        ..writeAsBytesSync(signed.writeToBuffer(), flush: true)
        ..renameSync(file.path);
      return Uint8List.fromList(cert.accountId);
    } finally {
      identity.dispose();
    }
  }

  /// Разбор конверта сертификата. Байты приходят из файла или из канала
  /// привязки, то есть недоверенные: `protobuf` на длине за границей буфера
  /// бросает `RangeError`, а это `Error`, а не `Exception` — ловим через
  /// общий разборщик ядра (`ManifestObjects.parseMessage`, фаззинг 1.8.5).
  static pb.Signed _parse(List<int> bytes, String source) {
    try {
      return ManifestObjects.parseMessage(
        source,
        () => pb.Signed.fromBuffer(bytes),
      );
    } on DataFormatException catch (e) {
      final detail = e.detail;
      throw NodeIdentityException(
        detail == null
            ? '$source: не fs.v1.Signed'
            : '$source: не fs.v1.Signed ($detail)',
      );
    }
  }

  static Future<pb.NodeCertificate> _check(
    CryptoProvider crypto,
    pb.Signed signed,
    DeviceKeys keys,
    String source,
  ) async {
    final pb.NodeCertificate cert;
    try {
      cert = await NodeCertificates.open(
        crypto,
        signed,
        nodeId: keys.sign.publicKey,
      );
    } on CoreException catch (e) {
      throw NodeIdentityException(
        '$source: сертификат не подходит к ключам узла (${e.message})',
      );
    }
    if (!constantTimeEquals(cert.nodeDh, keys.dh.publicKey)) {
      throw NodeIdentityException('$source: в сертификате другой ключ node_dh');
    }
    return cert;
  }

  /// Файл [file] доступен только владельцу: на Linux и macOS права не
  /// шире 0600. На Windows права задаются при записи (`icacls`) и здесь не
  /// проверяются.
  static void checkPrivate(File file) {
    if (Platform.isWindows) return;
    final mode = file.statSync().mode & 511; // 0777
    if (mode & 63 != 0) {
      throw NodeIdentityException(
        '${file.path}: права ${mode.toRadixString(8).padLeft(4, '0')}, '
        'нужно 0600 (chmod 600)',
      );
    }
  }

  void dispose() => keys.dispose();
}

/// Создаёт папку [dir], доступную только владельцу (0700 на Linux и
/// macOS): в папке данных узла — ключи, чужие фрагменты, журнал.
void createPrivateDir(Directory dir) {
  dir.createSync(recursive: true);
  if (!Platform.isWindows) setUnixFileMode(dir.path, 448); // 0700
}
