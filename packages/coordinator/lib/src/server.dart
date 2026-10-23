import 'dart:io';

import 'package:coordinator/src/auth/request_verifier.dart';
import 'package:coordinator/src/config.dart';
import 'package:coordinator/src/db/database.dart';
import 'package:coordinator/src/db/migrations.dart';
import 'package:coordinator/src/db/postgres_key_directory.dart';
import 'package:coordinator/src/limits/rate_limiter.dart';
import 'package:coordinator/src/log.dart';
import 'package:coordinator/src/rpc/api_handler.dart';
import 'package:coordinator/src/rpc/database_service.dart';
import 'package:coordinator/src/rpc/methods.dart';
import 'package:coordinator/src/rpc/service.dart';
import 'package:coordinator/src/signer/ticket_signer.dart';
import 'package:core/core.dart';
import 'package:logging/logging.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

/// Запущенный координатор: HTTP-сервер поверх базы.
final class CoordinatorServer {
  new _(this._http, this._db, this._signer);

  /// Открывает базу, проверяет версию схемы и начинает слушать порт.
  /// Схема должна быть актуальной (`coordinator migrate`), если не задан
  /// [migrate].
  static Future<CoordinatorServer> start(
    CoordinatorConfig config, {
    required CryptoProvider crypto,
    CoordinatorService Function(Database db)? service,
    bool migrate = false,
  }) async {
    final db = Database.open(config.database);
    final socket = config.signerSocket;
    final signer = socket == null ? null : SocketTicketSigner(socket);
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
      final handler = ApiHandler(
        methods: coordinatorMethods(
          service?.call(db) ??
              DatabaseCoordinatorService(
                db: db,
                crypto: crypto,
                config: config,
                signer: signer,
              ),
        ),
        verifier: RequestVerifier(
          crypto: crypto,
          keys: PostgresKeyDirectory(db),
        ),
        ipLimiter: RateLimiter(
          perSecond: limits.ipPerSecond,
          burst: limits.ipBurst,
        ),
        keyLimiter: RateLimiter(
          perSecond: limits.keyPerSecond,
          burst: limits.keyBurst,
        ),
        healthCheck: db.ping,
        trustForwardedFor: config.trustForwardedFor,
      );
      final http = await shelf_io.serve(
        handler.call,
        config.host,
        config.port,
        securityContext: _tls(config),
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
        }),
      );
      return CoordinatorServer._(http, db, signer);
    } on Object {
      await signer?.close();
      await db.close();
      rethrow;
    }
  }

  static final _log = Logger('coordinator');

  final HttpServer _http;
  final Database _db;
  final TicketSigner? _signer;

  int get port => _http.port;

  Future<void> close() async {
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
