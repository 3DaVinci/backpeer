// CoordinatorClient (задача 2.8.1) против заглушки HTTP-сервера: подпись,
// повторы, разбор ошибок. Против настоящего координатора —
// packages/coordinator/test/client_test.dart.

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:protocol/protocol.dart' as pb;
import 'package:test/test.dart';

void main() {
  late CryptoProvider crypto;
  late Ed25519KeyPair device;
  late HttpServer server;
  late List<HttpRequest> seen;
  late List<Uint8List> bodies;
  late Future<void> Function(HttpRequest) respond;
  final sleeps = <Duration>[];

  setUpAll(() async {
    crypto = await SodiumCryptoProvider.load();
    device = await crypto.ed25519FromSeed(SecretBytes(Uint8List(32)..[0] = 1));
  });

  setUp(() async {
    seen = [];
    bodies = [];
    sleeps.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0)
      ..listen((request) async {
        seen.add(request);
        final body = BytesBuilder();
        await request.forEach(body.add);
        bodies.add(body.takeBytes());
        await respond(request);
      });
  });
  tearDown(() => server.close(force: true));

  CoordinatorClient client({RetryPolicy retry = const RetryPolicy()}) =>
      CoordinatorClient(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
        crypto: crypto,
        deviceKey: device,
        retry: retry,
        random: Random(1),
        sleep: (d) async => sleeps.add(d),
      );

  Future<void> protobuf(HttpRequest r, int status, List<int> body) async {
    r.response
      ..statusCode = status
      ..headers.contentType = ContentType('application', 'x-protobuf')
      ..add(body);
    await r.response.close();
  }

  Future<void> error(
    HttpRequest r,
    pb.ErrorCode code, {
    int status = 503,
    int retryAfterMs = 0,
  }) => protobuf(
    r,
    status,
    pb.Error(
      code: code,
      message: 'ошибка',
      retryAfterMs: retryAfterMs,
    ).writeToBuffer(),
  );

  test('подписанный запрос, путь, тело, разбор ответа', () async {
    respond = (r) =>
        protobuf(r, 200, pb.GetObjectResponse(blob: [1, 2, 3]).writeToBuffer());
    final c = client();
    final response = await c.getObject(
      pb.GetObjectRequest(
        kind: pb.ObjectKind.OBJECT_KIND_SNAPSHOT,
        objectId: Uint8List(32),
      ),
    );
    expect(response.blob, [1, 2, 3]);
    final r = seen.single;
    expect(r.method, 'POST');
    expect(r.uri.path, '/api/v1/GetObject');
    expect(r.headers.contentType?.mimeType, 'application/x-protobuf');
    final auth = RequestAuth.parse(r.headers.value('FS-Auth')!);
    expect(auth.signer, device.publicKey);
    expect(
      await auth.verify(crypto, path: '/api/v1/GetObject', body: bodies.single),
      isTrue,
    );
    c.close();
  });

  test('без подписи — GetLoginParams', () async {
    respond = (r) =>
        protobuf(r, 200, pb.GetLoginParamsResponse().writeToBuffer());
    final c = client();
    await c.getLoginParams(pb.GetLoginParamsRequest(login: 'alice'));
    expect(seen.single.headers.value('FS-Auth'), isNull);
    c.close();
  });

  test('UNAVAILABLE и RATE_LIMITED повторяются, подпись — заново', () async {
    var calls = 0;
    respond = (r) async {
      calls++;
      if (calls == 1) {
        return await error(r, pb.ErrorCode.ERROR_CODE_UNAVAILABLE);
      }
      if (calls == 2) {
        return await error(
          r,
          pb.ErrorCode.ERROR_CODE_RATE_LIMITED,
          status: 429,
          retryAfterMs: 20000,
        );
      }
      return await protobuf(r, 200, pb.ListObjectsResponse().writeToBuffer());
    };
    final c = client();
    await c.listObjects(pb.ListObjectsRequest());
    expect(calls, 3);
    expect(sleeps, hasLength(2));
    expect(sleeps[1], const Duration(seconds: 20), reason: 'retry_after_ms');
    expect(
      seen.map((r) => r.headers.value('FS-Auth')).toSet(),
      hasLength(3),
      reason: 'каждая попытка подписана заново',
    );
    c.close();
  });

  test('паузы растут, попытки ограничены', () async {
    respond = (r) => error(r, pb.ErrorCode.ERROR_CODE_UNAVAILABLE);
    final c = client(
      retry: const RetryPolicy(
        initialDelay: Duration(seconds: 1),
        maxDelay: Duration(seconds: 4),
      ),
    );
    await expectLater(
      c.listObjects(pb.ListObjectsRequest()),
      throwsA(
        isA<CoordinatorException>()
            .having((e) => e.code, 'code', pb.ErrorCode.ERROR_CODE_UNAVAILABLE)
            .having((e) => e.httpStatus, 'httpStatus', 503),
      ),
    );
    expect(seen, hasLength(5));
    expect(sleeps, hasLength(4));
    for (var i = 0; i < sleeps.length; i++) {
      final cap = Duration(seconds: min(1 << i, 4));
      expect(sleeps[i], lessThanOrEqualTo(cap));
      expect(sleeps[i], greaterThanOrEqualTo(cap ~/ 2));
    }
    c.close();
  });

  test('прочие ошибки не повторяются', () async {
    respond = (r) => error(r, pb.ErrorCode.ERROR_CODE_NOT_FOUND, status: 404);
    final c = client();
    await expectLater(
      c.getObject(pb.GetObjectRequest()),
      throwsA(
        isA<CoordinatorException>()
            .having((e) => e.code, 'code', pb.ErrorCode.ERROR_CODE_NOT_FOUND)
            .having((e) => e.detail, 'detail', 'ошибка'),
      ),
    );
    expect(seen, hasLength(1));
    c.close();
  });

  test('ответ прокси без тела Error: 502 повторяется, 500 — нет', () async {
    var calls = 0;
    respond = (r) async {
      calls++;
      r.response
        ..statusCode = calls == 1 ? 502 : 500
        ..write('<html>bad gateway</html>');
      await r.response.close();
    };
    final c = client();
    await expectLater(
      c.listObjects(pb.ListObjectsRequest()),
      throwsA(
        isA<CoordinatorException>()
            .having((e) => e.code, 'code', pb.ErrorCode.ERROR_CODE_INTERNAL)
            .having((e) => e.httpStatus, 'httpStatus', 500),
      ),
    );
    expect(calls, 2);
    c.close();
  });

  test('сбой связи — повторы, потом UNAVAILABLE', () async {
    final port = server.port;
    await server.close(force: true);
    final c = CoordinatorClient(
      baseUri: Uri.parse('http://127.0.0.1:$port'),
      crypto: crypto,
      deviceKey: device,
      retry: const RetryPolicy(maxAttempts: 3),
      sleep: (d) async => sleeps.add(d),
    );
    await expectLater(
      c.listObjects(pb.ListObjectsRequest()),
      throwsA(
        isA<CoordinatorException>()
            .having((e) => e.code, 'code', pb.ErrorCode.ERROR_CODE_UNAVAILABLE)
            .having((e) => e.httpStatus, 'httpStatus', isNull),
      ),
    );
    expect(sleeps, hasLength(2));
    c.close();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  });

  test('без TLS — только к localhost; без ключа подписи — ошибка', () {
    expect(
      () => CoordinatorClient(
        baseUri: Uri.parse('http://coordinator.example.org'),
        crypto: crypto,
      ),
      throwsArgumentError,
    );
    CoordinatorClient(
      baseUri: Uri.parse('https://coordinator.example.org'),
      crypto: crypto,
    ).close();
    final c = CoordinatorClient(
      baseUri: Uri.parse('http://localhost:1'),
      crypto: crypto,
    );
    expect(() => c.listObjects(pb.ListObjectsRequest()), throwsStateError);
    c.close();
  });
}
