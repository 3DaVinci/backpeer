import 'dart:typed_data';

import 'package:coordinator/src/rpc/errors.dart';
import 'package:core/core.dart';
import 'package:protobuf/protobuf.dart';
import 'package:protocol/protocol.dart' as pb;

/// Проверка сертификатов устройств и узлов и отзывов (protocol.md, разделы
/// 4.7, 4.9). Ошибка в полях — `BAD_REQUEST`, подпись не та или не тем
/// ключом — `UNAUTHENTICATED`.
final class CertificateChecks {
  new(this.crypto, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final CryptoProvider crypto;
  final DateTime Function() _clock;

  static final int _skewMs = RequestAuth.maxClockSkew.inMilliseconds;

  /// `DeviceCertificate` учётной записи [accountId].
  Future<pb.DeviceCertificate> deviceCertificate(
    pb.Signed signed,
    Uint8List accountId,
  ) async {
    final cert = await _open(
      signed,
      accountId,
      context: 'device-cert',
      parse: pb.DeviceCertificate.fromBuffer,
    );
    if (!constantTimeEquals(cert.accountId, accountId)) {
      throw _bad('сертификат другой учётной записи');
    }
    if (cert.deviceSign.length != 32 || cert.deviceDh.length != 32) {
      throw _bad('ключи устройства — по 32 байта');
    }
    _notInFuture(cert.issuedAtUnixMs.toInt(), 'issued_at_unix_ms');
    return cert;
  }

  /// `DeviceRevocation` учётной записи [accountId].
  Future<pb.DeviceRevocation> revocation(
    pb.Signed signed,
    Uint8List accountId,
  ) async {
    final revocation = await _open(
      signed,
      accountId,
      context: 'device-revoke',
      parse: pb.DeviceRevocation.fromBuffer,
    );
    if (!constantTimeEquals(revocation.accountId, accountId)) {
      throw _bad('отзыв другой учётной записи');
    }
    if (revocation.deviceSign.length != 32) {
      throw _bad('ключ устройства — 32 байта');
    }
    _notInFuture(revocation.revokedAtUnixMs.toInt(), 'revoked_at_unix_ms');
    return revocation;
  }

  /// `NodeCertificate` узла [nodeId], подписанный ключом учётной записи из
  /// самого сертификата (контекст `node-cert`). Зарегистрирована ли эта
  /// учётная запись, проверяет вызывающий.
  Future<pb.NodeCertificate> nodeCertificate(
    pb.Signed signed,
    Uint8List nodeId,
  ) async {
    final owner = Uint8List.fromList(signed.signer);
    final cert = await _open(
      signed,
      owner,
      context: NodeCertificates.signingContext,
      parse: pb.NodeCertificate.fromBuffer,
    );
    if (!constantTimeEquals(cert.accountId, owner)) {
      throw const RpcException(
        pb.ErrorCode.ERROR_CODE_UNAUTHENTICATED,
        'сертификат узла подписан не его владельцем',
      );
    }
    if (cert.nodeId.length != 32 || cert.nodeDh.length != 32) {
      throw _bad('ключи узла — по 32 байта');
    }
    if (!constantTimeEquals(cert.nodeId, nodeId)) {
      throw _bad('сертификат другого узла');
    }
    _notInFuture(cert.issuedAtUnixMs.toInt(), 'issued_at_unix_ms');
    return cert;
  }

  /// KeyBundle и `auth_verifier`: оба пусты — `null` (режим без копии),
  /// иначе разобранный KeyBundle учётной записи [accountId].
  KeyBundle? keyBundle(
    List<int> keyBundle,
    List<int> authVerifier,
    Uint8List accountId,
  ) {
    if (keyBundle.isEmpty && authVerifier.isEmpty) return null;
    if (keyBundle.isEmpty || authVerifier.isEmpty) {
      throw _bad('key_bundle и auth_verifier задаются вместе');
    }
    if (authVerifier.length != 32) throw _bad('auth_verifier — 32 байта');
    final KeyBundle bundle;
    try {
      bundle = KeyBundle.parse(Uint8List.fromList(keyBundle));
    } on DataFormatException {
      throw _bad('key_bundle не разбирается');
    }
    if (!constantTimeEquals(bundle.accountId, accountId)) {
      throw _bad('key_bundle другой учётной записи');
    }
    return bundle;
  }

  Future<T> _open<T extends GeneratedMessage>(
    pb.Signed signed,
    Uint8List accountId, {
    required String context,
    required T Function(List<int>) parse,
  }) async {
    if (!signed.hasBody()) throw _bad('нет подписанного сообщения');
    if (!constantTimeEquals(signed.signer, accountId)) {
      throw const RpcException(
        pb.ErrorCode.ERROR_CODE_UNAUTHENTICATED,
        'подписано не ключом учётной записи',
      );
    }
    try {
      return await SignedMessages.open(
        crypto,
        signed,
        context: context,
        object: context,
        parse: parse,
      );
    } on IntegrityException {
      throw const RpcException(
        pb.ErrorCode.ERROR_CODE_UNAUTHENTICATED,
        'подпись не сходится',
      );
    } on DataFormatException {
      throw _bad('$context не разбирается');
    }
  }

  void _notInFuture(int timeMs, String field) {
    if (timeMs > _clock().millisecondsSinceEpoch + _skewMs) {
      throw _bad('$field в будущем');
    }
  }

  static RpcException _bad(String message) =>
      RpcException(pb.ErrorCode.ERROR_CODE_BAD_REQUEST, message);
}
