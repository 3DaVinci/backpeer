import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:agent/src/agent_keys.dart';
import 'package:agent/src/paths.dart';
import 'package:agent/src/schedule.dart';
import 'package:agent/src/secrets/secret_store.dart';
import 'package:agent/src/settings.dart';
import 'package:agent/src/state.dart';
import 'package:cli/cli.dart';
import 'package:core/core.dart';
import 'package:daemon_kit/daemon_kit.dart';
import 'package:logging/logging.dart';
import 'package:protocol/protocol.dart' as pb;

/// Вид задания агента.
enum JobKind { backup, verify, restore }

/// Состояние агента для приложения.
enum AgentStatus {
  /// Ждёт расписания или команды.
  idle,

  /// Выполняет задание ([BackupAgent.job]).
  working,

  /// Пауза: расписание не работает, бэкап остановлен с продолжением.
  paused,

  /// Пора работать, но ключей нет: хранилище ОС недоступно или закрыто,
  /// нужен пароль (метод `unlock`).
  waitingForKeys,

  stopping,
}

/// Идущее задание.
final class RunningJob {
  new(this.kind, this.trigger) : startedAt = DateTime.now();

  final JobKind kind;

  /// `schedule`, `manual`, `resume`.
  final String trigger;
  final DateTime startedAt;
  final CancellationToken cancel = CancellationToken();
  Map<String, Object?> progress = const {};

  /// Отменено паузой: бэкап продолжится после `resume`.
  bool paused = false;

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'trigger': trigger,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'progress': progress,
  };
}

/// Агент бэкапа (задачи 5.1.3, 5.1.4; ADR-008, ADR-010): второй фоновый
/// процесс рядом с хранителем `node`. Делает бэкап по расписанию,
/// проверку и восстановление в фоне; приложение и `agent unlock`
/// управляют им через локальный API (`docs/ops/agent.md`).
///
/// - Каталог программы ([AppHome]) общий с CLI: те же `config.json`,
///   ключи и локальный индекс. Одновременно — один агент на каталог
///   (`agent/agent.lock`).
/// - Ключи без пароля — из хранилища ОС ([AgentKeyVault]); нет его или оно
///   закрыто — агент ждёт пароль ([AgentStatus.waitingForKeys]).
/// - Незаконченный бэкап (`kill -9`, сбой питания, остановка, пауза)
///   продолжается при следующем запуске сразу ([AgentState.interrupted]).
final class BackupAgent {
  new _({
    required this.paths,
    required this.crypto,
    required this.vault,
    required this.argon2,
    required this.keysRetry,
    required this._lock,
    required this._writer,
    required this._logFile,
    required this.settings,
    required this.state,
  }) : startedAt = DateTime.now();

  /// Запускает агента для каталога [home]. [secrets] — хранилище ОС (по
  /// умолчанию [SecretStore.forPlatform]); [logFile] — путь журнала,
  /// `-` — stderr; [handleSignals] — останавливаться по SIGINT и SIGTERM;
  /// [allowedUid] — только для тестов локального API.
  ///
  /// Каталог занят другим агентом — [FileSystemException].
  static Future<BackupAgent> start({
    required AppHome home,
    required CryptoProvider crypto,
    SecretStore? secrets,
    Argon2Params argon2 = const Argon2Params(),
    String? logFile,
    Level logLevel = Level.INFO,
    String? socketPath,
    bool handleSignals = true,
    Duration keysRetry = const Duration(minutes: 1),
    int? allowedUid,
  }) async {
    final paths = AgentPaths(home);
    paths.dir.createSync(recursive: true);
    if (!Platform.isWindows) setUnixFileMode(paths.dir.path, 448); // 0700
    final lock = DirLock.acquire(
      paths.lock,
      busy: 'агент бэкапа для этого каталога уже запущен',
    );
    RotatingLogFile? rotating;
    JsonLogWriter? writer;
    try {
      if (logFile == '-') {
        writer = JsonLogWriter(stderr);
      } else {
        rotating = RotatingLogFile(
          logFile ?? paths.log,
          maxBytes: 10 << 20,
          files: 5,
        );
        writer = JsonLogWriter(rotating);
      }
      writer.attach(logLevel);
      final agent = BackupAgent._(
        paths: paths,
        crypto: crypto,
        vault: AgentKeyVault(
          file: paths.keys,
          crypto: crypto,
          secrets: secrets ?? SecretStore.forPlatform(),
          entry: home.dir.absolute.path,
        ),
        argon2: argon2,
        keysRetry: keysRetry,
        lock: lock,
        writer: writer,
        logFile: rotating,
        settings: AgentSettings.load(paths.settings),
        state: AgentState.load(paths.state),
      );
      agent._control = await ControlServer.bind(
        paths.endpoint(socketPath: socketPath),
        agent._handle,
        allowedUid: allowedUid,
      );
      if (handleSignals) {
        agent._signals.add(ProcessSignal.sigint.watch().listen(agent._signal));
        if (!Platform.isWindows) {
          agent._signals.add(
            ProcessSignal.sigterm.watch().listen(agent._signal),
          );
        }
      }
      _log.info(
        LogEvent('started', {
          'version': appVersion,
          'interrupted': agent.state.interrupted != null,
          'secrets': agent.vault.secrets.name,
          'remembered': agent.vault.exists,
        }),
      );
      agent._reschedule();
      return agent;
    } on Object catch (e, st) {
      _log.severe(LogEvent('start_failed', {'reason': '$e'}), null, st);
      await writer?.detach();
      rotating?.close();
      lock.release();
      rethrow;
    }
  }

