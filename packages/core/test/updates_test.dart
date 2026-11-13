// Автообновление: версии, манифест, подпись, раскатка, загрузка (задача
// 5.8.2, docs/spec/updates.md).

import 'dart:convert';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  late CryptoProvider crypto;
  late Ed25519KeyPair devKey;
  late Ed25519KeyPair otherKey;

  setUpAll(() async {
    crypto = await SodiumCryptoProvider.load();
    devKey = await crypto.ed25519FromSeed(
      SecretBytes(base64Decode('zLxiViV3qqs870oI1CqKSbYLMDWMzRxpuaXqc0Gemgs=')),
    );
    otherKey = await crypto.ed25519FromSeed(
      SecretBytes(Uint8List(32)..[0] = 7),
    );
  });

  String manifestJson({
    String version = '0.0.3',
    String minVersion = '0.0.2',
    String channel = 'stable',
    double rollout = 1,
    List<Object?>? packages,
    String? signer,
    String? nextKey,
  }) {
    final manifest = <String, Object?>{
      'format': 1,
      'channel': channel,
      'version': version,
      'minVersion': minVersion,
      'releasedAt': '2026-11-03T10:00:00Z',
      'rollout': rollout,
      'packages':
          packages ??
          [
            {
              'platform': 'linux',
              'arch': null,
              'url': 'https://updates.example/backpeer-0.0.3.AppImage',
              'sha256': '00' * 32,
              'size': 42,
            },
          ],
      'signer': signer ?? base64Encode(devKey.publicKey),
      'nextUpdatePublicKey': ?nextKey,
    };
    return jsonEncode(manifest);
  }

  Future<Uint8List> sign(String json, {Ed25519KeyPair? key}) =>
      crypto.ed25519Sign(
        key ?? devKey,
        signingInput('updates', Uint8List.fromList(utf8.encode(json))),
      );

  group('ProductVersion', () {
    test('разбирает и сравнивает', () {
      expect(ProductVersion.parse('1.2.3').toString(), '1.2.3');
      expect(
        ProductVersion.parse('1.2.3').compareTo(ProductVersion.parse('1.2.4')),
        lessThan(0),
      );
      expect(
        ProductVersion.parse('2.0.0').compareTo(ProductVersion.parse('1.9.9')),
        greaterThan(0),
      );
      expect(
        ProductVersion.parse('1.2.3') == ProductVersion.parse('1.2.3'),
        isTrue,
      );
    });

    test('отклоняет не SemVer', () {
      for (final bad in ['1.2', 'a.b.c', '1.2.3-rc.1', '', '1.2.', '1..2']) {
        expect(
          () => ProductVersion.parse(bad),
          throwsA(isA<DataFormatException>()),
          reason: bad,
        );
      }
    });
  });

  group('UpdateManifest.parse', () {
    test('разбирает корректный манифест', () {
      final m = UpdateManifest.parse(manifestJson());
      expect(m.format, 1);
      expect(m.channel, UpdateChannel.stable);
      expect(m.version, ProductVersion.parse('0.0.3'));
      expect(m.packages, hasLength(1));
      expect(m.packages.single.platform, UpdatePlatform.linux);
      expect(m.nextUpdatePublicKey, isNull);
    });

    test('отклоняет format ≠ 1 и битые поля', () {
      expect(
        () => UpdateManifest.parse(
          manifestJson().replaceFirst('"format":1', '"format":2'),
        ),
        throwsA(isA<DataFormatException>()),
      );
      expect(
        () => UpdateManifest.parse(manifestJson(channel: 'nightly')),
        throwsA(isA<DataFormatException>()),
      );
      expect(
        () => UpdateManifest.parse(manifestJson(packages: const [])),
        throwsA(isA<DataFormatException>()),
      );
    });

    test('отклоняет minVersion новее version', () {
      expect(
        () => UpdateManifest.parse(manifestJson(version: '0.0.1')),
        throwsA(isA<DataFormatException>()),
      );
    });

    test('выбирает сборку по платформе и архитектуре', () {
      final m = UpdateManifest.parse(
        manifestJson(
          packages: [
            {
              'platform': 'linux',
              'arch': 'x64',
              'url': 'https://u.example/x',
              'sha256': '00' * 32,
              'size': 1,
            },
            {
              'platform': 'linux',
              'arch': null,
              'url': 'https://u.example/any',
              'sha256': '00' * 32,
              'size': 2,
            },
            {
              'platform': 'windows',
              'arch': 'x64',
              'url': 'https://u.example/w',
              'sha256': '00' * 32,
              'size': 3,
            },
          ],
        ),
      );
      expect(m.packageFor(UpdatePlatform.linux, 'x64')?.size, 1);
      expect(m.packageFor(UpdatePlatform.linux, 'arm64')?.size, 2);
      expect(m.packageFor(UpdatePlatform.windows, 'x64')?.size, 3);
      expect(m.packageFor(UpdatePlatform.macos, null), isNull);
    });

    test('различает сборки одной платформы по виду файла', () {
      final m = UpdateManifest.parse(
        manifestJson(
          packages: [
            {
              'platform': 'linux',
              'arch': 'x64',
              'url': 'https://u.example/backpeer-0.0.8-x86_64.AppImage',
              'sha256': '00' * 32,
              'size': 1,
            },
            {
              'platform': 'linux',
              'arch': 'x64',
              'url': 'https://u.example/backpeer_0.0.8_amd64.deb',
              'sha256': '01' * 32,
              'size': 2,
            },
          ],
        ),
      );
      // Без вида — первая сборка платформы, как у клиентов 0.0.7 и раньше.
      expect(m.packageFor(UpdatePlatform.linux, 'x64')?.size, 1);
      expect(
        m.packageFor(UpdatePlatform.linux, 'x64', kind: 'appimage')?.size,
        1,
      );
      // Установленный .deb обновляется пакетом, а не образом AppImage.
      expect(m.packageFor(UpdatePlatform.linux, 'x64', kind: 'deb')?.size, 2);
      expect(m.packageFor(UpdatePlatform.linux, 'x64', kind: 'rpm'), isNull);
      expect(m.packages.first.kind, 'appimage');
      expect(m.packages.last.kind, 'deb');
    });
  });

  group('подпись манифеста', () {
    test('принимается верная подпись', () async {
      final json = manifestJson();
      final bytes = Uint8List.fromList(utf8.encode(json));
      await UpdateManifest.verifySignature(
        crypto,
        bytes: bytes,
        signature: await sign(json),
        acceptedKeys: [devKey.publicKey],
      );
    });

    test('отклоняется подменённый манифест', () async {
      final json = manifestJson();
      final tampered = Uint8List.fromList(
        utf8.encode(json.replaceFirst('0.0.3', '0.0.4')),
      );
      await expectLater(
        UpdateManifest.verifySignature(
          crypto,
          bytes: tampered,
          signature: await sign(json),
          acceptedKeys: [devKey.publicKey],
        ),
        throwsA(isA<IntegrityException>()),
      );
    });

    test(
      'отклоняется подпись другим ключом; ротация принимается вторым ключом',
      () async {
        final json = manifestJson();
        final bytes = Uint8List.fromList(utf8.encode(json));
        await expectLater(
          UpdateManifest.verifySignature(
            crypto,
            bytes: bytes,
            signature: await sign(json, key: otherKey),
            acceptedKeys: [devKey.publicKey],
          ),
          throwsA(isA<IntegrityException>()),
        );
        await UpdateManifest.verifySignature(
          crypto,
          bytes: bytes,
          signature: await sign(json, key: otherKey),
          acceptedKeys: [devKey.publicKey, otherKey.publicKey],
        );
      },
    );
  });

  group('применимость и раскатка', () {
    test('запрет отката и минимальная версия', () {
      final m = UpdateManifest.parse(manifestJson());
      expect(
        () => m.checkApplicable(ProductVersion.parse('0.0.3')),
        throwsA(isA<PreconditionException>()),
      );
      expect(
        () => m.checkApplicable(ProductVersion.parse('0.0.4')),
        throwsA(isA<PreconditionException>()),
      );
      expect(
        () => m.checkApplicable(ProductVersion.parse('0.0.1')),
        throwsA(isA<PreconditionException>()),
      );
      m.checkApplicable(ProductVersion.parse('0.0.2'));
    });

    test('раскатка детерминирована и учитывает долю', () {
      final m = UpdateManifest.parse(manifestJson(rollout: 0.5));
      final id = Uint8List.fromList(List.generate(16, (i) => i));
      final bucket = m.rolloutBucket(crypto, id);
      expect(bucket, inInclusiveRange(0, 99));
      expect(m.rolloutBucket(crypto, id), bucket);
      expect(m.rolloutAllows(crypto, id), bucket < 50);
      final all = UpdateManifest.parse(manifestJson());
      expect(all.rolloutAllows(crypto, id), isTrue);
      final none = UpdateManifest.parse(manifestJson(rollout: 0));
      expect(none.rolloutAllows(crypto, id), isFalse);
    });
  });

  group('UpdateClient', () {
    test('fetchManifest проверяет подпись и канал', () async {
      final json = manifestJson();
      final client = UpdateClient(
        crypto: crypto,
        acceptedKeys: [devKey.publicKey],
        fetch: (url) async {
          if (url.path.endsWith('.sig')) return await sign(json);
          return Uint8List.fromList(utf8.encode(json));
        },
      );
      final m = await client.fetchManifest(
        Uri.parse('https://u.example/stable.json'),
        channel: UpdateChannel.stable,
      );
      expect(m.version, ProductVersion.parse('0.0.3'));

      final wrongChannel = UpdateClient(
        crypto: crypto,
        acceptedKeys: [devKey.publicKey],
        fetch: (url) async {
          if (url.path.endsWith('.sig')) return await sign(json);
          return Uint8List.fromList(utf8.encode(json));
        },
      );
      await expectLater(
        wrongChannel.fetchManifest(
          Uri.parse('https://u.example/beta.json'),
          channel: UpdateChannel.beta,
        ),
        throwsA(isA<PreconditionException>()),
      );
    });

    test('download проверяет размер и хэш', () async {
      final payload = Uint8List.fromList(List.generate(42, (i) => i));
      final hash = crypto.blake2b256(payload);
      final m = UpdateManifest.parse(
        manifestJson(
          packages: [
            {
              'platform': 'linux',
              'arch': null,
              'url': 'https://u.example/pkg',
              'sha256': bytesToHex(hash),
              'size': 42,
            },
          ],
        ),
      );
      final client = UpdateClient(
        crypto: crypto,
        acceptedKeys: [devKey.publicKey],
        fetch: (url) async => payload,
      );
      expect(await client.download(m.packages.single), payload);

      final bad = UpdateClient(
        crypto: crypto,
        acceptedKeys: [devKey.publicKey],
        fetch: (url) async => Uint8List.fromList([...payload, 0]),
      );
      await expectLater(
        bad.download(m.packages.single),
        throwsA(isA<IntegrityException>()),
      );
    });

    test(
      'check возвращает null при откате и вне доли, иначе манифест',
      () async {
        Future<UpdateClient> client(String json) async => UpdateClient(
          crypto: crypto,
          acceptedKeys: [devKey.publicKey],
          fetch: (url) async {
            if (url.path.endsWith('.sig')) return await sign(json);
            return Uint8List.fromList(utf8.encode(json));
          },
        );

        final base = Uri.parse('https://u.example/');
        final id = Uint8List(16);

        final upToDate = await client(manifestJson());
        expect(
          await upToDate.check(
            baseUri: base,
            channel: UpdateChannel.stable,
            currentVersion: ProductVersion.parse('0.0.3'),
            installId: id,
          ),
          isNull,
        );

        final notInRollout = await client(manifestJson(rollout: 0));
        expect(
          await notInRollout.check(
            baseUri: base,
            channel: UpdateChannel.stable,
            currentVersion: ProductVersion.parse('0.0.2'),
            installId: id,
          ),
          isNull,
        );

        final available = await client(manifestJson());
        expect(
          await available.check(
            baseUri: base,
            channel: UpdateChannel.stable,
            currentVersion: ProductVersion.parse('0.0.2'),
            installId: id,
          ),
          isNotNull,
        );
      },
    );
  });
}
