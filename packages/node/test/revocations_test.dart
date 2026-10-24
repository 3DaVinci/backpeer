import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:fixnum/fixnum.dart';
import 'package:node/node.dart';
import 'package:protocol/protocol.dart' as pb;
import 'package:test/test.dart';

void main() {
  late CryptoProvider crypto;
  late AccountKeys owner;
  late AccountKeys stranger;
  late Directory dir;
  setUpAll(() async {
    crypto = await SodiumCryptoProvider.load();
    owner = await AccountKeys.fromMasterKey(
      SecretBytes(crypto.randomBytes(32)),
      crypto,
    );
    stranger = await AccountKeys.fromMasterKey(
      SecretBytes(crypto.randomBytes(32)),
      crypto,
    );
  });
  setUp(() => dir = Directory.systemTemp.createTempSync('fs-node-revoke-'));
  tearDown(() => dir.deleteSync(recursive: true));

  Future<pb.RevocationEntry> entry(
    int sequence,
    Uint8List device, {
    AccountKeys? account,
  }) async => pb.RevocationEntry(
    sequence: Int64(sequence),
    revocation: await DeviceCertificates.revoke(
      crypto,
      account ?? owner,
      deviceSign: device,
      revokedAt: DateTime.utc(2026, 10, 24),
    ),
  );

  test('отзывы сохраняются и действуют после перезапуска', () async {
    final a = crypto.randomBytes(32);
    final b = crypto.randomBytes(32);
    var index = FragmentIndex.open('${dir.path}/fragments.db');
    var list = RevocationList(index, crypto);
    expect(list.isRevoked(a), isFalse);
    expect(await list.apply([await entry(1, a), await entry(2, b)]), 2);
    // Повтор того же устройства под новым номером — не новый отзыв.
    expect(await list.apply([await entry(3, a)]), 0);
    expect(list.isRevoked(a), isTrue);
    expect(list.sequence, 3);
    index.close();

    index = FragmentIndex.open('${dir.path}/fragments.db');
    list = RevocationList(index, crypto);
    expect(list.isRevoked(a), isTrue);
    expect(list.isRevoked(b), isTrue);
    expect(list.isRevoked(crypto.randomBytes(32)), isFalse);
    expect(list.count, 2);
    expect(list.sequence, 3);
    index.close();
  });

  test('поддельный отзыв не принимается, номер продвигается', () async {
    final index = FragmentIndex.inMemory();
    final list = RevocationList(index, crypto);
    final device = crypto.randomBytes(32);
    // Подписан не той учётной записью, что в отзыве.
    final forged = await SignedMessages.sign(
      crypto,
      stranger.accountSign,
      DeviceCertificates.revocationContext,
      pb.DeviceRevocation(
        accountId: owner.accountId,
        deviceSign: device,
        revokedAtUnixMs: Int64(1),
      ),
    );
    final good = await entry(2, device, account: stranger);
    final tampered = good.deepCopy()
      ..sequence = Int64(3)
      ..revocation.signature = (Uint8List.fromList(good.revocation.signature)
        ..[5] ^= 1);
    expect(
      await list.apply([
        pb.RevocationEntry(sequence: Int64(1), revocation: forged),
        tampered,
      ]),
      0,
    );
    expect(list.isRevoked(device), isFalse);
    expect(list.sequence, 3);
    // Номера не по возрастанию пропускаются.
    expect(await list.apply([good]), 0);
    expect(list.isRevoked(device), isFalse);
    index.close();
  });

  test('синхронизация с координатором постранично', () async {
    final devices = [for (var i = 0; i < 3; i++) crypto.randomBytes(32)];
    final entries = [
      for (var i = 0; i < devices.length; i++) await entry(i + 1, devices[i]),
    ];
    final requests = <pb.ListRevocationsRequest>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final body = await request.fold<List<int>>([], (a, b) => a..addAll(b));
      final r = pb.ListRevocationsRequest.fromBuffer(body);
      requests.add(r);
      // Страницы по две записи.
      final after = r.afterSequence.toInt();
      final page = entries.skip(after).take(2).toList();
      request.response
        ..headers.contentType = ContentType('application', 'x-protobuf')
        ..add(
          pb.ListRevocationsResponse(
            revocations: page,
            more: after + page.length < entries.length,
          ).writeToBuffer(),
        );
      await request.response.close();
    });
    final client = CoordinatorClient(
      baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
      crypto: crypto,
      retry: RetryPolicy.none,
    );
    final index = FragmentIndex.inMemory();
    final list = RevocationList(index, crypto);
    final nodeKey = await crypto.ed25519FromSeed(
      SecretBytes(crypto.randomBytes(32)),
    );
    expect(await list.sync(client, nodeKey), 3);
    expect([for (final r in requests) r.afterSequence.toInt()], [0, 2]);
    expect(requests.first.limit, RevocationList.pageLimit);
    expect(devices.every(list.isRevoked), isTrue);
    // Следующая синхронизация начинает с последнего номера.
    expect(await list.sync(client, nodeKey), 0);
    expect(requests.last.afterSequence.toInt(), 3);
    client.close(force: true);
    await server.close(force: true);
    index.close();
  });
}
