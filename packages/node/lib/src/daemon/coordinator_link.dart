import 'dart:async';
import 'dart:math' as math;

import 'package:core/core.dart';
import 'package:fixnum/fixnum.dart';
import 'package:logging/logging.dart';
import 'package:node/src/daemon/identity.dart';
import 'package:node/src/daemon/log.dart';
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
final class CoordinatorLink {
  new({
    required this.client,
    required this.identity,
    required this.capacityBytes,
    required this.usedBytes,
    required this.trustedKeys,
    this.endpoints = const [],
    this.maxBackoff = const Duration(minutes: 5),
    this._interval = defaultInterval,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

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
  final CoordinatorKeySet trustedKeys;
  final List<String> endpoints;
  final Duration maxBackoff;
  final DateTime Function() _clock;

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

  bool get registered => _registered;

  /// Состояние для `cli node status`.
  Map<String, Object?> toJson() => {
    'url': client.baseUri.toString(),
    'registered': _registered,
    'lastHeartbeatAt': _lastHeartbeat?.toUtc().toIso8601String(),
    'nextAttemptAt': _nextAttempt?.toUtc().toIso8601String(),
    'lastError': _lastError,
    'unknownCoordinatorKeys': _unknownKeys,
  };

  /// Запускает цикл регистрации и heartbeat.
  void start() => _loop ??= _run();

  /// Останавливает цикл; текущий запрос к координатору (с его повторами)
  /// ждётся не дольше [wait].
  Future<void> stop({Duration wait = const Duration(seconds: 5)}) async {
    _stopped = true;
    if (_wake case final w? when !w.isCompleted) w.complete();
    try {
      await _loop?.timeout(wait);
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
          next = _interval;
        } else {
          next = await heartbeat();
        }
        failures = 0;
        reregistered = false;
        _lastError = null;
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

  /// `RegisterNode`; бросает [CoordinatorException].
  Future<void> register() async {
    final response = await client.registerNode(
      pb.RegisterNodeRequest(
        nodeCertificate: identity.certificate,
        capacityBytes: Int64(capacityBytes),
        endpoints: endpoints,
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
        'endpoints': endpoints.length,
      }),
    );
  }

  /// `Heartbeat`; возвращает паузу до следующего.
  Future<Duration> heartbeat() async {
    final used = usedBytes();
    final response = await client.heartbeat(
      pb.HeartbeatRequest(
        // Координатор отклоняет занятое больше ёмкости, а квоту могли
        // уменьшить в настройках при уже принятых фрагментах.
        usedBytes: Int64(math.min(used, capacityBytes)),
        capacityBytes: Int64(capacityBytes),
        endpoints: endpoints,
      ),
      nodeKey: identity.keys.sign,
    );
    _lastHeartbeat = _clock();
    if (response.nextHeartbeatMs > 0) {
      _interval = Duration(milliseconds: response.nextHeartbeatMs);
    }
    _log.fine(LogEvent('heartbeat', {'used_bytes': used}));
    return _interval;
  }

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
