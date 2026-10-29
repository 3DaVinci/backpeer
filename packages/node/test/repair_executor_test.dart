// Исполнитель ремонта (задача 4.3.4; protocol.md, раздел 4.14): проверка
// команды и приём задания. Сквозной ремонт по сети —
// coordinator/test/repair_network_test.dart.

import 'dart:async';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:fixnum/fixnum.dart';
import 'package:node/node.dart';
import 'package:protocol/protocol.dart' as pb;
import 'package:test/test.dart';

/// Транспорт, который не подключается, пока не закрыт.
final class _Hanging implements Transport {
  final _closed = Completer<void>();

  @override
  Future<PeerConnection> connect(NodeContact node) async {
    await _closed.future;
    throw PeerUnreachableException(node.nodeId, const []);
  }

  @override
  Future<void> close() async {
    if (!_closed.isCompleted) _closed.complete();
  }
}

void main() {
  late CryptoProvider crypto;
  late Ed25519KeyPair coordinator;
  final self = Uint8List(32)..[0] = 0xEE;
  setUpAll(() async {
    crypto = await SodiumCryptoProvider.load();
    coordinator = await crypto.ed25519FromSeed(
      SecretBytes(Uint8List(32)..[0] = 1),
    );
  });

  var ticketNo = 0;
  Future<pb.Placement> placement(
    int index,
    pb.TicketOperation op, {
    List<int>? device,
    int size = 1000,
    List<int>? nodeInTicket,
  }) async {
    final node = Uint8List(32)
      ..[0] = 0x10
      ..[1] = index;
    return pb.Placement(
      index: index,
      node: pb.NodeAddress(nodeId: node, endpoints: ['127.0.0.1:1']),
      ticket: await SignedMessages.sign(
        crypto,
        coordinator,
        FragmentTickets.signingContext,
        pb.FragmentTicket(
          operation: op,
          nodeId: nodeInTicket ?? node,
          deviceSign: device ?? self,
          fragmentId: Uint8List(32)..[0] = index,
          fragmentSize: size,
          expiresAtUnixMs: Int64(
            DateTime.now()
                .add(const Duration(minutes: 30))
                .millisecondsSinceEpoch,
          ),
          ticketId: Uint8List(16)..[0] = ++ticketNo,
          ownerAccount: op == pb.TicketOperation.TICKET_OPERATION_PUT
              ? (Uint8List(32)..[0] = 0xAA)
              : null,
        ),
      ),
    );
  }

  Future<pb.RepairCommand> command({int k = 2, int n = 4}) async =>
      pb.RepairCommand(
        jobId: Uint8List(16)..[0] = 7,
        k: k,
        n: n,
        fragmentSize: 1000,
        sources: [
          await placement(0, pb.TicketOperation.TICKET_OPERATION_GET),
          await placement(1, pb.TicketOperation.TICKET_OPERATION_GET),
        ],
        targets: [await placement(3, pb.TicketOperation.TICKET_OPERATION_PUT)],
        deadlineUnixMs: Int64(
          DateTime.now()
              .add(const Duration(minutes: 30))
              .millisecondsSinceEpoch,
        ),
      );

  Matcher fails(pb.ErrorCode code, [String detail = '']) => throwsA(
    isA<CoordinatorException>()
        .having((e) => e.code, 'code', code)
        .having((e) => e.detail, 'detail', contains(detail)),
  );

  test('неверные команды — BAD_REQUEST, задание не начинается', () async {
    final reports = <pb.ReportRepairRequest>[];
    final executor = RepairExecutor(
      crypto: crypto,
      nodeId: self,
      transport: _Hanging.new,
      report: (r) async => reports.add(r),
      gate: TransferGate(),
    );
    final good = await command();
    final cases = <String, pb.RepairCommand>{
      'job_id': good.deepCopy()..jobId = Uint8List(15),
      'k < n': good.deepCopy()..k = 4,
      'fragment_size': good.deepCopy()..fragmentSize = 96,
      'источников меньше k': good.deepCopy()..sources.removeLast(),
      'нет новых': good.deepCopy()..targets.clear(),
      'повторяется': good.deepCopy()
        ..targets.add(
          await placement(1, pb.TicketOperation.TICKET_OPERATION_PUT),
        ),
      '≥ n': good.deepCopy()
        ..targets.add(
          await placement(4, pb.TicketOperation.TICKET_OPERATION_PUT),
        ),
      'операция': good.deepCopy()
        ..targets[0] = await placement(
          3,
          pb.TicketOperation.TICKET_OPERATION_GET,
        ),
      'не на этот узел': good.deepCopy()
        ..sources[0] = await placement(
          0,
          pb.TicketOperation.TICKET_OPERATION_GET,
          device: Uint8List(32),
        ),
      'node_id талона': good.deepCopy()
        ..sources[0] = await placement(
          0,
          pb.TicketOperation.TICKET_OPERATION_GET,
          nodeInTicket: Uint8List(32),
        ),
      'fragment_size талона': good.deepCopy()
        ..targets[0] = await placement(
          3,
          pb.TicketOperation.TICKET_OPERATION_PUT,
          size: 2000,
        ),
    };
    for (final MapEntry(:key, :value) in cases.entries) {
      expect(
        () => executor.accept(value),
        fails(pb.ErrorCode.ERROR_CODE_BAD_REQUEST, key),
        reason: key,
      );
    }
    expect(executor.busy, isFalse);
    expect(executor.stats.jobsRejected, cases.length);
  });

  test('занят, на паузе, останавливается — UNAVAILABLE; задание держит '
      'передачу и отчитывается', () async {
    final gate = TransferGate();
    final reports = <pb.ReportRepairRequest>[];
    final transports = <_Hanging>[];
    final executor = RepairExecutor(
      crypto: crypto,
      nodeId: self,
      transport: () => _Hanging()..let(transports.add),
      report: (r) async => reports.add(r),
      gate: gate,
    );
    final c = await command();
    gate.paused = true;
    expect(
      () => executor.accept(c),
      fails(pb.ErrorCode.ERROR_CODE_UNAVAILABLE, 'пауз'),
    );
    gate.paused = false;
    executor.accept(c);
    expect(executor.busy, isTrue);
    expect(gate.active, 1);
    expect(
      () => executor.accept(c),
      fails(pb.ErrorCode.ERROR_CODE_UNAVAILABLE, 'другое задание'),
    );
    // Источники недоступны: отчёт с ошибкой, без загруженных номеров.
    await Future<void>.delayed(Duration.zero);
    for (final t in transports) {
      await t.close();
    }
    await executor.idle;
    expect(gate.active, 0);
    final report = reports.single;
    expect(report.jobId, c.jobId);
    expect(report.storedIndexes, isEmpty);
    expect(report.error, contains('из нужных 2'));
    expect(executor.stats.jobsFailed, 1);
    executor.close();
    expect(
      () => executor.accept(c),
      fails(pb.ErrorCode.ERROR_CODE_UNAVAILABLE),
    );
  });
}

extension<T> on T {
  void let(void Function(T) f) => f(this);
}
