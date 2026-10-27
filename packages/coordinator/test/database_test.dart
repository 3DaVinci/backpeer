// PostgreSQL координатора (задача 2.1.4): миграции с нуля и поверх прошлой
// версии, транзакции, справочник ключей, запуск сервера. Нужен
// FS_TEST_POSTGRES (test/support/postgres.dart).

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:coordinator/coordinator.dart';
import 'package:core/core.dart';
import 'package:postgres/postgres.dart';
import 'package:protocol/protocol.dart' as pb;
import 'package:test/test.dart';

import 'support/postgres.dart';

void main() {
  if (testPostgresUrl == null) {
    test('PostgreSQL', () {}, skip: skipWithoutPostgres);
    return;
  }
  late TestDatabase testDb;
  late Database db;

  setUp(() async {
    testDb = await TestDatabase.create();
    db = Database.open(testDb.config);
  });
  tearDown(() async {
    await db.close();
    await testDb.drop();
  });

  Future<List<String>> tables() async {
    final rows = await db.run(
      (s) => s.execute(
        "SELECT tablename FROM pg_tables WHERE schemaname = 'public' "
        'ORDER BY tablename',
      ),
    );
    return [for (final r in rows) r.single! as String];
  }

  final account = Uint8List(32)..[0] = 1;
  final device = Uint8List(32)..[0] = 2;
  final node = Uint8List(32)..[0] = 3;

  group('миграции', () {
    test('с нуля до последней версии', () async {
      final migrator = Migrator(db);
      expect(await migrator.currentVersion(), 0);
      expect(await migrator.migrate(), schemaMigrations.length);
      expect(await migrator.currentVersion(), schemaMigrations.length);
      expect(await tables(), [
        'accounts',
        'admin_audit',
        'audits',
        'devices',
        'fragments',
        'login_attempts',
        'node_uptime',
        'nodes',
        'objects',
        'relay_reports',
        'relay_usage',
        'schema_migrations',
        'segments',
        'server_secrets',
        'traffic_daily',
      ]);
      // Повторный запуск ничего не меняет.
      expect(await migrator.migrate(), schemaMigrations.length);
    });

    test('поверх прошлой версии: данные сохраняются', () async {
      final migrator = Migrator(db);
      expect(await migrator.migrate(target: 1), 1);
      expect(await tables(), ['accounts', 'devices', 'schema_migrations']);
      await db.transaction((tx) async {
        await tx.execute(
          Sql.named('INSERT INTO accounts (account_id) VALUES (@a:bytea)'),
          parameters: {'a': account},
        );
        await tx.execute(
          Sql.named(
            'INSERT INTO devices (device_sign, account_id, certificate) '
            'VALUES (@d:bytea, @a:bytea, @c:bytea)',
          ),
          parameters: {'d': device, 'a': account, 'c': Uint8List(10)},
        );
      });
      expect(await migrator.migrate(), schemaMigrations.length);
      final keys = PostgresKeyDirectory(db);
      expect((await keys.lookup(device))?.kind, KeyKind.device);
      final names = await db.run(
        (s) => s.execute('SELECT name FROM schema_migrations ORDER BY version'),
      );
      expect(
        [for (final r in names) r.single],
        [for (final m in schemaMigrations) m.name],
      );
    });

    test('база новее программы — ошибка', () async {
      await Migrator(db).migrate();
      final older = Migrator(db, migrations: schemaMigrations.sublist(0, 1));
      await expectLater(
        older.currentVersion(),
        throwsA(isA<MigrationException>()),
      );
      await expectLater(older.migrate(), throwsA(isA<MigrationException>()));
    });

    test('сбой в миграции откатывает её целиком', () async {
      final broken = [
        ...schemaMigrations,
        Migration(schemaMigrations.length + 1, 'сломанная', const [
          'CREATE TABLE half (x int)',
          'SELECT * FROM нет_такой_таблицы',
        ]),
      ];
      await expectLater(
        Migrator(db, migrations: broken).migrate(),
        throwsA(isA<ServerException>()),
      );
      expect(await Migrator(db).currentVersion(), schemaMigrations.length);
      expect(await tables(), isNot(contains('half')));
    });

    test('параллельный запуск применяет каждую миграцию один раз', () async {
      final versions = await Future.wait([
        for (var i = 0; i < 4; i++)
          Migrator(Database.open(testDb.config)).migrate(),
      ]);
      expect(versions, everyElement(schemaMigrations.length));
      final rows = await db.run(
        (s) => s.execute('SELECT count(*) FROM schema_migrations'),
      );
      expect(rows.single.single, schemaMigrations.length);
    });

    test('номера миграций должны идти подряд', () {
      expect(
        () => Migrator(db, migrations: const [Migration(2, 'x', [])]),
        throwsA(isA<MigrationException>()),
      );
    });
  });

  test('транзакция откатывается при исключении', () async {
    await Migrator(db).migrate();
    await expectLater(
      db.transaction((tx) async {
        await tx.execute(
          Sql.named('INSERT INTO accounts (account_id) VALUES (@a:bytea)'),
          parameters: {'a': account},
        );
        throw StateError('отмена');
      }),
      throwsStateError,
    );
    final rows = await db.run(
      (s) => s.execute('SELECT count(*) FROM accounts'),
    );
    expect(rows.single.single, 0);
    expect(await db.ping(), isTrue);
  });

  test('справочник ключей: учётная запись, устройство, узел, отзыв', () async {
    await Migrator(db).migrate();
    final otherDevice = Uint8List(32)..[0] = 4;
    await db.transaction((tx) async {
      await tx.execute(
        Sql.named('INSERT INTO accounts (account_id) VALUES (@a:bytea)'),
        parameters: {'a': account},
      );
      for (final (key, revoked) in [(device, false), (otherDevice, true)]) {
        await tx.execute(
          Sql.named(
            'INSERT INTO devices (device_sign, account_id, certificate, '
            'revoked_at) VALUES (@d:bytea, @a:bytea, @c:bytea, '
            'CASE WHEN @r:boolean THEN now() END)',
          ),
          parameters: {'d': key, 'a': account, 'c': Uint8List(1), 'r': revoked},
        );
      }
      await tx.execute(
        Sql.named(
          'INSERT INTO nodes (node_id, account_id, certificate) '
          'VALUES (@n:bytea, @a:bytea, @c:bytea)',
        ),
        parameters: {'n': node, 'a': account, 'c': Uint8List(1)},
      );
    });
    final keys = PostgresKeyDirectory(db);
    final a = await keys.lookup(account);
    expect(a?.kind, KeyKind.account);
    expect(a?.accountId, account);
    final d = await keys.lookup(device);
    expect((d?.kind, d?.revoked), (KeyKind.device, false));
    expect(d?.accountId, account);
    expect((await keys.lookup(otherDevice))?.revoked, isTrue);
    expect((await keys.lookup(node))?.kind, KeyKind.node);
    expect(await keys.lookup(Uint8List(32)), isNull);
  });

  group('сервер', () {
    late CryptoProvider crypto;
    setUpAll(() async => crypto = await SodiumCryptoProvider.load());

    CoordinatorConfig config() =>
        CoordinatorConfig(port: 0, database: testDb.config);

    test('без миграций не запускается', () async {
      await expectLater(
        CoordinatorServer.start(config(), crypto: crypto),
        throwsA(isA<MigrationException>()),
      );
    });

    test('health-check и подписанный запрос по HTTP', () async {
      final server = await CoordinatorServer.start(
        config(),
        crypto: crypto,
        migrate: true,
      );
      addTearDown(server.close);
      final client = HttpClient();
      addTearDown(client.close);
      final base = Uri.parse('http://127.0.0.1:${server.port}');

      final health = await (await client.getUrl(base.resolve('/health')))
          .close();
      expect(health.statusCode, 200);
      expect(await utf8.decodeStream(health), '{"status":"ok"}');

      // Устройство из базы: подпись принята, метод — заглушка.
      final key = await crypto.ed25519FromSeed(SecretBytes(Uint8List(32)));
      await db.transaction((tx) async {
        await tx.execute(
          Sql.named('INSERT INTO accounts (account_id) VALUES (@a:bytea)'),
          parameters: {'a': account},
        );
        await tx.execute(
          Sql.named(
            'INSERT INTO devices (device_sign, account_id, certificate) '
            'VALUES (@d:bytea, @a:bytea, @c:bytea)',
          ),
          parameters: {'d': key.publicKey, 'a': account, 'c': Uint8List(1)},
        );
      });
      Future<(int, pb.Error)> call(Ed25519KeyPair signer) async {
        // Подпись принята — до обработчика доходит пустой запрос.
        final body = pb.LocateSegmentRequest().writeToBuffer();
        final auth = await RequestAuth.sign(
          crypto,
          signer,
          path: '/api/v1/LocateSegment',
          body: body,
        );
        final request = await client.postUrl(
          base.resolve('/api/v1/LocateSegment'),
        );
        request.headers
          ..contentType = ContentType('application', 'x-protobuf')
          ..set('FS-Auth', auth.toHeader());
        request.add(body);
        final response = await request.close();
        final bytes = await response.fold<List<int>>(
          [],
          (a, b) => a..addAll(b),
        );
        return (response.statusCode, pb.Error.fromBuffer(bytes));
      }

      final (status, error) = await call(key);
      expect(status, 400);
      expect(error.message, contains('segment_id'));

      final stranger = await crypto.ed25519FromSeed(
        SecretBytes(Uint8List(32)..[0] = 9),
      );
      final (strangerStatus, strangerError) = await call(stranger);
      expect(strangerStatus, 401);
      expect(strangerError.code, pb.ErrorCode.ERROR_CODE_UNAUTHENTICATED);
    });
  });
}
