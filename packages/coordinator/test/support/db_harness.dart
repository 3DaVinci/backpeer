import 'dart:typed_data';

import 'package:coordinator/coordinator.dart';
import 'package:core/core.dart';
import 'package:fixnum/fixnum.dart';
import 'package:protobuf/protobuf.dart';
import 'package:protocol/protocol.dart' as pb;
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'harness.dart';
import 'postgres.dart';

/// Обработчик API поверх временной базы PostgreSQL с сервисом
/// [DatabaseCoordinatorService] и подменяемыми часами.
final class DbHarness {
  new _(this.crypto, this.clock, this.testDb, this.db, this.handler);

  static Future<DbHarness> create({
    CoordinatorConfig config = testConfig,
  }) async {
    final crypto = await SodiumCryptoProvider.load();
    final clock = FakeClock();
    final testDb = await TestDatabase.create();
    final db = Database.open(testDb.config);
    await Migrator(db).migrate();
    final handler = ApiHandler(
      methods: coordinatorMethods(
        DatabaseCoordinatorService(
          db: db,
          crypto: crypto,
          config: config,
          clock: clock.call,
        ),
      ),
      verifier: RequestVerifier(
        crypto: crypto,
        keys: PostgresKeyDirectory(db),
        clock: clock.call,
      ),
      ipLimiter: RateLimiter(perSecond: 1000, burst: 1000, clock: clock.call),
      keyLimiter: RateLimiter(perSecond: 1000, burst: 1000, clock: clock.call),
      healthCheck: db.ping,
      trustForwardedFor: true,
    );
    return DbHarness._(crypto, clock, testDb, db, handler);
  }

  /// Настройки тестов: узлы с любой ёмкостью.
  static const testConfig = CoordinatorConfig(
    nodes: NodePolicy(minCapacityBytes: 0),
  );

  /// Время [FakeClock] по умолчанию.
  static final DateTime startTime = FakeClock().now;

  final CryptoProvider crypto;
  final FakeClock clock;
  final TestDatabase testDb;
  final Database db;
  final ApiHandler handler;

  Future<void> close() async {
    await db.close();
    await testDb.drop();
  }

  /// Вызов метода; успех — разобранный ответ, ошибка — [RpcFailure].
  Future<R> call<R extends GeneratedMessage>(
    String method,
    GeneratedMessage request,
    R Function(List<int>) parse, {
    Ed25519KeyPair? key,
    String ip = '192.0.2.1',
  }) async {
    final path = '/api/v1/$method';
    final body = request.writeToBuffer();
    // Одинаковый запрос в ту же миллисекунду — повтор (protocol.md,
    // раздел 4.2): часы теста идут вперёд на каждый вызов.
    clock.advance(const Duration(milliseconds: 1));
    final auth = key == null
        ? null
        : (await RequestAuth.sign(
            crypto,
            key,
            path: path,
            body: body,
            timeMs: clock.now.millisecondsSinceEpoch,
          )).toHeader();
    final response = await handler.call(
      Request(
        'POST',
        Uri.parse('http://coordinator.test$path'),
        body: body,
        headers: {
          'content-type': 'application/x-protobuf',
          'x-forwarded-for': ip,
          'FS-Auth': ?auth,
        },
      ),
    );
    final bytes = await bodyOf(response);
    if (response.statusCode != 200) {
      throw RpcFailure(response.statusCode, pb.Error.fromBuffer(bytes));
    }
    return parse(bytes);
  }

  // --- клиентская сторона ----------------------------------------------

  var _seed = 100;

  Future<Ed25519KeyPair> newKey() async =>
      await crypto.ed25519FromSeed(SecretBytes(Uint8List(32)..[0] = ++_seed));

  Future<AccountKeys> newAccount() async {
    final mk = Uint8List(32)..[0] = ++_seed;
    return await AccountKeys.fromMasterKey(SecretBytes(mk), crypto);
  }

  Future<pb.Signed> deviceCert(
    AccountKeys account,
    Ed25519KeyPair device, {
    DateTime? issuedAt,
  }) => SignedMessages.sign(
    crypto,
    account.accountSign,
    'device-cert',
    pb.DeviceCertificate(
      accountId: account.accountId,
      deviceSign: device.publicKey,
      deviceDh: Uint8List(32)..[0] = 0x44,
      issuedAtUnixMs: Int64((issuedAt ?? clock.now).millisecondsSinceEpoch),
    ),
  );

  Future<pb.Signed> revocation(AccountKeys account, Ed25519KeyPair device) =>
      SignedMessages.sign(
        crypto,
        account.accountSign,
        'device-revoke',
        pb.DeviceRevocation(
          accountId: account.accountId,
          deviceSign: device.publicKey,
          revokedAtUnixMs: Int64(clock.now.millisecondsSinceEpoch),
        ),
      );

