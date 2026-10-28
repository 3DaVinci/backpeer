import 'dart:async';
import 'dart:io';

import 'package:coordinator/src/audits/audit_service.dart';
import 'package:coordinator/src/auth/key_directory.dart';
import 'package:coordinator/src/auth/request_verifier.dart';
import 'package:coordinator/src/config.dart';
import 'package:coordinator/src/db/database.dart';
import 'package:coordinator/src/db/migrations.dart';
import 'package:coordinator/src/db/postgres_key_directory.dart';
import 'package:coordinator/src/log.dart';
import 'package:coordinator/src/nodes/node_channels.dart';
import 'package:coordinator/src/nodes/rendezvous.dart';
import 'package:coordinator/src/repair/repair_service.dart';
import 'package:coordinator/src/rpc/api_handler.dart';
import 'package:coordinator/src/rpc/database_service.dart';
import 'package:coordinator/src/rpc/methods.dart';
import 'package:coordinator/src/rpc/service.dart';
import 'package:coordinator/src/signer/ticket_signer.dart';
import 'package:core/core.dart';
import 'package:fixnum/fixnum.dart';
import 'package:logging/logging.dart';
import 'package:protocol/protocol.dart' as pb;
import 'package:shelf/shelf_io.dart' as shelf_io;

/// Запущенный координатор: HTTP-сервер поверх базы и канал команд узлов
/// (`GET /api/v1/NodeChannel`, [channels]).
final class CoordinatorServer {
  new _(
    this._http,
    this._db,
    this._signer,
    this.channels,
    this._watch,
    this.rendezvous,
    this.audits,
    this.repair,
  );

  /// Открывает базу, проверяет версию схемы и начинает слушать порт.
  /// Схема должна быть актуальной (`coordinator migrate`), если не задан
  /// [migrate]. Ключ пропусков relay читается из `relay.pass_key_file`.
  static Future<CoordinatorServer> start(
    CoordinatorConfig config, {
    required CryptoProvider crypto,
    CoordinatorService Function(Database db)? service,
    bool migrate = false,
  }) async {
    final relayPassKey = switch (config.relay.passKeyFile) {
      final path? when service == null => await Ed25519KeyFile.load(
        path,
        crypto,
      ),
      _ => null,
    };
    final db = Database.open(config.database);
    final socket = config.signerSocket;
    final signer = socket == null ? null : SocketTicketSigner(socket);
    RendezvousService? rendezvous;
    AuditService? audits;
    RepairService? repair;
    try {
      final migrator = Migrator(db);
      final version = migrate
          ? await migrator.migrate()
          : await migrator.currentVersion();
      if (version != migrator.latestVersion) {
        throw MigrationException(
          'схема базы версии $version, нужна ${migrator.latestVersion}: '
          'выполните coordinator migrate',
        );
      }
      final limits = config.limits;
      final coordinatorService =
          service?.call(db) ??
          DatabaseCoordinatorService(
            db: db,
            crypto: crypto,
            config: config,
            signer: signer,
            relayPassKey: relayPassKey,
          );
      final verifier = RequestVerifier(
        crypto: crypto,
        keys: RelayKeyDirectory(PostgresKeyDirectory(db), [
          for (final r in config.relay.servers) r.publicKey,
        ]),
      );
      final ipLimiter = RateLimiter(
        perSecond: limits.ipPerSecond,
        burst: limits.ipBurst,
      );
      final keyLimiter = RateLimiter(
        perSecond: limits.keyPerSecond,
        burst: limits.keyBurst,
      );
      final handler = ApiHandler(
        methods: coordinatorMethods(coordinatorService),
        verifier: verifier,
        ipLimiter: ipLimiter,
        keyLimiter: keyLimiter,
        healthCheck: db.ping,
        trustForwardedFor: config.trustForwardedFor,
      );
      final channels = NodeChannels(
        service: coordinatorService,
        verifier: verifier,
        keys: verifier.keys,
        ipLimiter: ipLimiter,
        keyLimiter: keyLimiter,
        policy: config.channels,
        trustForwardedFor: config.trustForwardedFor,
      );
      if (coordinatorService case final DatabaseCoordinatorService s) {
        rendezvous = s.rendezvousService..channels = channels;
        await rendezvous.start();
        audits = (s.audits..channels = channels)..start();
        repair = s.repair..start();
      }
      // Новый отзыв устройства — узлы в канале дочитывают ListRevocations
      // сразу, не дожидаясь heartbeat.
      // ignore: cancel_subscriptions — отменяется в close.
      final watch = switch (coordinatorService) {
        final DatabaseCoordinatorService s => s.accounts.revocations.listen(
          (sequence) => channels.broadcast(
            pb.CoordinatorChannelMessage(
              syncRevocations: pb.SyncRevocationsCommand(
                sequence: Int64(sequence),
              ),
            ),
          ),
        ),
        _ => null,
      };
      final context = _tls(config);
      final http = context == null
          ? await HttpServer.bind(config.host, config.port)
          : await HttpServer.bindSecure(config.host, config.port, context);
      shelf_io.serveRequests(
        http.where((request) {
          if (!channels.handles(request)) return true;
          unawaited(channels.handle(request));
          return false;
        }),
        handler.call,
        poweredByHeader: null,
      );
      // Сервер сам ограничивает тело; простаивающие соединения закрываем.
      http
        ..idleTimeout = const Duration(seconds: 60)
        ..autoCompress = false;
      _log.info(
        LogEvent('listening', {
          'port': http.port,
          'tls': config.tlsCertificate != null,
          'schema': version,
          'signer': signer != null,
          'rendezvous': ?rendezvous?.ports,
          'relays': config.relay.servers.length,
          'audits': audits != null && config.audits.enabled,
          'repair': repair != null && config.repair.enabled,
        }),
      );
      if (!config.placement.distinctSubnets) {
        _log.warning(
          const LogEvent('placement_subnets_not_distinct', {
            'note': 'только для локального стенда',
          }),
        );
      }
      return CoordinatorServer._(
        http,
        db,
        signer,
        channels,
        watch,
        rendezvous,
        audits,
        repair,
      );
    } on Object {
      await repair?.close();
      await audits?.close();
      await rendezvous?.close();
      await signer?.close();
      await db.close();
      rethrow;
    }
  }

  static final _log = Logger('coordinator');

  final HttpServer _http;
  final Database _db;
  final TicketSigner? _signer;
  final StreamSubscription<int>? _watch;

  /// Открытые каналы команд узлов.
  final NodeChannels channels;

  /// Сведение узлов; `null` — сервис без базы (тесты).
  final RendezvousService? rendezvous;

  /// Аудиты хранения; `null` — сервис без базы (тесты).
  final AuditService? audits;

  /// Ремонт сегментов; `null` — сервис без базы (тесты).
  final RepairService? repair;

  int get port => _http.port;

  Future<void> close() async {
    await _watch?.cancel();
    await repair?.close();
    await audits?.close();
    await channels.close();
    await rendezvous?.close();
    await _http.close();
    await _signer?.close();
    await _db.close();
    _log.info(const LogEvent('stopped'));
  }

  static SecurityContext? _tls(CoordinatorConfig config) {
    final cert = config.tlsCertificate;
    final key = config.tlsPrivateKey;
    if (cert == null || key == null) return null;
    return SecurityContext()
      ..useCertificateChain(cert)
      ..usePrivateKey(key);
  }
}
