// Сертификат узла стенда от нового владельца (`node stand-cert`, Docker-образ
// узла, задача 3.10.1). Нужен FS_TEST_POSTGRES.

import 'dart:io';

import 'package:core/core.dart';
import 'package:fixnum/fixnum.dart';
import 'package:node/node.dart';
import 'package:protocol/protocol.dart' as pb;
import 'package:test/test.dart';

import 'support/live.dart';
import 'support/postgres.dart';

void main() {
  if (testPostgresUrl == null) {
    test('сертификат узла стенда', () {}, skip: skipWithoutPostgres);
    return;
  }
  late LiveCoordinator live;
  late Directory dir;

  setUp(() async {
    live = await LiveCoordinator.start();
    dir = Directory.systemTemp.createTempSync('fs-stand-cert-');
  });
  tearDown(() async {
    await live.close();
    dir.deleteSync(recursive: true);
  });

  test('у каждого узла свой владелец, узел регистрируется', () async {
    final crypto = live.crypto;
    final client = live.client();
    addTearDown(client.close);
    final owners = <String>{};
    for (var i = 0; i < 2; i++) {
      final data = Directory('${dir.path}/node$i');
      await NodeIdentity.ensureKeys(data, crypto);
      var identity = await NodeIdentity.load(data, crypto);
      final cert = await StubNodes.issueStandCertificate(
        client,
        crypto,
        nodeId: identity.nodeId,
        nodeDh: identity.nodeDh,
        loginPrefix: 'stand',
      );
      identity.dispose();
      final owner = await NodeIdentity.importCertificate(
        data,
        crypto,
        cert.writeToBuffer(),
      );
      owners.add(bytesToHex(owner));

      identity = await NodeIdentity.load(data, crypto);
      addTearDown(identity.dispose);
      final response = await client.registerNode(
        pb.RegisterNodeRequest(
          nodeCertificate: identity.certificate,
          capacityBytes: Int64(1 << 40),
          versions: const [1],
          software: 'node test',
        ),
        nodeKey: identity.keys.sign,
      );
      expect(response.coordinatorKeys, isNotEmpty);
    }
    expect(owners, hasLength(2));
  });
}
