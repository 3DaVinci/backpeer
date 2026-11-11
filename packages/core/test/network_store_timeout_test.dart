// Хранилище фрагментов по сети (задача 3.9.2): недоступный узел не должен
// задерживать размещение сегмента. Проверка владельца ждёт ответа не дольше
// `handshakeTimeout`, а потом узел на `failureBackoff` не трогается —
// иначе каждый сегмент бэкапа стоял бы на одном и том же молчащем узле.

import 'dart:async';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:protocol/protocol.dart' as pb;
import 'package:test/test.dart';

/// Транспорт, который принимает попытку подключения и молчит: так ведёт
/// себя узел за NAT, до которого не доходит ни TCP, ни UDP, ни relay.
final class _HangingTransport implements Transport {
  int attempts = 0;
  final _opened = <Completer<PeerConnection>>[];

  @override
  Future<PeerConnection> connect(NodeContact node) {
    attempts++;
    final completer = Completer<PeerConnection>();
    _opened.add(completer);
    return completer.future;
  }

  @override
  Future<void> close() async {
    for (final c in _opened) {
      if (!c.isCompleted) {
        c.completeError(PeerUnreachableException(Uint8List(32), const []));
      }
    }
    _opened.clear();
  }
}

final class _Access implements NodeAccess {
  new(this.node);

  final Uint8List node;

  @override
  List<Uint8List> get knownNodes => [node];

  @override
  NodeContact? contact(Uint8List nodeId) =>
      NodeContact(nodeId: nodeId, endpoints: const ['127.0.0.1:9']);

  /// Талон есть: до подключения дело доходит, и отказ — от недоступности,
  /// а не от отсутствия талона.
  @override
  Future<pb.Signed?> ticket(
    pb.TicketOperation operation,
    Uint8List nodeId,
    Uint8List fragmentId, {
    int? fragmentSize,
  }) async => pb.Signed();

  @override
  void consumed(
    pb.TicketOperation operation,
    Uint8List nodeId,
    Uint8List fragmentId,
  ) {}
}

void main() {
  late CryptoProvider crypto;
  final nodeId = Uint8List(32)..[0] = 7;
  final node = bytesToHex(nodeId);

  setUpAll(() async {
    crypto = await SodiumCryptoProvider.load();
  });

  test('молчащий узел: проверка владельца не ждёт дольше таймаута', () async {
    final transport = _HangingTransport();
    final store = NetworkFragmentStore(
      crypto: crypto,
      transport: transport,
      access: _Access(nodeId),
      handshakeTimeout: const Duration(milliseconds: 100),
      failureBackoff: const Duration(seconds: 5),
    );
    addTearDown(store.close);

    final watch = Stopwatch()..start();
    expect(await store.handshake(node), isNull);
    expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    expect(transport.attempts, 1);
  });

  test('узел не трогается повторно до конца паузы', () async {
    final transport = _HangingTransport();
    final store = NetworkFragmentStore(
      crypto: crypto,
      transport: transport,
      access: _Access(nodeId),
      handshakeTimeout: const Duration(milliseconds: 50),
      failureBackoff: const Duration(milliseconds: 200),
    );
    addTearDown(store.close);

    expect(await store.handshake(node), isNull);
    expect(transport.attempts, 1);
    // Второй раз — сразу `null`, без нового подключения.
    final watch = Stopwatch()..start();
    expect(await store.handshake(node), isNull);
    expect(watch.elapsed, lessThan(const Duration(milliseconds: 150)));
    expect(transport.attempts, 1);
    // Пауза прошла — попытка снова.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(await store.handshake(node), isNull);
    expect(transport.attempts, 2);
  });

  test('операция с недоступным узлом — unavailable, без ожидания', () async {
    final transport = _HangingTransport();
    final store = NetworkFragmentStore(
      crypto: crypto,
      transport: transport,
      access: _Access(nodeId),
      handshakeTimeout: const Duration(milliseconds: 50),
      failureBackoff: const Duration(seconds: 5),
    );
    addTearDown(store.close);
    await store.handshake(node);
    final watch = Stopwatch()..start();
    await expectLater(
      store.get(node, Uint8List(32)),
      throwsA(
        isA<StorageException>().having(
          (e) => e.problem,
          'problem',
          StorageProblem.unavailable,
        ),
      ),
    );
    expect(watch.elapsed, lessThan(const Duration(milliseconds: 150)));
  });
}
