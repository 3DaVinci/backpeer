// Фаззинг рукопожатия Noise и разборщика кадров (задача 3.3.4, модель
// угроз Х-9): мутации записанного рукопожатия и потока кадров. Каждая
// сторона либо принимает вход, либо отказывает подтипом CoreException, и
// каждый прогон завершается — без зависаний.
//
//   FS_FUZZ_SECONDS=600 dart test test/noise_fuzz_test.dart
//   FS_FUZZ_RUNS=100000 FS_FUZZ_SEED=7 dart test test/noise_fuzz_test.dart
//
// По умолчанию — 2000 входов на фаззер, seed 1.

import 'dart:math';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:fixnum/fixnum.dart';
import 'package:protocol/protocol.dart' as pb;
import 'package:test/test.dart';

import 'support/fuzz.dart';

void main() {
  late CryptoProvider crypto;
  late LocalPeer client;
  late LocalPeer node;
  late Uint8List nodeId;
  // Эфемерные ключи фиксированы: записанное рукопожатие воспроизводится,
  // и мутации доходят до Hello и проверки сертификата.
  final clientEphemeral = Uint8List(32)..fillRange(0, 32, 0x11);
  final nodeEphemeral = Uint8List(32)..fillRange(0, 32, 0x22);
  late Uint8List message1;
  late Uint8List message2;
  late Uint8List message3;
  late NoiseTransportKeys clientKeys;
  late NoiseTransportKeys nodeKeys;
  // Хвост, отправленный устройством после рукопожатия.
  late Uint8List channelWire;

  Future<X25519KeyPair> fixed(Uint8List secret) =>
      crypto.x25519FromSecret(SecretBytes(secret));

  setUpAll(() async {
    crypto = await SodiumCryptoProvider.load();
    final now = DateTime.utc(2026, 10, 24);
    final account = await AccountKeys.fromMasterKey(
      SecretBytes(Uint8List(32)..[0] = 1),
      crypto,
    );
    final device = await DeviceKeys.fromSecret(
      crypto,
      SecretBytes(Uint8List(64)..fillRange(0, 64, 3)),
    );
    final nodeSign = await crypto.ed25519FromSeed(
      SecretBytes(Uint8List(32)..[0] = 4),
    );
    nodeId = nodeSign.publicKey;
    final nodeDh = await fixed(Uint8List(32)..[0] = 5);
    client = LocalPeer(
      role: pb.PeerRole.PEER_ROLE_CLIENT,
      staticKey: device.dh,
      certificate: await DeviceCertificates.issue(
        crypto,
        account,
        device,
        issuedAt: now,
      ),
    );
    node = LocalPeer(
      role: pb.PeerRole.PEER_ROLE_NODE,
      staticKey: nodeDh,
      certificate: await NodeCertificates.issue(
        crypto,
        account,
        nodeId: nodeId,
        nodeDh: nodeDh.publicKey,
        issuedAt: now,
      ),
      software: 'node fuzz',
    );

    // Запись правильного рукопожатия теми же шагами, что PeerHandshake.
    final c = await NoiseHandshake.start(
      crypto,
      initiator: true,
      staticKey: client.staticKey,
      ephemeral: await fixed(clientEphemeral),
    );
    final n = await NoiseHandshake.start(
      crypto,
      initiator: false,
      staticKey: node.staticKey,
      ephemeral: await fixed(nodeEphemeral),
    );
    final m1 = await c.writeMessage(Uint8List(0));
    await n.readMessage(m1);
    final m2 = await n.writeMessage(node.hello().writeToBuffer());
    await c.readMessage(m2);
    final m3 = await c.writeMessage(client.hello().writeToBuffer());
    await n.readMessage(m3);
    message1 = NoiseFrames.frame(m1);
    message2 = NoiseFrames.frame(m2);
    message3 = NoiseFrames.frame(m3);
    clientKeys = c.finish();
    nodeKeys = n.finish();

    final encoder = ChannelEncoder(clientKeys.send.copy());
    channelWire = Uint8List.fromList([
      ...encoder.encode(
        pb.PeerMessage(
          requestId: Int64(1),
          ping: pb.Ping(nonce: Int64(7)),
        ).writeToBuffer(),
      ),
      ...encoder.encode(
        pb.PeerMessage(
          requestId: Int64(2),
          hasFragments: pb.HasFragments(fragmentIds: [Uint8List(32)]),
        ).writeToBuffer(),
      ),
    ]);
  });

  /// Отвечающий принимает [input] (поток инициатора), затем поток
  /// закрывается.
  Future<void> respond(Uint8List input) async {
    final (a, b) = memoryConnectionPair();
    final result = PeerHandshake.respond(
      crypto,
      b,
      local: node,
      policy: PeerPolicy.anyone(),
      ephemeral: await fixed(nodeEphemeral),
      timeout: const Duration(seconds: 5),
    );
    a.add(input);
    await a.close();
    final channel = await result;
    // Рукопожатие прошло (мутация не задела его): читаем канал до конца.
    await channel.messages.drain<void>();
  }

  test('рукопожатие: отвечающий (сообщения 1 и 3, хвост канала)', () async {
    final valid = Uint8List.fromList([...message1, ...message3]);
    // Образец без мутаций принимается.
    await respond(Uint8List.fromList([...valid, ...channelWire]));
    final rejected = await fuzzAsync('noise-respond', [
      valid,
      Uint8List.fromList([...valid, ...channelWire]),
      message1,
    ], respond);
    expect(rejected, greaterThan(0));
  });

  test('рукопожатие: инициатор (сообщение 2)', () async {
    Future<void> initiate(Uint8List input) async {
      final (a, b) = memoryConnectionPair();
      final result = PeerHandshake.initiate(
        crypto,
        a,
        local: client,
        policy: PeerPolicy.node(nodeId),
        ephemeral: await fixed(clientEphemeral),
        timeout: const Duration(seconds: 5),
      );
      b.add(input);
      await b.close();
      final channel = await result;
      await channel.messages.drain<void>();
    }

    await initiate(message2);
    final rejected = await fuzzAsync('noise-initiate', [message2], initiate);
    expect(rejected, greaterThan(0));
  });

  test('Hello и проверка сертификата', () async {
    final samples = [node.hello().writeToBuffer()];
    await fuzzAsync('hello', samples, (input) async {
      final hello = ManifestObjects.parseMessage(
        'hello',
        () => pb.Hello.fromBuffer(input),
      );
      await PeerVerifier.verify(
        crypto,
        hello,
        remoteStatic: node.staticKey.publicKey,
        policy: PeerPolicy.node(nodeId),
      );
    });
  });

  test('транспортные кадры и PeerMessage после рукопожатия', () {
    void receive(Uint8List wire, ChannelDecoder decoder) {
      final frames = TransportFrameDecoder();
      for (final frame in frames.add(wire)) {
        for (final body in decoder.add(frame)) {
          ManifestObjects.parseMessage(
            'peer-message',
            () => pb.PeerMessage.fromBuffer(body),
          );
        }
      }
    }

    // Мутации шифротекста: почти всё отсекает тег.
    fuzz('noise-wire', [
      channelWire,
    ], (input) => receive(input, ChannelDecoder(nodeKeys.receive.copy())));

    // Мутации открытого текста, зашифрованного правильно: доходят до
    // длин кадров приложения и разбора PeerMessage. Куски случайной
    // длины — разные границы транспортных кадров.
    final plain = <int>[];
    final open = nodeKeys.receive.copy();
    for (final frame in TransportFrameDecoder().add(channelWire)) {
      plain.addAll(open.decrypt(Uint8List(0), frame)!);
    }
    final random = Random(fuzzSeed);
    final rejected = fuzz('peer-stream', [Uint8List.fromList(plain)], (input) {
      final send = clientKeys.send.copy();
      final out = BytesBuilder(copy: false);
      for (var i = 0; i < input.length;) {
        final n = min(
          input.length - i,
          1 + random.nextInt(NoiseFrames.maxPlaintext),
        );
        out.add(
          NoiseFrames.frame(
            send.encrypt(Uint8List(0), Uint8List.sublistView(input, i, i + n)),
          ),
        );
        i += n;
      }
      final decoder = ChannelDecoder(nodeKeys.receive.copy());
      receive(out.takeBytes(), decoder);
      if (decoder.hasPartial) {
        throw const DataFormatException(
          object: 'peer-message',
          problem: FormatProblem.truncated,
        );
      }
    });
    expect(rejected, greaterThan(0));
  });
}
