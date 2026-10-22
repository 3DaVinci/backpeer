import 'dart:async';
import 'dart:typed_data';

import 'package:coordinator/coordinator.dart';
import 'package:core/core.dart';
import 'package:protocol/protocol.dart' as pb;
import 'package:shelf/shelf.dart';

/// Часы, которые тест двигает сам.
final class FakeClock {
  new([DateTime? start]) : now = start ?? DateTime.utc(2026, 10, 22, 12);

  DateTime now;

  DateTime call() => now;

  void advance(Duration d) => now = now.add(d);
}

/// Обработчик API с ключами в памяти и подменяемыми часами.
final class Harness {
  new _(this.crypto, this.clock, this.keys, this.handler);

  static Future<Harness> create({
    CoordinatorService service = const UnimplementedCoordinatorService(),
    RateLimits limits = const RateLimits(
      ipPerSecond: 1000,
      ipBurst: 1000,
      keyPerSecond: 1000,
      keyBurst: 1000,
    ),
    Future<bool> Function()? healthCheck,
    bool trustForwardedFor = false,
  }) async {
    final crypto = await SodiumCryptoProvider.load();
    final clock = FakeClock();
    final keys = InMemoryKeyDirectory();
    final handler = ApiHandler(
      methods: coordinatorMethods(service),
      verifier: RequestVerifier(crypto: crypto, keys: keys, clock: clock.call),
      ipLimiter: RateLimiter(
        perSecond: limits.ipPerSecond,
        burst: limits.ipBurst,
        clock: clock.call,
      ),
      keyLimiter: RateLimiter(
        perSecond: limits.keyPerSecond,
        burst: limits.keyBurst,
        clock: clock.call,
      ),
      healthCheck: healthCheck ?? () async => true,
      trustForwardedFor: trustForwardedFor,
    );
    return Harness._(crypto, clock, keys, handler);
  }

  final CryptoProvider crypto;
  final FakeClock clock;
  final InMemoryKeyDirectory keys;
  final ApiHandler handler;

  var _seed = 0;

  /// Новая пара ключей; с [kind] — сразу в справочнике.
  Future<Ed25519KeyPair> newKey({KeyKind? kind, bool revoked = false}) async {
    final seed = Uint8List(32)..[0] = ++_seed;
    final key = await crypto.ed25519FromSeed(SecretBytes(seed));
    if (kind != null) {
      keys.put(
        key.publicKey,
        KeyInfo(kind: kind, accountId: Uint8List(32), revoked: revoked),
      );
    }
    return key;
  }

  /// `POST /api/v1/<method>`; с [key] — с подписью `FS-Auth`.
  Future<Response> post(
    String method,
    List<int> body, {
    Ed25519KeyPair? key,
    int? timeMs,
    String? authHeader,
    Map<String, String> headers = const {},
    String contentType = 'application/x-protobuf',
  }) async {
    final path = '/api/v1/$method';
    var auth = authHeader;
    if (key != null) {
      auth = (await RequestAuth.sign(
        crypto,
        key,
        path: path,
        body: body,
        timeMs: timeMs ?? clock.now.millisecondsSinceEpoch,
      )).toHeader();
    }
    return await handler.call(
      Request(
        'POST',
        Uri.parse('http://coordinator.test$path'),
        body: body,
        headers: {'content-type': contentType, 'FS-Auth': ?auth, ...headers},
      ),
    );
  }
}

/// Тело ответа с ошибкой.
Future<pb.Error> errorOf(Response response) async {
  expect200(response, ok: false);
  return pb.Error.fromBuffer(await _bytes(response));
}

Future<Uint8List> bodyOf(Response response) => _bytes(response);

void expect200(Response response, {required bool ok}) {
  if ((response.statusCode == 200) != ok) {
    throw StateError('статус ${response.statusCode}');
  }
}

Future<Uint8List> _bytes(Response response) async {
  final builder = BytesBuilder(copy: false);
  await response.read().forEach(builder.add);
  return builder.takeBytes();
}