  static final _log = Logger('agent');

  final AgentPaths paths;
  final CryptoProvider crypto;
  final AgentKeyVault vault;
  final Argon2Params argon2;

  /// Как часто снова спрашивать хранилище ОС, когда ключей нет.
  final Duration keysRetry;
  final DateTime startedAt;
  final DirLock _lock;
  final JsonLogWriter _writer;
  final RotatingLogFile? _logFile;

  AgentSettings settings;
  AgentState state;

  late final ControlServer _control;
  final _signals = <StreamSubscription<ProcessSignal>>[];
  final _done = Completer<void>();
  Future<void>? _stopping;

  /// Ключи, открытые паролем без сохранения в хранилище ОС.
  KeyMaterial? _memoryKeys;

  /// Почему нет ключей; `null` — ключи есть или пока не нужны.
  String? _keysProblem;

  RunningJob? _job;
  Future<void>? _jobDone;
  Timer? _timer;
  DateTime? _nextAt;
  bool _paused = false;

  /// Завершается, когда агент остановлен.
  Future<void> get done => _done.future;

  RunningJob? get job => _job;

  /// Когда следующий бэкап по расписанию.
  DateTime? get nextBackupAt => _nextAt;

  AgentStatus get status {
    if (_stopping != null) return AgentStatus.stopping;
    // Бэкап, остановленный паузой, ещё дописывает начатый сегмент.
    if (_job case final job? when !job.paused) return AgentStatus.working;
    if (_paused) return AgentStatus.paused;
    if (_job != null) return AgentStatus.working;
    if (_keysProblem != null) return AgentStatus.waitingForKeys;
    return AgentStatus.idle;
  }

  /// Задание [_jobDone] закончится — для тестов.
  Future<void> get idle async {
    for (var f = _jobDone; f != null; f = _jobDone) {
      await f;
    }
  }

  // --- Расписание ---------------------------------------------------------

  void _reschedule() {
    _timer?.cancel();
    _timer = null;
    _nextAt = null;
    if (_stopping != null || _paused || !paths.home.initialized) {
      _publishStatus();
      return;
    }
    _nextAt = nextScheduledBackup(settings, state);
    if (_job == null) {
      if (_keysProblem != null && _nextAt != null) {
        // Ключей нет: снова спросить хранилище ОС через [keysRetry].
        _timer = Timer(keysRetry, () => _scheduled('schedule'));
      } else if (_nextAt case final at?) {
        final delay = at.difference(DateTime.now());
        _timer = Timer(
          delay.isNegative ? Duration.zero : delay,
          () => _scheduled(state.interrupted != null ? 'resume' : 'schedule'),
        );
      }
    }
    _publishStatus();
  }

