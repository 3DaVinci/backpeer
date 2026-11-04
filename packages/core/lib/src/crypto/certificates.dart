import 'dart:typed_data';

import 'package:core/src/crypto/account_keys.dart';
import 'package:core/src/crypto/crypto_provider.dart';
import 'package:core/src/crypto/device_keys.dart';
import 'package:core/src/crypto/signed_message.dart';
import 'package:core/src/errors.dart';
import 'package:core/src/util/bytes.dart';
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

  /// Проверяет сертификат узла, как его проверит клиент после рукопожатия
  /// (protocol.md, раздел 5, «Проверка размещения клиентом»): подписан
  /// ключом владельца из самого сертификата, ключи по 32 байта, и, если
  /// задан, это сертификат узла [nodeId]. Битые поля и чужой узел —
  /// [DataFormatException], подпись — [IntegrityException].
  static Future<pb.NodeCertificate> open(
    CryptoProvider crypto,
    pb.Signed signed, {
    Uint8List? nodeId,
  }) async {
    final cert = await SignedMessages.open(
      crypto,
      signed,
      context: signingContext,
      object: signingContext,
      parse: pb.NodeCertificate.fromBuffer,
    );
    if (!constantTimeEquals(cert.accountId, signed.signer)) {
      throw const IntegrityException(
        object: signingContext,
        check: IntegrityCheck.signature,
      );
    }
    if (cert.nodeId.length != CryptoProvider.keyLength ||
        cert.nodeDh.length != CryptoProvider.keyLength ||
        (nodeId != null && !constantTimeEquals(cert.nodeId, nodeId))) {
      throw const DataFormatException(
        object: signingContext,
        problem: FormatProblem.invalidField,
        detail: 'ключи узла или сертификат другого узла',
      );
    }
    return cert;
  }
}

/// Короткий отпечаток ключей узла для привязки (protocol.md, раздел 4.17):
/// первые 16 шестнадцатеричных символов BLAKE2b-256(node_id ‖ node_dh),
/// группами по 4 через дефис. Владелец сверяет отпечаток на экране узла и
/// на своём устройстве, чтобы не привязать чужой узел.
String nodeFingerprint(
  CryptoProvider crypto, {
  required Uint8List nodeId,
  required Uint8List nodeDh,
}) {
  final material = Uint8List(nodeId.length + nodeDh.length)
    ..setRange(0, nodeId.length, nodeId)
    ..setRange(nodeId.length, nodeId.length + nodeDh.length, nodeDh);
  final hex = bytesToHex(crypto.blake2b256(material).sublist(0, 8))
      .toUpperCase();
  return [for (var i = 0; i < hex.length; i += 4) hex.substring(i, i + 4)]
      .join('-');
}

/// Сертификат и отзыв устройства (protocol.md, разделы 4.7, 6):
/// `DeviceCertificate` в контексте `device-cert` и `DeviceRevocation` в
/// контексте `device-revoke`, оба подписаны ключом учётной записи.
abstract final class DeviceCertificates {
  static const signingContext = 'device-cert';
  static const revocationContext = 'device-revoke';

  static Future<pb.Signed> issue(
    CryptoProvider crypto,
    AccountKeys account,
    DeviceKeys device, {
    required DateTime issuedAt,
  }) => SignedMessages.sign(
    crypto,
    account.accountSign,
    signingContext,
    pb.DeviceCertificate(
      accountId: account.accountId,
      deviceSign: device.sign.publicKey,
      deviceDh: device.dh.publicKey,
      issuedAtUnixMs: Int64(issuedAt.millisecondsSinceEpoch),
    ),
  );

  static Future<pb.Signed> revoke(
    CryptoProvider crypto,
    AccountKeys account, {
    required Uint8List deviceSign,
    required DateTime revokedAt,
  }) {
    if (deviceSign.length != CryptoProvider.keyLength) {
      throw ArgumentError('device_sign — 32 байта');
    }
    return SignedMessages.sign(
      crypto,
      account.accountSign,
      revocationContext,
      pb.DeviceRevocation(
        accountId: account.accountId,
        deviceSign: deviceSign,
        revokedAtUnixMs: Int64(revokedAt.millisecondsSinceEpoch),
      ),
    );
  }

  /// Проверяет отзыв устройства (protocol.md, раздел 4.7), как его
  /// проверяет узел после `ListRevocations`: подписан ключом учётной
  /// записи из самого отзыва, `device_sign` — 32 байта. Битые поля —
  /// [DataFormatException], подпись — [IntegrityException].
  static Future<pb.DeviceRevocation> openRevocation(
    CryptoProvider crypto,
    pb.Signed signed,
  ) async {
    final revocation = await SignedMessages.open(
      crypto,
      signed,
      context: revocationContext,
      object: revocationContext,
      parse: pb.DeviceRevocation.fromBuffer,
    );
    if (!constantTimeEquals(revocation.accountId, signed.signer)) {
      throw const IntegrityException(
        object: revocationContext,
        check: IntegrityCheck.signature,
      );
    }
    if (revocation.deviceSign.length != CryptoProvider.keyLength) {
      throw const DataFormatException(
        object: revocationContext,
        problem: FormatProblem.invalidField,
        detail: 'device_sign',
      );
    }
    return revocation;
  }
}
