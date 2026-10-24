// Расписание пределов скорости и настройки собеседников (задача 3.4.3).

import 'package:node/node.dart';
import 'package:test/test.dart';

void main() {
  const base = SpeedLimits(
    uploadBytesPerSecond: 5000000,
    downloadBytesPerSecond: 6000000,
  );

  // 26.10.2026 — понедельник.
  DateTime at(int day, int hour, [int minute = 0]) =>
      DateTime(2026, 10, 25 + day, hour, minute);

  test('будни днём медленнее, вне правила — основные пределы', () {
    final s = SpeedSchedule.parse([
      'mon-fri 09:00-18:00 upload=1000000 download=2000000',
    ]);
    final day = s.at(at(1, 12), base);
    expect(day.uploadBytesPerSecond, 1000000);
    expect(day.downloadBytesPerSecond, 2000000);
    expect(s.at(at(1, 18), base), same(base));
    expect(s.at(at(1, 8, 59), base), same(base));
    // Суббота.
    expect(s.at(at(6, 12), base), same(base));
  });

  test('не указанный предел — из основных', () {
    final s = SpeedSchedule.parse(['09:00-18:00 upload=0']);
    final l = s.at(at(3, 10), base);
    expect(l.uploadBytesPerSecond, 0);
    expect(l.downloadBytesPerSecond, 6000000);
  });

  test('через полночь — по дню начала', () {
    final s = SpeedSchedule.parse(['fri 23:00-07:00 download=100']);
    expect(s.at(at(5, 23, 30), base).downloadBytesPerSecond, 100);
    // Суббота утром — продолжение пятничного правила.
    expect(s.at(at(6, 6, 59), base).downloadBytesPerSecond, 100);
    expect(s.at(at(6, 7), base), same(base));
    // Пятница утром — продолжение четверга, которого в правиле нет.
    expect(s.at(at(5, 6), base), same(base));
  });

  test('дни списком и промежутком через воскресенье', () {
    final r = SpeedRule.parse('sat,sun 00:00-24:00 upload=1');
    expect(r.days, {6, 7});
    expect(SpeedRule.parse('fri-mon 10:00-11:00 upload=1').days, {5, 6, 7, 1});
    expect(r.matches(at(7, 23, 59)), isTrue);
  });

  test('первое подходящее правило', () {
    final s = SpeedSchedule.parse([
      '12:00-13:00 upload=1',
      '09:00-18:00 upload=2',
    ]);
    expect(s.at(at(2, 12, 30), base).uploadBytesPerSecond, 1);
    expect(s.at(at(2, 14), base).uploadBytesPerSecond, 2);
    expect(s.toJson(), ['12:00-13:00 upload=1', '09:00-18:00 upload=2']);
  });

  test('ошибки в правилах', () {
    for (final bad in [
      '',
      'mon-fri',
      '9:00-18:00 upload=1',
      '09:00-25:00 upload=1',
      '09:00-09:00 upload=1',
      '09:00-18:00',
      '09:00-18:00 up=1',
      'moon 09:00-18:00 upload=1',
      '09:00-18:00 upload=-1',
    ]) {
      expect(
        () => SpeedRule.parse(bad),
        throwsA(isA<NodeConfigException>()),
        reason: bad,
      );
    }
  });

  test('настройки: limits.schedule и peers.*', () {
    final c = NodeConfig.parse(
      '''
limits:
  upload_bytes_per_second: 1000
  schedule:
    - mon-fri 09:00-18:00 upload=100
peers:
  max_connections: 10
  max_connections_per_peer: 2
  max_requests_per_peer: 4
  requests_per_second: 20
  transfer_timeout_seconds: 5
  idle_timeout_seconds: 60
''',
      const {},
      dataDir: '/data',
    );
    expect(c.schedule.toJson(), ['mon-fri 09:00-18:00 upload=100']);
    expect(c.peers.maxConnections, 10);
    expect(c.peers.maxConnectionsPerPeer, 2);
    expect(c.peers.maxRequestsPerPeer, 4);
    expect(c.peers.requestsPerSecond, 20);
    expect(c.peers.transferTimeout, const Duration(seconds: 5));
    expect(c.peers.idleTimeout, const Duration(minutes: 1));

    final env = NodeConfig.parse('', const {
      'FS_NODE_LIMITS_SCHEDULE':
          'sat,sun 10:00-12:00 download=2; 23:00-07:00 upload=0',
    }, dataDir: '/data');
    // В окружении правила — через «;», дни внутри правила — через запятую.
    expect(env.schedule.rules, hasLength(2));
    expect(env.schedule.rules.first.days, {6, 7});

    final defaults = NodeConfig.parse('', const {}, dataDir: '/data');
    expect(defaults.schedule.rules, isEmpty);
    expect(defaults.peers.maxConnections, 256);
    expect(
      () => NodeConfig.parse(
        'limits: {schedule: ["bad"]}',
        const {},
        dataDir: '/d',
      ),
      throwsA(isA<NodeConfigException>()),
    );
  });
}
