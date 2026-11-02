import 'dart:async';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:daemon_kit/daemon_kit.dart';
import 'package:fixnum/fixnum.dart';
import 'package:logging/logging.dart';
import 'package:node/src/daemon/transfers.dart';
import 'package:protocol/protocol.dart' as pb;

/// Счётчики ремонта узла с запуска для `cli node stats`; трафик ремонта
/// узел сообщает и координатору (`ReportRepair`) — для бартера, этап 7.
final class RepairStats {
  int jobsAccepted = 0;
  int jobsRejected = 0;
  int jobsCompleted = 0;
  int jobsFailed = 0;
  int fragmentsRebuilt = 0;
  int bytesDownloaded = 0;
  int bytesUploaded = 0;

  /// Перенос своих фрагментов на другие узлы (задачи 4.4.1, 4.4.2).
  int relocationsAccepted = 0;
  int relocationsRejected = 0;
  int relocationsDone = 0;
  int relocationsFailed = 0;
  int bytesRelocated = 0;

  Map<String, Object?> toJson() => {
    'jobsAccepted': jobsAccepted,
    'jobsRejected': jobsRejected,
    'jobsCompleted': jobsCompleted,
    'jobsFailed': jobsFailed,
    'fragmentsRebuilt': fragmentsRebuilt,
    'bytesDownloaded': bytesDownloaded,
    'bytesUploaded': bytesUploaded,
    'relocationsAccepted': relocationsAccepted,
    'relocationsRejected': relocationsRejected,
    'relocationsDone': relocationsDone,
    'relocationsFailed': relocationsFailed,
    'bytesRelocated': bytesRelocated,
  };
}

/// Задание ремонта после проверки команды.
final class _Job {
  new(this.command, this.sources, this.targets);

  final pb.RepairCommand command;

  /// Записи и `fragment_id` из талонов.
  final List<(pb.Placement, Uint8List)> sources;
  final List<(pb.Placement, Uint8List)> targets;

  String get id => bytesToHex(command.jobId);
}

/// Исполнитель ремонта (задача 4.3.4; protocol.md, раздел 4.14).
///
/// [accept] проверяет команду `repair` и, если узел свободен и не на
/// паузе, начинает задание в фоне; ответ координатору — сразу. Задание:
/// скачать фрагменты источников по талонам GET (не больше k
/// одновременно, при неудаче — следующий источник), проверить каждый
/// (корень дерева тела, `fragment_id` из талона, номер, параметры
/// сегмента), набрав k — пересоздать недостающие (`rebuildFragments`),
/// сверить их `fragment_id` с талонами PUT и разослать новым узлам; итог —
/// `ReportRepair` через [report], с повтором до срока задания. Фрагменты
/// держатся только в памяти.
///
/// Соединения с узлами — через [transport] (`ConnectionStrategy` со
/// своим сертификатом узла: TCP, UDP после сведения, relay), операции —
/// `NetworkFragmentStore` с талонами задания. Одно задание за раз:
/// второе — `UNAVAILABLE`. Задание держит [Transfer] у [gate]: остановка
/// узла ждёт его, как обычные передачи.
final class RepairExecutor {
  new({
    required this.crypto,
    required this.nodeId,
    required this.transport,
    required this.report,
    required this.gate,
    RepairStats? stats,
    this.uploadLimiter,
    this.downloadLimiter,
    this.reportRetry = const Duration(seconds: 5),
    DateTime Function()? clock,
  }) : stats = stats ?? RepairStats(),
       _clock = clock ?? DateTime.now;

  final CryptoProvider crypto;

  /// `node_id` этого узла: им связаны талоны задания.
  final Uint8List nodeId;

  /// Новый транспорт на задание; закрывается вместе с заданием.
  final Transport Function() transport;

