import 'dart:async';
import 'dart:io';

import 'package:core/core.dart';
import 'package:logging/logging.dart';
import 'package:node/src/control/control_endpoint.dart';
import 'package:node/src/control/control_server.dart';
import 'package:node/src/daemon/config.dart';
import 'package:node/src/daemon/coordinator_link.dart';
import 'package:node/src/daemon/identity.dart';
import 'package:node/src/daemon/log.dart';
import 'package:node/src/daemon/transfers.dart';
import 'package:node/src/net/peer_listener.dart';
import 'package:node/src/net/port_mapping/port_mapper.dart';
import 'package:node/src/net/reachability.dart';
import 'package:node/src/net/udp_peers.dart';
import 'package:node/src/peers/peer_service.dart';
import 'package:node/src/peers/revocations.dart';
import 'package:node/src/storage/fragment_storage.dart';
import 'package:node/src/storage/integrity_checker.dart';
import 'package:protocol/protocol.dart' as pb;

/// Состояние демона для `cli node status`.
enum NodeState { running, paused, stopping }

/// Демон хранителя (задачи 3.1.1–3.1.3, 3.2, 3.4, 3.5): папка данных под
/// блокировкой, журнал с ротацией, ключи и сертификат узла, хранилище
/// фрагментов с фоновой проверкой целостности, операции с фрагментами для
/// собеседников по Noise ([peers]) с приёмом TCP ([listener]), проброс
/// порта на роутере ([portMapper]), приём UDP после сведения узлов
/// ([udp], 3.7), регистрация у координатора, heartbeat
/// и проверка достижимости ([reachability]), локальный API управления.
///
/// Остановка ([stop], SIGINT, SIGTERM, метод `stop` локального API):
/// новые передачи не начинаются, начатые завершаются (не дольше
/// `shutdown.grace_seconds`), затем узел отключается от координатора и
/// освобождает папку данных. Повторный сигнал — остановка без ожидания.
/// Состояние на диске (ключи, сертификат, фрагменты и их индекс)
/// пишется атомарно, поэтому и прерванная остановка его не портит.
final class NodeDaemon {
  new _({
    required this.config,
    required this.identity,
    required this.storage,
    required this.checker,
    required this.revocations,
    required this.gate,
    required this._lock,
    required this._writer,
    required this._logFile,
  }) : _limits = config.limits,
       startedAt = DateTime.now();

  /// Запускает демон по [config]. [handleSignals] — останавливаться по
  /// SIGINT и SIGTERM (в тестах в одном процессе — нет). [allowedUid] —
  /// только для тестов локального API.
  ///
  /// Ошибки запуска: папка занята другим демоном — [FileSystemException],
  /// ключи и сертификат — [NodeIdentityException].
  static Future<NodeDaemon> start(
    NodeConfig config, {
    required CryptoProvider crypto,
    bool handleSignals = true,
    int? allowedUid,
  }) async {
    final dataDir = Directory(config.dataDir);
    createPrivateDir(dataDir);
    final lock = _acquireLock(dataDir);
    RotatingLogFile? logFile;
    JsonLogWriter? writer;
    NodeIdentity? identity;
    FragmentStorage? storage;
    try {
      if (config.log.file == '-') {
        writer = JsonLogWriter(stderr);
      } else {
        logFile = RotatingLogFile(
          config.log.file ?? '${dataDir.path}/logs/node.log',
          maxBytes: config.log.maxBytes,
          files: config.log.files,
        );
        writer = JsonLogWriter(logFile);
      }
      writer.attach(config.log.level);
      identity = await NodeIdentity.load(dataDir, crypto);
      if (config.coordinatorUrl != null && identity.certificate == null) {
        throw const NodeIdentityException(
          'нет сертификата узла: выпустите его командой cli node-cert на '
          'устройстве владельца и импортируйте (node import-cert)',
        );
      }
      storage = FragmentStorage.open(
        config.dataDir,
        crypto: crypto,
        quotaBytes: config.quotaBytes,
        freeReserveBytes: config.freeReserveBytes,
      );
      final daemon = NodeDaemon._(
        config: config,
        identity: identity,
        storage: storage,
        checker: IntegrityChecker(
          storage: storage,
          crypto: crypto,
          interval: config.checkInterval,
          bytesPerSecond: config.checkBytesPerSecond,
        ),
        revocations: RevocationList(storage.index, crypto),
        gate: TransferGate(),
        lock: lock,
        writer: writer,
        logFile: logFile,
      );
      try {
        await daemon._start(crypto, handleSignals, allowedUid);
      } on Object {
        await daemon._abortStart();
        rethrow;
      }
      return daemon;
    } on Object catch (e, st) {
      _log.severe(LogEvent('start_failed', {'reason': '$e'}), null, st);
      await storage?.close();
      identity?.dispose();
      await writer?.detach();
      logFile?.close();
      _releaseLock(dataDir, lock);
      rethrow;
    }
  }