  /// Бэкап по таймеру: ошибки запуска — только в журнал.
  void _scheduled(String trigger) => unawaited(
    _run(JobKind.backup, trigger).then<void>(
      (_) {},
      onError: (Object e) {
        _log.warning(LogEvent('schedule_skipped', {'reason': _describe(e)}));
        _reschedule();
      },
    ),
  );

  // --- Ключи --------------------------------------------------------------

  /// Ключи для задания: из памяти, иначе из хранилища ОС; нет — `null` и
  /// [_keysProblem].
  Future<KeyMaterial?> _material() async {
    if (_memoryKeys case final m?) return m;
    try {
      final m = await vault.open();
      if (m != null) {
        _keysProblem = null;
        return m;
      }
      _keysProblem = vault.exists
          ? 'ключ агента в хранилище ОС не найден'
          : 'ключи для работы без пароля не сохранены';
    } on SecretStoreException catch (e) {
      _keysProblem = 'хранилище ключей ОС недоступно: ${e.message}';
    }
    return null;
  }

  Future<Map<String, Object?>> _unlock(Map<String, Object?> params) async {
    final password = params['password'];
    final remember = params['remember'] ?? true;
    if (password is! String || remember is! bool) {
      throw const ControlException(
        'bad_request',
        'нужны password (строка) и remember (true или false)',
      );
    }
    final store = DeviceKeyStore(paths.home.keysFile, crypto, params: argon2);
    if (!store.exists) {
      throw const ControlException(
        'not_configured',
        'на этом устройстве нет ключей: сначала создайте учётную запись '
            'или войдите',
      );
    }
    final AccountKeys keys;
    final DeviceKeys? device;
    try {
      (keys, device) = await store.unlockWithDevice(password);
    } on IntegrityException {
      _log.warning(const LogEvent('unlock_failed'));
      throw const ControlException('wrong_password', 'неверный пароль');
    }
    String? notRemembered;
    try {
      if (remember) {
        try {
          await vault.remember(keys, device);
        } on SecretStoreException catch (e) {
          notRemembered = e.message;
        }
      }
      if (!remember || notRemembered != null) {
        _memoryKeys?.dispose();
        _memoryKeys = KeyMaterial.of(keys, device);
      } else {
        _memoryKeys?.dispose();
        _memoryKeys = null;
      }
    } finally {
      keys.dispose();
      device?.dispose();
    }
    _keysProblem = null;
    _log.info(
      LogEvent('unlocked', {
        'remembered': remember && notRemembered == null,
        'reason': ?notRemembered,
      }),
    );
    _reschedule();
    return {
      'remembered': remember && notRemembered == null,
      'reason': ?notRemembered,
      'keys': _keysJson(),
    };
  }

  Map<String, Object?> _keysJson() => {
    'store': vault.secrets.name,
    'remembered': vault.exists,
    'inMemory': _memoryKeys != null,
    'problem': _keysProblem,
  };

  // --- Задания ------------------------------------------------------------

  /// Запускает задание; уже идёт другое — [ControlException] `busy`.
  /// Возвращает `false`, если ключей нет (агент ждёт пароль).
  Future<bool> _run(
    JobKind kind,
    String trigger, [
    Map<String, Object?> params = const {},
  ]) async {
    if (_stopping != null) {
      throw const ControlException('unavailable', 'агент останавливается');
    }
    if (_job case final current?) {
      throw ControlException('busy', 'уже идёт задание: ${current.kind.name}');
    }
    if (!paths.home.initialized) {
      throw const ControlException(
        'not_configured',
        'нет учётной записи на этом устройстве',
      );
    }
    final job = _job = RunningJob(kind, trigger);
    _timer?.cancel();
    final KeyMaterial? material;
    try {
      material = await _material();
    } on Object {
      _job = null;
      rethrow;
    }
    if (material == null) {
      _job = null;
      _log.warning(LogEvent('keys_required', {'reason': _keysProblem}));
      _control.publish('keys_required', {'reason': _keysProblem});
      _reschedule();
      return false;
    }
    final keys = material;
    final completer = Completer<void>();
    _jobDone = completer.future;
    _publishStatus();
    unawaited(
      _execute(job, keys, params).whenComplete(() {
        if (!identical(keys, _memoryKeys)) keys.dispose();
        _job = null;
        _jobDone = null;
        completer.complete();
        _reschedule();
      }),
    );
    return true;
  }

