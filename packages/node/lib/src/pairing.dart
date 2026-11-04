import 'package:core/core.dart';
import 'package:protocol/protocol.dart' as pb;
import 'package:qr/qr.dart';

/// Сведения о начатой привязке узла к учётной записи.
final class PairingSession {
  const new({
    required this.code,
    required this.expiresAt,
    required this.fingerprint,
  });

  /// Одноразовый код, который узел показывает владельцу.
  final String code;

  /// Код действует до этого времени.
  final DateTime expiresAt;

  /// Отпечаток ключей узла для сверки на обоих экранах.
  final String fingerprint;
}

/// Привязка узла к учётной записи без ввода фразы восстановления (задачи
/// 6.1.1, 6.1.2; protocol.md, раздел 4.17). Узел показывает одноразовый
/// код, владелец вводит его на устройстве, где уже вошёл, и подписывает
/// `NodeCertificate`; узел забирает его у координатора.
final class NodePairing {
  new(this.client, this.crypto);

  final CoordinatorClient client;
  final CryptoProvider crypto;

  static const pollInterval = Duration(seconds: 2);

  /// Начинает привязку ключей [keys] и возвращает код для показа.
  Future<PairingSession> start(DeviceKeys keys) async {
    final response = await client.nodePairStart(
      pb.NodePairStartRequest(nodeDh: keys.dh.publicKey),
      nodeKey: keys.sign,
    );
    return PairingSession(
      code: response.code,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        response.expiresAtUnixMs.toInt(),
      ),
      fingerprint: nodeFingerprint(
        crypto,
        nodeId: keys.sign.publicKey,
        nodeDh: keys.dh.publicKey,
      ),
    );
  }

  /// Ждёт, пока владелец подпишет сертификат; возвращает его или `null`,
  /// если код просрочен или привязка отменена.
  Future<pb.Signed?> waitForCertificate(DeviceKeys keys) async {
    for (;;) {
      final status = await client.nodePairStatus(
        pb.NodePairStatusRequest(),
        nodeKey: keys.sign,
      );
      switch (status.status) {
        case pb.NodePairStatus.NODE_PAIR_STATUS_SIGNED:
          return status.nodeCertificate;
        case pb.NodePairStatus.NODE_PAIR_STATUS_EXPIRED:
          return null;
        case pb.NodePairStatus.NODE_PAIR_STATUS_PENDING:
        case pb.NodePairStatus.NODE_PAIR_STATUS_UNSPECIFIED:
          await Future<void>.delayed(pollInterval);
      }
    }
  }
}

/// Содержимое QR-кода привязки: URI `backpeer:pair:<code>` (приложение и
/// CLI позже читают его сканером).
String pairQrContent(String code) => 'backpeer:pair:$code';

/// QR-код [text] в терминале: блоки «██» и «  » с тихой зоной. Символы в
/// терминале выше, чем шире, поэтому каждый модуль занимает два столбца.
String renderPairQr(String text) {
  final image = QrImage(QrCode(payload: QrPayload.fromString(text)));
  final n = image.moduleCount;
  const quiet = 2;
  const dark = '██';
  const light = '  ';
  final buffer = StringBuffer();
  for (var y = -quiet; y < n + quiet; y++) {
    for (var x = -quiet; x < n + quiet; x++) {
      final inside = x >= 0 && x < n && y >= 0 && y < n;
      buffer.write(inside && image.isDark(y, x) ? dark : light);
    }
    buffer.writeln();
  }
  return buffer.toString();
}
