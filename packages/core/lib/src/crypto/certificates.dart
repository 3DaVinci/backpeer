import 'dart:typed_data';

import 'package:core/src/crypto/account_keys.dart';
import 'package:core/src/crypto/crypto_provider.dart';
import 'package:core/src/crypto/signed_message.dart';
import 'package:fixnum/fixnum.dart';
import 'package:protocol/protocol.dart' as pb;

/// Сертификат узла (protocol.md, раздел 6): `NodeCertificate`, подписанный
/// ключом учётной записи владельца в контексте `node-cert`. Выпускает
/// владелец на своём устройстве (`cli node-cert`), узел предъявляет его
/// координатору в `RegisterNode` и собеседникам в рукопожатии Noise.
abstract final class NodeCertificates {
  static const signingContext = 'node-cert';

  static Future<pb.Signed> issue(
    CryptoProvider crypto,
    AccountKeys owner, {
    required Uint8List nodeId,
    required Uint8List nodeDh,
    required DateTime issuedAt,
  }) {
    if (nodeId.length != CryptoProvider.keyLength ||
        nodeDh.length != CryptoProvider.keyLength) {
      throw ArgumentError('node_id и node_dh — по 32 байта');
    }
    return SignedMessages.sign(
      crypto,
      owner.accountSign,
      signingContext,
      pb.NodeCertificate(
        accountId: owner.accountId,
        nodeId: nodeId,
        nodeDh: nodeDh,
        issuedAtUnixMs: Int64(issuedAt.millisecondsSinceEpoch),
      ),
    );
  }
}
