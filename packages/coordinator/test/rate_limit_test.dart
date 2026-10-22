// Ограничение частоты запросов (задача 2.1.5, protocol.md, раздел 4.5).

import 'package:coordinator/coordinator.dart';
import 'package:core/core.dart';
import 'package:protocol/protocol.dart' as pb;
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'support/harness.dart';

void main() {
  group('RateLimiter', () {
    test('ведро: burst сразу, потом по скорости', () {
      final clock = FakeClock();
      final limiter = RateLimiter(perSecond: 2, burst: 3, clock: clock.call);
      for (var i = 0; i < 3; i++) {
        expect(limiter.take('a'), isNull);
      }
      final wait = limiter.take('a');
      expect(wait, const Duration(milliseconds: 500));
      expect(limiter.take('b'), isNull, reason: 'другой ключ — своё ведро');
      clock.advance(const Duration(milliseconds: 500));
      expect(limiter.take('a'), isNull);
      expect(limiter.take('a'), isNotNull);
      clock.advance(const Duration(hours: 1));
      for (var i = 0; i < 3; i++) {
        expect(limiter.take('a'), isNull, reason: 'не больше burst');
      }
      expect(limiter.take('a'), isNotNull);
    });

    test('запрос весом в несколько токенов', () {
      final clock = FakeClock();
      final limiter = RateLimiter(perSecond: 10, burst: 20, clock: clock.call);
      expect(limiter.take('a', cost: 15), isNull);
      expect(
        limiter.take('a', cost: 10),
        const Duration(milliseconds: 500),
        reason: 'не хватает 5 токенов',
      );
      expect(limiter.take('a', cost: 5), isNull, reason: 'отказ не списал');
      expect(() => limiter.take('a', cost: 21), throwsArgumentError);
      expect(() => limiter.take('a', cost: 0), throwsArgumentError);
    });

    test('полные вёдра удаляются, таблица ограничена', () {
      final clock = FakeClock();
      final limiter = RateLimiter(
        perSecond: 10,
        burst: 10,
        maxKeys: 3,
        clock: clock.call,
      );
      for (final k in ['a', 'b', 'c']) {
        expect(limiter.take(k), isNull);
      }
      expect(limiter.take('d'), isNotNull, reason: 'таблица заполнена');
      clock.advance(const Duration(seconds: 2));
      expect(limiter.take('d'), isNull);
      expect(limiter.trackedKeys, 1);
    });
  });

  group('через API', () {
    test('превышение по IP — 429 до проверки подписи', () async {
      final h = await Harness.create(
        limits: const RateLimits(
          ipPerSecond: 1,
          ipBurst: 2,
          keyPerSecond: 100,
          keyBurst: 101,
        ),
        trustForwardedFor: true,
      );
      Future<Response> from(String ip) => h.post(
        'GetObject',
        [],
        authHeader: 'неверная подпись',
        headers: {'x-forwarded-for': '10.0.0.1, $ip'},
      );
      expect((await from('192.0.2.1')).statusCode, 401);
      expect((await from('192.0.2.1')).statusCode, 401);
      final limited = await from('192.0.2.1');
      expect(limited.statusCode, 429);
      expect(limited.headers['retry-after'], '1');
      final error = await errorOf(limited);
      expect(error.code, pb.ErrorCode.ERROR_CODE_RATE_LIMITED);
      expect(error.retryAfterMs, 1000);
      // Другой адрес за тем же прокси — своё ведро.
      expect((await from('192.0.2.2')).statusCode, 401);
    });

    test('X-Forwarded-For без trust_forwarded_for не учитывается', () async {
      final h = await Harness.create(
        limits: const RateLimits(
          ipPerSecond: 1,
          ipBurst: 1,
          keyPerSecond: 100,
          keyBurst: 101,
        ),
      );
      Future<int> from(String ip) async => (await h.post(
        'GetKeyBundle',
        [],
        headers: {'x-forwarded-for': ip},
      )).statusCode;
      expect(await from('192.0.2.1'), 500);
      expect(await from('192.0.2.2'), 429);
    });

    test('превышение по ключу — 429 после проверки подписи', () async {
      final h = await Harness.create(
        limits: const RateLimits(
          ipPerSecond: 100,
          ipBurst: 100,
          keyPerSecond: 1,
          keyBurst: 2,
        ),
      );
      final a = await h.newKey(kind: KeyKind.device);
      final b = await h.newKey(kind: KeyKind.device);
      Future<int> call(Ed25519KeyPair key) async {
        // Новая миллисекунда — новая подпись, иначе это повтор.
        h.clock.advance(const Duration(milliseconds: 1));
        return (await h.post('ListObjects', [], key: key)).statusCode;
      }

      expect(await call(a), 500);
      expect(await call(a), 500);
      expect(await call(a), 429);
      expect(await call(b), 500, reason: 'другой ключ — своё ведро');
      h.clock.advance(const Duration(seconds: 1));
      expect(await call(a), 500);
    });
  });
}
