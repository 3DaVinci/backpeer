import 'dart:typed_data';

import 'package:core/src/coordinator/coordinator_client.dart';
import 'package:core/src/crypto/account_keys.dart';
import 'package:core/src/crypto/crypto_provider.dart';
import 'package:core/src/crypto/key_bundle.dart';
import 'package:core/src/crypto/password_login.dart';
import 'package:core/src/errors.dart';
import 'package:core/src/util/bytes.dart';
import 'package:fixnum/fixnum.dart';
import 'package:protocol/protocol.dart' as pb;

/// Вход по паролю на новом устройстве (protocol.md, раздел 4.7; crypto.md,
/// раздел 4.4): параметры Argon2id с координатора (в пределах разбора
/// KeyBundle), `AUTH`, доказательство на текущее время, KeyBundle,
/// расшифровка тем же выводом `KEK`. Возвращает ключи учётной записи и
/// KeyBundle с координатора.
///
/// Неверное имя или пароль, учётная запись без копии мастер-ключа —
/// [CoordinatorException] с `UNAUTHENTICATED`; пауза после неудач —
/// `RATE_LIMITED`. KeyBundle, который не открывается тем же паролем или
/// принадлежит другой учётной записи, — [IntegrityException].
Future<(AccountKeys, KeyBundle)> loginWithPassword(
  CoordinatorClient client,
  CryptoProvider crypto, {
  required String login,
  required String password,
  DateTime Function()? clock,
}) async {
  final name = LoginName.require(login);
  final params = await client.getLoginParams(
    pb.GetLoginParamsRequest(login: name),
  );
  final argon2 = Argon2Params(
    memoryKiB: params.memoryKib,
    iterations: params.iterations,
    parallelism: params.parallelism,
  );
  KeyBundle.checkParams(argon2);
  final salt = Uint8List.fromList(params.salt);
  if (salt.length != KeyBundle.saltLength) {
    throw const DataFormatException(
      object: 'login-params',
      problem: FormatProblem.invalidField,
      detail: 'соль — 16 байт',
    );
  }
  final derived = await PasswordKeys.derive(
    crypto,
    password: password,
    salt: salt,
    params: argon2,
  );
  try {
    final loginKey = await PasswordLogin.loginKey(crypto, derived);
    final time = (clock ?? DateTime.now)().millisecondsSinceEpoch;
    final proof = await PasswordLogin.prove(
      crypto,
      loginKey,
      login: name,
      timeMs: time,
    );
    loginKey.seed.dispose();
    final response = await client.getKeyBundle(
      pb.GetKeyBundleRequest(
        login: name,
        timeUnixMs: Int64(time),
        authProof: proof,
      ),
    );
    final bundle = KeyBundle.parse(Uint8List.fromList(response.keyBundle));
    // KeyBundle под той же солью и параметрами, что выдал GetLoginParams:
    // иначе KEK из этого вывода его не откроет.
    if (!constantTimeEquals(bundle.salt, salt) ||
        bundle.params.memoryKiB != argon2.memoryKiB ||
        bundle.params.iterations != argon2.iterations) {
      throw const IntegrityException(
        object: 'key-bundle',
        check: IntegrityCheck.objectId,
      );
    }
    return (await bundle.unlockWith(crypto, derived), bundle);
  } finally {
    derived.dispose();
  }
}
