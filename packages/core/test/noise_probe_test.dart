import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:protocol/protocol.dart' as pb;
import 'package:test/test.dart';

/// Проверка достижимости узла первыми двумя сообщениями Noise XX
/// (задача 3.5.1).
void main() {
  late CryptoProvider crypto;
  late X25519KeyPair nodeDh;
  late pb.Signed nodeCert;
  final servers = <ServerSocket>[];

  setUpAll(() async {
    crypto = await SodiumCryptoProvider.load();
    final owner = await AccountKeys.fromMasterKey(
      SecretBytes(crypto.randomBytes(32)),
      crypto,
    );
    final nodeSign = await crypto.ed25519FromSeed(
      SecretBytes(crypto.randomBytes(32)),
    );
    nodeDh = await crypto.x25519FromSecret(SecretBytes(crypto.randomBytes(32)));
    nodeCert = await NodeCertificates.issue(
      crypto,
      owner,
      nodeId: nodeSign.publicKey,
      nodeDh: nodeDh.publicKey,
      issuedAt: DateTime.now(),
    );
  });

  tearDown(() async {
    for (final s in servers) {
      await s.close();
    }
    servers.clear();
  });

  /// Сервер, который отвечает как узел; возвращает его порт и итоги
  /// рукопожатий на его стороне.
  Future<(int, List<Object>)> nodeServer() async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    servers.add(server);
    final outcomes = <Object>[];
    server.listen((socket) {
      unawaited(
        PeerHandshake.respond(
          crypto,
          SocketConnection(socket),
          local: LocalPeer(
            role: pb.PeerRole.PEER_ROLE_NODE,
            staticKey: nodeDh,
            certificate: nodeCert,
            software: 'node test',
          ),
          policy: PeerPolicy.anyone(),
        ).then(outcomes.add, onError: outcomes.add),
      );
    });
    return (server.port, outcomes);
  }

  Future<NoiseProbeResult> probe(
    int port, {
    Uint8List? expected,
    Duration timeout = const Duration(seconds: 5),
  }) => NoiseProbe.probe(
    crypto,
    address: InternetAddress.loopbackIPv4,
    port: port,
    expectedStatic: expected ?? nodeDh.publicKey,
    timeout: timeout,
  );

  test('узел с ожидаемым ключом — reachable; у узла рукопожатие '
      'обрывается без канала', () async {
    final (port, outcomes) = await nodeServer();
    expect(await probe(port), NoiseProbeResult.reachable);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(outcomes, [isA<PeerRejectedException>()]);
  });

  test('другой ключ — wrongPeer', () async {
    final (port, _) = await nodeServer();
    expect(
      await probe(port, expected: crypto.randomBytes(32)),
      NoiseProbeResult.wrongPeer,
    );
  });

  test('порт закрыт — refused', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = server.port;
    await server.close();
    expect(await probe(port), NoiseProbeResult.refused);
  });

  test('не Noise: сервер отвечает мусором или закрывает — wrongPeer', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    servers.add(server);
    var n = 0;
    server.listen((socket) {
      if (n++ == 0) {
        socket
          ..add(
            Uint8List.fromList('HTTP/1.1 400 Bad Request\r\n\r\n'.codeUnits),
          )
          ..destroy();
      } else {
        socket.destroy();
      }
    });
    expect(await probe(server.port), NoiseProbeResult.wrongPeer);
    expect(await probe(server.port), NoiseProbeResult.wrongPeer);
  });

  test('сервер молчит — timeout', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    servers.add(server);
    final held = <Socket>[];
    server.listen(held.add);
    final watch = Stopwatch()..start();
    expect(
      await probe(server.port, timeout: const Duration(milliseconds: 300)),
      NoiseProbeResult.timeout,
    );
    expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    for (final s in held) {
      s.destroy();
    }
  });
}
