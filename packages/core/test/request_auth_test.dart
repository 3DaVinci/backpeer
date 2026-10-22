// Подпись запроса к координатору (protocol.md, раздел 4.2) на векторах
// tool/protocol_vectors.py — обеими реализациями CryptoProvider.

import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:test/test.dart';
import 'package:test_vectors/test_vectors.dart';

void main() {
  final providers = <String, Future<CryptoProvider> Function()>{
    'libsodium': SodiumCryptoProvider.load,
    'dart': () async => DartCryptoProvider(),
  };
  final cases = vectorCases(loadVectors('protocol/api-request.json'));

  for (final MapEntry(key: name, value: load) in providers.entries) {
    group(name, () {
      late CryptoProvider crypto;
      setUpAll(() async => crypto = await load());

      for (final c in cases) {
        final input = c['input']! as Map<String, Object?>;
        final expected = c['expected']! as Map<String, Object?>;
        final path = input['path']! as String;
        final body = hexToBytes(input['body']! as String);

        test(c['name'], () async {
          if (input['operation'] == 'sign') {
            final key = await crypto.ed25519FromSeed(
              SecretBytes(hexToBytes(input['seed']! as String)),
            );
            final timeMs = input['timeMs']! as int;
            final message = RequestAuth.message(
              crypto,
              path: path,
              timeMs: timeMs,
              body: body,
            );
            expect(bytesToHex(message), expected['message']);
            final auth = await RequestAuth.sign(
              crypto,
              key,
              path: path,
              body: body,
              timeMs: timeMs,
            );
            expect(bytesToHex(auth.signer), expected['publicKey']);
            expect(bytesToHex(auth.signature), expected['signature']);
            expect(auth.toHeader(), expected['header']);
            expect(await auth.verify(crypto, path: path, body: body), isTrue);
            return;
          }
          final header = input['header']! as String;
          if (expected['error'] == 'format') {
            expect(
              () => RequestAuth.parse(header),
              throwsA(isA<DataFormatException>()),
            );
            return;
          }
          final auth = RequestAuth.parse(header);
          expect(bytesToHex(auth.signer), expected['publicKey']);
          expect(auth.timeMs, expected['timeMs']);
          expect(auth.toHeader(), header);
          expect(
            await auth.verify(crypto, path: path, body: body),
            expected['valid'],
          );
        });
      }
    });
  }

  test('signingInput: метка, 0x00, данные', () {
    expect(
      bytesToHex(signingInput('ticket', Uint8List.fromList([1, 2]))),
      '${bytesToHex('fs/v1/sign/ticket'.codeUnits)}000102',
    );
  });

  test('слишком длинный заголовок — ошибка формата без разбора', () {
    expect(
      () => RequestAuth.parse('a' * 100000),
      throwsA(isA<DataFormatException>()),
    );
  });

  test('время вне диапазона — ошибка программы', () async {
    final crypto = DartCryptoProvider();
    expect(
      () => RequestAuth.message(crypto, path: '/', timeMs: -1, body: []),
      throwsArgumentError,
    );
    expect(
      () => RequestAuth.message(
        crypto,
        path: '/',
        timeMs: RequestAuth.maxTimeMs + 1,
        body: [],
      ),
      throwsArgumentError,
    );
  });
}
