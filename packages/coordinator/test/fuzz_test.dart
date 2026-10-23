// Фаззинг API координатора (задача 2.9.2): тела запросов всех методов и
// заголовок FS-Auth. Запросы подписаны правильным ключом, поэтому доходят
// до разбора и обработки на настоящей базе. Координатор отвечает
// ошибкой протокола, но никогда INTERNAL (500): это значило бы
// необработанное исключение или ошибку базы на недоверенных данных.
// После прогона /health отвечает 200.
//
//   FS_FUZZ_RUNS=2000 FS_FUZZ_SEED=7 FS_TEST_POSTGRES=… dart test test/fuzz_test.dart
//
// FS_FUZZ_RUNS — входов на метод (по умолчанию 150), FS_FUZZ_SEED — seed
// (по умолчанию 1). Половина входов — мутация байтов правильного образца,
// половина — образец с граничными значениями полей. Упавший вход
// печатается в hex вместе с seed и номером прогона.

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:coordinator/coordinator.dart';
import 'package:core/core.dart';
import 'package:fixnum/fixnum.dart';
import 'package:protobuf/protobuf.dart';
import 'package:protocol/protocol.dart' as pb;
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import '../../core/test/fuzz_test.dart' show mutate;
import 'support/db_harness.dart';
import 'support/harness.dart';
import 'support/postgres.dart';

final Map<String, String> _env = Platform.environment;
final int _runs = int.parse(_env['FS_FUZZ_RUNS'] ?? '150');
final int _seed = int.parse(_env['FS_FUZZ_SEED'] ?? '1');

/// Образец с граничными значениями части полей (рекурсивно).
GeneratedMessage boundary(Random r, GeneratedMessage sample) {
  final m = sample.deepCopy();
  for (final fi in m.info_.fieldInfo.values) {
    if (r.nextInt(3) != 0) continue;
    final base = PbFieldType.baseType(fi.type);
    Object? value() => switch (base) {
      PbFieldType.BYTES_BIT => Uint8List.fromList(
        List.filled(
          const [0, 1, 15, 16, 17, 31, 32, 33, 64, 96, 97, 148, 300][r.nextInt(
            13,
          )],
          r.nextBool() ? 0 : r.nextInt(256),
        ),
      ),
      PbFieldType.STRING_BIT => const [
        '',
        'a',
        'alice',
        'ALICE',
        'ab',
        '-alice',
        'ёлка',
        '\u0000',
        'stub-0123456789abcdef',
      ][r.nextInt(9)],
      PbFieldType.BOOL_BIT => r.nextBool(),
      PbFieldType.INT32_BIT ||
      PbFieldType.SINT32_BIT ||
      PbFieldType.SFIXED32_BIT => const [
        0,
        1,
        -1,
        0x7FFFFFFF,
        -0x80000000,
      ][r.nextInt(5)],
      PbFieldType.UINT32_BIT || PbFieldType.FIXED32_BIT => const [
        0,
        1,
        2,
        10,
        16,
        20,
        255,
        256,
        1000,
        1001,
        65536,
        0x7FFFFFFF,
        0xFFFFFFFF,
      ][r.nextInt(13)],
      PbFieldType.INT64_BIT ||
      PbFieldType.SINT64_BIT ||
      PbFieldType.SFIXED64_BIT ||
      PbFieldType.UINT64_BIT ||
      PbFieldType.FIXED64_BIT => [
        Int64.ZERO,
        Int64.ONE,
        Int64(-1),
        Int64.MAX_VALUE,
        Int64.MIN_VALUE,
        Int64(1 << 40),
        Int64(DateTime.now().millisecondsSinceEpoch),
      ][r.nextInt(7)],
      PbFieldType.ENUM_BIT => () {
        final values = fi.enumValues ?? const [];
        return values.isEmpty ? null : values[r.nextInt(values.length)];
      }(),
      PbFieldType.MESSAGE_BIT => boundary(r, fi.subBuilder!()),
      _ => null,
    };
    if (fi.isRepeated) {
      final list = m.getField(fi.tagNumber) as List<Object?>;
      final n = const [0, 1, 2, 19, 20, 21, 300][r.nextInt(7)];
      if (r.nextBool()) list.clear();
      for (var i = 0; i < n && list.length < n; i++) {
        final v = value();
        if (v != null) list.add(v);
      }
    } else {
      final v = value();
      if (v != null) m.setField(fi.tagNumber, v);
    }
  }
  return m;
}

