// Каркас API координатора (задачи 2.1.2, 2.1.5): маршрутизация, Protobuf,
// Content-Type, предел тела, коды ошибок и HTTP-статусы по protocol.md,
// раздел 4.4, health-check.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:coordinator/coordinator.dart';
import 'package:protocol/protocol.dart' as pb;
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'support/harness.dart';

/// Сервис, в котором реализован один метод — для проверки успешного пути
/// и ошибок обработчика.
final class _EchoService extends CoordinatorService {
  const new();

  @override
  Future<pb.GetObjectResponse> getObject(
    CallContext context,
    pb.GetObjectRequest request,
  ) async {
    if (request.objectId.isEmpty) {
      throw const RpcException(pb.ErrorCode.ERROR_CODE_NOT_FOUND, 'нет');
    }
    if (request.objectId.first == 0xEE) throw StateError('сбой обработчика');
    return pb.GetObjectResponse(blob: request.objectId);
  }

  @override
  Future<pb.ListObjectsResponse> listObjects(
    CallContext context,
    pb.ListObjectsRequest request,
  ) => throw const RpcException(
    pb.ErrorCode.ERROR_CODE_UNAVAILABLE,
    'база недоступна',
    retryAfter: Duration(milliseconds: 1500),
  );
}

void main() {
  late Harness h;
  setUp(() async => h = await Harness.create(service: const _EchoService()));

  test('таблица методов совпадает с coordinator.proto', () {
    final proto = File('../protocol/proto/fs/v1/coordinator.proto')
        .readAsStringSync();
    final fromProto = RegExp(
      r'^message (\w+)Request \{',
      multiLine: true,
    ).allMatches(proto).map((m) => m.group(1)).toList();
    final names = coordinatorMethods(const UnimplementedCoordinatorService())
        .map((m) => m.name)
        .toList();
    expect(fromProto, hasLength(18));
    expect(names, fromProto);
  });

  group('заглушки', () {
    for (final method in coordinatorMethods(
      const UnimplementedCoordinatorService(),
    )) {
      test('${method.name} отвечает INTERNAL 500 «не реализован»', () async {
        final stub = await Harness.create();
        final kind = switch (method.auth) {
          AuthRequirement.account => KeyKind.account,
          AuthRequirement.device => KeyKind.device,
          AuthRequirement.node => KeyKind.node,
          AuthRequirement.none || AuthRequirement.registering => null,
        };
        final key = method.auth == AuthRequirement.none
            ? null
            : await stub.newKey(kind: kind);
        final response = await stub.post(method.name, [], key: key);
        expect(response.statusCode, 500);
        expect(response.headers['content-type'], 'application/x-protobuf');
        final error = await errorOf(response);
        expect(error.code, pb.ErrorCode.ERROR_CODE_INTERNAL);
        expect(error.message, contains('не реализован'));
      });
    }
  });

  test('успешный ответ — 200 и сериализованный Response', () async {
    final key = await h.newKey(kind: KeyKind.device);
    final request = pb.GetObjectRequest(objectId: [1, 2, 3]);
    final response = await h.post(
      'GetObject',
      request.writeToBuffer(),
      key: key,
    );
    expect(response.statusCode, 200);
    expect(response.headers['content-type'], 'application/x-protobuf');
    expect(response.headers['fs-request-id'], matches(r'^[0-9a-f]{16}$'));
    final body = pb.GetObjectResponse.fromBuffer(await bodyOf(response));
    expect(body.blob, [1, 2, 3]);
  });

  test('Content-Type с параметрами принимается', () async {
    final key = await h.newKey(kind: KeyKind.device);
    final response = await h.post(
      'GetObject',
      pb.GetObjectRequest(objectId: [1]).writeToBuffer(),
      key: key,
      contentType: 'Application/X-Protobuf; charset=binary',
    );
    expect(response.statusCode, 200);
  });

  group('коды ошибок и статусы', () {
    test('ошибка обработчика — её код и статус', () async {
      final key = await h.newKey(kind: KeyKind.device);
      final response = await h.post(
        'GetObject',
        pb.GetObjectRequest().writeToBuffer(),
        key: key,
      );
      expect(response.statusCode, 404);
      expect((await errorOf(response)).code, pb.ErrorCode.ERROR_CODE_NOT_FOUND);
    });

    test('UNAVAILABLE: 503, retry_after_ms и Retry-After', () async {
      final key = await h.newKey(kind: KeyKind.device);
      final response = await h.post('ListObjects', [], key: key);
      expect(response.statusCode, 503);
      expect(response.headers['retry-after'], '2');
      final error = await errorOf(response);
      expect(error.code, pb.ErrorCode.ERROR_CODE_UNAVAILABLE);
      expect(error.retryAfterMs, 1500);
    });

    test('исключение обработчика — INTERNAL 500 без подробностей', () async {
      final key = await h.newKey(kind: KeyKind.device);
      final response = await h.post(
        'GetObject',
        pb.GetObjectRequest(objectId: [0xEE]).writeToBuffer(),
        key: key,
      );
      expect(response.statusCode, 500);
      final error = await errorOf(response);
      expect(error.code, pb.ErrorCode.ERROR_CODE_INTERNAL);
      expect(error.message, isNot(contains('сбой обработчика')));
    });

    test('тело не разбирается — BAD_REQUEST 400', () async {
      final key = await h.newKey(kind: KeyKind.device);
      // Поле 2 (bytes) с длиной больше остатка и varint с битом знака.
      for (final body in [
        [0x12, 0x05, 0x01],
        [0x12, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x01],
        [0xFF],
      ]) {
        final response = await h.post('GetObject', body, key: key);
        expect(response.statusCode, 400, reason: '$body');
        expect(
          (await errorOf(response)).code,
          pb.ErrorCode.ERROR_CODE_BAD_REQUEST,
        );
      }
    });

    test('неизвестный метод — NOT_FOUND 404', () async {
      final response = await h.post('Nothing', []);
      expect(response.statusCode, 404);
      expect((await errorOf(response)).code, pb.ErrorCode.ERROR_CODE_NOT_FOUND);
    });

    test('путь вне /api/v1/ — 404 без тела Error', () async {
      final response = await h.handler.call(
        Request('POST', Uri.parse('http://coordinator.test/api/v2/GetObject')),
      );
      expect(response.statusCode, 404);
      expect(response.headers['content-type'], isNot('application/x-protobuf'));
    });

    test('не POST — BAD_REQUEST 405 и Allow', () async {
      final response = await h.handler.call(
        Request('GET', Uri.parse('http://coordinator.test/api/v1/GetObject')),
      );
      expect(response.statusCode, 405);
      expect(response.headers['allow'], 'POST');
      expect(
        (await errorOf(response)).code,
        pb.ErrorCode.ERROR_CODE_BAD_REQUEST,
      );
    });

    test('строка запроса — BAD_REQUEST 400', () async {
      final response = await h.handler.call(
        Request(
          'POST',
          Uri.parse('http://coordinator.test/api/v1/GetObject?x=1'),
          headers: {'content-type': 'application/x-protobuf'},
        ),
      );
      expect(response.statusCode, 400);
    });

    test('неверный Content-Type — BAD_REQUEST 415', () async {
      for (final type in ['application/json', 'application/x-protobuffer']) {
        final response = await h.post('GetKeyBundle', [], contentType: type);
        expect(response.statusCode, 415, reason: type);
        expect(
          (await errorOf(response)).code,
          pb.ErrorCode.ERROR_CODE_BAD_REQUEST,
        );
      }
      final response = await h.handler.call(
        Request(
          'POST',
          Uri.parse('http://coordinator.test/api/v1/GetKeyBundle'),
        ),
      );
      expect(response.statusCode, 415);
    });

    test('тело больше предела по Content-Length — 413', () async {
      final response = await h.post(
        'GetKeyBundle',
        Uint8List(defaultMaxBody + 1),
      );
      expect(response.statusCode, 413);
      expect(
        (await errorOf(response)).code,
        pb.ErrorCode.ERROR_CODE_BAD_REQUEST,
      );
    });

    test('тело больше предела без Content-Length — 413', () async {
      var sent = 0;
      final chunks = Stream<List<int>>.periodic(Duration.zero, (_) {
        sent += 16 * 1024;
        return Uint8List(16 * 1024);
      }).take(100);
      final response = await h.handler.call(
        Request(
          'POST',
          Uri.parse('http://coordinator.test/api/v1/GetKeyBundle'),
          body: chunks,
          headers: {'content-type': 'application/x-protobuf'},
        ),
      );
      expect(response.statusCode, 413);
      // Чтение прекращено вскоре после предела, а не на конце потока.
      expect(sent, lessThan(defaultMaxBody + 64 * 1024));
    });

    test('PutObject принимает блоб 8 МиБ', () async {
      final key = await h.newKey(kind: KeyKind.device);
      final request = pb.PutObjectRequest(
        kind: pb.ObjectKind.OBJECT_KIND_SNAPSHOT,
        objectId: Uint8List(32),
        blob: Uint8List(8 * 1024 * 1024),
      );
      final body = request.writeToBuffer();
      expect(body.length, greaterThan(defaultMaxBody));
      expect(body.length, lessThanOrEqualTo(putObjectMaxBody));
      final response = await h.post('PutObject', body, key: key);
      // Заглушка, но тело принято и разобрано.
      expect(response.statusCode, 500);
      final tooLarge = await h.post(
        'PutObject',
        Uint8List(putObjectMaxBody + 1),
        key: key,
      );
      expect(tooLarge.statusCode, 413);
    });
  });

  group('статусы для всех кодов', () {
    const expected = {
      pb.ErrorCode.ERROR_CODE_BAD_REQUEST: 400,
      pb.ErrorCode.ERROR_CODE_VERSION_UNSUPPORTED: 400,
      pb.ErrorCode.ERROR_CODE_UNAUTHENTICATED: 401,
      pb.ErrorCode.ERROR_CODE_PERMISSION_DENIED: 403,
      pb.ErrorCode.ERROR_CODE_NOT_FOUND: 404,
      pb.ErrorCode.ERROR_CODE_ALREADY_EXISTS: 409,
      pb.ErrorCode.ERROR_CODE_QUOTA_EXCEEDED: 507,
      pb.ErrorCode.ERROR_CODE_RATE_LIMITED: 429,
      pb.ErrorCode.ERROR_CODE_UNAVAILABLE: 503,
      pb.ErrorCode.ERROR_CODE_INTERNAL: 500,
      pb.ErrorCode.ERROR_CODE_INTEGRITY_FAILED: 500,
      pb.ErrorCode.ERROR_CODE_TICKET_EXPIRED: 500,
      pb.ErrorCode.ERROR_CODE_UNSPECIFIED: 500,
    };
    test('каждый код ErrorCode имеет статус и имя', () {
      expect(expected.keys, unorderedEquals(pb.ErrorCode.values));
      for (final MapEntry(key: code, value: status) in expected.entries) {
        expect(httpStatusFor(code), status, reason: '$code');
        expect(errorCodeName(code), isNot(startsWith('CODE_')));
      }
    });
  });

  group('health-check', () {
    test('база отвечает — 200 ok', () async {
      final response = await h.handler.call(
        Request('GET', Uri.parse('http://coordinator.test/health')),
      );
      expect(response.statusCode, 200);
      expect(await response.readAsString(), '{"status":"ok"}');
    });

    test('база не отвечает — 503', () async {
      for (final check in <Future<bool> Function()>[
        () async => false,
        () async => throw StateError('нет соединения'),
        () => Completer<bool>().future,
      ]) {
        final down = await Harness.create(healthCheck: check);
        final response = await down.handler.call(
          Request('GET', Uri.parse('http://coordinator.test/health')),
        );
        expect(response.statusCode, 503);
        expect(await response.readAsString(), '{"status":"unavailable"}');
      }
    }, timeout: const Timeout(Duration(seconds: 15)));

    test('POST на /health — 405', () async {
      final response = await h.handler.call(
        Request('POST', Uri.parse('http://coordinator.test/health')),
      );
      expect(response.statusCode, 405);
    });
  });
}