  Future<void> _execute(
    RunningJob job,
    KeyMaterial material,
    Map<String, Object?> params,
  ) async {
    _log.info(
      LogEvent('job_started', {'kind': job.kind.name, 'trigger': job.trigger}),
    );
    if (job.kind == JobKind.backup) {
      state.interrupted ??= job.startedAt;
      state.save(paths.state);
    }
    JobRecord record;
    try {
      final result = await _withSession(material, (session, config) {
        return switch (job.kind) {
          JobKind.backup => _backup(job, session, config),
          JobKind.verify => _verify(job, session, config, params),
          JobKind.restore => _restore(job, session, params),
        };
      });
      record = JobRecord(
        startedAt: job.startedAt,
        finishedAt: DateTime.now(),
        outcome: result.$1,
        result: result.$2,
      );
      if (job.kind == JobKind.backup) state.interrupted = null;
    } on CancelledException {
      // Незаконченный бэкап продолжится после паузы или перезапуска.
      record = JobRecord(
        startedAt: job.startedAt,
        finishedAt: DateTime.now(),
        outcome: JobOutcome.cancelled,
      );
    } on Object catch (e, st) {
      final message = _describe(e);
      _log.warning(
        LogEvent('job_failed', {'kind': job.kind.name, 'reason': message}),
        e is CoreException || e is SessionException ? null : e,
        e is CoreException || e is SessionException ? null : st,
      );
      record = JobRecord(
        startedAt: job.startedAt,
        finishedAt: DateTime.now(),
        outcome: JobOutcome.failed,
        error: message,
      );
      // Повтор — по расписанию через retryMinutes, а не сразу.
      if (job.kind == JobKind.backup) state.interrupted = null;
    }
    switch (job.kind) {
      case JobKind.backup:
        state.lastBackup = record;
      case JobKind.verify:
        state.lastVerify = record;
      case JobKind.restore:
        state.lastRestore = record;
    }
    state.save(paths.state);
    _log.info(
      LogEvent('job_finished', {
        'kind': job.kind.name,
        'outcome': record.outcome.name,
        ...record.result,
      }),
    );
    _control.publish('job_finished', {
      'kind': job.kind.name,
      ...record.toJson(),
    });
  }

  Future<T> _withSession<T>(
    KeyMaterial material,
    Future<T> Function(Session session, AppConfig config) body,
  ) async {
    final config = AppConfig.load(paths.home);
    final (keys, device) = await material.open(crypto);
    final LocalIndex index;
    try {
      index = LocalIndex.open(paths.home.indexPath);
    } on Object {
      keys.dispose();
      device?.dispose();
      rethrow;
    }
    final session = await openSession(
      config: config,
      crypto: crypto,
      keys: keys,
      device: device,
      index: index,
      software: 'agent/$appVersion',
    );
    try {
      return await body(session, config);
    } finally {
      await session.close();
    }
  }

  void _progress(RunningJob job, Map<String, Object?> data) {
    job.progress = data;
    _control.publish('progress', {'kind': job.kind.name, ...data});
  }

  Future<(JobOutcome, Map<String, Object?>)> _backup(
    RunningJob job,
    Session session,
    AppConfig config,
  ) async {
    if (settings.paths.isEmpty) {
      throw const ControlException('bad_request', 'не выбраны папки');
    }
    // Пул из 2 isolate, как у cli backup (docs/benchmarks.md, раздел 1.6.3).
    final encoder = await IsolateSegmentEncoder.start(2);
    try {
      final result = await runBackup(
        crypto: crypto,
        keys: session.keys,
        index: session.index,
        fragments: session.fragments,
        objects: session.objects,
        placer: session.placer,
        paths: settings.paths,
        deviceId: config.deviceId,
        excludes: ExcludeRules([...config.excludes, ...settings.excludes]),
        params: config.durability,
        encoder: encoder,
        cancel: job.cancel,
        progressInterval: const Duration(milliseconds: 500),
        onProgress: (p) => _progress(job, {
          'files': p.files,
          'bytesRead': p.bytesRead,
          'newBytes': p.newBytes,
          'segmentsStored': p.segmentsStored,
          'elapsedMs': p.elapsed.inMilliseconds,
        }),
      );
      final st = result.stats;
      final clean = result.report.isClean && result.warnings.isEmpty;
      return (
        clean ? JobOutcome.ok : JobOutcome.partial,
        <String, Object?>{
          'snapshotId': bytesToHex(result.snapshot.snapshotId),
          'sequence': result.snapshot.sequence.toInt(),
          'files': st.files,
          'directories': st.directories,
          'bytes': st.bytes,
          'newBytes': st.newBytes,
          'segments': result.segmentsStored,
          'skipped': result.report.skipped.length,
          'warnings': [for (final w in result.warnings) w.name],
        },
      );
    } finally {
      await encoder.close();
    }
  }

