// CoordinatorClient из core против настоящего координатора по HTTP и HTTPS
// (задача 2.8.1). Нужен FS_TEST_POSTGRES; проверка TLS — ещё openssl.

import 'dart:io';
import 'dart:typed_data';

import 'package:coordinator/coordinator.dart';
import 'package:core/core.dart';
import 'package:fixnum/fixnum.dart';
import 'package:protocol/protocol.dart' as pb;
import 'package:test/test.dart';

import 'support/postgres.dart';

void main() {
  if (testPostgresUrl == null) {
    test('клиент координатора', () {}, skip: skipWithoutPostgres);
    return;
  }
  late CryptoProvider crypto;
  late TestDatabase testDb;
  late CoordinatorServer server;
  late Directory dir;
  var seed = 0;

  setUpAll(() async => crypto = await SodiumCryptoProvider.load());

  Future<CoordinatorServer> start({
    RateLimits limits = const RateLimits(),
    String? certificate,
    String? privateKey,
  }) async {
    testDb = await TestDatabase.create();
    final config = CoordinatorConfig(
      port: 0,
      database: testDb.config,
      limits: limits,
      tlsCertificate: certificate,
      tlsPrivateKey: privateKey,
      nodes: const NodePolicy(minCapacityBytes: 0),
      placement: const PlacementPolicy(
        probation: Duration.zero,
        candidatesCache: Duration.zero,
      ),
    );
    final signerKey = await crypto.ed25519FromSeed(
      SecretBytes(Uint8List(32)..fillRange(0, 32, 0xC0)),
    );
    return server = await CoordinatorServer.start(
      config,
      crypto: crypto,
      migrate: true,
      service: (db) => DatabaseCoordinatorService(
        db: db,
        crypto: crypto,
        config: config,
        signer: InProcessTicketSigner(
          TicketSigningService(
            crypto: crypto,
            key: signerKey,
            limiter: RateLimiter(perSecond: 1000, burst: 1000),
          ),
        ),
      ),
    );
  }

  setUp(() => dir = Directory.systemTemp.createTempSync('fs-client-'));
  tearDown(() async {
    await server.close();
    await testDb.drop();
    dir.deleteSync(recursive: true);
  });

  Future<Ed25519KeyPair> newKey() =>
      crypto.ed25519FromSeed(SecretBytes(Uint8List(32)..[0] = ++seed));

  Future<AccountKeys> newAccount() => AccountKeys.fromMasterKey(
    SecretBytes(Uint8List(32)..[1] = ++seed),
    crypto,
  );

  Future<pb.Signed> deviceCert(AccountKeys account, Ed25519KeyPair device) =>
      SignedMessages.sign(
        crypto,
        account.accountSign,
        'device-cert',
        pb.DeviceCertificate(
          accountId: account.accountId,
          deviceSign: device.publicKey,
          deviceDh: Uint8List(32),
          issuedAtUnixMs: Int64(DateTime.now().millisecondsSinceEpoch),
        ),
      );

  CoordinatorClient client(
    Ed25519KeyPair? device, {
    String scheme = 'http',
    String host = '127.0.0.1',
    SecurityContext? trusted,
    RetryPolicy retry = const RetryPolicy(),
  }) => CoordinatorClient(
    baseUri: Uri.parse('$scheme://$host:${server.port}'),
    crypto: crypto,
    deviceKey: device,
    trustedCertificates: trusted,
    retry: retry,
  );

  test('учётная запись, устройства, объекты, вход по паролю', () async {
    await start();
    final account = await newAccount();
    final device = await newKey();
    final c = client(device);
    final copy = await KeyCopy.create(
      crypto,
      keys: account,
      password: 'пароль клиента',
      params: const Argon2Params(memoryKiB: 1024, iterations: 1),
    );
    await c.registerAccount(
      pb.RegisterAccountRequest(
        deviceCertificate: await deviceCert(account, device),
        login: 'alice',
        keyBundle: copy.keyBundle,
        authVerifier: copy.authVerifier,
      ),
      accountKey: account.accountSign,
    );
    final second = await newKey();
    await c.addDevice(
      pb.AddDeviceRequest(deviceCertificate: await deviceCert(account, second)),
      accountKey: account.accountSign,
    );
    expect(
      (await c.listDevices(accountKey: account.accountSign)).devices,
      hasLength(2),
    );

    await c.putObject(
      pb.PutObjectRequest(
        kind: pb.ObjectKind.OBJECT_KIND_SNAPSHOT,
        objectId: Uint8List(32)..[0] = 1,
        blob: [1, 2, 3],
        sequence: Int64(1),
      ),
    );
    final listed = await client(second).listObjects(
      pb.ListObjectsRequest(kind: pb.ObjectKind.OBJECT_KIND_SNAPSHOT),
    );
    expect(listed.objects.single.sequence.toInt(), 1);
    await expectLater(
      c.getObject(
        pb.GetObjectRequest(
          kind: pb.ObjectKind.OBJECT_KIND_SNAPSHOT,
          objectId: Uint8List(32),
        ),
      ),
      throwsA(
        isA<CoordinatorException>()
            .having((e) => e.code, 'code', pb.ErrorCode.ERROR_CODE_NOT_FOUND)
            .having((e) => e.httpStatus, 'httpStatus', 404),
      ),
    );

    // Вход на новом устройстве: клиент без ключей.
    final fresh = client(null);
    final params = await fresh.getLoginParams(
      pb.GetLoginParamsRequest(login: 'alice'),
    );
    final derived = await PasswordKeys.derive(
      crypto,
      password: 'пароль клиента',
      salt: Uint8List.fromList(params.salt),
      params: Argon2Params(
        memoryKiB: params.memoryKib,
        iterations: params.iterations,
        parallelism: params.parallelism,
      ),
    );
    final loginKey = await PasswordLogin.loginKey(crypto, derived);
    derived.dispose();
    final now = DateTime.now().millisecondsSinceEpoch;
    final bundle = await fresh.getKeyBundle(
      pb.GetKeyBundleRequest(
        login: 'alice',
        timeUnixMs: Int64(now),
        authProof: await PasswordLogin.prove(
          crypto,
          loginKey,
          login: 'alice',
          timeMs: now,
        ),
      ),
    );
    final keys = await KeyBundle.parse(Uint8List.fromList(bundle.keyBundle))
        .unlock(crypto, 'пароль клиента');
    expect(keys.accountId, account.accountId);
    for (final x in [c, fresh]) {
      x.close();
    }
  });

  test('узел и сегмент через клиент', () async {
    await start();
    final account = await newAccount();
    final device = await newKey();
    final c = client(device);
    await c.registerAccount(
      pb.RegisterAccountRequest(
        deviceCertificate: await deviceCert(account, device),
        login: 'bob',
      ),
      accountKey: account.accountSign,
    );
    // Один узел на loopback: размещаем сегмент 1 из 2 — не хватит узлов.
    final owner = await newAccount();
    final ownerDevice = await newKey();
    await c.registerAccount(
      pb.RegisterAccountRequest(
        deviceCertificate: await deviceCert(owner, ownerDevice),
        login: 'keeper',
      ),
      accountKey: owner.accountSign,
    );
    final node = await newKey();
    final registered = await c.registerNode(
      pb.RegisterNodeRequest(
        nodeCertificate: await NodeCertificates.issue(
          crypto,
          owner,
          nodeId: node.publicKey,
          nodeDh: Uint8List(32),
          issuedAt: DateTime.now(),
        ),
        capacityBytes: Int64(1 << 40),
        versions: [1],
      ),
      nodeKey: node,
    );
    expect(registered.coordinatorKeys, hasLength(1));
    await c.heartbeat(pb.HeartbeatRequest(), nodeKey: node);
    await expectLater(
      client(device, retry: RetryPolicy.none).allocateSegment(
        pb.AllocateSegmentRequest(
          segmentId: Uint8List(32),
          k: 1,
          n: 2,
          repairThreshold: 1,
          fragmentSize: 1000,
          fragmentIds: [Uint8List(32), Uint8List(32)],
          bodyRoots: [Uint8List(32), Uint8List(32)],
        ),
      ),
      throwsA(
        isA<CoordinatorException>().having(
          (e) => e.code,
          'code',
          pb.ErrorCode.ERROR_CODE_UNAVAILABLE,
        ),
      ),
    );
    c.close();
  });

  test('RATE_LIMITED: клиент ждёт retry_after и повторяет', () async {
    await start(limits: const RateLimits(ipPerSecond: 5, ipBurst: 2));
    final c = client(null);
    final watch = Stopwatch()..start();
    for (var i = 0; i < 5; i++) {
      await c.getLoginParams(pb.GetLoginParamsRequest(login: 'anyone'));
    }
    // 2 сразу, ещё 3 — по 200 мс.
    expect(watch.elapsed, greaterThan(const Duration(milliseconds: 400)));
    c.close();
  });

  group('TLS', () {
    late String cert;
    late String key;

    setUp(() async {
      cert = '${dir.path}/cert.pem';
      key = '${dir.path}/key.pem';
      final result = await Process.run('openssl', [
        'req',
        '-x509',
        '-newkey',
        'ec',
        '-pkeyopt',
        'ec_paramgen_curve:P-256',
        '-nodes',
        '-keyout',
        key,
        '-out',
        cert,
        '-days',
        '1',
        '-subj',
        '/CN=localhost',
        '-addext',
        'subjectAltName=DNS:localhost',
      ]);
      if (result.exitCode != 0) fail('openssl: ${result.stderr}');
    });

    test(
      'чужой сертификат отклоняется без повторов, свой УЦ — принят',
      () async {
        await start(certificate: cert, privateKey: key);
        final untrusted = client(
          null,
          scheme: 'https',
          host: 'localhost',
          retry: const RetryPolicy(maxAttempts: 3),
        );
        await expectLater(
          untrusted.getLoginParams(pb.GetLoginParamsRequest(login: 'alice')),
          throwsA(
            isA<CoordinatorException>().having(
              (e) => e.code,
              'code',
              pb.ErrorCode.ERROR_CODE_UNAUTHENTICATED,
            ),
          ),
        );
        untrusted.close();

        final trusted = client(
          null,
          scheme: 'https',
          host: 'localhost',
          trusted: SecurityContext()..setTrustedCertificates(cert),
        );
        final params = await trusted.getLoginParams(
          pb.GetLoginParamsRequest(login: 'alice'),
        );
        expect(params.salt, hasLength(16));
        trusted.close();
      },
    );
  }, testOn: '!windows');
}
