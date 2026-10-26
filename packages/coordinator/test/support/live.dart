import 'dart:typed_data';

import 'package:coordinator/coordinator.dart';
import 'package:core/core.dart';

import 'postgres.dart';

/// Настоящий координатор по HTTP на свободном порту поверх временной базы,
/// с подписантом в процессе. Настройки — для стенда с узлами-заглушками
/// (`node stub`): узлы любой ёмкости, без испытательного срока, подсети
/// могут совпадать (все узлы приходят с 127.0.0.1).
final class LiveCoordinator {
  new _(this.crypto, this.db, this.server);

  static Future<LiveCoordinator> start({
    RateLimits limits = const RateLimits(
      ipPerSecond: 10000,
      ipBurst: 10000,
      keyPerSecond: 10000,
      keyBurst: 10000,
      loginPerMinute: 1000,
      loginBurst: 1000,
    ),
  }) async {
    final crypto = await SodiumCryptoProvider.load();
    final db = await TestDatabase.create();
    final config = CoordinatorConfig(
      port: 0,
      database: db.config,
      limits: limits,
      // Узлы тестов — на loopback: проверка достижимости с частных
      // адресов, как на стенде.
      nodes: const NodePolicy(minCapacityBytes: 0, checkPrivateAddresses: true),
      placement: const PlacementPolicy(
        probation: Duration.zero,
        distinctSubnets: false,
        candidatesCache: Duration.zero,
      ),
      // Сводник на loopback, порты — любые свободные.
      rendezvous: const RendezvousPolicy(
        publicHost: '127.0.0.1',
        host: '127.0.0.1',
        port: 0,
      ),
    );
    final signerKey = await crypto.ed25519FromSeed(
      SecretBytes(Uint8List(32)..fillRange(0, 32, 0xC0)),
    );
    final server = await CoordinatorServer.start(
      config,
      crypto: crypto,
      migrate: true,
      service: (database) => DatabaseCoordinatorService(
        db: database,
        crypto: crypto,
        config: config,
        signer: InProcessTicketSigner(
          TicketSigningService(
            crypto: crypto,
            key: signerKey,
            limiter: RateLimiter(perSecond: 100000, burst: 100000),
          ),
        ),
      ),
    );
    return LiveCoordinator._(crypto, db, server);
  }

  final CryptoProvider crypto;
  final TestDatabase db;
  final CoordinatorServer server;

  String get url => 'http://127.0.0.1:${server.port}';

  CoordinatorClient client({DeviceKeys? device}) => CoordinatorClient(
    baseUri: Uri.parse(url),
    crypto: crypto,
    deviceKey: device?.sign,
  );

  Future<void> close() async {
    await server.close();
    await db.drop();
  }
}
