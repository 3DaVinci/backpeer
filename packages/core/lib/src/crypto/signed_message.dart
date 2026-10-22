import 'dart:typed_data';

import 'package:core/src/crypto/crypto_provider.dart';
import 'package:core/src/crypto/signing.dart';
import 'package:core/src/errors.dart';
import 'package:core/src/snapshot/manifest_objects.dart';
import 'package:protobuf/protobuf.dart';
import 'package:protocol/protocol.dart' as pb;

/// Сообщения `fs.v1.Signed`: сертификаты, отзывы, талоны (protocol.md,
/// раздел 6). Подпись — Ed25519 над `"fs/v1/sign/<контекст>" || 0x00 ||
/// body`.
abstract final class SignedMessages {
  /// Подписывает [message] ключом [key] в контексте [context].
  static Future<pb.Signed> sign(
    CryptoProvider crypto,
    Ed25519KeyPair key,
    String context,
    GeneratedMessage message,
  ) async {
    final body = message.writeToBuffer();
    return pb.Signed(
      body: body,
      signer: key.publicKey,
      signature: await crypto.ed25519Sign(key, signingInput(context, body)),
    );
  }

  /// Проверяет подпись [signed] ключом из `signer` и разбирает тело.
  /// Битые поля и тело — [DataFormatException] (`object`: [object]),
  /// неверная подпись — [IntegrityException]. Кто должен был подписать,
  /// проверяет вызывающий.
  static Future<T> open<T extends GeneratedMessage>(
    CryptoProvider crypto,
    pb.Signed signed, {
    required String context,
    required String object,
    required T Function(List<int> body) parse,
  }) async {
    final signer = Uint8List.fromList(signed.signer);
    final signature = Uint8List.fromList(signed.signature);
    if (signer.length != CryptoProvider.keyLength ||
        signature.length != CryptoProvider.ed25519SignatureLength) {
      throw DataFormatException(
        object: object,
        problem: FormatProblem.invalidField,
        detail: 'signer или signature неверной длины',
      );
    }
    final body = Uint8List.fromList(signed.body);
    final valid = await crypto.ed25519Verify(
      publicKey: signer,
      message: signingInput(context, body),
      signature: signature,
    );
    if (!valid) {
      throw IntegrityException(object: object, check: IntegrityCheck.signature);
    }
    return ManifestObjects.parseMessage<T>(object, () => parse(body));
  }
}
