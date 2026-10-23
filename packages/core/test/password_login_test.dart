// Вход по паролю (protocol.md, раздел 4.7; crypto.md, раздел 4.4) на
// векторах tool/protocol_vectors.py — обеими реализациями CryptoProvider.

import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:protocol/protocol.dart' as pb;
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

  group('KeyCopy', () {
    test('копия открывается паролем, verifier — ключ входа из AUTH', () async {
      final crypto = await SodiumCryptoProvider.load();
      final keys = await AccountKeys.fromMasterKey(
        SecretBytes(Uint8List(32)..[0] = 5),
        crypto,
      );
      const params = Argon2Params(memoryKiB: 1024, iterations: 1);
      final copy = await KeyCopy.create(
        crypto,
        keys: keys,
        password: 'пароль',
        params: params,
      );
      expect(copy.enabled, isTrue);
      expect(copy.authVerifier, hasLength(32));
      final bundle = KeyBundle.parse(copy.keyBundle);
      expect(bundle.accountId, keys.accountId);
      final derived = await bundle.deriveKeys(crypto, 'пароль');
      final loginKey = await PasswordLogin.loginKey(crypto, derived);
      expect(loginKey.publicKey, copy.authVerifier);
      expect(
        (await bundle.unlockWith(crypto, derived)).accountId,
        keys.accountId,
      );

      expect(KeyCopy.none.enabled, isFalse);
      expect(KeyCopy.none.keyBundle, isEmpty);
      expect(KeyCopy.none.authVerifier, isEmpty);
    });
  });

  test(
    'NodeCertificates: подпись ключом учётной записи, контекст node-cert',
    () async {
      final crypto = await SodiumCryptoProvider.load();
      final owner = await AccountKeys.fromMasterKey(
        SecretBytes(Uint8List(32)..[0] = 6),
        crypto,
      );
      final nodeId = Uint8List(32)..[0] = 1;
      final signed = await NodeCertificates.issue(
        crypto,
        owner,
        nodeId: nodeId,
        nodeDh: Uint8List(32)..[0] = 2,
        issuedAt: DateTime.utc(2026, 10, 23),
      );
      expect(signed.signer, owner.accountId);
      final cert = await SignedMessages.open(
        crypto,
        signed,
        context: 'node-cert',
        object: 'node-cert',
        parse: pb.NodeCertificate.fromBuffer,
      );
      expect(cert.nodeId, nodeId);
      expect(cert.accountId, owner.accountId);
      await expectLater(
        SignedMessages.open(
          crypto,
          signed,
          context: 'device-cert',
          object: 'device-cert',
          parse: pb.NodeCertificate.fromBuffer,
        ),
        throwsA(isA<IntegrityException>()),
        reason: 'другой контекст',
      );
      expect(
        () => NodeCertificates.issue(
          crypto,
          owner,
          nodeId: Uint8List(31),
          nodeDh: Uint8List(32),
          issuedAt: DateTime.utc(2026),
        ),
        throwsArgumentError,
      );
    },
  );
}
