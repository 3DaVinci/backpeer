import 'dart:convert';
import 'dart:typed_data';

import 'package:core/src/crypto/crypto_provider.dart';
import 'package:core/src/crypto/signing.dart';
import 'package:core/src/errors.dart';
import 'package:core/src/util/bytes.dart';

/// Подпись запроса к координатору, заголовок `FS-Auth`
/// (protocol.md, раздел 4.2): `<ключ hex>.<время в мс>.<подпись hex>`.
///
/// Окно времени, известность ключа и защиту от повтора проверяет
/// координатор: это его состояние, а не формат.
final class RequestAuth {
  const new _({
    required this.signer,
    required this.timeMs,
    required this.signature,
  });

  /// Разбор заголовка. Любое отклонение от формата —
  /// [DataFormatException] (`object: fs-auth`).
  factory parse(String header) {
    // Заголовок приходит от кого угодно: длину проверяем до регулярного
    // выражения.
    final match = header.length <= 64 + 1 + 15 + 1 + 128
        ? _header.firstMatch(header)
        : null;
    if (match == null) {
      throw const DataFormatException(
        object: 'fs-auth',
        problem: FormatProblem.invalidField,
        detail: 'заголовок не в формате <ключ>.<время>.<подпись>',
      );
    }
    return RequestAuth._(
      signer: hexToBytes(match.group(1)!),
      timeMs: int.parse(match.group(2)!),
      signature: hexToBytes(match.group(3)!),
    );
  }

  /// Имя заголовка (HTTP-заголовки не зависят от регистра).
  static const headerName = 'FS-Auth';

  /// Допустимое расхождение часов клиента и координатора.
  static const maxClockSkew = Duration(minutes: 5);

  /// Время — не больше 15 десятичных цифр.
  static const maxTimeMs = 999999999999999;

  static final _header = RegExp(
    r'^([0-9a-f]{64})\.(0|[1-9][0-9]{0,14})\.([0-9a-f]{128})$',
  );

  /// Открытый ключ Ed25519 подписавшего, 32 байта.
  final Uint8List signer;

  /// Время подписи, миллисекунды Unix.
  final int timeMs;

  /// Подпись Ed25519, 64 байта.
  final Uint8List signature;

  /// Подписываемое сообщение:
  /// `"fs/v1/sign/api-request" || 0x00 || путь || u64be(время) || H(тело)`.
  static Uint8List message(
    CryptoProvider crypto, {
    required String path,
    required int timeMs,
    required List<int> body,
  }) {
    if (timeMs < 0 || timeMs > maxTimeMs) {
      throw ArgumentError.value(timeMs, 'timeMs', 'вне 0…$maxTimeMs');
    }
    final pathBytes = utf8.encode(path);
    final data = Uint8List(pathBytes.length + 8 + CryptoProvider.hashLength)
      ..setAll(0, pathBytes);
    ByteData.sublistView(data).setUint64(pathBytes.length, timeMs);
    data.setAll(
      pathBytes.length + 8,
      crypto.blake2b256(body is Uint8List ? body : Uint8List.fromList(body)),
    );
    return signingInput('api-request', data);
  }

  /// Подписывает запрос ключом [key]. [timeMs] по умолчанию — текущее
  /// время; при повторе запроса подпись нужна новая (раздел 4.2).
  static Future<RequestAuth> sign(
    CryptoProvider crypto,
    Ed25519KeyPair key, {
    required String path,
    required List<int> body,
    int? timeMs,
  }) async {
    final time = timeMs ?? DateTime.now().millisecondsSinceEpoch;
    final signature = await crypto.ed25519Sign(
      key,
      message(crypto, path: path, timeMs: time, body: body),
    );
    return RequestAuth._(
      signer: Uint8List.fromList(key.publicKey),
      timeMs: time,
      signature: signature,
    );
  }

  /// Проверяет подпись над [path] и [body].
  Future<bool> verify(
    CryptoProvider crypto, {
    required String path,
    required List<int> body,
  }) => crypto.ed25519Verify(
    publicKey: signer,
    message: message(crypto, path: path, timeMs: timeMs, body: body),
    signature: signature,
  );

  /// Значение заголовка `FS-Auth`.
  String toHeader() => '${bytesToHex(signer)}.$timeMs.${bytesToHex(signature)}';
}
