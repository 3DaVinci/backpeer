// Вход по паролю (protocol.md, раздел 4.7; crypto.md, раздел 4.4) на
// векторах tool/protocol_vectors.py — обеими реализациями CryptoProvider.

import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:test/test.dart';
import 'package:test_vectors/test_vectors.dart';

void main() {
  final providers = <String, Future<CryptoProvider> Function()>{
    'libsodium': SodiumCryptoProvider.load,
    'dart': () async => DartCryptoProvider(),
  };
  final cases = vectorCases(loadVectors('protocol/login.json'));

  for (final MapEntry(key: name, value: load) in providers.entries) {
    group(name, () {
      late CryptoProvider crypto;
      setUpAll(() async => crypto = await load());

      for (final c in cases) {
        final input = c['input']! as Map<String, Object?>;
        final expected = c['expected']! as Map<String, Object?>;
        test(c['name'], () async {
          if (input['operation'] == 'normalize') {
            final login = input['login']! as String;
            expect(LoginName.normalize(login), expected['login']);
            if (expected['login'] == null) {
              expect(
                () => LoginName.require(login),
                throwsA(isA<DataFormatException>()),
              );
            }
            return;
          }
          final keys = await PasswordKeys.derive(
            crypto,
            password: input['password']! as String,
            salt: hexToBytes(input['salt']! as String),
            params: Argon2Params(
              memoryKiB: input['memoryKiB']! as int,
              iterations: input['iterations']! as int,
            ),
          );
          expect(bytesToHex(keys.auth.bytes), expected['auth']);
          final key = await PasswordLogin.loginKey(crypto, keys);
          expect(bytesToHex(key.publicKey), expected['verifier']);
          final login = input['login']! as String;
          final timeMs = input['timeMs']! as int;
          expect(
            bytesToHex(PasswordLogin.message(login: login, timeMs: timeMs)),
            expected['message'],
          );
          final proof = await PasswordLogin.prove(
            crypto,
            key,
            login: login,
            timeMs: timeMs,
          );
          expect(bytesToHex(proof), expected['proof']);
          final verifier = hexToBytes(expected['verifier']! as String);
          expect(
            await PasswordLogin.verify(
              crypto,
              verifier: verifier,
              login: login.toUpperCase(),
              timeMs: timeMs,
              proof: proof,
            ),
            isTrue,
            reason: 'регистр имени не важен',
          );
          for (final (l, t) in [(login, timeMs + 1), ('${login}x', timeMs)]) {
            expect(
              await PasswordLogin.verify(
                crypto,
                verifier: verifier,
                login: l,
                timeMs: t,
                proof: proof,
              ),
              isFalse,
            );
          }
          expect(
            await PasswordLogin.verify(
              crypto,
              verifier: Uint8List(31),
              login: login,
              timeMs: timeMs,
              proof: proof,
            ),
            isFalse,
          );
          keys.dispose();
        });
      }
    });
  }
}
