// Сверка фрагментов узла с координатором и карантин (задача 4.4.3;
// protocol.md, раздел 4.15), ёмкость для heartbeat при нехватке места на
// диске (4.4.2), проверки команды переноса (4.4.1). Сквозной выход узла —
// coordinator/test/relocation_network_test.dart.

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:fixnum/fixnum.dart';
import 'package:node/node.dart';
import 'package:protocol/protocol.dart' as pb;
import 'package:test/test.dart';

import 'support.dart';

/// Транспорт, с которым ни один узел не доступен.
final class _Unreachable implements Transport {
  @override
  Future<PeerConnection> connect(NodeContact node) async =>
      throw PeerUnreachableException(node.nodeId, const []);

  @override
  Future<void> close() async {}
}

void main() {
  late CryptoProvider crypto;
  late Directory dir;
  final open = <FragmentStorage>[];
  setUpAll(() async => crypto = await SodiumCryptoProvider.load());
  setUp(() => dir = Directory.systemTemp.createTempSync('fs-node-reconcile-'));
  tearDown(() async {
    for (final s in open) {
      await s.close();
    }
    open.clear();
    dir.deleteSync(recursive: true);
  });

  final account = Uint8List(32)..[0] = 1;

  FragmentStorage storage({
    int quota = 1 << 40,
    int reserve = 0,
    int? Function(String)? disk,
  }) {
    final s = FragmentStorage.open(
      dir.path,
      crypto: crypto,
      quotaBytes: quota,
      freeReserveBytes: reserve,
      diskAvailable: disk ?? (_) => null,
    );
    open.add(s);
    return s;
  }

  Future<Uint8List> put(FragmentStorage s, Fragment f) async {
    final id = fragmentIdOf(crypto, f);
    final bytes = f.bytes;
    final incoming = await s.beginPut(
      fragmentId: id,
      size: bytes.length,
      accountId: account,
    );
    for (var offset = 0; offset < bytes.length; offset += 61440) {
      await incoming.add(
        Uint8List.sublistView(bytes, offset, min(offset + 61440, bytes.length)),
      );
    }
    await incoming.commit();
    return id;
  }

  group('сверка (4.4.3)', () {
    test('неучтённый фрагмент удаляется только после карантина; признанный '
        'снова — остаётся', () async {
      final s = storage();
      final ids = [
        for (var i = 1; i <= 3; i++)
          await put(s, testFragment(crypto, seed: i, blobLength: 4000)),
      ];
      var now = DateTime.utc(2026, 10, 28, 12);
      final unknown = <String>{bytesToHex(ids[0]), bytesToHex(ids[1])};
      final calls = <(int, bool)>[];
      final r = FragmentReconciler(
        storage: s,
        batch: 2,
        clock: () => now,
        query: (batch, {required first}) async {
          calls.add((batch.length, first));
          return [
            for (final id in batch)
              if (unknown.contains(bytesToHex(id))) id,
            // Чужой идентификатор в ответе не учитывается.
            Uint8List(32)..[0] = 0xFF,
          ];
        },
      );
      expect(r.due, isTrue, reason: 'сверки ещё не было');
      expect(await r.run(), 0);
      expect(calls, [(2, true), (1, false)], reason: 'пачки по 2');
      expect(s.index.orphans().count, 2);
      expect(r.due, isFalse);

      // Координатор снова признал один из двух.
      unknown.remove(bytesToHex(ids[1]));
      now = now.add(const Duration(hours: 23));
      r.request();
      expect(await r.run(), 0, reason: 'карантин не истёк');
      expect(s.index.orphans().count, 1);

      now = now.add(const Duration(hours: 1));
      expect(r.due, isTrue, reason: 'истёк карантин отмеченного');
      expect(await r.run(), 1);
      expect(s.record(ids[0]), isNull);
      expect(s.record(ids[1]), isNotNull);
      expect(s.record(ids[2]), isNotNull);
      expect(s.index.orphans().count, 0);
      expect(r.toJson(), containsPair('deleted', 1));
    });

    test('сбой координатора — проход прерван и будет повторён', () async {
      final s = storage();
      await put(s, testFragment(crypto, blobLength: 4000));
      var fail = true;
      final r = FragmentReconciler(
        storage: s,
        query: (batch, {required first}) async {
          if (fail) {
            throw const CoordinatorException(
              pb.ErrorCode.ERROR_CODE_UNAVAILABLE,
              'нет связи',
            );
          }
          return const [];
        },
      );
      await expectLater(r.run(), throwsA(isA<CoordinatorException>()));
      expect(r.lastPassAt, isNull);
      expect(r.due, isTrue);
      fail = false;
      await r.run();
      expect(r.lastPassAt, isNotNull);
      expect(r.due, isFalse);
    });

    test('deleteAll удаляет все фрагменты', () async {
      final s = storage();
      for (var i = 1; i <= 3; i++) {
        await put(s, testFragment(crypto, seed: i, blobLength: 4000));
      }
      expect(s.deleteAll(), 3);
      expect(s.fragmentCount, 0);
      expect(s.usedBytes, 0);
    });
  });

  test('ёмкость: квота, а при нехватке места на диске — меньше занятого '
      '(4.4.2)', () async {
    var disk = 1 << 30;
    final s = storage(quota: 1 << 20, reserve: 10000, disk: (_) => disk);
    final f = testFragment(crypto, blobLength: 4000);
    await put(s, f);
    final used = s.usedBytes;
    expect(s.capacityBytes, 1 << 20);
    disk = 10000 - 300;
    expect(s.capacityBytes, used - 300);
    disk = 0;
    expect(s.capacityBytes, 0, reason: 'не меньше нуля');
  });

  group('команда переноса (4.4.1)', () {
    late Ed25519KeyPair coordinator;
    final self = Uint8List(32)..[0] = 0xEE;
    final target = Uint8List(32)..[0] = 0x20;
    setUpAll(
      () async => coordinator = await crypto.ed25519FromSeed(
        SecretBytes(Uint8List(32)..[0] = 1),
      ),
    );

    Future<pb.RelocateCommand> command(
      Uint8List fragmentId,
      int size, {
      List<int>? owner,
      List<int>? device,
      List<int>? nodeInTicket,
      pb.TicketOperation op = pb.TicketOperation.TICKET_OPERATION_PUT,
    }) async {
      final expires = DateTime.now().add(const Duration(minutes: 30));
      return pb.RelocateCommand(
        jobId: Uint8List(16)..[0] = 9,
        target: pb.Placement(
          index: 3,
          node: pb.NodeAddress(nodeId: target, endpoints: ['127.0.0.1:1']),
          ticket: await SignedMessages.sign(
            crypto,
            coordinator,
            FragmentTickets.signingContext,
            pb.FragmentTicket(
              operation: op,
              nodeId: nodeInTicket ?? target,
              deviceSign: device ?? self,
              fragmentId: fragmentId,
              fragmentSize: size,
              expiresAtUnixMs: Int64(expires.millisecondsSinceEpoch),
              ticketId: Uint8List(16)..[0] = 1,
              ownerAccount: op == pb.TicketOperation.TICKET_OPERATION_PUT
                  ? owner ?? account
                  : null,
            ),
          ),
        ),
        deadlineUnixMs: Int64(expires.millisecondsSinceEpoch),
      );
    }

    Matcher fails(pb.ErrorCode code, [String detail = '']) => throwsA(
      isA<CoordinatorException>()
          .having((e) => e.code, 'code', code)
          .having((e) => e.detail, 'detail', contains(detail)),
    );

    test('неверная команда — отказ; верная — перенос и отчёт', () async {
      final s = storage();
      final f = testFragment(crypto, blobLength: 4000);
      final id = await put(s, f);
      final size = f.bytes.length;
      final reports = <pb.ReportRepairRequest>[];
      final gate = TransferGate();
      final relocator = Relocator(
        crypto: crypto,
        nodeId: self,
        storage: s,
        // Новый узел недоступен: перенос проваливается, отчёт — с причиной.
        transport: _Unreachable.new,
        report: (r) async => reports.add(r),
        gate: gate,
        reportRetry: Duration.zero,
      );
      final cases = {
        'job_id': (await command(id, size))..jobId = Uint8List(3),
        'операция': await command(
          id,
          size,
          op: pb.TicketOperation.TICKET_OPERATION_GET,
        ),
        'node_id талона': await command(id, size, nodeInTicket: self),
        'не на этот узел': await command(id, size, device: target),
        'fragment_size': await command(id, size + 1),
        'владелец': await command(id, size, owner: Uint8List(32)..[0] = 5),
      };
      for (final MapEntry(:key, :value) in cases.entries) {
        expect(
          () => relocator.accept(value),
          fails(pb.ErrorCode.ERROR_CODE_BAD_REQUEST),
          reason: key,
        );
      }
      expect(
        () async => relocator.accept(await command(Uint8List(32), size)),
        fails(pb.ErrorCode.ERROR_CODE_NOT_FOUND, 'фрагмента нет'),
      );
      gate.paused = true;
      final good = await command(id, size);
      expect(
        () => relocator.accept(good),
        fails(pb.ErrorCode.ERROR_CODE_UNAVAILABLE, 'пауз'),
      );
      gate.paused = false;
      relocator.accept(good);
      expect(relocator.active, 1);
      await relocator.idle;
      final report = reports.single;
      expect(report.jobId, good.jobId);
      expect(report.storedIndexes, isEmpty);
      expect(report.failures.single.index, 3);
      expect(relocator.stats.relocationsFailed, 1);
      expect(s.record(id), isNotNull, reason: 'фрагмент остаётся до сверки');
    });
  });
}