String _hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  if (testPostgresUrl == null) {
    test('фаззинг API', () {}, skip: skipWithoutPostgres);
    return;
  }
  late DbHarness h;

  /// Метод → (образец запроса, ключ подписи или `null` — без подписи).
  final samples = <String, (GeneratedMessage, Ed25519KeyPair?)>{};

  setUpAll(() async {
    h = await DbHarness.create();
    final account = await h.newAccount();
    final device = await h.newKey();
    await h.register(account, device, login: 'alice', password: 'пароль');
    final second = await h.newKey();
    final owner = await h.newAccount();
    await h.register(owner, await h.newKey(), login: 'keeper');
    final node = await h.newKey();
    await h.registerNode(owner, node);
    final fresh = await h.newAccount();
    final freshDevice = await h.newKey();
    final freshNode = await h.newKey();
    final (bundle, verifier) = await h.keyCopy(account, 'новый пароль');
    Uint8List id(int b) => Uint8List(32)..[0] = b;
    final now = Int64(h.clock.now.millisecondsSinceEpoch);
    samples.addAll({
      'RegisterAccount': (
        pb.RegisterAccountRequest(
          deviceCertificate: await h.deviceCert(fresh, freshDevice),
          login: 'bob',
          keyBundle: bundle,
          authVerifier: verifier,
        ),
        fresh.accountSign,
      ),
      'AddDevice': (
        pb.AddDeviceRequest(
          deviceCertificate: await h.deviceCert(account, second),
        ),
        account.accountSign,
      ),
      'ListDevices': (pb.ListDevicesRequest(), account.accountSign),
      'RevokeDevice': (
        pb.RevokeDeviceRequest(revocation: await h.revocation(account, second)),
        account.accountSign,
      ),
      'SetKeyBundle': (
        pb.SetKeyBundleRequest(keyBundle: bundle, authVerifier: verifier),
        account.accountSign,
      ),
      'GetLoginParams': (pb.GetLoginParamsRequest(login: 'alice'), null),
      'GetKeyBundle': (
        pb.GetKeyBundleRequest(
          login: 'alice',
          timeUnixMs: now,
          authProof: Uint8List(64),
        ),
        null,
      ),
      'PutObject': (
        pb.PutObjectRequest(
          kind: pb.ObjectKind.OBJECT_KIND_SNAPSHOT,
          objectId: id(1),
          blob: [1, 2, 3],
          sequence: Int64.ONE,
        ),
        device,
      ),
      'ListObjects': (
        pb.ListObjectsRequest(
          kind: pb.ObjectKind.OBJECT_KIND_SNAPSHOT,
          afterObjectId: id(0),
          limit: 10,
        ),
        device,
      ),
      'GetObject': (
        pb.GetObjectRequest(
          kind: pb.ObjectKind.OBJECT_KIND_SNAPSHOT,
          objectId: id(1),
        ),
        device,
      ),
      'DeleteObject': (
        pb.DeleteObjectRequest(
          kind: pb.ObjectKind.OBJECT_KIND_INDEX,
          objectId: id(2),
        ),
        device,
      ),
      'AllocateSegment': (
        pb.AllocateSegmentRequest(
          segmentId: id(3),
          k: 1,
          n: 1 + 1,
          repairThreshold: 1,
          fragmentSize: 1000,
          fragmentIds: [id(4), id(5)],
          bodyRoots: [id(6), id(7)],
        ),
        device,
      ),
      'CommitSegment': (
        pb.CommitSegmentRequest(segmentId: id(3), storedIndexes: [0, 1]),
        device,
      ),
      'LocateSegment': (pb.LocateSegmentRequest(segmentId: id(3)), device),
      'DeleteSegment': (pb.DeleteSegmentRequest(segmentId: id(3)), device),
      'RegisterNode': (
        pb.RegisterNodeRequest(
          nodeCertificate: await h.nodeCert(owner, freshNode),
          capacityBytes: Int64(1 << 40),
          endpoints: ['203.0.113.10:7000', '[2001:db8::1]:7000'],
          versions: [1],
          software: 'node 0.2.0',
        ),
        freshNode,
      ),
      'Heartbeat': (
        pb.HeartbeatRequest(
          usedBytes: Int64(10),
          capacityBytes: Int64(1 << 40),
          endpoints: ['203.0.113.10:7000'],
        ),
        node,
      ),
      'ListRevocations': (
        pb.ListRevocationsRequest(afterSequence: Int64.ZERO, limit: 5),
        node,
      ),
    });
  });
  tearDownAll(() => h.close());

  Future<Response> send(
    String method,
    List<int> body,
    Ed25519KeyPair? key,
  ) async {
    final path = '/api/v1/$method';
    h.clock.advance(const Duration(milliseconds: 1));
    final auth = key == null
        ? null
        : (await RequestAuth.sign(
            h.crypto,
            key,
            path: path,
            body: body,
            timeMs: h.clock.now.millisecondsSinceEpoch,
          )).toHeader();
    return await h.handler.call(
      Request(
        'POST',
        Uri.parse('http://coordinator.test$path'),
        body: body,
        headers: {
          'content-type': 'application/x-protobuf',
          'x-forwarded-for': '192.0.2.1',
          'FS-Auth': ?auth,
        },
      ),
    );
  }

  test('тела запросов всех методов', () async {
    expect(samples.keys.toSet(), {
      for (final m in coordinatorMethods(
        const UnimplementedCoordinatorService(),
      ))
        m.name,
    }, reason: 'образец есть у каждого метода coordinator.proto');
    final r = Random(_seed);
    final statuses = <int, int>{};
    for (final MapEntry(key: method, value: (sample, key)) in samples.entries) {
      for (var run = 0; run < _runs; run++) {
        final body = run.isEven
            ? mutate(r, sample.writeToBuffer())
            : boundary(r, sample).writeToBuffer();
        final response = await send(method, body, key);
        final bytes = await bodyOf(response);
        statuses.update(response.statusCode, (n) => n + 1, ifAbsent: () => 1);
        if (response.statusCode == 500) {
          final error = pb.Error.fromBuffer(bytes);
          fail(
            '$method, seed $_seed, прогон $run: INTERNAL '
            '(${error.message}); тело ${_hex(body)}',
          );
        }
      }
    }
    final health = await h.handler.call(
      Request('GET', Uri.parse('http://coordinator.test/health')),
    );
    expect(health.statusCode, 200);
    stdout.writeln('статусы ответов: $statuses');
  }, timeout: Timeout.none);

  test('заголовок FS-Auth', () async {
    final r = Random(_seed + 1);
    final (sample, key) = samples['ListDevices']!;
    final body = sample.writeToBuffer();
    const path = '/api/v1/ListDevices';
    final good = (await RequestAuth.sign(
      h.crypto,
      key!,
      path: path,
      body: body,
      timeMs: h.clock.now.millisecondsSinceEpoch,
    )).toHeader();
    for (var run = 0; run < _runs * 10; run++) {
      final bytes = mutate(r, Uint8List.fromList(good.codeUnits));
      // Заголовок HTTP — только печатные символы ASCII.
      final header = String.fromCharCodes([
        for (final b in bytes) 0x20 + b % 0x5F,
      ]);
      final response = await h.handler.call(
        Request(
          'POST',
          Uri.parse('http://coordinator.test$path'),
          body: body,
          headers: {
            'content-type': 'application/x-protobuf',
            'x-forwarded-for': '192.0.2.2',
            'FS-Auth': header,
          },
        ),
      );
      await bodyOf(response);
      expect(
        response.statusCode,
        anyOf(200, 401, 403, 429),
        reason: 'seed $_seed, прогон $run: «$header»',
      );
    }
  }, timeout: Timeout.none);
}
