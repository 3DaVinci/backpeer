import 'package:admin/admin.dart';
import 'package:admin/src/config.dart';
import 'package:test/test.dart';

const _hash =
    r'argon2id$v=19$m=65536,t=3,p=1$c2FsdHNhbHRzYWx0c2E'
    r'$aGFzaGhhc2hoYXNoaGFzaGhhc2hoYXNoaGFzaA';

String _yaml({String users = '  users:\n    operator: "$_hash"\n'}) =>
    '''
listen:
  host: 127.0.0.1
  port: 8092
  cookie_secure: false
database:
  host: db.example.org
  port: 5433
  name: fs_coordinator
  user: fs_admin_web
  password: test
auth:
$users
reports:
  dir: /var/lib/fs-admin/reports
''';

void main() {
  test('настройки по умолчанию и разбор YAML', () {
    final config = AdminConfig.parse(_yaml(), {
      'FS_ADMIN_AUTH_SESSION_HOURS': '6',
      'FS_ADMIN_LISTEN_PORT': '9000',
    });
    expect(config.host, '127.0.0.1');
    expect(config.port, 9000);
    expect(config.cookieSecure, isFalse);
    expect(config.database.host, 'db.example.org');
    expect(config.database.port, 5433);
    expect(config.database.user, 'fs_admin_web');
    expect(config.users.keys, ['operator']);
    expect(config.sessionLifetime, const Duration(hours: 6));
    expect(config.onlineWindow, const Duration(minutes: 15));
    expect(config.probation, const Duration(hours: 72));
    expect(config.economy.barterRatio, 2.5);
    expect(config.reportRetentionDays, 90);
  });

  test('неизвестная настройка — ошибка', () {
    expect(
      () => AdminConfig.parse('${_yaml()}bogus: 1\n', {}),
      throwsA(
        isA<AdminConfigException>().having(
          (e) => e.message,
          'message',
          contains('bogus'),
        ),
      ),
    );
  });

  test('без операторов и с чужим хэшем — ошибка', () {
    expect(
      () => AdminConfig.parse(_yaml(users: '  users: {}\n'), {}),
      throwsA(isA<AdminConfigException>()),
    );
    expect(
      () => AdminConfig.parse(
        _yaml(users: '  users:\n    operator: "plain"\n'),
        {},
      ),
      throwsA(isA<AdminConfigException>()),
    );
  });

  test('внешний адрес проверяется', () {
    expect(
      () => AdminConfig.parse(
        _yaml().replaceFirst(
          'cookie_secure: false',
          'cookie_secure: false\n  public_url: ftp://x',
        ),
        {},
      ),
      throwsA(isA<AdminConfigException>()),
    );
  });

  test('переменные окружения важнее файла, пустые пропускаются', () {
    final config = AdminConfig.parse(_yaml(), {
      'FS_ADMIN_REPORTS_RETENTION_DAYS': '30',
      'FS_ADMIN_DATABASE_MAX_CONNECTIONS': '',
      'FS_ADMIN_LISTEN_HOST': '0.0.0.0',
    });
    expect(config.reportRetentionDays, 30);
    expect(config.host, '0.0.0.0');
    expect(config.database.maxConnections, 4);
  });
}