  /// Параметры Argon2id для тестов: быстрые.
  static const fastParams = Argon2Params(memoryKiB: 1024, iterations: 1);

  /// KeyBundle и `auth_verifier` под [password].
  Future<(Uint8List, Uint8List)> keyCopy(
    AccountKeys account,
    String password, {
    Argon2Params params = fastParams,
  }) async {
    final copy = await KeyCopy.create(
      crypto,
      keys: account,
      password: password,
      params: params,
    );
    return (copy.keyBundle, copy.authVerifier);
  }

  /// Регистрирует учётную запись с первым устройством [device].
  Future<void> register(
    AccountKeys account,
    Ed25519KeyPair device, {
    required String login,
    String? password,
  }) async {
    final copy = password == null ? null : await keyCopy(account, password);
    await call(
      'RegisterAccount',
      pb.RegisterAccountRequest(
        deviceCertificate: await deviceCert(account, device),
        login: login,
        keyBundle: copy?.$1,
        authVerifier: copy?.$2,
      ),
      pb.RegisterAccountResponse.fromBuffer,
      key: account.accountSign,
    );
  }

  /// Вход по паролю, как на новом устройстве: параметры, `AUTH`,
  /// доказательство, KeyBundle.
  Future<KeyBundle> loginWithPassword(
    String login,
    String password, {
    String ip = '192.0.2.1',
    int? timeMs,
  }) async {
    final params = await call(
      'GetLoginParams',
      pb.GetLoginParamsRequest(login: login),
      pb.GetLoginParamsResponse.fromBuffer,
      ip: ip,
    );
    final derived = await PasswordKeys.derive(
      crypto,
      password: password,
      salt: Uint8List.fromList(params.salt),
      params: Argon2Params(
        memoryKiB: params.memoryKib,
        iterations: params.iterations,
        parallelism: params.parallelism,
      ),
    );
    final key = await PasswordLogin.loginKey(crypto, derived);
    derived.dispose();
    final time = timeMs ?? clock.now.millisecondsSinceEpoch;
    final response = await call(
      'GetKeyBundle',
      pb.GetKeyBundleRequest(
        login: login,
        timeUnixMs: Int64(time),
        authProof: await PasswordLogin.prove(
          crypto,
          key,
          login: login,
          timeMs: time,
        ),
      ),
      pb.GetKeyBundleResponse.fromBuffer,
      ip: ip,
    );
    return KeyBundle.parse(Uint8List.fromList(response.keyBundle));
  }
}

extension NodeHarness on DbHarness {
  /// Сертификат узла [node], выпущенный владельцем [owner].
  Future<pb.Signed> nodeCert(
    AccountKeys owner,
    Ed25519KeyPair node, {
    DateTime? issuedAt,
  }) => NodeCertificates.issue(
    crypto,
    owner,
    nodeId: node.publicKey,
    nodeDh: Uint8List(32)..[0] = 0x55,
    issuedAt: issuedAt ?? clock.now,
  );

  /// Регистрирует узел [node] владельца [owner] с адреса [ip].
  Future<pb.RegisterNodeResponse> registerNode(
    AccountKeys owner,
    Ed25519KeyPair node, {
    String ip = '203.0.113.10',
    int capacity = 1 << 40,
    List<String> endpoints = const ['203.0.113.10:7000'],
    List<int> versions = const [1],
    pb.Signed? certificate,
  }) async => await call(
    'RegisterNode',
    pb.RegisterNodeRequest(
      nodeCertificate: certificate ?? await nodeCert(owner, node),
      capacityBytes: Int64(capacity),
      endpoints: endpoints,
      versions: versions,
      software: 'node 0.2.0',
    ),
    pb.RegisterNodeResponse.fromBuffer,
    key: node,
    ip: ip,
  );

  Future<pb.HeartbeatResponse> heartbeat(
    Ed25519KeyPair node, {
    String ip = '203.0.113.10',
    int used = 0,
    int capacity = 1 << 40,
  }) => call(
    'Heartbeat',
    pb.HeartbeatRequest(
      usedBytes: Int64(used),
      capacityBytes: Int64(capacity),
      endpoints: const ['203.0.113.10:7000'],
    ),
    pb.HeartbeatResponse.fromBuffer,
    key: node,
    ip: ip,
  );
}

/// Ответ API с ошибкой.
final class RpcFailure implements Exception {
  const new(this.status, this.error);

  final int status;
  final pb.Error error;

  pb.ErrorCode get code => error.code;

  @override
  String toString() =>
      'RpcFailure($status, ${errorCodeName(code)}: '
      '${error.message})';
}

/// Ожидание ошибки с кодом [code].
Matcher failsWith(pb.ErrorCode code) =>
    throwsA(isA<RpcFailure>().having((f) => f.code, 'code', code));
