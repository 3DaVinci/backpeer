// Проверка и применение обновлений в приложении (задача 5.8.2): порядок
// «загрузить → проверить → остановить процессы → установить», подменённый
// пакет отклоняется до остановки процессов и установки.

import 'dart:convert';
import 'dart:typed_data';

import 'package:app/src/services/updater.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

Future<String> _okInstall(UpdatePackage package, Uint8List bytes) async => 'ok';

void main() {
  late CryptoProvider crypto;
  late Ed25519KeyPair devKey;
  late Uint8List payload;
  late String manifestJson;

  setUpAll(() async {
    crypto = await SodiumCryptoProvider.load();
    devKey = await crypto.ed25519FromSeed(
      SecretBytes(base64Decode('zLxiViV3qqs870oI1CqKSbYLMDWMzRxpuaXqc0Gemgs=')),
    );
    payload = Uint8List.fromList(List.generate(42, (i) => i));
    manifestJson = jsonEncode({
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
          'url': 'https://u.example/pkg',
          'sha256': bytesToHex(crypto.blake2b256(payload)),
          'size': 42,
        },
      ],
      'signer': base64Encode(devKey.publicKey),
    });
  });

  Updater updater({
    UpdateFetch? fetch,
    Future<String> Function(UpdatePackage, Uint8List)? install,
    Future<void> Function()? restart,
  }) {
    final client = UpdateClient(
      crypto: crypto,
      acceptedKeys: [devKey.publicKey],
      fetch: fetch,
    );
    final installer = _FakeInstaller(install ?? _okInstall);
    return Updater(
      client: client,
      currentVersion: ProductVersion.parse('0.0.2'),
      installId: Uint8List(16),
      platform: UpdatePlatform.linux,
      installer: installer,
      restart: restart ?? () async {},
    );
  }

  test('apply: загрузка и проверка до остановки и установки', () async {
    final order = <String>[];
    final u = updater(
      fetch: (url) async {
        order.add('fetch:${url.path}');
        return payload;
      },
      install: (pkg, bytes) async {
        order.add('install');
        return 'ok';
      },
      restart: () async {
        order.add('restart');
      },
    );
    final manifest = UpdateManifest.parse(manifestJson);
    final result = await u.apply(manifest);
    expect(result, 'ok');
    expect(order, ['fetch:/pkg', 'restart', 'install']);
  });

  test(
    'apply: подменённый пакет отклоняется до остановки и установки',
    () async {
      var restarted = false;
      var installed = false;
      final u = updater(
        fetch: (url) async => Uint8List.fromList([...payload, 0xFF]),
        install: (pkg, bytes) async {
          installed = true;
          return 'ok';
        },
        restart: () async {
          restarted = true;
        },
      );
      final manifest = UpdateManifest.parse(manifestJson);
      await expectLater(u.apply(manifest), throwsA(isA<IntegrityException>()));
      expect(restarted, isFalse);
      expect(installed, isFalse);
    },
  );

  test('apply: нет сборки под платформу', () async {
    final u = updater(fetch: (url) async => payload);
    await expectLater(
      u.apply(
        UpdateManifest.parse(manifestJson.replaceFirst('"linux"', '"windows"')),
      ),
      throwsA(isA<PreconditionException>()),
    );
  });
}

final class _FakeInstaller implements UpdateInstaller {
  new(this._apply);

  final Future<String> Function(UpdatePackage, Uint8List) _apply;

  @override
  String get description => 'тест';

  @override
  Future<String> apply(UpdatePackage package, Uint8List bytes) =>
      _apply(package, bytes);
}