  Future<(JobOutcome, Map<String, Object?>)> _verify(
    RunningJob job,
    Session session,
    AppConfig config,
    Map<String, Object?> params,
  ) async {
    final full = params['full'] == true;
    final report = await runVerify(
      crypto: crypto,
      keys: session.keys,
      index: session.index,
      fragments: session.fragments,
      locator: session.locator,
      full: full,
      params: config.durability,
      cancel: job.cancel,
    );
    return (
      report.unrecoverable.isNotEmpty
          ? JobOutcome.failed
          : report.isHealthy
          ? JobOutcome.ok
          : JobOutcome.partial,
      <String, Object?>{
        'full': full,
        'segments': report.segments,
        'fragments': report.fragments,
        'healthy': report.isHealthy,
        'problems': report.problems.length,
        'atRisk': report.atRisk.length,
        'unrecoverable': report.unrecoverable.length,
      },
    );
  }

  Future<(JobOutcome, Map<String, Object?>)> _restore(
    RunningJob job,
    Session session,
    Map<String, Object?> params,
  ) async {
    final id = await _snapshotId(session, params['snapshot']);
    final target = params['target']! as String;
    final paths = (params['paths'] as List<Object?>? ?? const [])
        .cast<String>();
    final waitMinutes = params['waitMinutes'] as int? ?? 0;
    final result = await runRestore(
      crypto: crypto,
      keys: session.keys,
      index: session.index,
      fragments: session.fragments,
      objects: session.objects,
      locator: session.locator,
      snapshotId: id,
      target: Directory(target),
      paths: paths,
      overwrite: params['overwrite'] == true,
      cancel: job.cancel,
      wait: RestoreWait(
        maxWait: Duration(minutes: waitMinutes),
        retryInterval: const Duration(seconds: 10),
      ),
      progressInterval: const Duration(milliseconds: 500),
      onProgress: (p) => _progress(job, {
        'files': p.files,
        'bytes': p.bytes,
        'totalBytes': p.totalBytes,
        'waitingFiles': p.waitingFiles,
        'etaMs': p.eta?.inMilliseconds,
        'elapsedMs': p.elapsed.inMilliseconds,
      }),
    );
    return (
      result.isComplete ? JobOutcome.ok : JobOutcome.partial,
      <String, Object?>{
        'snapshotId': bytesToHex(id),
        'target': target,
        'files': result.files,
        'directories': result.directories,
        'bytes': result.bytes,
        'skippedExisting': result.skippedExisting.length,
        'errors': [
          for (final (path, reason) in result.errors.take(100))
            {'path': path, 'reason': reason},
        ],
      },
    );
  }

  /// Снимок по идентификатору или его началу (не короче 4 hex-символов).
  Future<Uint8List> _snapshotId(Session session, Object? prefix) async {
    if (prefix is! String || prefix.length < 4) {
      throw const ControlException(
        'bad_request',
        'snapshot: не меньше 4 символов идентификатора',
      );
    }
    final found = await _catalog(session).matching(prefix);
    return switch (found) {
      [final id] => id,
      [] => throw ControlException('not_found', 'снимок $prefix не найден'),
      _ => throw ControlException(
        'bad_request',
        'префикс $prefix подходит к ${found.length} снимкам',
      ),
    };
  }

