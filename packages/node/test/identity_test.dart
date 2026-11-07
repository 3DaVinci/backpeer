import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:node/node.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late CryptoProvider crypto;
  late Directory dir;
  setUpAll(() async => crypto = await SodiumCryptoProvider.load());
  setUp(() => dir = Directory.systemTemp.createTempSync('fs-node-id-'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('ключи создаются один раз, права 0600, папка 0700', () async {
    final data = Directory('${dir.path}/data');
    expect(await NodeIdentity.ensureKeys(data, crypto), isTrue);
    expect(await NodeIdentity.ensureKeys(data, crypto), isFalse);
    final key = File('${data.path}/${NodeIdentity.keyFile}');
    expect(key.lengthSync(), DeviceKeys.secretLength);
    if (!Platform.isWindows) {
      expect(key.statSync().mode & 511, 384);
      expect(data.statSync().mode & 511, 448);
    }
    final a = await NodeIdentity.load(data, crypto);
    final b = await NodeIdentity.load(data, crypto);
    expect(a.nodeId, b.nodeId);
    expect(a.certificate, isNull);
    a.dispose();
    b.dispose();
  });

  test('нет ключей или права шире 0600 — ошибка', () async {
    await expectLater(
      NodeIdentity.load(dir, crypto),
      throwsA(isA<NodeIdentityException>()),
    );
    if (Platform.isWindows) return;
    await NodeIdentity.ensureKeys(dir, crypto);
    setUnixFileMode('${dir.path}/${NodeIdentity.keyFile}', 420); // 0644
    await expectLater(
      NodeIdentity.load(dir, crypto),
      throwsA(
        isA<NodeIdentityException>().having(
          (e) => e.message,
          'message',
          contains('0644'),
        ),
      ),
    );
  });

  test('импорт сертификата: владелец запоминается', () async {
    final owner = await nodeWithCertificate(dir, crypto);
    final identity = await NodeIdentity.load(dir, crypto);
    expect(identity.certificate, isNotNull);
    expect(identity.owner, owner.accountId);
    identity.dispose();
    owner.dispose();
  });

  test('чужой сертификат, другой node_dh, мусор — отказ', () async {
    await NodeIdentity.ensureKeys(dir, crypto);
    final owner = await AccountKeys.fromMasterKey(
      SecretBytes(crypto.randomBytes(32)),
      crypto,
    );
    final identity = await NodeIdentity.load(dir, crypto);
    final cases = {
      'другой узел': await foreignCertificate(crypto, owner),
      'другой node_dh': await foreignCertificate(
        crypto,
        owner,
        nodeId: identity.nodeId,
      ),
    };
    final tampered = await foreignCertificate(
      crypto,
      owner,
      nodeId: identity.nodeId,
      nodeDh: identity.nodeDh,
    );
    tampered.signature[0] ^= 1;
    cases['подпись'] = tampered;
    for (final MapEntry(:key, :value) in cases.entries) {
      await expectLater(
        NodeIdentity.importCertificate(dir, crypto, value.writeToBuffer()),
        throwsA(isA<NodeIdentityException>()),
        reason: key,
      );
    }
    // Мусор: поле с неизвестным номером и длиной за границей буфера —
    // здесь protobuf 6.1 бросает RangeError (Error, а не Exception), и
    // раньше он вылетал наружу вместо NodeIdentityException (фаззинг 1.8.5).
    for (final garbage in <List<int>>[
      [0x2a, 0xff, 0xff, 0xff, 0xff, 0x0f],
      List.filled(40, 0xff),
      crypto.randomBytes(40),
    ]) {
      await expectLater(
        NodeIdentity.importCertificate(
          dir,
          crypto,
          Uint8List.fromList(garbage),
        ),
        throwsA(isA<NodeIdentityException>()),
        reason: 'мусор ${bytesToHex(Uint8List.fromList(garbage))}',
      );
    }
    expect(
      File('${dir.path}/${NodeIdentity.certificateFile}').existsSync(),
      isFalse,
    );
    identity.dispose();
    owner.dispose();
  });
}
