// Привязка узла к учётной записи по одноразовому коду (задачи 6.1.1,
// 6.1.2; protocol.md, раздел 4.17). Нужен FS_TEST_POSTGRES.

import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:protocol/protocol.dart' as pb;
import 'package:test/test.dart';

import 'support/db_harness.dart';
import 'support/postgres.dart';

void main() {
  if (testPostgresUrl == null) {
    test('привязка узла', () {}, skip: skipWithoutPostgres);
    return;
  }
  late DbHarness h;
  late AccountKeys owner;
  setUp(() async {
    h = await DbHarness.create();
    owner = await h.newAccount();
    await h.register(owner, await h.newKey(), login: 'owner');
  });
  tearDown(() => h.close());

  Uint8List dh([int seed = 0x55]) => Uint8List(32)..[0] = seed;

  Future<pb.NodePairStartResponse> start(
    Ed25519KeyPair node,
    Uint8List nodeDh,
  ) => h.call(
    'NodePairStart',
    pb.NodePairStartRequest(nodeDh: nodeDh),
    pb.NodePairStartResponse.fromBuffer,
    key: node,
  );

  Future<pb.NodePairStatusResponse> status(Ed25519KeyPair node) => h.call(
    'NodePairStatus',
    pb.NodePairStatusRequest(),
    pb.NodePairStatusResponse.fromBuffer,
    key: node,
  );

  Future<pb.NodePairLookupResponse> lookup(String code) => h.call(
    'NodePairLookup',
    pb.NodePairLookupRequest(code: code),
    pb.NodePairLookupResponse.fromBuffer,
    key: owner.accountSign,
  );

  Future<pb.NodePairSignResponse> sign(
    String code,
    Ed25519KeyPair node,
    Uint8List nodeDh,
  ) async {
    final certificate = await NodeCertificates.issue(
      h.crypto,
      owner,
      nodeId: node.publicKey,
      nodeDh: nodeDh,
      issuedAt: h.clock.now,
    );
    return await h.call(
      'NodePairSign',
      pb.NodePairSignRequest(code: code, nodeCertificate: certificate),
      pb.NodePairSignResponse.fromBuffer,
      key: owner.accountSign,
    );
  }

  test('полный путь: код → сверка → сертификат → узел забирает', () async {
    final node = await h.newKey();
    final nodeDh = dh();
    final started = await start(node, nodeDh);
    expect(started.code, matches(RegExp(r'^[0-9A-Z]{8}$')));
    expect(started.expiresAtUnixMs.toInt(), greaterThan(0));

    expect(
      (await status(node)).status,
      pb.NodePairStatus.NODE_PAIR_STATUS_PENDING,
    );

    final found = await lookup(started.code);
    expect(found.nodeId, node.publicKey);
    expect(found.nodeDh, nodeDh);

    await sign(started.code, node, nodeDh);

    final signed = await status(node);
    expect(signed.status, pb.NodePairStatus.NODE_PAIR_STATUS_SIGNED);
    final cert = await NodeCertificates.open(
      h.crypto,
      signed.nodeCertificate,
      nodeId: node.publicKey,
    );
    expect(cert.accountId, owner.accountId);
    expect(cert.nodeDh, nodeDh);
  });

  test('неверный код — NOT_FOUND', () async {
    final node = await h.newKey();
    await start(node, dh());
    await expectLater(
      lookup('AAAAAAAA'),
      failsWith(pb.ErrorCode.ERROR_CODE_NOT_FOUND),
    );
  });

  test('код с недопустимым форматом — BAD_REQUEST', () async {
    await expectLater(
      lookup('короткий'),
      failsWith(pb.ErrorCode.ERROR_CODE_BAD_REQUEST),
    );
  });

  test('просроченный код: у узла EXPIRED, у владельца NOT_FOUND', () async {
    final node = await h.newKey();
    final started = await start(node, dh());
    h.clock.advance(const Duration(minutes: 11));
    expect(
      (await status(node)).status,
      pb.NodePairStatus.NODE_PAIR_STATUS_EXPIRED,
    );
    await expectLater(
      lookup(started.code),
      failsWith(pb.ErrorCode.ERROR_CODE_NOT_FOUND),
    );
  });

  test('сертификат другой учётной записи отклоняется', () async {
    final node = await h.newKey();
    final nodeDh = dh();
    final started = await start(node, nodeDh);
    final other = await h.newAccount();
    // Запрос подписан владельцем, а сертификат — другой учётной записью.
    final foreign = await NodeCertificates.issue(
      h.crypto,
      other,
      nodeId: node.publicKey,
      nodeDh: nodeDh,
      issuedAt: h.clock.now,
    );
    await expectLater(
      h.call(
        'NodePairSign',
        pb.NodePairSignRequest(code: started.code, nodeCertificate: foreign),
        pb.NodePairSignResponse.fromBuffer,
        key: owner.accountSign,
      ),
      failsWith(pb.ErrorCode.ERROR_CODE_PERMISSION_DENIED),
    );
  });

  test('лимит попыток: после исчерпания код не действует', () async {
    final node = await h.newKey();
    final nodeDh = dh();
    final started = await start(node, nodeDh);
    final other = await h.newAccount();
    final foreign = await NodeCertificates.issue(
      h.crypto,
      other,
      nodeId: node.publicKey,
      nodeDh: nodeDh,
      issuedAt: h.clock.now,
    );
    for (var i = 0; i < 5; i++) {
      await expectLater(
        h.call(
          'NodePairSign',
          pb.NodePairSignRequest(code: started.code, nodeCertificate: foreign),
          pb.NodePairSignResponse.fromBuffer,
          key: owner.accountSign,
        ),
        failsWith(pb.ErrorCode.ERROR_CODE_PERMISSION_DENIED),
      );
    }
    await expectLater(
      lookup(started.code),
      failsWith(pb.ErrorCode.ERROR_CODE_NOT_FOUND),
    );
  });
}