  SnapshotCatalog _catalog(Session session) => SnapshotCatalog(
    crypto: crypto,
    manifestKey: session.keys.manifestKey,
    store: session.objects,
    index: session.index,
  );

  /// Запрос с ключами без задания (список снимков, дерево снимка).
  Future<Map<String, Object?>> _query(
    Future<Map<String, Object?>> Function(Session session) body,
  ) async {
    if (!paths.home.initialized) {
      throw const ControlException(
        'not_configured',
        'нет учётной записи на этом устройстве',
      );
    }
    final material = await _material();
    if (material == null) {
      _publishStatus();
      throw ControlException('keys_required', _keysProblem ?? 'нужен пароль');
    }
    try {
      return await _withSession(material, (session, _) => body(session));
    } on CoreException catch (e) {
      throw ControlException('failed', e.message);
    } on SessionException catch (e) {
      throw ControlException('failed', e.message);
    } finally {
      if (!identical(material, _memoryKeys)) material.dispose();
    }
  }

  Future<Map<String, Object?>> _snapshots() => _query((session) async {
    final listing = await _catalog(session).list();
    return {
      'snapshots': [
        for (final snap in listing.snapshots)
          {
            'id': bytesToHex(snap.snapshotId),
            'sequence': snap.sequence.toInt(),
            'createdAt': DateTime.fromMillisecondsSinceEpoch(
              snap.createdAtUnixMs.toInt(),
              isUtc: true,
            ).toIso8601String(),
            'hostname': snap.hostname,
            'paths': snap.paths,
            'files': snap.stats.files.toInt(),
            'bytes': snap.stats.bytes.toInt(),
          },
      ],
      'warnings': [for (final w in listing.warnings) w.name],
      'unreadable': [for (final (id, _) in listing.unreadable) bytesToHex(id)],
    };
  });

  /// Каталог снимка: `path` — имена от корня, `offset` и `limit` — для
  /// ленивой загрузки больших каталогов (5.4.1).
  Future<Map<String, Object?>> _tree(Map<String, Object?> params) {
    final path = params['path'] ?? const <Object?>[];
    final offset = params['offset'] ?? 0;
    final limit = params['limit'] ?? 1000;
    if (path is! List<Object?> ||
        path.any((p) => p is! String) ||
        offset is! int ||
        limit is! int ||
        offset < 0 ||
        limit < 1 ||
        limit > 10000) {
      throw const ControlException(
        'bad_request',
        'path — список имён, offset ≥ 0, 1 ≤ limit ≤ 10000',
      );
    }
    return _query((session) async {
      final id = await _snapshotId(session, params['snapshot']);
      final nodes = await SnapshotBrowser(
        crypto: crypto,
        keys: session.keys,
        index: session.index,
        fragments: session.fragments,
        objects: session.objects,
        locator: session.locator,
      ).list(id, path.cast<String>());
      return {
        'total': nodes.length,
        'entries': [
          for (final n in nodes.skip(offset).take(limit))
            {
              'name': utf8.decode(n.name, allowMalformed: true),
              'type': switch (n.type) {
                pb.NodeType.NODE_TYPE_FILE => 'file',
                pb.NodeType.NODE_TYPE_DIRECTORY => 'directory',
                pb.NodeType.NODE_TYPE_SYMLINK => 'symlink',
                _ => 'unknown',
              },
              'size': n.size.toInt(),
              'mtime': DateTime.fromMicrosecondsSinceEpoch(
                n.mtimeNs.toInt() ~/ 1000,
                isUtc: true,
              ).toIso8601String(),
            },
        ],
      };
    });
  }

  // --- Локальный API ------------------------------------------------------

  Map<String, Object?> statusJson() => {
    'version': appVersion,
    'status': status.name,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'home': paths.home.dir.path,
    'configured': paths.home.initialized,
    'job': _job?.toJson(),
    'nextBackupAt': _nextAt?.toUtc().toIso8601String(),
    'interrupted': state.interrupted != null,
    'lastBackup': state.lastBackup?.toJson(),
    'lastVerify': state.lastVerify?.toJson(),
    'lastRestore': state.lastRestore?.toJson(),
    'keys': _keysJson(),
    'settings': settings.toJson(),
  };

