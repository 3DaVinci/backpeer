// Сведение узлов через сводник и пробивание NAT (задача 3.7.2;
// protocol.md, раздел 4.11) на модели сети: NAT разных типов по RFC 4787,
// определение симметричного NAT, поток после сведения.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:test/test.dart';

final class _World {
  new(NatType a, NatType b, {LinkConditions link = const LinkConditions()})
    : net = SimulatedNetwork(random: math.Random(3)) {
    final server = net.host('192.0.2.1');
    rendezvous = RendezvousServer([
      server.bind(3478),
      server.bind(3479),
    ], issueToken: (address, port) => Uint8List(20)..[0] = port & 0xff);
    servers = [(server.address, 3478), (server.address, 3479)];
    alice = UdpEndpoint(
      net.nat('203.0.113.1', a).host('10.0.0.2', uplink: link).bind(),
    );
    bob = UdpEndpoint(
      net.nat('203.0.113.2', b).host('192.168.1.5', uplink: link).bind(),
    );
  }

  final SimulatedNetwork net;
  late final RendezvousServer rendezvous;
  late final List<(InternetAddress, int)> servers;
  late final UdpEndpoint alice;
  late final UdpEndpoint bob;

  /// Полное сведение: адреса у сводника, пробивание с обеих сторон,
  /// поток от Алисы к Бобу.
  Future<(UdpStream, UdpStream)> connect({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final a = await alice.discover(servers);
    final b = await bob.discover(servers);
    final punchId = Uint8List(16)..[0] = 42;
    final results = await Future.wait([
      alice.punch(punchId, b.address, b.port, timeout: timeout),
      bob.punch(punchId, a.address, a.port, timeout: timeout),
    ]);
    final (address, port) = results.first;
    final accepted = bob.incoming.first;
    final stream = await alice.connect(address, port, punchId: punchId);
    return (stream, await accepted);
  }

  Future<void> close() async {
    await alice.close();
    await bob.close();
    await rendezvous.close();
  }
}

void main() {
  test('сводник сообщает внешний адрес NAT и подтверждение', () async {
    final w = _World(NatType.portRestricted, NatType.fullCone);
    final b = await w.alice.discover(w.servers);
    expect(b.address, InternetAddress('203.0.113.1'));
    expect(b.port, greaterThanOrEqualTo(40000));
    expect(b.symmetric, isFalse);
    expect(b.token[0], b.port & 0xff);
    expect(b.endpoint, '203.0.113.1:${b.port}');
    await w.close();
  });

  test('симметричный NAT определяется по двум портам сводника', () async {
    final w = _World(NatType.symmetric, NatType.portRestricted);
    expect((await w.alice.discover(w.servers)).symmetric, isTrue);
    expect((await w.bob.discover(w.servers)).symmetric, isFalse);
    await w.close();
  });

  test('сводник не отвечает — ошибка', () async {
    final w = _World(NatType.fullCone, NatType.fullCone);
    await w.rendezvous.close();
    await expectLater(
      w.alice.discover(w.servers, timeout: const Duration(milliseconds: 500)),
      throwsA(isA<UdpRendezvousException>()),
    );
    await w.close();
  });

  test('ответил один порт — адрес без признака симметричного NAT', () async {
    final w = _World(NatType.symmetric, NatType.fullCone);
    final b = await w.alice.discover([
      w.servers.first,
      (InternetAddress('192.0.2.99'), 1),
    ], timeout: const Duration(milliseconds: 500));
    expect(b.symmetric, isFalse);
    await w.close();
  });

  for (final (a, b) in [
    (NatType.portRestricted, NatType.portRestricted),
    (NatType.addressRestricted, NatType.portRestricted),
    (NatType.fullCone, NatType.portRestricted),
    (NatType.fullCone, NatType.symmetric),
  ]) {
    test('${a.name} ↔ ${b.name}: сведение и поток', () async {
      final w = _World(
        a,
        b,
        link: const LinkConditions(
          delay: Duration(milliseconds: 15),
          loss: 0.02,
        ),
      );
      final (client, node) = await w.connect();
      client.add(Uint8List.fromList(List.generate(100000, (i) => i)));
      final closing = client.close();
      final got = await node.input.fold<int>(0, (n, d) => n + d.length);
      expect(got, 100000);
      await node.close();
      await closing;
      await w.close();
    });
  }

  test('симметричный ↔ portRestricted: пробиться не удаётся', () async {
    final w = _World(NatType.symmetric, NatType.portRestricted);
    await expectLater(
      w.connect(timeout: const Duration(milliseconds: 800)),
      throwsA(isA<UdpRendezvousException>()),
    );
    expect(w.alice.punchesFailed + w.bob.punchesFailed, greaterThan(0));
    await w.close();
  });

  test('пакеты чужого номера сведения не засчитываются', () async {
    final w = _World(NatType.fullCone, NatType.fullCone);
    final a = await w.alice.discover(w.servers);
    final b = await w.bob.discover(w.servers);
    await expectLater(
      Future.wait([
        w.alice.punch(
          Uint8List(16)..[0] = 1,
          b.address,
          b.port,
          timeout: const Duration(milliseconds: 500),
        ),
        w.bob.punch(
          Uint8List(16)..[0] = 2,
          a.address,
          a.port,
          timeout: const Duration(milliseconds: 500),
        ),
      ]),
      throwsA(isA<UdpRendezvousException>()),
    );
    await w.close();
  });

  test('адреса узла: разбор и запись', () {
    expect(parseIpEndpoint('203.0.113.1:7'), (
      InternetAddress('203.0.113.1'),
      7,
    ));
    expect(parseIpEndpoint('[2001:db8::1]:443')!.$2, 443);
    expect(parseIpEndpoint('2001:db8::1:443'), isNull);
    expect(parseIpEndpoint('host:1'), isNull);
    expect(parseIpEndpoint('1.2.3.4:0'), isNull);
    expect(
      formatEndpoint(InternetAddress('2001:db8::1'), 5),
      '[2001:db8::1]:5',
    );
  });
}
