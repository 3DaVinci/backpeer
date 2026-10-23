import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  group('PlacementCheck', () {
    Uint8List id(int b) => Uint8List(32)..[0] = b;
    PlacedNode node(int n, int owner, [List<String> endpoints = const []]) =>
        PlacedNode(nodeId: id(n), owner: id(owner), endpoints: endpoints);

    test('подсеть адреса', () {
      expect(PlacementCheck.subnetOf('203.0.113.7:7000'), '203.0.113.0/24');
      expect(PlacementCheck.subnetOf('[2001:db8:1:2::5]:7000'), isNotNull);
      expect(
        PlacementCheck.subnetOf('[2001:db8:1:2::5]:7000'),
        PlacementCheck.subnetOf('[2001:db8:1:ffff::9]:1'),
        reason: 'IPv6 — /48',
      );
      expect(
        PlacementCheck.subnetOf('[::ffff:203.0.113.9]:7000'),
        '203.0.113.0/24',
      );
      expect(PlacementCheck.subnetOf('node.example:7000'), isNull);
      expect(PlacementCheck.subnetOf('мусор'), isNull);
    });

    test('годное размещение', () {
      expect(
        PlacementCheck.problem([
          node(1, 11, ['203.0.113.1:7000']),
          node(2, 12, ['203.0.114.1:7000']),
          node(3, 13),
          node(4, 14),
        ], ownAccount: id(99)),
        isNull,
      );
    });

    test('нарушения', () {
      expect(PlacementCheck.problem([node(1, 11), node(1, 12)]), isNotNull);
      expect(PlacementCheck.problem([node(1, 11), node(2, 11)]), isNotNull);
      expect(
        PlacementCheck.problem([
          node(1, 11, ['203.0.113.1:7000']),
          node(2, 12, ['203.0.113.200:7001']),
        ]),
        contains('203.0.113.0/24'),
      );
      expect(
        PlacementCheck.problem([node(1, 11)], ownAccount: id(11)),
        isNotNull,
      );
      // Два адреса одного узла в одной подсети — не нарушение.
      expect(
        PlacementCheck.problem([
          node(1, 11, ['203.0.113.1:7000', '203.0.113.1:7001']),
        ]),
        isNull,
      );
    });
  });

  group('NodeFolders', () {
    late CryptoProvider crypto;
    late Directory dir;
    setUpAll(() async => crypto = await SodiumCryptoProvider.load());
    setUp(() => dir = Directory.systemTemp.createTempSync('fs-nodes-'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('узлы — папки с сертификатом; остальные недоступны', () async {
      final owner = await AccountKeys.fromMasterKey(
        SecretBytes(Uint8List(32)..[0] = 1),
        crypto,
      );
      final nodeId = Uint8List(32)..[0] = 0xAB;
      final name = bytesToHex(nodeId);
      final cert = await NodeCertificates.issue(
        crypto,
        owner,
        nodeId: nodeId,
        nodeDh: Uint8List(32),
        issuedAt: DateTime.now(),
      );
      Directory('${dir.path}/$name').createSync();
      File('${dir.path}/$name/${NodeFolders.certificateFile}')
          .writeAsBytesSync(cert.writeToBuffer());
      Directory('${dir.path}/${'cd' * 32}').createSync(); // без сертификата
      Directory('${dir.path}/other').createSync();

      final folders = NodeFolders(dir, crypto);
      expect(folders.nodes, [name]);
      expect(folders.nameOf(nodeId), name);
      final signed = (await folders.handshake(name))!;
      final opened = await NodeCertificates.open(
        crypto,
        signed,
        nodeId: nodeId,
      );
      expect(opened.accountId, owner.accountId);
      await expectLater(
        NodeCertificates.open(crypto, signed, nodeId: Uint8List(32)),
        throwsA(isA<DataFormatException>()),
      );
      expect(await folders.handshake('cd' * 32), isNull);
      expect(
        () => folders.get('cd' * 32, Uint8List(32)),
        throwsA(
          isA<StorageException>().having(
            (e) => e.problem,
            'problem',
            StorageProblem.unavailable,
          ),
        ),
      );
    });
  });
}
