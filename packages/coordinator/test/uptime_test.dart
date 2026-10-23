// Доступность узла и адреса (задачи 2.6.1, 2.6.2) — без базы.

import 'dart:typed_data';

import 'package:coordinator/coordinator.dart';
import 'package:test/test.dart';

void main() {
  group('Uptime', () {
    final start = DateTime.utc(2026, 9);

    Map<int, Uint8List> history(Iterable<DateTime> beats) {
      final days = <int, Uint8List>{};
      for (final t in beats) {
        final slot = Uptime.slotAt(t);
        Uptime.mark(
          days.putIfAbsent(Uptime.dayOf(slot), Uptime.emptyDay),
          slot,
        );
      }
      return days;
    }

    Iterable<DateTime> every(Duration step, DateTime from, DateTime to) sync* {
      for (var t = from; t.isBefore(to); t = t.add(step)) {
        yield t;
      }
    }

    test('узел в сети половину времени за 30 дней — 0,5', () {
      final now = start.add(const Duration(days: 40));
      // Сутки в сети, сутки нет; heartbeat каждые 5 минут.
      final beats = every(
        const Duration(minutes: 5),
        start,
        now,
      ).where((t) => t.difference(start).inDays.isEven);
      final a = Uptime.availability(
        history(beats),
        registeredAt: start,
        now: now.subtract(const Duration(milliseconds: 1)),
      );
      expect(a, closeTo(0.5, 0.01));
    });

    test('всё время в сети — 1, ни разу — 0', () {
      final now = start.add(const Duration(days: 31));
      final always = history(every(const Duration(minutes: 15), start, now));
      expect(
        Uptime.availability(always, registeredAt: start, now: now),
        closeTo(1, 0.001),
      );
      expect(Uptime.availability({}, registeredAt: start, now: now), 0);
    });

    test('узел моложе окна считается с регистрации', () {
      final registered = start;
      final now = start.add(const Duration(days: 2));
      // Первые сутки в сети, вторые — нет.
      final beats = every(
        const Duration(minutes: 15),
        registered,
        registered.add(const Duration(days: 1)),
      );
      final a = Uptime.availability(
        history(beats),
        registeredAt: registered,
        now: now.subtract(const Duration(milliseconds: 1)),
      );
      expect(a, closeTo(0.5, 0.01));
    });

    test('биты — как set_bit для bytea', () {
      final day = Uptime.emptyDay();
      Uptime.mark(day, 0);
      Uptime.mark(day, 9);
      Uptime.mark(day, 95);
      expect(day[0], 0x01);
      expect(day[1], 0x02);
      expect(day[11], 0x80);
    });
  });

  group('NodeAddresses', () {
    test('подсеть /24 для IPv4 и /48 для IPv6', () {
      expect(NodeAddresses.subnetOf('203.0.113.77'), '203.0.113.0/24');
      expect(NodeAddresses.subnetOf('::ffff:203.0.113.5'), '203.0.113.0/24');
      expect(
        NodeAddresses.subnetOf('2001:db8:abcd:12::1'),
        '2001:db8:abcd::/48',
      );
      expect(NodeAddresses.subnetOf('не адрес'), isNull);
      expect(NodeAddresses.subnetOf(''), isNull);
    });

    test('адреса host:port', () {
      for (final ok in [
        '203.0.113.1:7000',
        'node.example.org:443',
        '[2001:db8::1]:7000',
        'localhost:1',
      ]) {
        expect(NodeAddresses.endpointProblem(ok), isNull, reason: ok);
      }
      for (final bad in [
        '',
        '203.0.113.1',
        '203.0.113.1:0',
        '203.0.113.1:65536',
        '203.0.113.1:07000',
        '2001:db8::1:7000',
        '[2001:db8::1]7000',
        '[203.0.113.1]:7000',
        'bad_host:7000',
        '-host:7000',
        ':7000',
      ]) {
        expect(NodeAddresses.endpointProblem(bad), isNotNull, reason: bad);
      }
      expect(
        NodeAddresses.endpointsProblem(['a.example:1', 'a.example:1']),
        isNotNull,
      );
      expect(
        NodeAddresses.endpointsProblem([
          for (var i = 1; i <= 9; i++) 'a.example:$i',
        ]),
        isNotNull,
      );
    });
  });
}
