import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

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
    // Занятое — как есть, даже больше квоты: координатор перенесёт
    // лишнее (4.4.2).
    expect(beat.usedBytes.toInt(), 5000);
    expect(beat.capacityBytes.toInt(), 1000);
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

  test('свободное место в heartbeat; отчёт о повреждённых фрагментах '
      'с повтором после сбоя', () async {
    final owner = await nodeWithCertificate(dir, crypto);
    final identity = await NodeIdentity.load(dir, crypto);
    final damaged = _Damaged([
      for (var i = 0; i < 1001; i++)
        Uint8List(32)
          ..[0] = i % 256
          ..[1] = i ~/ 256,
    ]);
    var reports = 0;
    final fake = await _FakeCoordinator.start((method, body) {
      switch (method) {
        case 'RegisterNode':
          return pb.RegisterNodeResponse();
        case 'ReportDamagedFragments':
          reports++;
          if (reports == 1) {
            return pb.Error(
              code: pb.ErrorCode.ERROR_CODE_UNAUTHENTICATED,
              message: 'сбой',
            );
          }
          final r = pb.ReportDamagedFragmentsRequest.fromBuffer(body);
          return pb.ReportDamagedFragmentsResponse(known: r.fragmentIds.length);
        default:
          return pb.HeartbeatResponse(nextHeartbeatMs: 20);
      }
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
      usedBytes: () => 100,
      freeBytes: () => 5000, // больше ёмкости — шлётся ёмкость
      damaged: damaged,
      trustedKeys: CoordinatorKeySet(const []),
      interval: const Duration(milliseconds: 20),
    )..start();
    // Регистрация, отчёт (сбой), heartbeat, отчёт двумя пачками.
    await fake.waitCalls(5);
    await link.stop();
    client.close(force: true);
    await fake.close();
    expect(fake.calls.take(5), [
      'RegisterNode',
      'ReportDamagedFragments',
      'Heartbeat',
      'ReportDamagedFragments',
      'ReportDamagedFragments',
    ]);
    final beat = pb.HeartbeatRequest.fromBuffer(fake.bodies[2]);
    expect(beat.hasFreeBytes(), isTrue);
    expect(beat.freeBytes.toInt(), 1000);
    expect(
      pb.ReportDamagedFragmentsRequest.fromBuffer(fake.bodies[3]).fragmentIds,
      hasLength(1000),
    );
    expect(
      pb.ReportDamagedFragmentsRequest.fromBuffer(fake.bodies[4]).fragmentIds,
      hasLength(1),
    );
    expect(damaged.pending, isEmpty);
    identity.dispose();
    owner.dispose();
  });

  group('достижимость (3.5.1)', () {
    test('адреса: заданные, затем найденные; IPv6 в скобках; без повторов, '
        'не больше 8', () async {
      var ports = [7340];
      final r = Reachability(
        manualEndpoints: const ['nas.example.org:7340', '198.51.100.1:7340'],
        ports: () => ports,
      );
      expect(r.endpoints, ['nas.example.org:7340', '198.51.100.1:7340']);
      expect(r.due, isTrue);
      expect(Reachability.hostPort('2001:db8::1', 7340), '[2001:db8::1]:7340');
      expect(Reachability.hostPort('203.0.113.5', 1), '203.0.113.5:1');
      final fake = await _FakeCoordinator.start(
        (method, body) => pb.CheckReachabilityResponse(
          observedAddress: '198.51.100.1',
          results: [
            for (final p in pb.CheckReachabilityRequest.fromBuffer(body).ports)
              pb.ReachabilityResult(
                port: p,
                status: p == 7340
                    ? pb.ReachabilityStatus.REACHABILITY_STATUS_REACHABLE
                    : pb.ReachabilityStatus.REACHABILITY_STATUS_TIMEOUT,
              ),
          ],
        ),
      );
      final client = CoordinatorClient(
        baseUri: Uri.parse(fake.url),
        crypto: crypto,
        retry: RetryPolicy.none,
      );
      final key = await crypto.ed25519FromSeed(
        SecretBytes(crypto.randomBytes(32)),
      );
      // Найденный адрес совпал с заданным: не повторяется.
      expect(await r.check(client, key), isFalse);
      expect(r.reachable, isTrue);
      expect(r.due, isFalse);
      ports = [7340, 41000];
      expect(r.due, isTrue, reason: 'порты изменились');
      expect(await r.check(client, key), isFalse);
      expect(r.toJson()['ports'], {'7340': 'reachable', '41000': 'timeout'});
      expect(r.reachablePort, 7340);
      client.close(force: true);
      await fake.close();
      final many = Reachability(
        manualEndpoints: [for (var i = 1; i <= 9; i++) 'h$i.example:1'],
        ports: () => const [],
      );
      expect(many.endpoints, hasLength(8));
    });

    test('после регистрации — проверка; адреса изменились — heartbeat с '
        'ними сразу; recheckReachability — проверка вне очереди', () async {
      final owner = await nodeWithCertificate(dir, crypto);
      final identity = await NodeIdentity.load(dir, crypto);
      var reachable = true;
      final fake = await _FakeCoordinator.start((method, body) {
        switch (method) {
          case 'RegisterNode':
            return pb.RegisterNodeResponse();
          case 'CheckReachability':
            final ports = pb.CheckReachabilityRequest.fromBuffer(body).ports;
            return pb.CheckReachabilityResponse(
              observedAddress: '203.0.113.9',
              results: [
                for (final p in ports)
                  pb.ReachabilityResult(
                    port: p,
                    status: reachable && p == 41000
                        ? pb.ReachabilityStatus.REACHABILITY_STATUS_REACHABLE
                        : pb.ReachabilityStatus.REACHABILITY_STATUS_REFUSED,
                  ),
              ],
            );
          default:
            return pb.HeartbeatResponse(nextHeartbeatMs: 60000);
        }
      });
      final client = CoordinatorClient(
        baseUri: Uri.parse(fake.url),
        crypto: crypto,
        retry: RetryPolicy.none,
      );
      final reachability = Reachability(
        manualEndpoints: const ['nas.example.org:7340'],
        ports: () => const [7340, 41000],
      );
      final link = CoordinatorLink(
        client: client,
        identity: identity,
        capacityBytes: 1000,
        usedBytes: () => 0,
        trustedKeys: CoordinatorKeySet(const []),
        reachability: reachability,
        // Без изменения адресов следующий heartbeat — нескоро.
        interval: const Duration(minutes: 1),
      )..start();
      await fake.waitCalls(3);
      expect(fake.calls.take(3), [
        'RegisterNode',
        'CheckReachability',
        'Heartbeat',
      ]);
      expect(pb.RegisterNodeRequest.fromBuffer(fake.bodies[0]).endpoints, [
        'nas.example.org:7340',
      ]);
      expect(pb.CheckReachabilityRequest.fromBuffer(fake.bodies[1]).ports, [
        7340,
        41000,
      ]);
      expect(pb.HeartbeatRequest.fromBuffer(fake.bodies[2]).endpoints, [
        'nas.example.org:7340',
        '203.0.113.9:41000',
      ]);
      expect(reachability.reachable, isTrue);
      expect(reachability.observedAddress, '203.0.113.9');

      // Проброс снят: проверка вне очереди, адрес пропадает.
      reachable = false;
      // Ответ на heartbeat дошёл до узла, цикл уснул.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      link.recheckReachability();
      await fake.waitCalls(6);
      expect(fake.calls.skip(3).take(3), [
        'Heartbeat',
        'CheckReachability',
        'Heartbeat',
      ]);
      expect(pb.HeartbeatRequest.fromBuffer(fake.bodies[5]).endpoints, [
        'nas.example.org:7340',
      ]);
      expect(link.toJson()['lastError'], isNull);
      await link.stop();
      client.close(force: true);
      await fake.close();
      identity.dispose();
      owner.dispose();
    });

    test('координатор не умеет CheckReachability: ошибка в статусе, '
        'heartbeat идут', () async {
      final owner = await nodeWithCertificate(dir, crypto);
      final identity = await NodeIdentity.load(dir, crypto);
      final fake = await _FakeCoordinator.start(
        (method, body) => switch (method) {
          'RegisterNode' => pb.RegisterNodeResponse(),
          'CheckReachability' => pb.Error(
            code: pb.ErrorCode.ERROR_CODE_NOT_FOUND,
            message: 'нет метода',
          ),
          _ => pb.HeartbeatResponse(nextHeartbeatMs: 20),
        },
      );
      final client = CoordinatorClient(
        baseUri: Uri.parse(fake.url),
        crypto: crypto,
        retry: RetryPolicy.none,
      );
      final reachability = Reachability(
        manualEndpoints: const [],
        ports: () => const [7340],
      );
      final link = CoordinatorLink(
        client: client,
        identity: identity,
        capacityBytes: 1000,
        usedBytes: () => 0,
        trustedKeys: CoordinatorKeySet(const []),
        reachability: reachability,
        interval: const Duration(milliseconds: 20),
      )..start();
      await fake.waitCalls(4);
      expect(fake.calls.take(4), [
        'RegisterNode',
        'CheckReachability',
        'Heartbeat',
        'Heartbeat',
      ], reason: 'повтор проверки — не раньше чем через 5 минут');
      expect(link.registered, isTrue);
      expect(reachability.toJson()['lastError'], contains('NOT_FOUND'));
      expect(reachability.reachable, isFalse);
      await link.stop();
      client.close(force: true);
      await fake.close();
      identity.dispose();
      owner.dispose();
    });
  });
}

/// Повреждённые фрагменты в памяти.
final class _Damaged implements DamagedFragments {
  new(this.pending);

  final List<Uint8List> pending;

  @override
  List<Uint8List> unreportedDamaged({int limit = 1000}) =>
      pending.take(limit).toList();

  @override
  void markReported(List<Uint8List> fragmentIds) =>
      pending.removeWhere(fragmentIds.contains);
}