  void _publishStatus() {
    if (_control.hasSubscribers('status')) {
      _control.publish('status', statusJson());
    }
  }

  Future<Map<String, Object?>> _handle(
    String method,
    Map<String, Object?> params,
  ) async {
    switch (method) {
      case 'status':
        return statusJson();
      case 'settings':
        if (params.isNotEmpty) {
          final AgentSettings next;
          try {
            next = settings.merge(params);
          } on ConfigException catch (e) {
            throw ControlException('bad_request', e.message);
          }
          for (final p in next.paths) {
            if (!Directory(p).isAbsolute) {
              throw ControlException('bad_request', 'путь не абсолютный: $p');
            }
          }
          next.save(paths.settings);
          settings = next;
          _log.info(
            LogEvent('settings_changed', {
              'paths': next.paths.length,
              'intervalMinutes': next.intervalMinutes,
            }),
          );
          _reschedule();
        }
        return settings.toJson();
      case 'backup':
        return {'started': await _run(JobKind.backup, 'manual')};
      case 'verify':
        return {'started': await _run(JobKind.verify, 'manual', params)};
      case 'restore':
        if (params['target'] is! String ||
            !Directory(params['target']! as String).isAbsolute) {
          throw const ControlException(
            'bad_request',
            'target — абсолютный путь папки назначения',
          );
        }
        return {'started': await _run(JobKind.restore, 'manual', params)};
      case 'cancel':
        _job?.cancel.cancel();
        return {'cancelled': _job != null};
      case 'pause':
        if (!_paused) _log.info(const LogEvent('paused'));
        _paused = true;
        if (_job case final job? when job.kind == JobKind.backup) {
          job
            ..paused = true
            ..cancel.cancel();
        }
        _reschedule();
        return {'status': status.name};
      case 'resume':
        if (_paused) _log.info(const LogEvent('resumed'));
        _paused = false;
        _reschedule();
        return {'status': status.name};
      case 'progress':
        return {'job': _job?.toJson()};
      case 'snapshots':
        return await _snapshots();
      case 'tree':
        return await _tree(params);
      case 'health':
        return {'lastVerify': state.lastVerify?.toJson()};
      case 'unlock':
        return await _unlock(params);
      case 'lock':
        _memoryKeys?.dispose();
        _memoryKeys = null;
        return {'keys': _keysJson()};
      case 'forget_keys':
        _memoryKeys?.dispose();
        _memoryKeys = null;
        try {
          await vault.forget();
        } on SecretStoreException catch (e) {
          throw ControlException('failed', e.message);
        }
        _log.info(const LogEvent('keys_forgotten'));
        _publishStatus();
        return {'keys': _keysJson()};
      case 'stop':
        Timer.run(() => unawaited(stop(reason: 'control')));
        return {'status': AgentStatus.stopping.name};
      default:
        throw ControlException('unknown_method', 'неизвестный метод $method');
    }
  }

  // --- Остановка ----------------------------------------------------------

  void _signal(ProcessSignal signal) => unawaited(stop(reason: '$signal'));

  /// Остановка: задание отменяется (бэкап продолжится при следующем
  /// запуске), затем закрываются API и журнал.
  Future<void> stop({String reason = 'request'}) => _stopping ??= _stop(reason);

  Future<void> _stop(String reason) async {
    _log.info(LogEvent('stopping', {'reason': reason}));
    _timer?.cancel();
    _job?.cancel.cancel();
    _publishStatus();
    await idle;
    for (final s in _signals) {
      await s.cancel();
    }
    await _control.close();
    _memoryKeys?.dispose();
    _log.info(const LogEvent('stopped'));
    await _writer.detach();
    _logFile?.close();
    _lock.release();
    _done.complete();
  }
}

/// Сообщение об ошибке для человека, без текста исключений сторонних
/// пакетов.
String _describe(Object e) => switch (e) {
  CoreException() => e.message,
  SessionException() => e.message,
  ControlException() => e.message,
  FileSystemException() =>
    '${e.path ?? ''}: ${e.osError?.message ?? e.message}',
  _ => 'внутренняя ошибка (${e.runtimeType})',
};
