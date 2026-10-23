import 'dart:async';
import 'dart:io';

import 'package:core/core.dart';
import 'package:node/node.dart';
import 'package:protocol/protocol.dart' as pb;
import 'package:test/test.dart';

import 'support.dart';

/// Подставной координатор: отвечает на `RegisterNode` и `Heartbeat` по
/// сценарию [respond].
final class _FakeCoordinator {
  new _(this._server, this.respond) {
    _server.listen(_handle);
  }

  static Future<_FakeCoordinator> start(
    Object Function(String method, List<int> body) respond,
  ) async => _FakeCoordinator._(
    await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    respond,
  );

  final HttpServer _server;
  final Object Function(String method, List<int> body) respond;
  final calls = <String>[];
  final bodies = <List<int>>[];
  final _calls = StreamController<String>.broadcast();

  String get url => 'http://127.0.0.1:${_server.port}';

  /// Ждёт, пока методов будет [n].
  Future<void> waitCalls(int n) async {
    while (calls.length < n) {
      await _calls.stream.first.timeout(const Duration(seconds: 10));
    }
  }

  Future<void> _handle(HttpRequest request) async {
    final method = request.uri.pathSegments.last;
    final body = await request.fold<List<int>>([], (a, b) => a..addAll(b));
    calls.add(method);
    bodies.add(body);
    final reply = respond(method, body);
    request.response.headers.contentType = ContentType(
      'application',
      'x-protobuf',
    );
    if (reply case final pb.Error error) {
      request.response.statusCode = 401;
      request.response.add(error.writeToBuffer());
    } else {
      request.response.add((reply as dynamic).writeToBuffer() as List<int>);
    }
    await request.response.close();
    _calls.add(method);
  }

  Future<void> close() => _server.close(force: true);
}

void main() {
  late CryptoProvider crypto;
  late Directory dir;
  setUpAll(() async => crypto = await SodiumCryptoProvider.load());
  setUp(() => dir = Directory.systemTemp.createTempSync('fs-node-link-'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('регистрация, heartbeat, повторная регистрация после '
      'UNAUTHENTICATED, ключи координатора', () async {
    final owner = await nodeWithCertificate(dir, crypto);
    final identity = await NodeIdentity.load(dir, crypto);
    final known = crypto.randomBytes(32);
    final unknown = crypto.randomBytes(32);
    var heartbeats = 0;
    final fake = await _FakeCoordinator.start((method, body) {
      if (method == 'RegisterNode') {
        return pb.RegisterNodeResponse(coordinatorKeys: [known, unknown]);
      }
      heartbeats++;
      if (heartbeats == 2) {
        return pb.Error(
          code: pb.ErrorCode.ERROR_CODE_UNAUTHENTICATED,
          message: 'узел не зарегистрирован',
        );
      }
      return pb.HeartbeatResponse(nextHeartbeatMs: 20);
    });
    final client = CoordinatorClient(
      baseUri: Uri.parse(fake.url),
      crypto: crypto,
      retry: RetryPolicy.none,
    );
    final link = CoordinatorLink(
      client: client,
      identity: identity,
      capacityBytes: 1000,
      usedBytes: () => 5000, // больше ёмкости — шлётся ёмкость
      trustedKeys: CoordinatorKeySet([known]),
      endpoints: const ['203.0.113.1:7340'],
      interval: const Duration(milliseconds: 20),
    )..start();
    // Регистрация, heartbeat, отказ, регистрация, heartbeat.
    await fake.waitCalls(5);
    await link.stop();
    client.close(force: true);
    await fake.close();
    expect(fake.calls.take(5), [
      'RegisterNode',
      'Heartbeat',
      'Heartbeat',
      'RegisterNode',
      'Heartbeat',
    ]);
    final register = pb.RegisterNodeRequest.fromBuffer(fake.bodies.first);
    expect(register.nodeCertificate, identity.certificate);
    expect(register.capacityBytes.toInt(), 1000);
    expect(register.endpoints, ['203.0.113.1:7340']);
    expect(register.versions, [1]);
    expect(register.software, startsWith('node '));
    final beat = pb.HeartbeatRequest.fromBuffer(fake.bodies[1]);
    expect(beat.usedBytes.toInt(), 1000);
    expect(link.registered, isTrue);
    expect(link.toJson()['unknownCoordinatorKeys'], [
      CoordinatorKeySet.keyId(crypto, unknown),
    ]);
    identity.dispose();
    owner.dispose();
  });

  test('координатор недоступен: повторы с паузой, ошибка в статусе', () async {
    final owner = await nodeWithCertificate(dir, crypto);
    final identity = await NodeIdentity.load(dir, crypto);
    final fake = await _FakeCoordinator.start(
      (method, body) => pb.Error(
        code: pb.ErrorCode.ERROR_CODE_PERMISSION_DENIED,
        message: 'заблокирована',
      ),
    );
    final client = CoordinatorClient(
      baseUri: Uri.parse(fake.url),
      crypto: crypto,
      retry: RetryPolicy.none,
    );
    final link = CoordinatorLink(
      client: client,
      identity: identity,
      capacityBytes: 1000,
      usedBytes: () => 0,
      trustedKeys: CoordinatorKeySet(const []),
      maxBackoff: const Duration(seconds: 1),
    )..start();
    await fake.waitCalls(1);
    // Пауза после первой неудачи — 2 с, ограничена maxBackoff.
    await fake.waitCalls(2);
    final status = link.toJson();
    expect(status['registered'], isFalse);
    expect(status['lastError'], contains('PERMISSION_DENIED'));
    expect(status['nextAttemptAt'], isNotNull);
    final stopped = Stopwatch()..start();
    await link.stop();
    expect(stopped.elapsed, lessThan(const Duration(seconds: 1)));
    client.close(force: true);
    await fake.close();
    identity.dispose();
    owner.dispose();
  });
}
