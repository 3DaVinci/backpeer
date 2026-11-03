// Генератор тестовых векторов автообновления (docs/spec/updates.md,
// раздел 9): подписанный манифест разработки и хэш пакета, чтобы реализация
// на другом языке давала те же байты. Ed25519 с фиксированным seed — подпись
// детерминирована, вывод стабилен.
//
//   dart run tool/updates/vectors.dart > test-vectors/updates/updates.json
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';

Future<void> main() async {
  final crypto = await SodiumCryptoProvider.load();
  final seed = SecretBytes(
    base64Decode('zLxiViV3qqs870oI1CqKSbYLMDWMzRxpuaXqc0Gemgs='),
  );
  final key = await crypto.ed25519FromSeed(seed);

  final package = Uint8List.fromList(List.generate(42, (i) => i));
  final packageSha256 = bytesToHex(crypto.blake2b256(package));

  final manifest = jsonEncode({
    'format': 1,
    'channel': 'stable',
    'version': '0.0.3',
    'minVersion': '0.0.2',
    'releasedAt': '2026-11-03T10:00:00Z',
    'rollout': 1,
    'packages': [
      {
        'platform': 'linux',
        'arch': null,
        'url': 'https://updates.example/backpeer-0.0.3.AppImage',
        'sha256': packageSha256,
        'size': 42,
      },
    ],
    'signer': base64Encode(key.publicKey),
  });
  final signature = await crypto.ed25519Sign(
    key,
    signingInput('updates', Uint8List.fromList(utf8.encode(manifest))),
  );

  stdout.writeln(
    const JsonEncoder.withIndent('  ').convert({
      'spec': 'updates/updates',
      'specVersion': 1,
      'generator': 'tool/updates/vectors.dart',
      'description':
          'Манифест обновлений разработки (docs/spec/updates.md): '
          'подпись Ed25519 над точными байтами манифеста в контексте '
          'fs/v1/sign/updates ключом разработки; пакет — 42 байта 0..41, хэш '
          'BLAKE2b-256.',
      'cases': [
        {
          'name': 'manifest',
          'signer': bytesToHex(key.publicKey),
          'manifest': manifest,
          'signature': bytesToHex(signature),
        },
        {
          'name': 'package-hash',
          'package': bytesToHex(package),
          'sha256': packageSha256,
        },
      ],
    }),
  );
}
