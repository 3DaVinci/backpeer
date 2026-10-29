import 'dart:async';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:daemon_kit/daemon_kit.dart';
import 'package:fixnum/fixnum.dart';
import 'package:logging/logging.dart';
import 'package:node/src/daemon/transfers.dart';
import 'package:node/src/repair/repair_executor.dart';
import 'package:node/src/storage/fragment_index.dart';
import 'package:node/src/storage/fragment_storage.dart';
import 'package:protocol/protocol.dart' as pb;

/// Перенос своих фрагментов на другие узлы (задачи 4.4.1, 4.4.2;
/// protocol.md, раздел 4.15): узел уходит из сети или хранит больше, чем
/// готов, и координатор поручает ему отдать фрагмент новому узлу.
///
/// [accept] проверяет команду `relocate` — талон PUT на новый узел от
/// имени этого узла с `owner_account`, фрагмент есть здесь, сохранён, его
/// размер и владелец совпадают с талоном — и начинает перенос в фоне:
/// прочитать фрагмент, загрузить его по Noise (как исполнитель ремонта,
/// через [transport]) и отчитаться `ReportRepair` до срока задания.
/// Фрагмент остаётся здесь: удалит его сверка, когда координатор засчитает
/// новый ([FragmentStorage], задача 4.4.3). Одновременно — не больше
/// [maxConcurrent] переносов; каждый держит [Transfer] у [gate].
final class Relocator {
  new({
    required this.crypto,
    required this.nodeId,
    required this.storage,
    required this.transport,
    required this.report,
    required this.gate,
    RepairStats? stats,
    this.uploadLimiter,
    this.maxConcurrent = 8,
    this.reportRetry = const Duration(seconds: 5),
    DateTime Function()? clock,
  }) : stats = stats ?? RepairStats(),
       _clock = clock ?? DateTime.now;

  final CryptoProvider crypto;

  /// `node_id` этого узла: им связан талон.
  final Uint8List nodeId;
  final FragmentStorage storage;

  /// Новый транспорт на перенос; закрывается вместе с ним.
  final Transport Function() transport;

  /// Отправка `ReportRepair`; ошибка — повтор через [reportRetry].
  final Future<void> Function(pb.ReportRepairRequest request) report;
  final TransferGate gate;
  final RepairStats stats;
  final BandwidthLimiter? uploadLimiter;
  final int maxConcurrent;
  final Duration reportRetry;
  final DateTime Function() _clock;

  static final _log = Logger('relocate');

  final _running = <Future<void>>{};
  bool _closed = false;

  /// Переносов сейчас.
  int get active => _running.length;

  /// Завершается, когда текущие переносы закончены.
  Future<void> get idle => Future.wait(_running.toList());

  /// Принимает перенос. Неверная команда — `BAD_REQUEST`; фрагмента нет —
  /// `NOT_FOUND`; переносов слишком много, узел на паузе или
  /// останавливается — `UNAVAILABLE` ([CoordinatorException]).
  void accept(pb.RelocateCommand command) {
    final (Uint8List fragmentId, int size) checked;
    try {
      checked = _check(command);
    } on CoordinatorException {
      stats.relocationsRejected++;
      rethrow;
    }
    if (_running.length >= maxConcurrent || _closed) {
      stats.relocationsRejected++;
      throw const CoordinatorException(
        pb.ErrorCode.ERROR_CODE_UNAVAILABLE,
        'узел выполняет другие переносы',
      );
    }
    final transfer = gate.tryBegin();
    if (transfer == null) {
      stats.relocationsRejected++;
      throw CoordinatorException(
        pb.ErrorCode.ERROR_CODE_UNAVAILABLE,
        gate.closed ? 'узел останавливается' : 'узел на паузе',
      );
    }
    stats.relocationsAccepted++;
    final (fragmentId, size) = checked;
    late final Future<void> run;
    run = _run(command, fragmentId, size)
        .catchError((Object e, StackTrace st) {
          _log.severe(
            LogEvent('relocation_crashed', {'job': bytesToHex(command.jobId)}),
            e,
            st,
          );
        })
        .whenComplete(() {
          transfer.end();
          _running.remove(run);
        });
    _running.add(run);
  }

