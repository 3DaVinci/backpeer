import 'dart:convert';
import 'dart:typed_data';

import 'package:core/src/crypto/account_keys.dart';
import 'package:core/src/crypto/crypto_provider.dart';
import 'package:core/src/crypto/key_bundle.dart';
import 'package:core/src/crypto/secret_bytes.dart';
import 'package:core/src/crypto/signing.dart';
import 'package:core/src/errors.dart';

/// Имя для входа по паролю (protocol.md, раздел 4.7): 3–32 символа
/// `a–z`, `0–9`, `.`, `_`, `-`, первый — буква или цифра, без учёта
/// регистра.
abstract final class LoginName {
  static const minLength = 3;
  static const maxLength = 32;

  static final _pattern = RegExp(r'^[a-z0-9][a-z0-9._-]{2,31}$');

  /// Каноническая запись (нижний регистр) или `null`, если имя
  /// недопустимо. Не-ASCII отклоняется до приведения регистра: знак
  /// Кельвина `K` в нижнем регистре — ASCII `k`.
  static String? normalize(String login) {
    if (login.codeUnits.any((c) => c > 0x7F)) return null;
    final lowered = login.toLowerCase();
    return _pattern.hasMatch(lowered) ? lowered : null;
  }

  /// Как [normalize], но недопустимое имя — [DataFormatException].
  static String require(String login) =>
      normalize(login) ??
      (throw const DataFormatException(
        object: 'login',
        problem: FormatProblem.invalidField,
        detail: 'имя для входа: 3–32 символа a–z, 0–9, «.», «_», «-»',
      ));
}

/// Вход по паролю на новом устройстве (crypto.md, раздел 4.4): из `AUTH`
/// выводится ключ входа Ed25519, координатор хранит его открытую часть
/// (`auth_verifier`) и проверяет подпись `auth_proof`.
abstract final class PasswordLogin {
  static const signingContext = 'login';

  /// Ключ входа: Ed25519 с seed = `AUTH`.
  static Future<Ed25519KeyPair> loginKey(
    CryptoProvider crypto,
    PasswordKeys keys,
  ) => crypto.ed25519FromSeed(SecretBytes(keys.auth.bytes));

  /// Подписываемое сообщение:
  /// `"fs/v1/sign/login" || 0x00 || u64be(time_ms) || login`.
  static Uint8List message({required String login, required int timeMs}) {
    final name = ascii.encode(LoginName.require(login));
    if (timeMs < 0) throw ArgumentError.value(timeMs, 'timeMs');
    final data = Uint8List(8 + name.length)..setAll(8, name);
    ByteData.sublistView(data).setUint64(0, timeMs);
    return signingInput(signingContext, data);
  }

  /// `auth_proof` для `GetKeyBundle`.
  static Future<Uint8List> prove(
    CryptoProvider crypto,
    Ed25519KeyPair loginKey, {
    required String login,
    required int timeMs,
  }) => crypto.ed25519Sign(loginKey, message(login: login, timeMs: timeMs));

  /// Проверка `auth_proof` под [verifier] (сторона координатора).
  static Future<bool> verify(
    CryptoProvider crypto, {
    required Uint8List verifier,
    required String login,
    required int timeMs,
    required Uint8List proof,
  }) async {
    if (verifier.length != CryptoProvider.keyLength ||
        proof.length != CryptoProvider.ed25519SignatureLength) {
      return false;
    }
    return await crypto.ed25519Verify(
      publicKey: verifier,
      message: message(login: login, timeMs: timeMs),
      signature: proof,
    );
  }
}

/// Копия мастер-ключа на координаторе (crypto.md, разделы 4.1, 4.4;
/// модель угроз, К-3): поля `key_bundle` и `auth_verifier` запросов
/// `RegisterAccount` и `SetKeyBundle`. [KeyCopy.none] — режим без копии:
/// оба поля пусты, координатор удаляет KeyBundle и `auth_verifier`, и
/// войти на новом устройстве можно только по фразе. Переключение в обе
/// стороны — `SetKeyBundle` с [create] или [none] (задача 2.4.3).
final class KeyCopy {
  const new _(this.keyBundle, this.authVerifier);

  /// Режим без копии мастер-ключа на координаторе.
  static final KeyCopy none = KeyCopy._(Uint8List(0), Uint8List(0));

  /// Копия ключей [keys] под [password]: новый KeyBundle со случайной
  /// солью и открытый ключ входа из его `AUTH`.
  static Future<KeyCopy> create(
    CryptoProvider crypto, {
    required AccountKeys keys,
    required String password,
    Argon2Params params = const Argon2Params(),
  }) async {
    final (bundle, derived) = await KeyBundle.createDerived(
      crypto,
      keys: keys,
      password: password,
      params: params,
    );
    try {
      final loginKey = await PasswordLogin.loginKey(crypto, derived);
      return KeyCopy._(bundle.toBytes(), loginKey.publicKey);
    } finally {
      derived.dispose();
    }
  }

  /// Сериализованный KeyBundle или пусто.
  final Uint8List keyBundle;

  /// Открытый ключ входа (32 байта) или пусто.
  final Uint8List authVerifier;

  /// Копия есть: вход по паролю на новом устройстве возможен.
  bool get enabled => keyBundle.isNotEmpty;
}