  static final _log = Logger('node');

  final NodeConfig config;
  final NodeIdentity identity;
  final FragmentStorage storage;
  final IntegrityChecker checker;

  /// Отозванные устройства: рукопожатие с ними не проходит (3.3.2).
  final RevocationList revocations;

  /// Операции с фрагментами для собеседников; `null` — у узла нет
  /// сертификата (рукопожатие без него невозможно). Соединения передаёт
  /// транспорт ([PeerService.serve]): приём TCP ([listener]), позже UDP и
  /// relay.
  PeerService? get peers => _peers;
  PeerService? _peers;

  /// Приём TCP; `null` — нет [peers].
  PeerListener? get listener => _listener;
  PeerListener? _listener;

  /// Проброс порта на роутере; `null` — нет [listener].
  PortMapper? get portMapper => _portMapper;
  PortMapper? _portMapper;

  /// Приём по UDP после сведения узлов; `null` — нет [listener] или
  /// `listen.udp: false`.
  UdpPeers? get udp => _udp;
  UdpPeers? _udp;

  /// Доступность извне и адреса узла; `null` — нет [listener].
  Reachability? get reachability => _reachability;
  Reachability? _reachability;
  final TransferGate gate;
  final NodeStats stats = NodeStats();
  final DateTime startedAt;
  final RandomAccessFile _lock;
  final JsonLogWriter _writer;
  final RotatingLogFile? _logFile;

  SpeedLimits _limits;
  CoordinatorClient? _client;
  CoordinatorLink? _link;
  ControlServer? _control;
  final _signals = <StreamSubscription<ProcessSignal>>[];
  final _done = Completer<void>();
  Future<void>? _stopping;
  bool _force = false;

  /// Завершается, когда демон остановлен.
  Future<void> get done => _done.future;

  NodeState get state => _stopping != null
      ? NodeState.stopping
      : gate.paused
      ? NodeState.paused
      : NodeState.running;

  /// Основные пределы скорости; меняются через локальный API до
  /// перезапуска.
  SpeedLimits get limits => _limits;

  /// Пределы сейчас: основные с учётом расписания `limits.schedule`.
  SpeedLimits get effectiveLimits =>
      config.schedule.at(DateTime.now(), _limits);

  CoordinatorLink? get link => _link;
  ControlServer? get control => _control;