  /// Не начинает новых переносов.
  void close() => _closed = true;

  /// Проверка команды (protocol.md, раздел 4.15); возвращает
  /// `fragment_id` и размер из талона.
  (Uint8List, int) _check(pb.RelocateCommand c) {
    Never bad(String message) => throw CoordinatorException(
      pb.ErrorCode.ERROR_CODE_BAD_REQUEST,
      'перенос: $message',
    );
    if (c.jobId.length != 16) bad('job_id — 16 байт');
    final p = c.target;
    final pb.FragmentTicket t;
    try {
      t = FragmentTickets.parse(Uint8List.fromList(p.ticket.body));
    } on DataFormatException catch (e) {
      bad('талон: ${e.detail}');
    }
    if (t.operation != pb.TicketOperation.TICKET_OPERATION_PUT) {
      bad('операция талона');
    }
    if (!constantTimeEquals(t.nodeId, p.node.nodeId)) bad('node_id талона');
    if (constantTimeEquals(t.nodeId, nodeId)) bad('новый узел — этот же');
    if (!constantTimeEquals(t.deviceSign, nodeId)) {
      bad('талон не на этот узел');
    }
    if (t.ownerAccount.isEmpty) bad('в талоне нет owner_account');
    final record = storage.record(t.fragmentId);
    if (record == null || record.state != FragmentState.stored) {
      throw const CoordinatorException(
        pb.ErrorCode.ERROR_CODE_NOT_FOUND,
        'перенос: фрагмента нет на узле',
      );
    }
    if (record.size != t.fragmentSize) bad('fragment_size талона');
    if (!constantTimeEquals(record.accountId, t.ownerAccount)) {
      bad('владелец фрагмента не тот, что в талоне');
    }
    return (Uint8List.fromList(t.fragmentId), record.size);
  }

  Future<void> _run(
    pb.RelocateCommand c,
    Uint8List fragmentId,
    int size,
  ) async {
    final job = bytesToHex(c.jobId);
    final target = c.target;
    final store = NetworkFragmentStore(
      crypto: crypto,
      transport: transport(),
      access: TicketBook()..addPlacements([target]),
      failureBackoff: Duration.zero,
      uploadLimiter: uploadLimiter,
    );
    String? failure;
    var uploaded = 0;
    try {
      final bytes = BytesBuilder(copy: false);
      await storage.openRead(fragmentId).forEach(bytes.add);
      final data = bytes.takeBytes();
      if (data.length != size) throw StateError('прочитано ${data.length}');
      await store.put(
        bytesToHex(target.node.nodeId),
        data,
        expectedFragmentId: fragmentId,
      );
      uploaded = data.length;
    } on CoreException catch (e) {
      failure = e.message;
    } on Object catch (e, st) {
      _log.severe(LogEvent('relocation_failed', {'job': job}), e, st);
      failure = 'сбой исполнителя: $e';
    } finally {
      await store.close();
    }
    stats.bytesRelocated += uploaded;
    if (failure == null) {
      stats.relocationsDone++;
    } else {
      stats.relocationsFailed++;
    }
    _log.info(
      LogEvent('relocation_done', {
        'job': job,
        'index': target.index,
        'uploaded': uploaded,
        'failure': ?failure,
      }),
    );
    await sendRepairReport(
      report,
      pb.ReportRepairRequest(
        jobId: c.jobId,
        storedIndexes: [if (failure == null) target.index],
        failures: [
          if (failure != null)
            pb.RepairFailure(
              index: target.index,
              reason: failure.length <= RepairExecutor.maxReasonLength
                  ? failure
                  : failure.substring(0, RepairExecutor.maxReasonLength),
            ),
        ],
        bytesUploaded: Int64(uploaded),
      ),
      deadline: DateTime.fromMillisecondsSinceEpoch(c.deadlineUnixMs.toInt()),
      retry: reportRetry,
      clock: _clock,
    );
  }
}
