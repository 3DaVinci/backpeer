// Noise XX и кадры канала (задачи 3.3.1, 3.3.3): официальные векторы
// cacophony на обеих реализациях CryptoProvider и векторы кадров
// protocol/noise-frames.json от эталона на Python (tool/noise_vectors.py).

import 'dart:math';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:test/test.dart';
import 'package:test_vectors/test_vectors.dart';

import 'support/reference.dart' as reference;

Map<String, Object?> _map(Object? value) => value! as Map<String, Object?>;
Uint8List _hex(Object? value) => hexToBytes(value! as String);

Future<X25519KeyPair> _pair(CryptoProvider crypto, Object? hex) =>
    crypto.x25519FromSecret(SecretBytes(_hex(hex)));

/// Обе стороны рукопожатия XX с фиксированными ключами; возвращает
/// сообщения рукопожатия и шифры сторон.
Future<(List<Uint8List>, NoiseTransportKeys, NoiseTransportKeys)> _handshake(
  CryptoProvider crypto, {
  required Object? initStatic,
  required Object? initEphemeral,
  required Object? respStatic,
  required Object? respEphemeral,
  required Uint8List prologue,
  required List<Uint8List> payloads,
}) async {
  final i = await NoiseHandshake.start(
    crypto,
    initiator: true,
    staticKey: await _pair(crypto, initStatic),
    ephemeral: await _pair(crypto, initEphemeral),
    prologue: prologue,
  );
  final r = await NoiseHandshake.start(
    crypto,
    initiator: false,
    staticKey: await _pair(crypto, respStatic),
    ephemeral: await _pair(crypto, respEphemeral),
    prologue: prologue,
  );
  final wire = <Uint8List>[];
  for (var step = 0; step < 3; step++) {
    final (writer, reader) = step.isEven ? (i, r) : (r, i);
    expect(writer.isMyTurn, isTrue);
    final message = await writer.writeMessage(payloads[step]);
    expect(await reader.readMessage(message), payloads[step]);
    wire.add(message);
  }
  return (wire, i.finish(), r.finish());
}

Uint8List _messageBytes(Map<String, Object?> m) {
  if (m['message'] case final String hex) return hexToBytes(hex);
  final spec = _map(m['message']);
  expect(spec['type'], 'splitmix64-le');
  return splitmix64Bytes(spec['seed']! as int, spec['length']! as int);
}

void _expectWire(Map<String, Object?> m, Uint8List wire) {
  if (m['wire'] != null) {
    expect(bytesToHex(wire), m['wire']);
  } else {
    expect(wire.length, m['wireLength']);
    expect(bytesToHex(reference.blake2b(wire)), m['wireHash']);
  }
}

/// Режет [wire] на куски случайной длины, как их отдаёт TCP.
List<Uint8List> _chunks(Random r, Uint8List wire) {
  final out = <Uint8List>[];
  var i = 0;
  while (i < wire.length) {
    final n = min(wire.length - i, 1 + r.nextInt(r.nextBool() ? 7 : 70000));
    out.add(Uint8List.sublistView(wire, i, i + n));
    i += n;
  }
  return out;
}

/// Принимает [wire] через разбор транспортных кадров и [decoder].
List<Uint8List> _receive(
  Uint8List wire,
  ChannelDecoder decoder, {
  Random? split,
}) {
  final frames = TransportFrameDecoder();
  final out = <Uint8List>[];
  for (final chunk in split == null ? [wire] : _chunks(split, wire)) {
    for (final frame in frames.add(chunk)) {
      out.addAll(decoder.add(frame));
    }
  }
  if (frames.hasPartial) {
    throw const DataFormatException(
      object: 'noise-frame',
      problem: FormatProblem.truncated,
    );
  }
  if (decoder.hasPartial) {
    throw const DataFormatException(
      object: 'peer-message',
      problem: FormatProblem.truncated,
    );
  }
  return out;
}