  Future<void> _start(
    CryptoProvider crypto,
    bool handleSignals,
    int? allowedUid,
  ) async {
    final trustedKeys = config.coordinatorKeys.isEmpty
        ? CoordinatorKeySet.builtIn
        : CoordinatorKeySet.fromHex(config.coordinatorKeys);
    if (identity.certificate case final certificate?) {
      _peers = PeerService(
        crypto: crypto,
        local: LocalPeer(
          role: pb.PeerRole.PEER_ROLE_NODE,
          staticKey: identity.keys.dh,
          certificate: certificate,
          software: 'node $appVersion',
        ),
        nodeId: identity.nodeId,
        storage: storage,
        trustedKeys: trustedKeys,
        revocations: revocations,
        gate: gate,
        stats: stats,
        limits: config.peers,
        uploadLimiter: BandwidthLimiter(
          () => effectiveLimits.uploadBytesPerSecond,
        ),
        downloadLimiter: BandwidthLimiter(
          () => effectiveLimits.downloadBytesPerSecond,
        ),
      );
      final listener = _listener = await PeerListener.bind(
        config.listenHost,
        config.listenPort,
        _peers!.serve,
      );
      if (config.udp) {
        try {
          _udp = await UdpPeers.bind(listener.port, _peers!.serve);
        } on SocketException catch (e) {
          // Номер занят по UDP: внешний адрес всё равно назовёт сводник.
          _log.warning(LogEvent('udp_port_busy', {'reason': e.message}));
          _udp = await UdpPeers.bind(0, _peers!.serve);
        }
      }
      if (config.portMapping != PortMappingMode.off) {
        _portMapper = PortMapper(
          internalPort: listener.port,
          protocols: PortMapper.protocolsFor(config.portMapping),
          onChange: () => _link?.recheckReachability(),
        )..start();
      }
      _reachability = Reachability(
        manualEndpoints: config.endpoints,
        ports: () => {listener.port, ?_portMapper?.externalPort}.toList(),
      );
    }
    if (config.coordinatorUrl case final String url) {
      final SecurityContext? trusted;
      if (config.coordinatorCa case final String ca) {
        trusted = SecurityContext()..setTrustedCertificates(ca);
      } else {
        trusted = null;
      }
      final client = _client = CoordinatorClient(
        baseUri: Uri.parse(url),
        crypto: crypto,
        trustedCertificates: trusted,
        userAgent: 'node/$appVersion',
      );
      _link = CoordinatorLink(
        client: client,
        identity: identity,
        capacityBytes: config.quotaBytes,
        usedBytes: () => storage.usedBytes,
        freeBytes: () => storage.freeBytes,
        damaged: storage,
        revocations: revocations,
        endpoints: config.endpoints,
        reachability: _reachability,
        rendezvous: _udp?.handle,
        trustedKeys: trustedKeys,
        commandChannel: config.commandChannel,
      )..start();
    }
    checker.onDamaged = (_) {
      if (_link case final link?) unawaited(link.reportDamaged());
    };
    checker.start();
    _control = await ControlServer.bind(
      ControlEndpoint.forDataDir(
        config.dataDir,
        socketPath: config.controlSocket,
      ),
      _handle,
      allowedUid: allowedUid,
    );
    if (handleSignals) {
      _signals.add(ProcessSignal.sigint.watch().listen(_onSignal));
      if (!Platform.isWindows) {
        _signals.add(ProcessSignal.sigterm.watch().listen(_onSignal));
      }
    }
    _log.info(
      LogEvent('started', {
        'version': appVersion,
        'node_id': bytesToHex(identity.nodeId),
        'quota_bytes': config.quotaBytes,
        'used_bytes': storage.usedBytes,
        'fragments': storage.fragmentCount,
        'listen_port': ?_listener?.port,
        'udp_port': ?_udp?.port,
        'coordinator': config.coordinatorUrl != null,
      }),
    );
  }

  /// Запуск не удался после [_start]: освободить порт, проброс и связь
  /// с координатором; хранилище закрывает [start].
  Future<void> _abortStart() async {
    await _listener?.close();
    await _udp?.close();
    await _peers?.close();
    await checker.stop();
    await _link?.stop(wait: Duration.zero);
    _client?.close(force: true);
    await _portMapper?.stop();
    for (final s in _signals) {
      await s.cancel();
    }
    await _control?.close();
  }

  void _onSignal(ProcessSignal signal) {
    if (_stopping != null) {
      _log.warning(LogEvent('stop_forced', {'signal': '$signal'}));
      _force = true;
      gate.forceClose();
      return;
    }
    unawaited(stop(reason: '$signal'));
  }

  /// Корректная остановка; повторный вызов возвращает ту же остановку.
  Future<void> stop({String reason = 'request'}) => _stopping ??= _stop(reason);

  Future<void> _stop(String reason) async {
    _log.info(LogEvent('stopping', {'reason': reason, 'active': gate.active}));
    final drained = await gate.close(config.shutdownGrace);
    if (!drained && !_force) {
      _log.warning(LogEvent('transfers_abandoned', {'active': gate.active}));
    }
    await _listener?.close();
    await _udp?.close();
    await _peers?.close();
    await checker.stop();
    await _link?.stop();
    await _portMapper?.stop();
    _client?.close(force: true);
    for (final s in _signals) {
      await s.cancel();
    }
    await _control?.close();
    await storage.close();
    identity.dispose();
    _log.info(const LogEvent('stopped'));
    await _writer.detach();
    _logFile?.close();
    _releaseLock(Directory(config.dataDir), _lock);
    _done.complete();
  }

