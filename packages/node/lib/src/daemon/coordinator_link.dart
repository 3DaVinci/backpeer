import 'dart:async';
import 'dart:math' as math;

import 'package:core/core.dart';
import 'package:fixnum/fixnum.dart';
import 'package:logging/logging.dart';
import 'package:node/src/daemon/command_channel.dart';
import 'package:node/src/daemon/identity.dart';
import 'package:node/src/daemon/log.dart';
import 'package:node/src/net/reachability.dart';
import 'package:node/src/peers/revocations.dart';
import 'package:node/src/storage/fragment_storage.dart';
import 'package:protocol/protocol.dart' as pb;

/// Регистрация узла у координатора и heartbeat (`protocol.md`,
/// раздел 4.9). Работает до [stop]: сбои связи и ошибки координатора не
/// останавливают узел, а повторяются с растущей паузой до [maxBackoff].
///
/// - Сначала `RegisterNode` (сертификат, ёмкость, адреса, версии); ответ
///   несёт ключи координатора — узел сверяет их со своим списком и
///   предупреждает о расхождении, но доверяет только списку.
/// - Затем `Heartbeat` с интервалом из ответа координатора.
/// - `UNAUTHENTICATED` на heartbeat (координатор не знает узел, например
///   после очистки базы стенда) — повторная регистрация.
/// - После регистрации и каждого heartbeat — отчёт о повреждённых
///   фрагментах ([damaged], `ReportDamagedFragments`), если они есть;
///   [reportDamaged] отправляет его сразу.
/// - Там же — новые отзывы устройств ([revocations], `ListRevocations`).
/// - Там же, когда пора, — проверка достижимости ([reachability],
///   `CheckReachability`); изменились адреса узла — heartbeat с ними
///   сразу. [recheckReachability] проверяет вне очереди (получен или снят
///   проброс порта).
/// - С `commandChannel` после регистрации открывается канал команд
///   ([CommandChannel], задача 3.6.1): heartbeat идёт по нему, а по HTTP —
///   только пока канала нет; открылся канал — heartbeat сразу. Команда
///   `SyncRevocations` дочитывает отзывы со случайной задержкой до
///   [revocationJitter], чтобы узлы не пришли к координатору разом.
final class CoordinatorLink {
  new({
    required this.client,
    required this.identity,
    required this.capacityBytes,
    required this.usedBytes,
    required this.trustedKeys,
    this.freeBytes,
    this.damaged,
    this.revocations,
    this.endpoints = const [],
    this.reachability,
    this.rendezvous,
    this.audit,
    this.repair,
    this.maxBackoff = const Duration(minutes: 5),
    this._interval = defaultInterval,
    bool commandChannel = false,
    this.revocationJitter = const Duration(seconds: 10),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    if (commandChannel) {
      channel = CommandChannel(
        client: client,
        nodeKey: identity.keys.sign,
        onCommand: _onCommand,
        onConnected: _wakeUp,
        maxBackoff: maxBackoff,
      );
    }
  }

  /// Версии протокола между узлами, которые знает узел (раздел 2).
  static const versions = [1];

  /// Пауза до первого heartbeat после регистрации, пока координатор не
  /// назвал свою; сама регистрация засчитывает интервал доступности.
  static const defaultInterval = Duration(minutes: 5);

  final CoordinatorClient client;
  final NodeIdentity identity;
  final int capacityBytes;

  /// Занятое место сейчас.
  final int Function() usedBytes;

  /// Сколько ещё байт узел готов принять (`HeartbeatRequest.free_bytes`);
  /// `null` — не сообщать.
  final int Function()? freeBytes;

  /// Повреждённые фрагменты для отчёта.
  final DamagedFragments? damaged;

  /// Список отозванных устройств, который дополняется от координатора.
  final RevocationList? revocations;
  final CoordinatorKeySet trustedKeys;

  /// Адреса узла, если нет [reachability].
  final List<String> endpoints;

  /// Проверка достижимости и адреса узла (задача 3.5.1).
  final Reachability? reachability;

  /// Выполняет команду сведения узлов (задача 3.7.2); `null` — узел не
  /// принимает UDP, команда отклоняется `NOT_FOUND`.
  final Future<pb.RendezvousReply> Function(pb.RendezvousCommand command)?
  rendezvous;

  /// Отвечает на аудит (задача 4.1.2; protocol.md, раздел 4.13); `null` —
  /// хранилища нет, команда отклоняется `NOT_FOUND`.
  final Future<pb.AuditReply> Function(pb.AuditCommand command)? audit;

  /// Принимает задание ремонта (задача 4.3.4; protocol.md, раздел 4.14) и
  /// выполняет его в фоне; отказ — [CoordinatorException]. `null` — узел
  /// не выполняет ремонт, команда отклоняется `UNAVAILABLE`.
  final void Function(pb.RepairCommand command)? repair;
  final Duration maxBackoff;

  /// Наибольшая случайная задержка `ListRevocations` по команде.
  final Duration revocationJitter;
  final DateTime Function() _clock;

  /// Канал команд; `null` — выключен.
  CommandChannel? channel;

  static final _log = Logger('coordinator');

  bool _registered = false;
  bool _stopped = false;
  Duration _interval;
  DateTime? _lastHeartbeat;
  DateTime? _nextAttempt;
  String? _lastError;
  List<String> _unknownKeys = const [];
  Completer<void>? _wake;
  Future<void>? _loop;
  Future<void>? _reporting;

  bool get registered => _registered;

  /// Состояние для `cli node status`.
  Map<String, Object?> toJson() => {
    'url': client.baseUri.toString(),
    'registered': _registered,
    'lastHeartbeatAt': _lastHeartbeat?.toUtc().toIso8601String(),
    'nextAttemptAt': _nextAttempt?.toUtc().toIso8601String(),
    'lastError': _lastError,
    'unknownCoordinatorKeys': _unknownKeys,
    'channel': channel?.toJson(),
  };

  /// Запускает цикл регистрации и heartbeat.
  void start() => _loop ??= _run();

  /// Останавливает цикл; текущий запрос к координатору (с его повторами)
  /// ждётся не дольше [wait].
  Future<void> stop({Duration wait = const Duration(seconds: 5)}) async {
    _stopped = true;
    _wakeUp();
    try {
      await Future.wait([?_loop, ?channel?.stop()]).timeout(wait);
    } on TimeoutException {
      _log.warning(const LogEvent('stop_request_abandoned'));
    }
  }

  Future<void> _run() async {
    var failures = 0;
    var reregistered = false;
    while (!_stopped) {
      Duration next;
      try {
        if (!_registered) {
          await register();
          channel?.start();
          next = _interval;
        } else {
          next = await heartbeat();
        }
        failures = 0;
        reregistered = false;
        _lastError = null;
        await reportDamaged();
        await syncRevocations();
        if (await _checkReachability()) next = Duration.zero;
      } on CoordinatorException catch (e) {
        if (_stopped) break;
        _lastError = '${e.code.name}: ${e.detail}';
        if (e.code == pb.ErrorCode.ERROR_CODE_UNAUTHENTICATED &&
            _registered &&
            !reregistered) {
          _log.warning(const LogEvent('heartbeat_unknown_node'));
          _registered = false;
          reregistered = true;
          continue;
        }
        failures++;
        next = _backoff(failures, e.retryAfter);
        _log.warning(
          LogEvent(_registered ? 'heartbeat_failed' : 'register_failed', {
            'code': e.code.name,
            'http_status': e.httpStatus,
            'retry_in_s': next.inSeconds,
          }),
        );
      }
      if (_stopped) break;
      _nextAttempt = _clock().add(next);
      await _sleep(next);
    }
  }

  Duration _backoff(int failures, Duration? retryAfter) {
    final seconds = math.min(
      1 << math.min(failures + 1, 20),
      maxBackoff.inSeconds,
    );
    final pause = Duration(seconds: seconds);
    if (retryAfter != null && retryAfter > pause) return retryAfter;
    return pause;
  }

  Future<void> _sleep(Duration d) async {
    final wake = _wake = Completer<void>();
    final timer = Timer(d, () {
      if (!wake.isCompleted) wake.complete();
    });
    await wake.future;
    timer.cancel();
  }

  /// Адреса для координатора сейчас.
  List<String> get currentEndpoints => reachability?.endpoints ?? endpoints;

  /// Проверить достижимость вне очереди (после регистрации).
  void recheckReachability() {
    final r = reachability;
    if (r == null) return;
    r.invalidate();
    if (!_registered) return;
    _wakeUp();
  }

  /// Прервать паузу цикла: следующий heartbeat — сейчас.
  void _wakeUp() {
    if (_wake case final w? when !w.isCompleted) w.complete();
  }

  /// Команда координатора по каналу (protocol.md, раздел 4.10); `null` —
  /// ответ `CommandDone`.
  Future<pb.NodeChannelMessage?> _onCommand(
    pb.CoordinatorChannelMessage command,
  ) async {
    switch (command.whichBody()) {
      case pb.CoordinatorChannelMessage_Body.ping:
        return null;
      case pb.CoordinatorChannelMessage_Body.rendezvous:
        final handler = rendezvous;
        if (handler == null) {
          throw const CoordinatorException(
            pb.ErrorCode.ERROR_CODE_NOT_FOUND,
            'узел не принимает UDP',
          );
        }
        return pb.NodeChannelMessage(
          rendezvous: await handler(command.rendezvous),
        );
      case pb.CoordinatorChannelMessage_Body.audit:
        final handler = audit;
        if (handler == null) {
          throw const CoordinatorException(
            pb.ErrorCode.ERROR_CODE_NOT_FOUND,
            'узел не хранит фрагменты',
          );
        }
        return pb.NodeChannelMessage(audit: await handler(command.audit));
      case pb.CoordinatorChannelMessage_Body.repair:
        final handler = repair;
        if (handler == null) {
          throw const CoordinatorException(
            pb.ErrorCode.ERROR_CODE_UNAVAILABLE,
            'узел не выполняет ремонт',
          );
        }
        // Принятое задание выполняется в фоне, итог — ReportRepair.
        handler(command.repair);
        return null;
      case pb.CoordinatorChannelMessage_Body.syncRevocations:
        final list = revocations;
        if (list == null ||
            command.syncRevocations.sequence.toInt() <= list.sequence) {
          return null;
        }
        final ms = revocationJitter.inMilliseconds;
        final delay = Duration(
          milliseconds: ms == 0 ? 0 : math.Random().nextInt(ms),
        );
        unawaited(Future<void>.delayed(delay, syncRevocations));
        return null;
      case pb.CoordinatorChannelMessage_Body.heartbeat ||
          pb.CoordinatorChannelMessage_Body.error ||
          pb.CoordinatorChannelMessage_Body.notSet:
        // Новая команда, которой этот узел не знает.
        throw const CoordinatorException(
          pb.ErrorCode.ERROR_CODE_BAD_REQUEST,
          'неизвестная команда',
        );
    }
  }

  /// Проверка, если пора; `true` — адреса изменились.
  Future<bool> _checkReachability() async {
    final r = reachability;
    if (r == null || !_registered || _stopped || !r.due) return false;
    return await r.check(client, identity.keys.sign);
  }

  /// `RegisterNode`; бросает [CoordinatorException].
  Future<void> register() async {
    final response = await client.registerNode(
      pb.RegisterNodeRequest(
        nodeCertificate: identity.certificate,
        capacityBytes: Int64(capacityBytes),
        endpoints: currentEndpoints,
        versions: versions,
        software: 'node $appVersion',
      ),
      nodeKey: identity.keys.sign,
    );
    _registered = true;
    _lastHeartbeat = _clock();
    _checkKeys(response.coordinatorKeys);
    _log.info(
      LogEvent('registered', {
        'node_id': bytesToHex(identity.nodeId),
        'capacity_bytes': capacityBytes,
        'endpoints': currentEndpoints.length,
      }),
    );
  }

  /// `Heartbeat`; возвращает паузу до следующего.
  Future<Duration> heartbeat() async {
    final used = usedBytes();
    final request = pb.HeartbeatRequest(
      // Координатор отклоняет занятое больше ёмкости, а квоту могли
      // уменьшить в настройках при уже принятых фрагментах.
      usedBytes: Int64(math.min(used, capacityBytes)),
      capacityBytes: Int64(capacityBytes),
      endpoints: currentEndpoints,
      freeBytes: switch (freeBytes) {
        final f? => Int64(math.min(f(), capacityBytes)),
        null => null,
      },
    );
    final response = await _sendHeartbeat(request);
    _lastHeartbeat = _clock();
    if (response.nextHeartbeatMs > 0) {
      _interval = Duration(milliseconds: response.nextHeartbeatMs);
    }
    _log.fine(LogEvent('heartbeat', {'used_bytes': used}));
    return _interval;
  }

  /// По каналу, если он открыт, иначе по HTTP.
  Future<pb.HeartbeatResponse> _sendHeartbeat(
    pb.HeartbeatRequest request,
  ) async {
    if (channel case final c? when c.connected) {
      try {
        return await c.heartbeat(request);
      } on ChannelUnavailableException catch (e) {
        _log.fine(LogEvent('channel_heartbeat_failed', {'reason': e.reason}));
      }
    }
    return await client.heartbeat(request, nodeKey: identity.keys.sign);
  }

  /// Отправляет координатору повреждённые фрагменты, о которых он ещё не
  /// знает, пачками по [maxDamagedPerReport]. Узел не
  /// зарегистрирован — ничего не делает (отчёт уйдёт после регистрации);
  /// сбой связи — в журнал, повтор после следующего heartbeat.
  /// Одновременные вызовы ждут один отчёт.
  Future<void> reportDamaged() =>
      _reporting ??= _report().whenComplete(() => _reporting = null);

  Future<void> _report() async {
    final source = damaged;
    if (source == null || !_registered) return;
    try {
      while (!_stopped) {
        final ids = source.unreportedDamaged(limit: maxDamagedPerReport);
        if (ids.isEmpty) return;
        final response = await client.reportDamagedFragments(
          pb.ReportDamagedFragmentsRequest(fragmentIds: ids),
          nodeKey: identity.keys.sign,
        );
        source.markReported(ids);
        _log.info(
          LogEvent('damaged_reported', {
            'fragments': ids.length,
            'known': response.known,
          }),
        );
      }
    } on CoordinatorException catch (e) {
      _log.warning(
        LogEvent('damaged_report_failed', {
          'code': e.code.name,
          'http_status': e.httpStatus,
        }),
      );
    }
  }

  /// Дочитывает отзывы устройств у координатора. Сбой связи — в журнал,
  /// повтор после следующего heartbeat.
  Future<void> syncRevocations() async {
    final list = revocations;
    if (list == null || !_registered || _stopped) return;
    try {
      await list.sync(client, identity.keys.sign);
    } on CoordinatorException catch (e) {
      _log.warning(
        LogEvent('revocations_sync_failed', {
          'code': e.code.name,
          'http_status': e.httpStatus,
        }),
      );
    }
  }

  /// Наибольшая пачка `ReportDamagedFragments` (protocol.md, раздел 4.9).
  static const maxDamagedPerReport = 1000;

  void _checkKeys(List<List<int>> keys) {
    final crypto = client.crypto;
    _unknownKeys = [
      for (final k in keys)
        if (!trustedKeys.trusts(k)) CoordinatorKeySet.keyId(crypto, k),
    ];
    if (trustedKeys.isEmpty) {
      _log.warning(const LogEvent('coordinator_keys_not_configured'));
    } else if (_unknownKeys.isNotEmpty) {
      // Координатор подписывает ключом, которого нет в списке узла: талоны
      // им не будут приняты — нужно обновление (раздел 5.1).
      _log.warning(
        LogEvent('coordinator_key_unknown', {'key_ids': _unknownKeys}),
      );
    }
  }
}