  /// Отправка `ReportRepair`; ошибка — повтор через [reportRetry].
  final Future<void> Function(pb.ReportRepairRequest request) report;
  final TransferGate gate;
  final RepairStats stats;
  final BandwidthLimiter? uploadLimiter;
  final BandwidthLimiter? downloadLimiter;
  final Duration reportRetry;
  final DateTime Function() _clock;

  static final _log = Logger('repair');

  /// Наибольшая длина причины в отчёте (protocol.md, раздел 4.14).
  static const maxReasonLength = 200;

  Future<void>? _running;
  bool _closed = false;

  /// Выполняется задание.
  bool get busy => _running != null;

  /// Завершается, когда текущее задание (если есть) закончено.
  Future<void> get idle => _running ?? Future.value();

  Map<String, Object?> toJson() => {'busy': busy, ...stats.toJson()};

  /// Принимает задание. Неверная команда — `BAD_REQUEST`; узел занят, на
  /// паузе или останавливается — `UNAVAILABLE` ([CoordinatorException]).
  void accept(pb.RepairCommand command) {
    final _Job job;
    try {
      job = _check(command);
    } on CoordinatorException {
      stats.jobsRejected++;
      rethrow;
    }
    if (_running != null || _closed) {
      stats.jobsRejected++;
      throw const CoordinatorException(
        pb.ErrorCode.ERROR_CODE_UNAVAILABLE,
        'узел выполняет другое задание ремонта',
      );
    }
    final transfer = gate.tryBegin();
    if (transfer == null) {
      stats.jobsRejected++;
      throw CoordinatorException(
        pb.ErrorCode.ERROR_CODE_UNAVAILABLE,
        gate.closed ? 'узел останавливается' : 'узел на паузе',
      );
    }
    stats.jobsAccepted++;
    _log.info(
      LogEvent('repair_accepted', {
        'job': job.id,
        'sources': job.sources.length,
        'targets': job.targets.length,
      }),
    );
    _running = _run(job)
        .catchError((Object e, StackTrace st) {
          _log.severe(LogEvent('repair_crashed', {'job': job.id}), e, st);
        })
        .whenComplete(() {
          transfer.end();
          _running = null;
        });
  }

  /// Не начинает новых заданий. Текущее задание держит [Transfer]: его
  /// ждёт остановка узла ([TransferGate.close]); после неё оно доходит в
  /// фоне до ошибки соединений или отчёта.
  void close() => _closed = true;

  /// Проверка команды (protocol.md, раздел 4.14, шаг 1).
  _Job _check(pb.RepairCommand c) {
    Never bad(String message) => throw CoordinatorException(
      pb.ErrorCode.ERROR_CODE_BAD_REQUEST,
      'задание ремонта: $message',
    );
    if (c.jobId.length != 16) bad('job_id — 16 байт');
    final k = c.k;
    final n = c.n;
    if (k < 1 || k >= n || n > 255) bad('нужно 1 ≤ k < n ≤ 255');
    final size = c.fragmentSize;
    if (size < FragmentTickets.minFragmentSize ||
        size > FragmentTickets.maxFragmentSize) {
      bad('fragment_size вне пределов');
    }
    if (c.sources.length < k) bad('источников меньше k');
    if (c.targets.isEmpty) bad('нет новых фрагментов');
    final seen = <int>{};
    List<(pb.Placement, Uint8List)> entries(
      List<pb.Placement> list,
      pb.TicketOperation operation,
      String name,
    ) => [
      for (final p in list)
        () {
          if (p.index >= n) bad('$name: номер ${p.index} ≥ n');
          if (!seen.add(p.index)) bad('$name: номер ${p.index} повторяется');
          final pb.FragmentTicket t;
          try {
            t = FragmentTickets.parse(Uint8List.fromList(p.ticket.body));
          } on DataFormatException catch (e) {
            bad('$name: талон: ${e.detail}');
          }
          if (t.operation != operation) bad('$name: операция талона');
          if (!constantTimeEquals(t.nodeId, p.node.nodeId)) {
            bad('$name: node_id талона');
          }
          if (!constantTimeEquals(t.deviceSign, nodeId)) {
            bad('$name: талон не на этот узел');
          }
          if (t.fragmentSize != size) bad('$name: fragment_size талона');
          return (p, Uint8List.fromList(t.fragmentId));
        }(),
    ];
    return _Job(
      c,
      entries(c.sources, pb.TicketOperation.TICKET_OPERATION_GET, 'источник'),
      entries(c.targets, pb.TicketOperation.TICKET_OPERATION_PUT, 'новый'),
    );
  }

