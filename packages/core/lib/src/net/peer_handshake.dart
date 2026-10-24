import 'dart:async';
import 'dart:typed_data';

import 'package:core/src/crypto/crypto_provider.dart';
import 'package:core/src/errors.dart';
import 'package:core/src/net/byte_connection.dart';
import 'package:core/src/net/frames.dart';
import 'package:core/src/net/noise.dart';
import 'package:core/src/net/peer_identity.dart';
import 'package:core/src/net/secure_channel.dart';
import 'package:core/src/snapshot/manifest_objects.dart';
import 'package:meta/meta.dart';
import 'package:protocol/protocol.dart' as pb;

/// Рукопожатие Noise XX с обменом `Hello` и проверкой собеседника
/// (protocol.md, разделы 3.1–3.2):
///
/// 1. инициатор → отвечающий: `e`, полезная нагрузка пустая;
/// 2. отвечающий → инициатор: `e, ee, s, es` и `Hello` отвечающего;
/// 3. инициатор → отвечающий: `s, se` и `Hello` инициатора.
///
/// Любой отказ — закрытие соединения без ответа и
/// [PeerRejectedException]. Исключение — нет общей версии протокола:
/// рукопожатие доводится до конца, сторона отправляет `PeerMessage.error`
/// с `ERROR_CODE_VERSION_UNSUPPORTED` и закрывает соединение.
abstract final class PeerHandshake {
  /// Сколько ждать рукопожатия целиком.
  static const defaultTimeout = Duration(seconds: 15);

  /// Подключающаяся сторона (клиент к узлу, узел к узлу при ремонте).
  static Future<SecureChannel> initiate(
    CryptoProvider crypto,
    ByteConnection connection, {
    required LocalPeer local,
    required PeerPolicy policy,
    Duration timeout = defaultTimeout,
    @visibleForTesting X25519KeyPair? ephemeral,
    @visibleForTesting int rekeyInterval = NoiseFrames.rekeyInterval,
  }) => _run(
    crypto,
    connection,
    initiator: true,
    local: local,
    policy: policy,
    timeout: timeout,
    ephemeral: ephemeral,
    rekeyInterval: rekeyInterval,
  );

  /// Принимающая сторона (узел).
  static Future<SecureChannel> respond(
    CryptoProvider crypto,
    ByteConnection connection, {
    required LocalPeer local,
    required PeerPolicy policy,
    Duration timeout = defaultTimeout,
    @visibleForTesting X25519KeyPair? ephemeral,
    @visibleForTesting int rekeyInterval = NoiseFrames.rekeyInterval,
  }) => _run(
    crypto,
    connection,
    initiator: false,
    local: local,
    policy: policy,
    timeout: timeout,
    ephemeral: ephemeral,
    rekeyInterval: rekeyInterval,
  );

  static Future<SecureChannel> _run(
    CryptoProvider crypto,
    ByteConnection connection, {
    required bool initiator,
    required LocalPeer local,
    required PeerPolicy policy,
    required Duration timeout,
    required X25519KeyPair? ephemeral,
    required int rekeyInterval,
  }) async {
    final reader = NoiseFrameReader(connection.input);
    NoiseHandshake? handshake;
    void fail() {
      connection.destroy();
      handshake?.dispose();
      unawaited(reader.cancel());
    }

    Future<SecureChannel> steps() async {
      final hs = handshake = await NoiseHandshake.start(
        crypto,
        initiator: initiator,
        staticKey: local.staticKey,
        ephemeral: ephemeral,
      );
      final hello = local.hello().writeToBuffer();
      pb.Hello remoteHello;
      if (initiator) {
        await _send(connection, await hs.writeMessage(Uint8List(0)));
        remoteHello = _parseHello(await hs.readMessage(await _next(reader)));
      } else {
        final first = await hs.readMessage(await _next(reader));
        if (first.isNotEmpty) {
          throw const PeerRejectedException(
            PeerRejection.handshake,
            detail: 'непустая нагрузка сообщения 1',
          );
        }
        await _send(connection, await hs.writeMessage(hello));
        remoteHello = _parseHello(await hs.readMessage(await _next(reader)));
      }
      PeerIdentity? identity;
      PeerRejectedException? noVersion;
      try {
        identity = await PeerVerifier.verify(
          crypto,
          remoteHello,
          remoteStatic: hs.remoteStatic!,
          policy: policy,
          versions: local.versions,
        );
      } on PeerRejectedException catch (e) {
        if (e.reason != PeerRejection.versionUnsupported) rethrow;
        noVersion = e;
      }
      if (initiator) await _send(connection, await hs.writeMessage(hello));
      final keys = hs.finish();
      if (noVersion != null) {
        final encoder = ChannelEncoder(keys.send, rekeyInterval: rekeyInterval);
        connection.add(
          encoder.encode(
            pb.PeerMessage(
              error: pb.Error(
                code: pb.ErrorCode.ERROR_CODE_VERSION_UNSUPPORTED,
                message: 'версии: ${local.versions.join(', ')}',
              ),
            ).writeToBuffer(),
          ),
        );
        keys.dispose();
        unawaited(reader.cancel());
        await connection.close();
        throw noVersion;
      }
      return SecureChannel(
        connection,
        reader,
        keys,
        identity!,
        rekeyInterval: rekeyInterval,
      );
    }

    try {
      return await steps().timeout(timeout);
    } on TimeoutException {
      fail();
      throw const PeerRejectedException(PeerRejection.timeout);
    } on PeerRejectedException catch (e) {
      // Нет общей версии: соединение уже закрыто после ответа.
      if (e.reason != PeerRejection.versionUnsupported) fail();
      rethrow;
    } on CoreException catch (e) {
      fail();
      throw PeerRejectedException(PeerRejection.handshake, detail: e.message);
    } on Object {
      fail();
      rethrow;
    }
  }

  static Future<void> _send(ByteConnection connection, Uint8List message) {
    connection.add(NoiseFrames.frame(message));
    return connection.flush();
  }

  static Future<Uint8List> _next(NoiseFrameReader reader) async =>
      await reader.next() ??
      (throw const PeerRejectedException(
        PeerRejection.handshake,
        detail: 'соединение закрыто',
      ));

  static pb.Hello _parseHello(Uint8List payload) {
    try {
      return ManifestObjects.parseMessage(
        'hello',
        () => pb.Hello.fromBuffer(payload),
      );
    } on DataFormatException catch (e) {
      throw PeerRejectedException(PeerRejection.hello, detail: e.message);
    }
  }
}
