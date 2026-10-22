import 'package:coordinator/src/config.dart';
import 'package:postgres/postgres.dart';

/// Пул соединений с PostgreSQL. Запись — транзакциями ([transaction]);
/// много записей одного запроса — пачкой в одной транзакции: каждая
/// фиксация — это fsync (находка 1.8.3 для SQLite, то же для PostgreSQL).
final class Database {
  new _(this._pool);

  /// Открывает пул; соединения создаются по требованию.
  factory open(DatabaseConfig config) => Database._(
    Pool<void>.withEndpoints(
      [
        Endpoint(
          host: config.host,
          port: config.port,
          database: config.name,
          username: config.user,
          password: config.password,
        ),
      ],
      settings: PoolSettings(
        maxConnectionCount: config.maxConnections,
        applicationName: 'fs-coordinator',
        connectTimeout: const Duration(seconds: 10),
        queryTimeout: const Duration(seconds: 30),
        sslMode: switch (config.ssl) {
          DatabaseSsl.disable => SslMode.disable,
          DatabaseSsl.require => SslMode.require,
          DatabaseSsl.verifyFull => SslMode.verifyFull,
        },
      ),
    ),
  );

  final Pool<void> _pool;

  /// [fn] в транзакции; исключение откатывает её.
  Future<T> transaction<T>(Future<T> Function(TxSession tx) fn) =>
      _pool.runTx(fn);

  /// [fn] без транзакции (чтение одним запросом).
  Future<T> run<T>(Future<T> Function(Session session) fn) => _pool.run(fn);

  /// База отвечает на `SELECT 1`.
  Future<bool> ping() async {
    final result = await _pool.execute('SELECT 1');
    return result.length == 1;
  }

  Future<void> close() => _pool.close();
}
