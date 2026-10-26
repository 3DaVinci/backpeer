import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:core/src/crypto/crypto_provider.dart';
import 'package:core/src/crypto/secret_bytes.dart';
import 'package:core/src/errors.dart';
import 'package:core/src/net/byte_connection.dart';
import 'package:core/src/net/frames.dart';
import 'package:core/src/net/noise.dart';
import 'package:core/src/net/secure_channel.dart';
import 'package:core/src/util/bytes.dart';

/// Итог [NoiseProbe.probe].
enum NoiseProbeResult {
  /// Ответил владелец ожидаемого статического ключа.
  reachable,

  /// Соединение отклонено (порт закрыт).
  refused,

  /// Соединение или ответ не пришли вовремя.
  timeout,

  /// Ответил кто-то другой: другой ключ, не Noise, соединение закрыто.
  wrongPeer,
}

/// Проверка достижимости узла (задача 3.5.1; protocol.md, раздел 4.9):
/// первые два сообщения рукопожатия Noise XX и сверка статического ключа
/// отвечающего. Третье сообщение не отправляется, соединение закрывается:
/// проверяющему не нужен сертификат, а отвечающий тратит на проверку одно
/// рукопожатие.
///
/// Ключ подтверждён: нагрузка сообщения 2 зашифрована ключом, в который
/// вошёл DH `es`, и расшифровать её можно, только если отвечающий владеет
/// закрытой частью показанного статического ключа.
abstract final class NoiseProbe {
  static Future<NoiseProbeResult> probe(
    CryptoProvider crypto, {
    required InternetAddress address,
    required int port,
    required Uint8List expectedStatic,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final deadline = Stopwatch()..start();
    final Socket socket;
    try {
      socket = await Socket.connect(address, port, timeout: timeout);
    } on SocketException catch (e) {
      return _isTimeout(e)
          ? NoiseProbeResult.timeout
          : NoiseProbeResult.refused;
    }
    try {
      final rest = timeout - deadline.elapsed;
      if (rest <= Duration.zero) return NoiseProbeResult.timeout;
      return await respondsWith(
        crypto,
        SocketConnection(socket),
        expectedStatic,
      ).timeout(rest);
    } on TimeoutException {
      return NoiseProbeResult.timeout;
    } finally {
      socket.destroy();
    }
  }

  /// Сообщения 1 и 2 по уже установленному [connection]: показал ли
  /// отвечающий ключ [expectedStatic]. Соединение не закрывает.
  static Future<NoiseProbeResult> respondsWith(
    CryptoProvider crypto,
    ByteConnection connection,
    Uint8List expectedStatic,
  ) async {
    // Свой статический ключ нужен только для сообщения 3, которого не
    // будет: одноразовый.
    final local = await crypto.x25519FromSecret(
      SecretBytes.adopt(crypto.randomBytes(Noise.dhLength)),
    );
    final hs = await NoiseHandshake.start(
      crypto,
      initiator: true,
      staticKey: local,
    );
    final reader = NoiseFrameReader(connection.input);
    try {
      connection.add(NoiseFrames.frame(await hs.writeMessage(Uint8List(0))));
      await connection.flush();
      final second = await reader.next();
      if (second == null) return NoiseProbeResult.wrongPeer;
      await hs.readMessage(second);
      final remote = hs.remoteStatic;
      return remote != null && constantTimeEquals(remote, expectedStatic)
          ? NoiseProbeResult.reachable
          : NoiseProbeResult.wrongPeer;
    } on CoreException {
      return NoiseProbeResult.wrongPeer;
    } on SocketException {
      return NoiseProbeResult.wrongPeer;
    } finally {
      hs.dispose();
      local.secretKey.dispose();
      unawaited(reader.cancel().catchError((_) {}));
    }
  }

  static bool _isTimeout(SocketException e) =>
      e.osError == null || e.message.contains('timed out');
}
