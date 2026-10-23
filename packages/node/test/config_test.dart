import 'package:logging/logging.dart';
import 'package:node/node.dart';
import 'package:test/test.dart';

void main() {
  NodeConfig parse(String yaml, [Map<String, String> env = const {}]) =>
      NodeConfig.parse(yaml, env, dataDir: '/data');

  test(
    'по умолчанию: папка данных снаружи, квота 100 ГБ, без координатора',
    () {
      final c = parse('');
      expect(c.dataDir, '/data');
      expect(c.quotaBytes, 100000000000);
      expect(c.listenPort, 7340);
      expect(c.coordinatorUrl, isNull);
      expect(c.limits.uploadBytesPerSecond, 0);
      expect(c.shutdownGrace, const Duration(seconds: 30));
      expect(c.log.level, Level.INFO);
      expect(c.log.files, 5);
    },
  );

  test('YAML и окружение поверх него', () {
    final c = parse(
      '''
data:
  dir: /srv/node
storage:
  quota_bytes: 2000000000000
listen:
  port: 9000
  endpoints: [203.0.113.5:9000, "[2001:db8::1]:9000"]
limits:
  upload_bytes_per_second: 1000000
coordinator:
  url: https://coord.example
  keys:
    - ${'ab' * 32}
log:
  level: fine
  file: "-"
''',
      {
        'FS_NODE_LISTEN_PORT': '9100',
        'FS_NODE_LIMITS_DOWNLOAD_BYTES_PER_SECOND': '5000',
        'FS_NODE_COORDINATOR_KEYS': '${'cd' * 32}, ${'ef' * 32}',
      },
    );
    expect(c.dataDir, '/srv/node');
    expect(c.quotaBytes, 2000000000000);
    expect(c.listenPort, 9100);
    expect(c.endpoints, ['203.0.113.5:9000', '[2001:db8::1]:9000']);
    expect(c.limits.uploadBytesPerSecond, 1000000);
    expect(c.limits.downloadBytesPerSecond, 5000);
    expect(c.coordinatorUrl, 'https://coord.example');
    expect(c.coordinatorKeys, ['cd' * 32, 'ef' * 32]);
    expect(c.log.level, Level.FINE);
    expect(c.log.file, '-');
  });

  test('ошибки: неизвестный ключ, вне диапазона, адрес, ключ координатора', () {
    for (final yaml in [
      'storage:\n  qouta_bytes: 1',
      'listen:\n  port: 70000',
      'storage:\n  quota_bytes: 10',
      'coordinator:\n  url: ftp://x',
      'coordinator:\n  keys: [abc]',
      'log:\n  level: debug',
      '- список',
    ]) {
      expect(
        () => parse(yaml),
        throwsA(isA<NodeConfigException>()),
        reason: yaml,
      );
    }
    expect(
      () => parse('', {'FS_NODE_SHUTDOWN_GRACE_SECONDS': 'x'}),
      throwsA(isA<NodeConfigException>()),
    );
  });

  test('имя переменной окружения', () {
    expect(NodeConfig.envName('data.dir'), 'FS_NODE_DATA_DIR');
    expect(
      NodeConfig.envName('limits.upload_bytes_per_second'),
      'FS_NODE_LIMITS_UPLOAD_BYTES_PER_SECOND',
    );
  });
}