  /// Методы локального API (`docs/ops/node.md`, раздел «Локальный API»).
  Future<Map<String, Object?>> _handle(
    String method,
    Map<String, Object?> params,
  ) async {
    switch (method) {
      case 'status':
        return status();
      case 'stats':
        return {
          ...stats.toJson(),
          ...checker.toJson(),
          'activeTransfers': gate.active,
          'uptimeSeconds': DateTime.now().difference(startedAt).inSeconds,
        };
      case 'limits':
        _limits = SpeedLimits(
          uploadBytesPerSecond:
              _limit(params, 'upload') ?? _limits.uploadBytesPerSecond,
          downloadBytesPerSecond:
              _limit(params, 'download') ?? _limits.downloadBytesPerSecond,
        );
        if (params.isNotEmpty) {
          _log.info(LogEvent('limits_changed', _limits.toJson()));
        }
        return _limitsJson();
      case 'pause':
        if (!gate.paused) _log.info(const LogEvent('paused'));
        gate.paused = true;
        return {'state': state.name};
      case 'resume':
        if (gate.paused) _log.info(const LogEvent('resumed'));
        gate.paused = false;
        return {'state': state.name};
      case 'stop':
        // Ответ уходит до закрытия сервера API.
        Timer.run(() => unawaited(stop(reason: 'control')));
        return {'state': NodeState.stopping.name};
      default:
        throw ControlException('unknown_method', 'неизвестный метод $method');
    }
  }

  static int? _limit(Map<String, Object?> params, String key) {
    final v = params[key];
    if (v == null) return null;
    if (v is int && v >= 0) return v;
    throw ControlException('bad_request', '$key: целое число байт в секунду');
  }

  /// Ответ метода `status`.
  Map<String, Object?> status() => {
    'nodeId': bytesToHex(identity.nodeId),
    'owner': switch (identity.owner) {
      final o? => bytesToHex(o),
      null => null,
    },
    'version': appVersion,
    'state': state.name,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'dataDir': config.dataDir,
    'quotaBytes': config.quotaBytes,
    'usedBytes': storage.usedBytes,
    'freeBytes': storage.freeBytes,
    'diskAvailableBytes': storage.diskAvailable,
    'fragments': storage.fragmentCount,
    'damagedFragments': storage.damagedCount,
    'revokedDevices': revocations.count,
    'limits': _limitsJson(),
    'activeTransfers': gate.active,
    'connections': _peers?.connectionCount ?? 0,
    'listen': _listener?.toJson(),
    'udp': _udp?.toJson(),
    'portMapping': _portMapper?.toJson(),
    'reachability': _reachability?.toJson(),
    'coordinator': _link?.toJson(),
  };

  Map<String, Object?> _limitsJson() => {
    ..._limits.toJson(),
    'effective': effectiveLimits.toJson(),
    'schedule': config.schedule.toJson(),
  };

  /// Папка данных — одному демону: исключительная блокировка
  /// `node.lock` (на Windows она же не даёт удалить файл). Внутри — pid
  /// для диагностики.
  static RandomAccessFile _acquireLock(Directory dataDir) {
    final raf = File('${dataDir.path}/node.lock')
        .openSync(mode: FileMode.append);
    try {
      raf.lockSync();
    } on FileSystemException {
      raf.closeSync();
      throw FileSystemException(
        'папка данных занята другим демоном узла',
        dataDir.path,
      );
    }
    raf
      ..truncateSync(0)
      ..setPositionSync(0)
      ..writeStringSync('$pid\n')
      ..flushSync();
    return raf;
  }

  static void _releaseLock(Directory dataDir, RandomAccessFile lock) {
    try {
      lock
        ..truncateSync(0)
        ..unlockSync()
        ..closeSync();
    } on FileSystemException {
      // Уже закрыт.
    }
  }
}
