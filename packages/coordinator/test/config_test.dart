// Настройки координатора: YAML и переменные окружения (задача 2.1.4).

import 'dart:io';

import 'package:coordinator/coordinator.dart';
import 'package:logging/logging.dart';
import 'package:test/test.dart';

void main() {
  test('пустые настройки — значения по умолчанию', () {
    final c = CoordinatorConfig.parse('', {});
    expect(c.host, '127.0.0.1');
    expect(c.port, 8443);
    expect(c.tlsCertificate, isNull);
    expect(c.database.name, 'fs_coordinator');
    expect(c.database.ssl, DatabaseSsl.disable);
    expect(c.limits.ipBurst, 200);
    expect(c.maxObjectBytesPerAccount, 1 << 30);
    expect(c.nodes.minCapacityBytes, 100000000000);
    expect(c.nodes.heartbeatInterval, const Duration(minutes: 5));
    expect(c.logLevel, Level.INFO);
  });

  test('размещение и подписант (2.7)', () {
    final c = CoordinatorConfig.parse('''
placement:
  min_availability: 0.7
  probation_hours: 24
  max_probation_share: 0.1
  ticket_minutes: 15
  distinct_subnets: false
signer:
  socket: /run/fs-signer/signer.sock
''', {});
    expect(c.placement.minAvailability, 0.7);
    expect(c.placement.probation, const Duration(hours: 24));
    expect(c.placement.maxProbation(20), 2);
    expect(c.placement.ticketLifetime, const Duration(minutes: 15));
    expect(c.placement.distinctSubnets, isFalse);
    expect(const PlacementPolicy().distinctSubnets, isTrue);
    expect(c.signerSocket, '/run/fs-signer/signer.sock');
    expect(const CoordinatorConfig().signerSocket, isNull);
    for (final bad in [
      'placement:\n  min_availability: 1.5\n',
      'placement:\n  ticket_minutes: 61\n',
    ]) {
      expect(
        () => CoordinatorConfig.parse(bad, {}),
        throwsA(isA<ConfigException>()),
      );
    }
  });

  test('объекты и реестр узлов (2.5, 2.6)', () {
    final c = CoordinatorConfig.parse(
      '''
accounts:
  max_object_bytes: 2097152
nodes:
  min_capacity_bytes: 0
  max_per_account: 3
''',
      {'FS_COORDINATOR_NODES_HEARTBEAT_SECONDS': '60'},
    );
    expect(c.maxObjectBytesPerAccount, 2097152);
    expect(c.nodes.minCapacityBytes, 0);
    expect(c.nodes.maxPerAccount, 3);
    expect(c.nodes.heartbeatInterval, const Duration(minutes: 1));
    expect(
      () => CoordinatorConfig.parse('nodes:\n  heartbeat_seconds: 1\n', {}),
      throwsA(isA<ConfigException>()),
    );
  });

  test('пример настроек из docs/ops разбирается', () {
    final c = CoordinatorConfig.parse(
      File('config/coordinator.example.yaml').readAsStringSync(),
      {},
    );
    expect(c.database.ssl, DatabaseSsl.verifyFull);
    expect(c.trustForwardedFor, isTrue);
  });

  test('YAML и окружение поверх него', () {
    final c = CoordinatorConfig.parse(
      '''
listen:
  host: 0.0.0.0
  port: 9000
database:
  host: db.internal
  ssl: require
  max_connections: 4
limits:
  ip_per_second: 2.5
log:
  level: warning
''',
      {
        'FS_COORDINATOR_LISTEN_PORT': '9443',
        'FS_COORDINATOR_DATABASE_PASSWORD': 'секрет',
        'FS_COORDINATOR_LISTEN_TRUST_FORWARDED_FOR': 'true',
        'UNRELATED': 'x',
      },
    );
    expect(c.host, '0.0.0.0');
    expect(c.port, 9443);
    expect(c.trustForwardedFor, isTrue);
    expect(c.database.host, 'db.internal');
    expect(c.database.ssl, DatabaseSsl.require);
    expect(c.database.maxConnections, 4);
    expect(c.database.password, 'секрет');
    expect(c.limits.ipPerSecond, 2.5);
    expect(c.logLevel, Level.WARNING);
  });

  test('пароль из файла', () {
    final dir = Directory.systemTemp.createTempSync('fs-config-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/password')..writeAsStringSync('из файла\n');
    final c = CoordinatorConfig.parse(
      'database:\n  password_file: ${file.path}\n',
      {},
    );
    expect(c.database.password, 'из файла');
  });

  test('пароль не попадает в toString', () {
    final c = CoordinatorConfig.parse('database:\n  password: hunter2\n', {});
    expect('${c.database}', isNot(contains('hunter2')));
  });

  group('ошибки', () {
    for (final (name, yaml, env) in [
      ('неизвестный ключ', 'listen:\n  prot: 1\n', <String, String>{}),
      ('порт вне диапазона', 'listen:\n  port: 70000\n', <String, String>{}),
      ('порт не число', '', {'FS_COORDINATOR_LISTEN_PORT': 'abc'}),
      ('неверный ssl', 'database:\n  ssl: maybe\n', <String, String>{}),
      (
        'неверный bool',
        'listen:\n  trust_forwarded_for: yes\n',
        <String, String>{},
      ),
      (
        'сертификат без ключа',
        'tls:\n  certificate: a.pem\n',
        <String, String>{},
      ),
      (
        'пароль и файл пароля',
        'database:\n  password: a\n  password_file: b\n',
        <String, String>{},
      ),
      (
        'нет файла пароля',
        'database:\n  password_file: /нет/такого\n',
        <String, String>{},
      ),
      (
        'скорость не положительна',
        'limits:\n  key_per_second: 0\n',
        <String, String>{},
      ),
      ('корень не словарь', '- 1\n', <String, String>{}),
      ('битый YAML', 'listen: [\n', <String, String>{}),
    ]) {
      test(name, () {
        expect(
          () => CoordinatorConfig.parse(yaml, env),
          throwsA(isA<ConfigException>()),
        );
      });
    }
  });
}