  Future<void> _run(_Job job) async {
    final c = job.command;
    final book = TicketBook()
      ..addPlacements(c.sources)
      ..addPlacements(c.targets);
    final store = NetworkFragmentStore(
      crypto: crypto,
      transport: transport(),
      access: book,
      failureBackoff: Duration.zero,
      uploadLimiter: uploadLimiter,
      downloadLimiter: downloadLimiter,
    );
    var downloaded = 0;
    var uploaded = 0;
    final stored = <int>[];
    final failures = <pb.RepairFailure>[];
    String? error;
    try {
      final (fragments, problems) = await _gather(job, store, (bytes) {
        downloaded += bytes;
      });
      if (fragments.length < c.k) {
        error = _clip(
          'источников проверено ${fragments.length} из нужных ${c.k}'
          '${problems.isEmpty ? '' : ': ${problems.join('; ')}'}',
        );
      } else {
        final rebuilt = rebuildFragments(crypto, fragments, [
          for (final (p, _) in job.targets) p.index,
        ], verified: true);
        stats.fragmentsRebuilt += rebuilt.length;
        await Future.wait([
          for (var i = 0; i < job.targets.length; i++)
            () async {
              final (p, fragmentId) = job.targets[i];
              final fragment = rebuilt[i];
              if (!constantTimeEquals(
                fragment.header.fragmentId(crypto),
                fragmentId,
              )) {
                failures.add(_failure(p.index, 'fragment_id'));
                return;
              }
              try {
                final bytes = fragment.toBytes();
                await store.put(
                  bytesToHex(p.node.nodeId),
                  bytes,
                  expectedFragmentId: fragmentId,
                );
                uploaded += bytes.length;
                stored.add(p.index);
              } on CoreException catch (e) {
                failures.add(_failure(p.index, e.message));
              }
            }(),
        ]);
      }
    } on Object catch (e, st) {
      _log.severe(LogEvent('repair_failed', {'job': job.id}), e, st);
      error = _clip('сбой исполнителя: $e');
    } finally {
      await store.close();
    }
    stored.sort();
    stats
      ..bytesDownloaded += downloaded
      ..bytesUploaded += uploaded;
    if (error == null && failures.isEmpty) {
      stats.jobsCompleted++;
    } else {
      stats.jobsFailed++;
    }
    _log.info(
      LogEvent('repair_done', {
        'job': job.id,
        'stored': stored.length,
        'failed': failures.length,
        'error': ?error,
        'downloaded': downloaded,
        'uploaded': uploaded,
      }),
    );
    await _report(
      job,
      pb.ReportRepairRequest(
        jobId: c.jobId,
        storedIndexes: stored,
        failures: failures,
        error: error,
        bytesDownloaded: Int64(downloaded),
        bytesUploaded: Int64(uploaded),
      ),
    );
  }

