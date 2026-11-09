// Проверка и применение обновлений в приложении (задача 5.8.2): порядок
// «загрузить → проверить → остановить процессы → установить», подменённый
// пакет отклоняется до остановки процессов и установки; платформенные
// установщики (Windows, macOS, AppImage).

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:app/src/services/updater.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

Future<UpdateOutcome> _okInstall(
  UpdatePackage package,
  Uint8List bytes,
) async => const UpdateOutcome(restartRequired: true);

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
    Future<UpdateOutcome> Function(UpdatePackage, Uint8List)? install,
    Future<void> Function()? stop,
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
      stop: stop ?? () async {},
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
        return const UpdateOutcome(restartRequired: true);
      },
      stop: () async {
        order.add('stop');
      },
    );
    final manifest = UpdateManifest.parse(manifestJson);
    final result = await u.apply(manifest);
    expect(result.restartRequired, isTrue);
    expect(order, ['fetch:/pkg', 'stop', 'install']);
  });

  test(
    'apply: подменённый пакет отклоняется до остановки и установки',
    () async {
      var stopped = false;
      var installed = false;
      final u = updater(
        fetch: (url) async => Uint8List.fromList([...payload, 0xFF]),
        install: (pkg, bytes) async {
          installed = true;
          return const UpdateOutcome();
        },
        stop: () async {
          stopped = true;
        },
      );
      final manifest = UpdateManifest.parse(manifestJson);
      await expectLater(u.apply(manifest), throwsA(isA<IntegrityException>()));
      expect(stopped, isFalse);
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

  test('AppImage: заменяет образ, сохраняет права и запускает новую '
      'версию', () async {
    final dir = Directory.systemTemp.createTempSync('fs-appimage-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final image = File('${dir.path}/backpeer.AppImage')
      ..writeAsBytesSync([1, 2, 3]);
    setUnixFileMode(image.path, 0x1ED); // 0755
    String? helper;
    final installer = AppImageInstaller(
      appImage: image.path,
      startHelper: (executable, args) async {
        helper = '$executable ${args.join(' ')}';
      },
    );
    final outcome = await installer.apply(
      UpdatePackage(
        platform: UpdatePlatform.linux,
        arch: null,
        url: Uri.parse('https://u.example/app'),
        sha256: Uint8List(32),
        size: 4,
      ),
      Uint8List.fromList([9, 9, 9, 9]),
    );
    expect(outcome.restartRequired, isTrue);
    expect(image.readAsBytesSync(), [9, 9, 9, 9]);
    expect(image.statSync().mode & 0x1FF, 0x1ED);
    expect(helper, startsWith('/bin/sh -c '));
    expect(helper, contains(image.path));
  }, skip: Platform.isWindows ? 'права POSIX' : false);

  test('Windows: скрипт ждёт приложение, ставит молча и запускает новую '
      'версию', () {
    final script = windowsUpdateScript(
      pid: 42,
      installer: r"C:\Temp\setup's.exe",
      app: r'C:\Apps\backpeer.exe',
      tempDir: r'C:\Temp\upd',
    );
    expect(script, contains('Wait-Process -Id 42'));
    expect(script, contains(r"'C:\Temp\setup''s.exe'"));
    expect(script, contains('/VERYSILENT'));
    expect(script, contains(r"'C:\Apps\backpeer.exe'"));
    expect(script, contains('Remove-Item -LiteralPath'));
  });

  test('macOS: скрипт монтирует .dmg, заменяет .app и открывает его', () {
    final script = macUpdateScript(
      pid: 7,
      dmg: '/tmp/back peer.dmg',
      appBundle: '/Applications/Backpeer.app',
    );
    expect(script, contains("'/tmp/back peer.dmg'"));
    expect(script, contains('hdiutil attach'));
    expect(script, contains("'/Applications/Backpeer.app'"));
    expect(script, contains('ditto '));
    expect(script, contains('open '));
  });
}

final class _FakeInstaller implements UpdateInstaller {
  new(this._apply);

  final Future<UpdateOutcome> Function(UpdatePackage, Uint8List) _apply;

  @override
  String get description => 'тест';

  @override
  bool get needsDownload => true;

  @override
  Future<UpdateOutcome> apply(UpdatePackage package, Uint8List bytes) =>
      _apply(package, bytes);
}
