import 'dart:typed_data';

import 'package:core/src/crypto/certificates.dart';
import 'package:core/src/crypto/crypto_provider.dart';
import 'package:core/src/crypto/signed_message.dart';
import 'package:core/src/errors.dart';
import 'package:core/src/util/bytes.dart';
import 'package:protocol/protocol.dart' as pb;

/// Версии протокола, которые поддерживает эта сборка (protocol.md,
/// раздел 2).
const List<int> supportedProtocolVersions = [1];

/// Отозванные устройства (protocol.md, раздел 4.7): узел получает отзывы
/// от координатора (`ListRevocations`) и не принимает отозванных клиентов.
abstract interface class RevokedDevices {
  bool isRevoked(Uint8List deviceSign);
}

/// Своя сторона канала: роль, статический ключ Noise и сертификат с ним.
final class LocalPeer {
  new({
    required this.role,
    required this.staticKey,
    required this.certificate,
    this.software = '',
    this.versions = supportedProtocolVersions,
  });

  final pb.PeerRole role;

  /// `device_dh` клиента или `node_dh` узла.
  final X25519KeyPair staticKey;

  /// `Signed` с `DeviceCertificate` или `NodeCertificate`.
  final pb.Signed certificate;

  /// Для журнала собеседника, например `node 0.3.0`.
  final String software;

  final List<int> versions;

  pb.Hello hello() => pb.Hello(
    versions: versions,
    role: role,
    certificate: certificate,
    software: software,
  );
}

/// Кого принимать (protocol.md, раздел 3.2).
final class PeerPolicy {
  new({required this.roles, this.expectedNodeId, this.revoked});

  /// Клиент подключается к узлу [nodeId] из ответа координатора.
  new node(Uint8List nodeId)
    : roles = const {pb.PeerRole.PEER_ROLE_NODE},
      expectedNodeId = nodeId,
      revoked = null;

  /// Узел принимает клиентов и другие узлы (ремонт, этап 4).
  new anyone({this.revoked})
    : roles = const {pb.PeerRole.PEER_ROLE_CLIENT, pb.PeerRole.PEER_ROLE_NODE},
      expectedNodeId = null;

  final Set<pb.PeerRole> roles;

  /// `node_id`, который обязан быть в сертификате узла.
  final Uint8List? expectedNodeId;

  /// Проверка отзыва сертификатов устройств.
  final RevokedDevices? revoked;
}

/// Проверенный собеседник.
final class PeerIdentity {
  new({
    required this.role,
    required this.accountId,
    required this.signKey,
    required this.noiseKey,
    required this.version,
    required this.software,
    this.certificate,
  });

  final pb.PeerRole role;

  /// Учётная запись из сертификата (владелец узла или устройства).
  final Uint8List accountId;

  /// `device_sign` клиента или `node_id` узла: им связаны талоны
  /// (`FragmentTicket.device_sign`) и размещение.
  final Uint8List signKey;

  /// Статический ключ Noise собеседника.
  final Uint8List noiseKey;

  /// Выбранная версия протокола.
  final int version;

  final String software;

  /// Сертификат из `Hello`: по нему клиент проверяет владельца узла из
  /// ответа координатора (protocol.md, раздел 5).
  final pb.Signed? certificate;

  bool get isClient => role == pb.PeerRole.PEER_ROLE_CLIENT;
  bool get isNode => role == pb.PeerRole.PEER_ROLE_NODE;
}

/// Проверка `Hello` собеседника (protocol.md, раздел 3.2).
abstract final class PeerVerifier {
  /// Наибольшая общая версия или `null`.
  static int? selectVersion(List<int> local, List<int> remote) {
    int? best;
    for (final v in remote) {
      if (local.contains(v) && (best == null || v > best)) best = v;
    }
    return best;
  }

  /// Проверяет [hello], пришедший по Noise со статическим ключом
  /// [remoteStatic]. Нет общей версии — [PeerRejection.versionUnsupported];
  /// остальные отказы — свои [PeerRejection].
  static Future<PeerIdentity> verify(
    CryptoProvider crypto,
    pb.Hello hello, {
    required Uint8List remoteStatic,
    required PeerPolicy policy,
    List<int> versions = supportedProtocolVersions,
  }) async {
    if (!policy.roles.contains(hello.role)) {
      throw PeerRejectedException(
        PeerRejection.role,
        detail: 'роль ${hello.role.value}',
      );
    }
    if (!hello.hasCertificate()) {
      throw const PeerRejectedException(
        PeerRejection.certificate,
        detail: 'нет сертификата',
      );
    }
    final (accountId, signKey, dhKey) = await _openCertificate(
      crypto,
      hello.role,
      hello.certificate,
    );
    if (!constantTimeEquals(dhKey, remoteStatic)) {
      throw const PeerRejectedException(PeerRejection.keyMismatch);
    }
    final expected = policy.expectedNodeId;
    if (expected != null && !constantTimeEquals(signKey, expected)) {
      throw const PeerRejectedException(PeerRejection.unexpectedNode);
    }
    if (hello.role == pb.PeerRole.PEER_ROLE_CLIENT &&
        (policy.revoked?.isRevoked(signKey) ?? false)) {
      throw const PeerRejectedException(PeerRejection.revoked);
    }
    final version = selectVersion(versions, hello.versions);
    if (version == null) {
      throw PeerRejectedException(
        PeerRejection.versionUnsupported,
        detail: 'собеседник: ${hello.versions.join(', ')}',
      );
    }
    return PeerIdentity(
      role: hello.role,
      accountId: accountId,
      signKey: signKey,
      noiseKey: Uint8List.fromList(remoteStatic),
      version: version,
      software: hello.software,
      certificate: hello.certificate,
    );
  }

  /// `(account_id, ключ подписи, ключ X25519)` из сертификата: подпись
  /// ключом учётной записи из самого сертификата, ключи по 32 байта.
  static Future<(Uint8List, Uint8List, Uint8List)> _openCertificate(
    CryptoProvider crypto,
    pb.PeerRole role,
    pb.Signed certificate,
  ) async {
    try {
      if (role == pb.PeerRole.PEER_ROLE_NODE) {
        final cert = await NodeCertificates.open(crypto, certificate);
        return (
          Uint8List.fromList(cert.accountId),
          Uint8List.fromList(cert.nodeId),
          Uint8List.fromList(cert.nodeDh),
        );
      }
      final cert = await SignedMessages.open(
        crypto,
        certificate,
        context: DeviceCertificates.signingContext,
        object: DeviceCertificates.signingContext,
        parse: pb.DeviceCertificate.fromBuffer,
      );
      if (!constantTimeEquals(cert.accountId, certificate.signer) ||
          cert.deviceSign.length != CryptoProvider.keyLength ||
          cert.deviceDh.length != CryptoProvider.keyLength) {
        throw const PeerRejectedException(
          PeerRejection.certificate,
          detail: 'поля сертификата устройства',
        );
      }
      return (
        Uint8List.fromList(cert.accountId),
        Uint8List.fromList(cert.deviceSign),
        Uint8List.fromList(cert.deviceDh),
      );
    } on DataFormatException catch (e) {
      throw PeerRejectedException(PeerRejection.certificate, detail: e.message);
    } on IntegrityException catch (e) {
      throw PeerRejectedException(PeerRejection.certificate, detail: e.message);
    }
  }
}
