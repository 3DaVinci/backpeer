import 'dart:io';
import 'dart:math';

import 'package:coordinator/coordinator.dart';
import 'package:postgres/postgres.dart';

/// Адрес PostgreSQL для тестов: `FS_TEST_POSTGRES`, например
/// `postgres://fs:пароль@127.0.0.1:5432/postgres`. Пользователь должен
/// иметь право `CREATEDB`: каждый тест получает свою базу.
final String? testPostgresUrl = Platform.environment['FS_TEST_POSTGRES'];

/// Причина пропуска тестов с базой или `false`.
Object get skipWithoutPostgres =>
    testPostgresUrl == null ? 'FS_TEST_POSTGRES не задан' : false;

/// Временная база данных: создаётся пустой, удаляется в [drop].
final class TestDatabase {
  new _(this.config, this._admin, this._name);

  static Future<TestDatabase> create() async {
    final url = Uri.parse(testPostgresUrl!);
    final user = url.userInfo.split(':');
    final base = DatabaseConfig(
      host: url.host,
      port: url.hasPort ? url.port : 5432,
      name: url.pathSegments.isEmpty ? 'postgres' : url.pathSegments.first,
      user: Uri.decodeComponent(user.first),
      password: user.length > 1 ? Uri.decodeComponent(user[1]) : null,
    );
    final admin = await Connection.open(
      Endpoint(
        host: base.host,
        port: base.port,
        database: base.name,
        username: base.user,
        password: base.password,
      ),
      settings: const ConnectionSettings(sslMode: SslMode.disable),
    );
    final suffix = Random().nextInt(1 << 32).toRadixString(16);
    final name = 'fs_test_${suffix.padLeft(8, '0')}';
    await admin.execute('CREATE DATABASE $name');
    return TestDatabase._(
      DatabaseConfig(
        host: base.host,
        port: base.port,
        name: name,
        user: base.user,
        password: base.password,
        maxConnections: 4,
      ),
      admin,
      name,
    );
  }

  final DatabaseConfig config;
  final Connection _admin;
  final String _name;

  final List<String> _roles = [];

  /// Роль кластера с входом по паролю [password]; удаляется в [drop].
  /// Пользователю тестов нужно право `CREATEROLE`, иначе
  /// `ServerException` с кодом 42501.
  Future<void> createRole(String role, String password) async {
    await _admin.execute("CREATE ROLE $role LOGIN PASSWORD '$password'");
    _roles.add(role);
  }

  /// Настройки подключения к базе теста от имени [role].
  DatabaseConfig as(String role, String password) => DatabaseConfig(
    host: config.host,
    port: config.port,
    name: config.name,
    user: role,
    password: password,
    maxConnections: 2,
  );

  Future<void> drop() async {
    await _admin.execute('DROP DATABASE IF EXISTS $_name WITH (FORCE)');
    for (final role in _roles) {
      await _admin.execute('DROP ROLE IF EXISTS $role');
    }
    await _admin.close();
  }
}