void main() {
  final providers = <String, Future<CryptoProvider> Function()>{
    'libsodium': SodiumCryptoProvider.load,
    'dart': () async => DartCryptoProvider(),
  };

  for (final MapEntry(key: name, value: create) in providers.entries) {
    group('cacophony ($name)', () {
      late CryptoProvider crypto;
      setUpAll(() async => crypto = await create());
      for (final c in vectorCases(
        loadVectors('protocol/noise-cacophony.json'),
      )) {
        test(c['name'], () async {
          final input = _map(c['input']);
          final expected = _map(c['expected']);
          final messages = (expected['messages']! as List<Object?>)
              .map(_map)
              .toList();
          final (wire, i, r) = await _handshake(
            crypto,
            initStatic: input['init_static'],
            initEphemeral: input['init_ephemeral'],
            respStatic: input['resp_static'],
            respEphemeral: input['resp_ephemeral'],
            prologue: _hex(input['init_prologue']),
            payloads: [for (final m in messages.take(3)) _hex(m['payload'])],
          );
          for (var step = 0; step < 3; step++) {
            expect(bytesToHex(wire[step]), messages[step]['ciphertext']);
          }
          expect(bytesToHex(i.handshakeHash), expected['handshake_hash']);
          expect(r.handshakeHash, i.handshakeHash);
          for (var index = 3; index < messages.length; index++) {
            final (send, receive) = index.isEven
                ? (i.send, r.receive)
                : (r.send, i.receive);
            final payload = _hex(messages[index]['payload']);
            final ct = send.encrypt(Uint8List(0), payload);
            expect(bytesToHex(ct), messages[index]['ciphertext']);
            expect(receive.decrypt(Uint8List(0), ct), payload);
          }
        });
      }
    });
  }

  group('кадры', () {
    late CryptoProvider crypto;
    setUpAll(() async => crypto = await SodiumCryptoProvider.load());
    final vectors = loadVectors('protocol/noise-frames.json');

    Future<(List<Uint8List>, NoiseTransportKeys, NoiseTransportKeys)> start(
      Map<String, Object?> input,
    ) => _handshake(
      crypto,
      initStatic: input['initStatic'],
      initEphemeral: input['initEphemeral'],
      respStatic: input['respStatic'],
      respEphemeral: input['respEphemeral'],
      prologue: _hex(input['prologue']),
      payloads: [
        for (final p in input['handshakePayloads']! as List<Object?>) _hex(p),
      ],
    );

    for (final c in vectorCases(vectors)) {
      final input = _map(c['input']);
      final expected = _map(c['expected']);
      final interval = input['rekeyInterval']! as int;
      test(c['name'], () async {
        expect(bytesToHex(Noise.prologue), input['prologue']);
        final (wire, i, r) = await start(input);
        if (expected['error'] case final String error) {
          final decoder = ChannelDecoder(r.receive, rekeyInterval: interval);
          expect(
            () => _receive(_hex(input['initiatorWire']), decoder),
            throwsA(
              error == 'format'
                  ? isA<DataFormatException>()
                  : isA<IntegrityException>(),
            ),
          );
          return;
        }
        final handshake = expected['handshake']! as List<Object?>;
        for (var step = 0; step < 3; step++) {
          expect(bytesToHex(NoiseFrames.frame(wire[step])), handshake[step]);
        }
        expect(bytesToHex(i.handshakeHash), expected['handshakeHash']);
        expect(bytesToHex(r.remoteStatic), expected['initiatorStatic']);
        expect(bytesToHex(i.remoteStatic), expected['responderStatic']);

        final sides = {
          'initiator': (
            ChannelEncoder(i.send, rekeyInterval: interval),
            ChannelDecoder(r.receive, rekeyInterval: interval),
          ),
          'responder': (
            ChannelEncoder(r.send, rekeyInterval: interval),
            ChannelDecoder(i.receive, rekeyInterval: interval),
          ),
        };
        final random = Random(7);
        for (final m in (expected['messages']! as List<Object?>).map(_map)) {
          final (encoder, decoder) = sides[m['from']]!;
          final body = _messageBytes(m);
          final out = encoder.encode(body);
          _expectWire(m, out);
          // Получатель не опирается на границы кусков TCP.
          final received = _receive(out, decoder, split: random);
          expect(received, hasLength(1));
          expect(received.single, body);
          var frames = 0;
          for (var at = 0; at < out.length; frames++) {
            at += 2 + (out[at] << 8 | out[at + 1]);
          }
          expect(frames, m['transportFrames']);
        }
      });
    }

    test('несколько сообщений в одном куске и пустые куски', () async {
      final (_, i, r) = await start(_map(vectorCases(vectors).first['input']));
      final encoder = ChannelEncoder(i.send);
      final decoder = ChannelDecoder(r.receive);
      final bodies = [
        for (var n = 0; n < 20; n++) splitmix64Bytes(n, n * 9000),
      ];
      final wire = Uint8List.fromList([
        for (final b in bodies) ...encoder.encode(b),
      ]);
      final frames = TransportFrameDecoder();
      final out = <Uint8List>[];
      expect(frames.add(Uint8List(0)), isEmpty);
      for (final frame in frames.add(wire)) {
        out.addAll(decoder.add(frame));
      }
      expect(out, bodies);
      expect(frames.hasPartial, isFalse);
    });

    test('сообщение длиннее 1 МиБ не отправляется', () async {
      final (_, i, _) = await start(_map(vectorCases(vectors).first['input']));
      expect(
        () =>
            ChannelEncoder(i.send)
                .encode(Uint8List(NoiseFrames.maxAppMessage + 1)),
        throwsArgumentError,
      );
    });

    test('смена ключей меняет шифротекст, nonce продолжается', () async {
      final input = _map(vectorCases(vectors).first['input']);
      final (_, a, _) = await start(input);
      final (_, b, _) = await start(input);
      final plain = Uint8List(10);
      final first = a.send.encrypt(Uint8List(0), plain);
      expect(b.send.encrypt(Uint8List(0), plain), first);
      b.send.rekey();
      expect(a.send.nonce, b.send.nonce);
      expect(
        a.send.encrypt(Uint8List(0), plain),
        isNot(b.send.encrypt(Uint8List(0), plain)),
      );
    });
  });

  group('рукопожатие', () {
    late CryptoProvider crypto;
    setUpAll(() async => crypto = await SodiumCryptoProvider.load());

    Future<(NoiseHandshake, NoiseHandshake)> pair() async {
      Future<X25519KeyPair> key() =>
          crypto.x25519FromSecret(SecretBytes(crypto.randomBytes(32)));
      return (
        await NoiseHandshake.start(
          crypto,
          initiator: true,
          staticKey: await key(),
        ),
        await NoiseHandshake.start(
          crypto,
          initiator: false,
          staticKey: await key(),
        ),
      );
    }

    test('порядок сообщений соблюдается', () async {
      final (i, r) = await pair();
      expect(() => r.writeMessage(Uint8List(0)), throwsStateError);
      expect(() => i.readMessage(Uint8List(32)), throwsStateError);
      expect(i.finish, throwsStateError);
    });

    test('короткое и подменённое сообщение 2', () async {
      final (i, r) = await pair();
      await r.readMessage(await i.writeMessage(Uint8List(0)));
      final m2 = await r.writeMessage(Uint8List.fromList([1, 2, 3]));
      await expectLater(
        i.readMessage(Uint8List.sublistView(m2, 0, 60)),
        throwsA(isA<DataFormatException>()),
      );
      final tampered = Uint8List.fromList(m2)..[40] ^= 1;
      await expectLater(
        i.readMessage(tampered),
        throwsA(isA<IntegrityException>()),
      );
    });

    test('эфемерный ключ малого порядка', () async {
      final (_, r) = await pair();
      await r.readMessage(Uint8List(32));
      await expectLater(
        r.writeMessage(Uint8List(0)),
        throwsA(isA<DataFormatException>()),
      );
    });
  });
}
