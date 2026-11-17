// Модель чтения на настоящей PostgreSQL: проверяет, что запросы обзора и
// сети разбираются в типы Dart (в частности, avg(latency_ms) — numeric,
// а не double). Нужен FS_TEST_POSTGRES с правом CREATEDB.

import 'dart:io';
import 'dart:math';

import 'package:admin/src/postgres_read_model.dart';
import 'package:coordinator/coordinator.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

final String? _url = Platform.environment['FS_TEST_POSTGRES'];

final class _Db {
  new(this.config, this.admin, this.name);

  final DatabaseConfig config;
  final Connection admin;
  final String name;

  static Future<_Db> create() async {
    final url = Uri.parse(_url!);
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
    final name = 'fs_admin_test_${suffix.padLeft(8, '0')}';
    await admin.execute('CREATE DATABASE $name');
    return _Db(
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

  Future<void> drop() async {
    await admin.execute('DROP DATABASE IF EXISTS $name WITH (FORCE)');
    await admin.close();
  }
}

void main() {
  test('обзор и сеть читаются на настоящей базе', () async {
    final testDb = await _Db.create();
    final db = Database.open(testDb.config);
    addTearDown(() async {
      await db.close();
      await testDb.drop();
    });
    await Migrator(db).migrate();
    await db.run((s) async {
      await s.execute('''
        INSERT INTO accounts (account_id, created_at, login)
        VALUES (decode(repeat('aa', 32), 'hex'), now(), 'alice')''');
      await s.execute('''
        INSERT INTO nodes (node_id, account_id, certificate, registered_at)
        VALUES (
          decode(repeat('11', 32), 'hex'),
          decode(repeat('aa', 32), 'hex'),
          decode('01', 'hex'), now())''');
      await s.execute(
        '''
        INSERT INTO audits
          (node_id, fragment_id, block_index, at, passed, recheck, reason,
           latency_ms)
        VALUES (
          decode(repeat('11', 32), 'hex'),
          decode(repeat('a1', 32), 'hex'), 0, now(), true, false, NULL, 123)''',
      );
    });

    final model = PostgresReadModel(
      db,
      onlineWindow: const Duration(minutes: 15),
      probation: Duration.zero,
    );
    final overview = await model.overview();
    final overviewAudits = overview['audits']! as Map<String, Object?>;
    expect(overviewAudits['passed24h'], 1);
    expect(overviewAudits['latencyMs'], 123);
    expect(overview['stats'], isNotNull);

    final network = await model.network();
    final networkAudits = network['audits']! as Map<String, Object?>;
    expect(networkAudits['passed'], 1);
    expect(networkAudits['latencyMs'], 123);
  }, skip: _url == null ? 'FS_TEST_POSTGRES не задан' : false);
}
