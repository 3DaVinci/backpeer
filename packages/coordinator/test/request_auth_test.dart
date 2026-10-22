// Проверка подписи запроса FS-Auth на координаторе (задача 2.1.3,
// protocol.md, разделы 4.2 и 4.3): подделка, окно времени, повтор,
// неизвестный и отозванный ключ, вид ключа.

import 'dart:typed_data';

import 'package:coordinator/coordinator.dart';
import 'package:core/core.dart';
import 'package:protocol/protocol.dart' as pb;
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'support/harness.dart';

void main() {
  late Harness h;
  late Ed25519KeyPair device;
  final body = pb.GetObjectRequest(objectId: [1, 2, 3]).writeToBuffer();

  setUp(() async {
    h = await Harness.create();
    device = await h.newKey(kind: KeyKind.device);
  });

  Future<pb.ErrorCode> codeOf(Future<Response> response) async =>
      (await errorOf(await response)).code;

  const unauthenticated = pb.ErrorCode.ERROR_CODE_UNAUTHENTICATED;
  // Заглушка метода: подпись принята, дальше «не реализован».
  const accepted = pb.ErrorCode.ERROR_CODE_INTERNAL;

  test('верная подпись принимается', () async {
    expect(await codeOf(h.post('GetObject', body, key: device)), accepted);
  });

  test('без заголовка — 401', () async {
    final response = await h.post('GetObject', body);
    expect(response.statusCode, 401);
    expect((await errorOf(response)).code, unauthenticated);
  });

  group('подделка', () {
    late RequestAuth good;
    setUp(() async {
      good = await RequestAuth.sign(
        h.crypto,
        device,
        path: '/api/v1/GetObject',
        body: body,
        timeMs: h.clock.now.millisecondsSinceEpoch,
      );
    });

    test('подпись над другим телом', () async {
      final other = Uint8List.fromList([...body, 0]);
      expect(
        await codeOf(h.post('GetObject', other, authHeader: good.toHeader())),
        unauthenticated,
      );
    });

    test('подпись над другим методом', () async {
      expect(
        await codeOf(h.post('DeleteObject', body, authHeader: good.toHeader())),
        unauthenticated,
      );
    });

    test('подменено время', () async {
      final header = good.toHeader().replaceFirst(
        '.${good.timeMs}.',
        '.${good.timeMs + 1}.',
      );
      expect(
        await codeOf(h.post('GetObject', body, authHeader: header)),
        unauthenticated,
      );
    });

    test('подпись чужим ключом под известным ключом', () async {
      final stranger = await h.newKey();
      final forged = await RequestAuth.sign(
        h.crypto,
        stranger,
        path: '/api/v1/GetObject',
        body: body,
        timeMs: good.timeMs,
      );
      final header =
          '${bytesToHex(device.publicKey)}.${good.timeMs}.'
          '${bytesToHex(forged.signature)}';
      expect(
        await codeOf(h.post('GetObject', body, authHeader: header)),
        unauthenticated,
      );
    });

    test('испорченный заголовок', () async {
      for (final header in [
        '',
        'abc',
        good.toHeader().toUpperCase(),
        '${good.toHeader()}.',
        good.toHeader().substring(1),
      ]) {
        expect(
          await codeOf(h.post('GetObject', body, authHeader: header)),
          unauthenticated,
          reason: header,
        );
      }
    });
  });

  group('окно времени ±5 минут', () {
    int at(Duration offset) => h.clock.now.add(offset).millisecondsSinceEpoch;

    test('на границе окна принимается', () async {
      for (final offset in [
        const Duration(minutes: -5),
        const Duration(minutes: 5),
      ]) {
        expect(
          await codeOf(
            h.post('GetObject', body, key: device, timeMs: at(offset)),
          ),
          accepted,
          reason: '$offset',
        );
      }
    });

    test('просроченное и будущее время — 401', () async {
      for (final offset in [
        const Duration(minutes: -5, milliseconds: -1),
        const Duration(minutes: 5, milliseconds: 1),
        const Duration(days: -365),
      ]) {
        expect(
          await codeOf(
            h.post('GetObject', body, key: device, timeMs: at(offset)),
          ),
          unauthenticated,
          reason: '$offset',
        );
      }
    });
  });

  group('повтор', () {
    test('тот же запрос второй раз — 401', () async {
      final auth = await RequestAuth.sign(
        h.crypto,
        device,
        path: '/api/v1/GetObject',
        body: body,
        timeMs: h.clock.now.millisecondsSinceEpoch,
      );
      expect(
        await codeOf(h.post('GetObject', body, authHeader: auth.toHeader())),
        accepted,
      );
      h.clock.advance(const Duration(minutes: 4));
      expect(
        await codeOf(h.post('GetObject', body, authHeader: auth.toHeader())),
        unauthenticated,
      );
    });

    test('повтор с новой подписью принимается', () async {
      expect(await codeOf(h.post('GetObject', body, key: device)), accepted);
      h.clock.advance(const Duration(milliseconds: 1));
      expect(await codeOf(h.post('GetObject', body, key: device)), accepted);
    });

    test('неверная подпись не запоминается', () async {
      final auth = await RequestAuth.sign(
        h.crypto,
        device,
        path: '/api/v1/GetObject',
        body: body,
        timeMs: h.clock.now.millisecondsSinceEpoch,
      );
      // Та же подпись к другому телу отклонена…
      expect(
        await codeOf(
          h.post('GetObject', [...body, 0], authHeader: auth.toHeader()),
        ),
        unauthenticated,
      );
      // …и не мешает настоящему запросу.
      expect(
        await codeOf(h.post('GetObject', body, authHeader: auth.toHeader())),
        accepted,
      );
    });

    test('кеш подписей чистится после выхода из окна', () {
      final cache = ReplayCache(capacity: 2);
      final a = Uint8List(64)..[0] = 1;
      final b = Uint8List(64)..[0] = 2;
      final c = Uint8List(64)..[0] = 3;
      expect(cache.remember(a, expiresAtMs: 1000, nowMs: 0), isTrue);
      expect(cache.remember(a, expiresAtMs: 1000, nowMs: 500), isFalse);
      expect(cache.remember(b, expiresAtMs: 1000, nowMs: 500), isTrue);
      expect(
        () => cache.remember(c, expiresAtMs: 2000, nowMs: 600),
        throwsA(isA<ReplayCacheFullException>()),
      );
      expect(cache.remember(c, expiresAtMs: 2000, nowMs: 1001), isTrue);
      expect(cache.length, 1);
    });

    test('переполненный кеш — UNAVAILABLE, а не вытеснение', () async {
      final verifier = RequestVerifier(
        crypto: h.crypto,
        keys: h.keys,
        clock: h.clock.call,
        replayCapacity: 1,
      );
      Future<void> verify() async {
        final auth = await RequestAuth.sign(
          h.crypto,
          device,
          path: '/p',
          body: const [],
          timeMs: h.clock.now.millisecondsSinceEpoch,
        );
        h.clock.advance(const Duration(milliseconds: 1));
        await verifier.verify(
          requirement: AuthRequirement.device,
          path: '/p',
          header: auth.toHeader(),
          body: const [],
        );
      }

      await verify();
      await expectLater(
        verify(),
        throwsA(
          isA<RpcException>().having(
            (e) => e.code,
            'code',
            pb.ErrorCode.ERROR_CODE_UNAVAILABLE,
          ),
        ),
      );
    });
  });

  group('ключи', () {
    test('неизвестный ключ — 401', () async {
      final stranger = await h.newKey();
      expect(
        await codeOf(h.post('GetObject', body, key: stranger)),
        unauthenticated,
      );
    });

    test('отозванное устройство — 401', () async {
      final revoked = await h.newKey(kind: KeyKind.device, revoked: true);
      expect(
        await codeOf(h.post('GetObject', body, key: revoked)),
        unauthenticated,
      );
    });

    test('ключ другого вида — 403', () async {
      final node = await h.newKey(kind: KeyKind.node);
      final account = await h.newKey(kind: KeyKind.account);
      final response = await h.post('GetObject', body, key: node);
      expect(response.statusCode, 403);
      expect(
        (await errorOf(response)).code,
        pb.ErrorCode.ERROR_CODE_PERMISSION_DENIED,
      );
      expect(
        await codeOf(h.post('Heartbeat', [], key: device)),
        pb.ErrorCode.ERROR_CODE_PERMISSION_DENIED,
      );
      expect(
        await codeOf(h.post('RevokeDevice', [], key: device)),
        pb.ErrorCode.ERROR_CODE_PERMISSION_DENIED,
      );
      expect(await codeOf(h.post('Heartbeat', [], key: node)), accepted);
      expect(await codeOf(h.post('AddDevice', [], key: account)), accepted);
    });

    test('регистрация: неизвестный ключ допустим, отозванный — нет', () async {
      final fresh = await h.newKey();
      expect(await codeOf(h.post('RegisterAccount', [], key: fresh)), accepted);
      expect(await codeOf(h.post('RegisterNode', [], key: fresh)), accepted);
      final revoked = await h.newKey(kind: KeyKind.node, revoked: true);
      expect(
        await codeOf(h.post('RegisterNode', [], key: revoked)),
        unauthenticated,
      );
      // Подпись при регистрации всё равно обязательна.
      expect(await codeOf(h.post('RegisterAccount', [])), unauthenticated);
    });

    test('GetKeyBundle без подписи', () async {
      expect(await codeOf(h.post('GetKeyBundle', [])), accepted);
    });
  });
}
