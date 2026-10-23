import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:node/node.dart';
import 'package:protocol/protocol.dart' as pb;

/// Ключи узла в [dir] и сертификат от случайной учётной записи владельца;
/// возвращает владельца (затирает вызывающий).
Future<AccountKeys> nodeWithCertificate(
  Directory dir,
  CryptoProvider crypto,
) async {
  await NodeIdentity.ensureKeys(dir, crypto);
  final owner = await AccountKeys.fromMasterKey(
    SecretBytes(crypto.randomBytes(32)),
    crypto,
  );
  final identity = await NodeIdentity.load(dir, crypto);
  try {
    final cert = await NodeCertificates.issue(
      crypto,
      owner,
      nodeId: identity.nodeId,
      nodeDh: identity.nodeDh,
      issuedAt: DateTime.now(),
    );
    await NodeIdentity.importCertificate(dir, crypto, cert.writeToBuffer());
  } finally {
    identity.dispose();
  }
  return owner;
}

/// Сертификат на произвольные ключи от [owner].
Future<pb.Signed> foreignCertificate(
  CryptoProvider crypto,
  AccountKeys owner, {
  Uint8List? nodeId,
  Uint8List? nodeDh,
}) => NodeCertificates.issue(
  crypto,
  owner,
  nodeId: nodeId ?? crypto.randomBytes(32),
  nodeDh: nodeDh ?? crypto.randomBytes(32),
  issuedAt: DateTime.now(),
);