  /// Скачивает и проверяет фрагменты источников, пока не наберётся k:
  /// не больше k запросов одновременно, неудачный источник заменяется
  /// следующим. Возвращает проверенные фрагменты и причины отказов.
  Future<(List<Fragment>, List<String>)> _gather(
    _Job job,
    NetworkFragmentStore store,
    void Function(int bytes) counted,
  ) async {
    final c = job.command;
    final queue = [...job.sources];
    final failed = <(pb.Placement, Uint8List)>[];
    final got = <Fragment>[];
    final problems = <String>[];
    Future<void> worker() async {
      while (got.length < c.k && queue.isNotEmpty) {
        final (p, fragmentId) = queue.removeAt(0);
        try {
          final bytes = await store.get(bytesToHex(p.node.nodeId), fragmentId);
          counted(bytes.length);
          final f = Fragment.parse(bytes);
          final h = f.header;
          if (h.index != p.index ||
              h.k != c.k ||
              h.n != c.n ||
              bytes.length != c.fragmentSize ||
              (got.isNotEmpty && !h.sameSegment(got.first.header))) {
            throw const IntegrityException(
              object: 'fragment',
              check: IntegrityCheck.objectId,
            );
          }
          f.verify(crypto, expectedFragmentId: fragmentId);
          if (got.length < c.k) got.add(f);
        } on CoreException catch (e) {
          problems.add('${p.index}: ${e.message}');
          failed.add((p, fragmentId));
        }
      }
    }

    await Future.wait([for (var i = 0; i < c.k; i++) worker()]);
    // Узел мог быть просто без сети в этот момент (уход узла, обрыв):
    // повторяем неудачные источники, пока не наберётся k. Источников
    // обычно больше k, но при уходе узлов их может остаться меньше, и
    // задание без повтора проваливается на ровном месте.
    for (
      var attempt = 0;
      attempt < sourceRetries && got.length < c.k;
      attempt++
    ) {
      if (failed.isEmpty) break;
      await Future<void>.delayed(sourceRetryDelay);
      queue.addAll(failed);
      failed.clear();
      await Future.wait([for (var i = 0; i < c.k; i++) worker()]);
    }
    return (got, problems.toSet().toList());
  }

  /// Сколько раз повторять неудачные источники, прежде чем провалить
  /// задание: узел без сети на секунды не должен срывать ремонт.
  static const int sourceRetries = 2;

  /// Пауза перед повтором источников.
  static const Duration sourceRetryDelay = Duration(seconds: 2);

  /// Отчёт с повтором до срока задания.
  Future<void> _report(_Job job, pb.ReportRepairRequest request) =>
      sendRepairReport(
        report,
        request,
        deadline: DateTime.fromMillisecondsSinceEpoch(
          job.command.deadlineUnixMs.toInt(),
        ),
        retry: reportRetry,
        clock: _clock,
      );

  static pb.RepairFailure _failure(int index, String reason) =>
      pb.RepairFailure(index: index, reason: _clip(reason));

  static String _clip(String s) =>
      s.length <= maxReasonLength ? s : s.substring(0, maxReasonLength);
}

/// Отправляет `ReportRepair` через [report] с повтором через [retry] до
/// [deadline]: ремонт и перенос (protocol.md, разделы 4.14, 4.15). Отказ
/// координатора по существу (задание неизвестно, поля) не повторяется.
Future<void> sendRepairReport(
  Future<void> Function(pb.ReportRepairRequest request) report,
  pb.ReportRepairRequest request, {
  required DateTime deadline,
  required Duration retry,
  required DateTime Function() clock,
}) async {
  final job = bytesToHex(request.jobId);
  while (true) {
    try {
      await report(request);
      return;
    } on Object catch (e) {
      if (e is CoordinatorException &&
          e.code != pb.ErrorCode.ERROR_CODE_UNAVAILABLE &&
          e.code != pb.ErrorCode.ERROR_CODE_INTERNAL &&
          e.code != pb.ErrorCode.ERROR_CODE_RATE_LIMITED) {
        RepairExecutor._log.warning(
          LogEvent('repair_report_rejected', {
            'job': job,
            'code': errorCodeName(e.code),
          }),
        );
        return;
      }
      if (clock().add(retry).isAfter(deadline)) {
        RepairExecutor._log.warning(
          LogEvent('repair_report_lost', {'job': job}),
        );
        return;
      }
      await Future<void>.delayed(retry);
    }
  }
}
