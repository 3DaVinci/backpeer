// Привязка узла к учётной записи (задачи 6.1.1, 6.1.2; protocol.md,
// раздел 4.17): клиентская часть NodePairing и QR-код кода привязки в
// терминале. Координатор подменяется локальным HTTP-сервером.

import 'dart:io';

import 'package:core/core.dart';
import 'package:fixnum/fixnum.dart';
import 'package:node/node.dart';
import 'package:protocol/protocol.dart' as pb;
import 'package:qr/qr.dart';
import 'package:test/test.dart';

/// Подставной координатор: отвечает на методы по сценарию [respond].
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
  Object Function(String method, List<int> body) respond;
  final calls = <String>[];
  final bodies = <List<int>>[];

  String get url => 'http://127.0.0.1:${_server.port}';

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
  }

  Future<void> close() => _server.close(force: true);
}

void main() {
  late CryptoProvider crypto;
  setUpAll(() async => crypto = await SodiumCryptoProvider.load());

  group('QR-код привязки', () {
    test('pairQrContent — URI backpeer:pair:<код>', () {
      expect(pairQrContent('ABCD1234'), 'backpeer:pair:ABCD1234');
    });

    test('renderPairQr: тихая зона, по два столбца на модуль, '
        'детерминированный', () {
      const code = 'ABCD1234';
      final text = pairQrContent(code);
      final image = QrImage(QrCode(payload: QrPayload.fromString(text)));
      final n = image.moduleCount;
      const quiet = 2;
      final width = (n + 2 * quiet) * 2;

      final rendered = renderPairQr(text);
      // Вывод заканчивается переводом строки: убрать хвостовой пустой элемент,
      // не трогая нижнюю тихую зону (строки из одних пробелов).
      final lines = rendered.split('\n')..removeLast();
      expect(lines, hasLength(n + 2 * quiet));
      for (final line in lines) {
        expect(line.length, width);
      }
      // Тихая зона по краям — светлая.
      expect(lines.first, ' ' * width);
      expect(lines.last, ' ' * width);
      for (final line in lines) {
        expect(line.substring(0, quiet * 2), ' ' * (quiet * 2));
        expect(line.substring(line.length - quiet * 2), ' ' * (quiet * 2));
      }
      // Внутри есть тёмные и светлые модули.
      expect(rendered, contains('██'));
      expect(rendered, contains('  '));
      // Один и тот же код рисуется одинаково.
      expect(renderPairQr(text), rendered);
      // Разные коды — разный рисунок.
      expect(
        renderPairQr(text),
        isNot(renderPairQr(pairQrContent('ZZZZ9999'))),
      );
    });
  });

  group('NodePairing', () {
    Future<NodePairing> pairing(_FakeCoordinator fake) async {
      final client = CoordinatorClient(
        baseUri: Uri.parse(fake.url),
        crypto: crypto,
        retry: RetryPolicy.none,
      );
      addTearDown(() => client.close(force: true));
      return NodePairing(client, crypto);
    }

    test(
      'start: шлёт открытый X25519, возвращает код, срок и отпечаток',
      () async {
        final keys = await DeviceKeys.generate(crypto);
        addTearDown(keys.dispose);
        final fake = await _FakeCoordinator.start(
          (method, body) => pb.NodePairStartResponse(
            code: 'ABCD1234',
            expiresAtUnixMs: Int64(1700000000000),
          ),
        );
        addTearDown(fake.close);

        final session = await (await pairing(fake)).start(keys);

        expect(fake.calls, ['NodePairStart']);
        expect(
          pb.NodePairStartRequest.fromBuffer(fake.bodies.single).nodeDh,
          keys.dh.publicKey,
        );
        expect(session.code, 'ABCD1234');
        expect(
          session.expiresAt,
          DateTime.fromMillisecondsSinceEpoch(1700000000000),
        );
        expect(
          session.fingerprint,
          nodeFingerprint(
            crypto,
            nodeId: keys.sign.publicKey,
            nodeDh: keys.dh.publicKey,
          ),
        );
      },
    );

    test(
      'waitForCertificate: сертификат уже подписан — возвращает его',
      () async {
        final keys = await DeviceKeys.generate(crypto);
        addTearDown(keys.dispose);
        final signed = pb.Signed(
          signer: crypto.randomBytes(32),
          signature: crypto.randomBytes(64),
        );
        final fake = await _FakeCoordinator.start(
          (method, body) => pb.NodePairStatusResponse(
            status: pb.NodePairStatus.NODE_PAIR_STATUS_SIGNED,
            nodeCertificate: signed,
          ),
        );
        addTearDown(fake.close);

        final cert = await (await pairing(fake)).waitForCertificate(keys);

        expect(cert, isNotNull);
        expect(cert!.writeToBuffer(), signed.writeToBuffer());
        expect(fake.calls, ['NodePairStatus']);
      },
    );

    test('waitForCertificate: код просрочен — null', () async {
      final keys = await DeviceKeys.generate(crypto);
      addTearDown(keys.dispose);
      final fake = await _FakeCoordinator.start(
        (method, body) => pb.NodePairStatusResponse(
          status: pb.NodePairStatus.NODE_PAIR_STATUS_EXPIRED,
        ),
      );
      addTearDown(fake.close);

      expect(await (await pairing(fake)).waitForCertificate(keys), isNull);
    });

    test(
      'waitForCertificate: PENDING, затем SIGNED — дожидается подписи',
      () async {
        final keys = await DeviceKeys.generate(crypto);
        addTearDown(keys.dispose);
        final signed = pb.Signed(
          signer: crypto.randomBytes(32),
          signature: crypto.randomBytes(64),
        );
        var polls = 0;
        final fake = await _FakeCoordinator.start((method, body) {
          polls++;
          return polls == 1
              ? pb.NodePairStatusResponse(
                  status: pb.NodePairStatus.NODE_PAIR_STATUS_PENDING,
                )
              : pb.NodePairStatusResponse(
                  status: pb.NodePairStatus.NODE_PAIR_STATUS_SIGNED,
                  nodeCertificate: signed,
                );
        });
        addTearDown(fake.close);

        final cert = await (await pairing(fake)).waitForCertificate(keys);

        expect(cert!.writeToBuffer(), signed.writeToBuffer());
        expect(polls, 2);
      },
      timeout: const Timeout(Duration(seconds: 20)),
    );
  });
}
