// Демон узла против настоящего координатора (задача 3.1.2): регистрация с
// сертификатом от учётной записи владельца, heartbeat, узел в реестре,
// ключ подписанта совпадает со списком узла; отзыв устройства доходит до
// узла (3.3.2); координатор подключается к узлу по TCP и узел сообщает
// найденный адрес (3.5.1); канал команд: ping доходит, новый отзыв узел
// дочитывает сам по команде координатора (3.6.1). Нужен FS_TEST_POSTGRES.

import 'dart:io';
import 'dart:typed_data';

import 'package:coordinator/coordinator.dart';
import 'package:core/core.dart';
import 'package:node/node.dart';
import 'package:postgres/postgres.dart';
import 'package:protocol/protocol.dart' as pb;
import 'package:test/test.dart';

import 'support/live.dart';
import 'support/postgres.dart';

void main() {
  if (testPostgresUrl == null) {
    test('демон узла через координатор', () {}, skip: skipWithoutPostgres);
    return;
  }
  late LiveCoordinator live;
  late Directory dir;

  setUp(() async {
    live = await LiveCoordinator.start();
    dir = Directory.systemTemp.createTempSync('fs-node-coord-');
  });
  tearDown(() async {
    await live.close();
    dir.deleteSync(recursive: true);
  });

  test('узел регистрируется, шлёт heartbeat и виден в реестре', () async {
    final crypto = live.crypto;
    // Владелец: учётная запись на координаторе, сертификат узла от неё —
    // как после cli register и cli node-cert.
    final owner = await AccountKeys.fromMasterKey(
      SecretBytes(crypto.randomBytes(32)),
      crypto,
    );
    final device = await DeviceKeys.generate(crypto);
    final client = live.client();
    await client.registerAccount(
      pb.RegisterAccountRequest(
        deviceCertificate: await DeviceCertificates.issue(
          crypto,
          owner,
          device,
          issuedAt: DateTime.now(),
        ),
        login: 'node-owner',
      ),
      accountKey: owner.accountSign,
    );
    client.close();
    await NodeIdentity.ensureKeys(dir, crypto);
    final identity = await NodeIdentity.load(dir, crypto);
    await NodeIdentity.importCertificate(
      dir,
      crypto,
      (await NodeCertificates.issue(
        crypto,
        owner,
        nodeId: identity.nodeId,
        nodeDh: identity.nodeDh,
        issuedAt: DateTime.now(),
      )).writeToBuffer(),
    );
    final nodeId = identity.nodeId;
    identity.dispose();

    final signerKey = await crypto.ed25519FromSeed(
      SecretBytes(Uint8List(32)..fillRange(0, 32, 0xC0)),
    );
    final daemon = await NodeDaemon.start(
      NodeConfig.parse(
        '''
storage:
  quota_bytes: 200000000000
listen:
  port: 0
  port_mapping: off
  endpoints: [127.0.0.1:7340]
coordinator:
  url: ${live.url}
  keys: [${bytesToHex(signerKey.publicKey)}]
''',
        const {},
        dataDir: dir.path,
      ),
      crypto: crypto,
      handleSignals: false,
    );
    final link = daemon.link!;
    for (var i = 0; i < 100 && !link.registered; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(link.registered, isTrue, reason: '${link.toJson()}');
    expect(link.toJson()['unknownCoordinatorKeys'], isEmpty);
    // Проверка достижимости сразу после регистрации: координатор
    // подключается к порту приёма узла.
    final reachability = daemon.reachability!;
    for (var i = 0; i < 100 && !reachability.reachable; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(reachability.reachable, isTrue, reason: '${reachability.toJson()}');
    expect(reachability.observedAddress, '127.0.0.1');
    final found = '127.0.0.1:${daemon.listener!.port}';
    expect(reachability.endpoints, ['127.0.0.1:7340', found]);
    expect((daemon.status()['reachability']! as Map)['ports'], {
      '${daemon.listener!.port}': 'reachable',
    });
    await link.heartbeat();

    final db = Database.open(live.db.config);
    final rows = await db.run(
      (s) => s.execute(
        Sql.named(
          'SELECT account_id, capacity_bytes, endpoints, '
          'last_heartbeat_at IS NOT NULL, free_bytes '
          'FROM nodes WHERE node_id = @n:bytea',
        ),
        parameters: {'n': nodeId},
      ),
    );
    await db.close();
    expect(rows, hasLength(1));
    expect(rows.single[0], owner.accountId);
    expect(rows.single[1], 200000000000);
    expect(rows.single[2], ['127.0.0.1:7340', found]);
    expect(rows.single[3], isTrue);
    // Свободное место — меньшее из квоты и диска за вычетом запаса; диск
    // мог измениться с момента heartbeat.
    expect(
      rows.single[4],
      isA<int>().having((v) => v, 'free', lessThanOrEqualTo(200000000000)),
    );

    // Отзыв второго устройства владельца доходит до узла через
    // ListRevocations и переживает перезапуск демона.
    final second = await DeviceKeys.generate(crypto);
    final owners = live.client();
    await owners.addDevice(
      pb.AddDeviceRequest(
        deviceCertificate: await DeviceCertificates.issue(
          crypto,
          owner,
          second,
          issuedAt: DateTime.now(),
        ),
      ),
      accountKey: owner.accountSign,
    );
    await owners.revokeDevice(
      pb.RevokeDeviceRequest(
        revocation: await DeviceCertificates.revoke(
          crypto,
          owner,
          deviceSign: second.sign.publicKey,
          revokedAt: DateTime.now(),
        ),
      ),
      accountKey: owner.accountSign,
    );
    await link.syncRevocations();
    expect(daemon.revocations.isRevoked(second.sign.publicKey), isTrue);
    expect(daemon.revocations.isRevoked(device.sign.publicKey), isFalse);

    // Канал команд: открыт, ping доходит; следующий отзыв узел дочитывает
    // сам по команде SyncRevocations (с задержкой до 10 с), без heartbeat.
    final channels = live.server.channels;
    for (var i = 0; i < 100 && !channels.isConnected(nodeId); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(link.channel!.connected, isTrue);
    final pong = await channels.send(
      nodeId,
      pb.CoordinatorChannelMessage(ping: pb.PingCommand()),
    );
    expect(pong!.hasDone(), isTrue);
    final third = await DeviceKeys.generate(crypto);
    await owners.addDevice(
      pb.AddDeviceRequest(
        deviceCertificate: await DeviceCertificates.issue(
          crypto,
          owner,
          third,
          issuedAt: DateTime.now(),
        ),
      ),
      accountKey: owner.accountSign,
    );
    await owners.revokeDevice(
      pb.RevokeDeviceRequest(
        revocation: await DeviceCertificates.revoke(
          crypto,
          owner,
          deviceSign: third.sign.publicKey,
          revokedAt: DateTime.now(),
        ),
      ),
      accountKey: owner.accountSign,
    );
    owners.close();
    for (
      var i = 0;
      i < 300 && !daemon.revocations.isRevoked(third.sign.publicKey);
      i++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(daemon.revocations.isRevoked(third.sign.publicKey), isTrue);
    third.dispose();

    final control = await NodeControlClient.connect(
      ControlEndpoint.forDataDir(dir.path),
    );
    final status = await control.call('status');
    await control.close();
    expect(status['owner'], bytesToHex(owner.accountId));
    expect(status['revokedDevices'], 2);
    expect(
      (status['coordinator']! as Map<String, Object?>)['registered'],
      isTrue,
    );
    await daemon.stop();
    owner.dispose();
    device.dispose();
    second.dispose();
  });
}
