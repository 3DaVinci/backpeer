// Векторы автообновления test-vectors/updates/updates.json
// (docs/spec/updates.md, раздел 9; генератор tool/updates/vectors.dart):
// подпись манифеста и хэш пакета должны сходиться у любой реализации.

import 'dart:convert';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:test/test.dart';
import 'package:test_vectors/test_vectors.dart';

void main() {
  late CryptoProvider crypto;
  setUpAll(() async => crypto = await SodiumCryptoProvider.load());

  for (final c in vectorCases(loadVectors('updates/updates.json'))) {
    test(c['name']! as String, () async {
      switch (c['name']) {
        case 'manifest':
          final manifest = c['manifest']! as String;
          final signer = hexToBytes(c['signer']! as String);
          final signature = hexToBytes(c['signature']! as String);
          await UpdateManifest.verifySignature(
            crypto,
            bytes: Uint8List.fromList(utf8.encode(manifest)),
            signature: signature,
            acceptedKeys: [signer],
          );
          final parsed = UpdateManifest.parse(manifest);
          expect(parsed.signer, signer);
        case 'package-hash':
          final package = hexToBytes(c['package']! as String);
          expect(bytesToHex(crypto.blake2b256(package)), c['sha256']);
        default:
          fail('неизвестный случай ${c['name']}');
      }
    });
  }
}
