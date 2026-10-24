import 'dart:io';
import 'dart:math';
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

/// Детерминированный фрагмент для тестов хранилища: блоб [blobLength]
/// байт и сегмент из генератора с зерном [seed], k = 1, n = 2.
Fragment testFragment(
  CryptoProvider crypto, {
  int seed = 1,
  int blobLength = 3 << 20,
}) {
  final random = Random(seed);
  Uint8List bytes(int n) =>
      Uint8List.fromList(List<int>.generate(n, (_) => random.nextInt(256)));
  final segmentId = bytes(32);
  return encodeFragments(
    crypto,
    blob: bytes(blobLength),
    segmentId: segmentId,
    k: 1,
    n: 2,
  ).first;
}

/// `fragment_id` фрагмента.
Uint8List fragmentIdOf(CryptoProvider crypto, Fragment f) =>
    f.header.fragmentId(crypto);
