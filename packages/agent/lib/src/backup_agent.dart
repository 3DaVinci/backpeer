import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:agent/src/account_api.dart';
import 'package:agent/src/agent_keys.dart';
import 'package:agent/src/desktop/notifier.dart';
import 'package:agent/src/desktop/power.dart';
import 'package:agent/src/desktop/system_events.dart';
import 'package:agent/src/health.dart';
import 'package:agent/src/keeper.dart';
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

  /// Пора работать по расписанию, но компьютер от батареи, а в настройках
  /// — только от сети (`onlyOnAcPower`).
  waitingForPower,

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

  /// Отменено переходом на батарею: продолжится от сети.
  bool onBattery = false;

  /// Отменено сном компьютера: продолжится после пробуждения (5.6.3).
  bool asleep = false;

  /// Задержка сна, пока идёт бэкап: агент успевает его остановить.
  SleepInhibit? inhibit;

  /// Оценка объёма бэкапа (обход в отдельном isolate) — для доли и
  /// оставшегося времени; `null` — ещё считается.
  BackupEstimate? estimate;

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
    required this.power,
    required this.notifier,
    required this.powerRetry,
    required this.systemEvents,
    required this.wakeDelay,
    required this._lock,
    required this._writer,
    required this._logFile,
    required this.settings,
    required this.state,
  }) : startedAt = DateTime.now();

  /// Запускает агента для каталога [home]. [secrets] — хранилище ОС (по
  /// умолчанию [SecretStore.forPlatform]); [logFile] — путь журнала,
  /// `-` — stderr; [handleSignals] — останавливаться по SIGINT и SIGTERM;
  /// [power] и [notifier] — питание и уведомления ОС (по умолчанию для
  /// текущей ОС); [allowedUid] — только для тестов локального API.
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
    PowerSource? power,
    Notifier? notifier,
    Duration powerRetry = const Duration(minutes: 1),
    int? allowedUid,
    String? nodeDataDir,
    NodeLauncher? nodeLauncher,
    Linger? linger,
    SystemEvents? systemEvents,
    Duration wakeDelay = const Duration(seconds: 15),
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
        power: power ?? PowerSource.forPlatform(),
        notifier: notifier ?? Notifier.forPlatform(),
        powerRetry: powerRetry,
        systemEvents: systemEvents ?? NoSystemEvents(),
        wakeDelay: wakeDelay,
        lock: lock,
        writer: writer,
        logFile: rotating,
        settings: AgentSettings.load(paths.settings),
        state: AgentState.load(paths.state),
      );
      agent._account = AccountApi(
        ops: AccountOps(
          home: home,
          crypto: crypto,
          argon2: argon2,
          software: 'agent/$appVersion',
        ),
        adopt: agent._adoptKeys,
        withKeys: agent._withKeys,
      );
      agent._keeper = KeeperApi(
        home: home,
        file: paths.keeper,
        crypto: crypto,
        withKeys: (body) => agent._withKeys((keys, _) => body(keys)),
        launcher: nodeLauncher ?? ProcessNodeLauncher(),
        dataDir: nodeDataDir ?? KeeperApi.defaultDataDir(),
        linger: linger,
      );
      agent._control = await ControlServer.bind(
        paths.endpoint(socketPath: socketPath),
        agent._handle,
        allowedUid: allowedUid,
      );
      agent._systemSub = agent.systemEvents.events.listen(agent._onSystem);
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
          'power': agent.power.name,
          'notifier': agent.notifier.name,
          'systemEvents': agent.systemEvents.name,
          'nodeLauncher': agent._keeper.launcher.kind,
        }),
      );
      agent._reschedule();
      // Роль включена — хранитель должен работать: служба ОС (5.6.1)
      // или, без служб, процесс от агента.
      unawaited(
        agent._keeper.ensureRunning().catchError((Object e) {
          _log.warning(LogEvent('keeper_start_failed', {'reason': '$e'}));
        }),
      );
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

  /// Питание: бэкап по расписанию — только от сети (`onlyOnAcPower`).
  final PowerSource power;

  /// Уведомления о проблемах с бэкапом (5.3.4).
  final Notifier notifier;

  /// Как часто проверять питание, пока ждём сеть или идёт бэкап.
  final Duration powerRetry;

  /// Сон, пробуждение и сеть (5.6.3).
  final SystemEvents systemEvents;

  /// Пауза после пробуждения или появления сети перед продолжением: сеть
  /// поднимается не сразу.
  final Duration wakeDelay;
  final DateTime startedAt;
  final DirLock _lock;
  final JsonLogWriter _writer;
  final RotatingLogFile? _logFile;

  AgentSettings settings;
  AgentState state;

  late final ControlServer _control;
  late final AccountApi _account;
  late final KeeperApi _keeper;
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
  Timer? _powerWatch;
  DateTime? _nextAt;
  DateTime? _nextVerifyAt;
  bool _paused = false;
  bool _waitingForPower = false;

  /// Компьютер засыпает: расписание стоит до пробуждения.
  bool _asleep = false;

  /// После пробуждения или появления сети повторить неудачный бэкап, не
  /// дожидаясь `retryMinutes`: скорее всего, он упал из-за сети.
  bool _retrySoon = false;
  Timer? _wakeTimer;
  StreamSubscription<SystemEvent>? _systemSub;

  /// Последнее опубликованное событием `health` состояние.
  String? _healthSignature;

  /// Завершается, когда агент остановлен.
  Future<void> get done => _done.future;

  RunningJob? get job => _job;

  /// Когда следующий бэкап по расписанию.
  DateTime? get nextBackupAt => _nextAt;

  /// Когда следующая проверка по расписанию.
  DateTime? get nextVerifyAt => _nextVerifyAt;

  AgentStatus get status {
    if (_stopping != null) return AgentStatus.stopping;
    // Бэкап, остановленный паузой, ещё дописывает начатый сегмент.
    if (_job case final job? when !job.paused) return AgentStatus.working;
    if (_paused) return AgentStatus.paused;
    if (_job != null) return AgentStatus.working;
    if (_keysProblem != null) return AgentStatus.waitingForKeys;
    if (_waitingForPower) return AgentStatus.waitingForPower;
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
    _nextVerifyAt = null;
    if (_stopping != null || _paused || !paths.home.initialized) {
      _waitingForPower = false;
      _publishStatus();
      return;
    }
    _nextAt = nextScheduledBackup(settings, state);
    if (_retrySoon &&
        _nextAt != null &&
        state.lastBackup?.outcome == JobOutcome.failed) {
      _nextAt = DateTime.now();
    }
    if (_asleep) {
      // Таймеры во сне не идут, а после пробуждения _onSystem пересчитает.
      _publishStatus();
      return;
    }
    _nextVerifyAt = nextScheduledVerify(settings, state);
    if (_job == null) {
      final next = _earliest(_nextAt, _nextVerifyAt);
      if (next != null && (_keysProblem != null || _waitingForPower)) {
        // Ключей или сети нет: снова спросить через паузу.
        _timer = Timer(
          _keysProblem != null ? keysRetry : powerRetry,
          _scheduled,
        );
      } else if (next != null) {
        final delay = next.difference(DateTime.now());
        _timer = Timer(delay.isNegative ? Duration.zero : delay, _scheduled);
      } else {
        _waitingForPower = false;
      }
    }
    _publishStatus();
  }

  static DateTime? _earliest(DateTime? a, DateTime? b) =>
      a == null || (b != null && b.isBefore(a)) ? b : a;

  /// Задание по таймеру: бэкап, если пора, иначе проверка. Ошибки запуска
  /// — только в журнал.
  void _scheduled() => unawaited(
    _startScheduled().then<void>(
      (_) {},
      onError: (Object e) {
        _log.warning(LogEvent('schedule_skipped', {'reason': _describe(e)}));
        _reschedule();
      },
    ),
  );

  Future<void> _startScheduled() async {
    final soon = DateTime.now().add(const Duration(seconds: 1));
    final JobKind kind;
    if (_nextAt case final at? when !at.isAfter(soon)) {
      kind = JobKind.backup;
    } else if (_nextVerifyAt case final at? when !at.isAfter(soon)) {
      kind = JobKind.verify;
    } else {
      _reschedule();
      return;
    }
    if (settings.onlyOnAcPower && await power.onBattery() == true) {
      if (!_waitingForPower) {
        _log.info(LogEvent('waiting_for_power', {'kind': kind.name}));
      }
      _waitingForPower = true;
      _reschedule();
      return;
    }
    _waitingForPower = false;
    final trigger = kind == JobKind.backup && state.interrupted != null
        ? 'resume'
        : 'schedule';
    await _run(kind, trigger);
  }

  /// Пока идёт бэкап по расписанию с `onlyOnAcPower`, следить за питанием:
  /// от батареи — остановить с продолжением.
  void _watchPower(RunningJob job) {
    if (!settings.onlyOnAcPower ||
        job.kind != JobKind.backup ||
        job.trigger == 'manual') {
      return;
    }
    _powerWatch = Timer.periodic(powerRetry, (_) async {
      if (!identical(_job, job) || job.cancel.isCancelled) return;
      if (await power.onBattery() != true) return;
      _log.info(const LogEvent('on_battery', {'action': 'suspend'}));
      _waitingForPower = true;
      job
        ..onBattery = true
        ..cancel.cancel();
    });
  }

  // --- Сон, пробуждение, сеть (5.6.3) -------------------------------------

  void _onSystem(SystemEvent event) {
    if (_stopping != null) return;
    switch (event) {
      case SystemEvent.sleep:
        _log.info(const LogEvent('sleep'));
        _asleep = true;
        _timer?.cancel();
        _timer = null;
        if (_job case final job?
            when job.kind == JobKind.backup && !job.cancel.isCancelled) {
          // Остановить с продолжением, пока logind ждёт (задержка сна).
          job
            ..asleep = true
            ..cancel.cancel();
          final inhibit = job.inhibit;
          unawaited(
            (_jobDone ?? Future<void>.value())
                .timeout(const Duration(seconds: 4), onTimeout: () {})
                .whenComplete(() => inhibit?.release()),
          );
        }
      case SystemEvent.wake || SystemEvent.networkUp:
        _log.info(LogEvent(event == SystemEvent.wake ? 'wake' : 'network_up'));
        _asleep = false;
        _retrySoon = true;
        _wakeTimer?.cancel();
        _wakeTimer = Timer(wakeDelay, () {
          if (_job == null) _reschedule();
        });
    }
  }

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
    try {
      return await _adoptKeys(keys, device, remember: remember);
    } finally {
      keys.dispose();
      device?.dispose();
    }
  }

  /// Ключи открыты паролем (`unlock`, вход, новая учётная запись):
  /// сохранить для работы без пароля ([remember]) или держать в памяти,
  /// затем запустить расписание. [keys] и [device] остаются у вызывающего.
  Future<Map<String, Object?>> _adoptKeys(
    AccountKeys keys,
    DeviceKeys? device, {
    required bool remember,
  }) async {
    String? notRemembered;
    if (remember) {
      try {
        await vault.remember(keys, device);
      } on SecretStoreException catch (e) {
        notRemembered = e.message;
      }
    }
    _memoryKeys?.dispose();
    _memoryKeys = !remember || notRemembered != null
        ? KeyMaterial.of(keys, device)
        : null;
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

  /// Ключи агента без пароля для метода учётной записи (`account.devices`,
  /// `account.revoke`); нет — `keys_required`.
  Future<Map<String, Object?>> _withKeys(
    Future<Map<String, Object?>> Function(AccountKeys, DeviceKeys?) body,
  ) async {
    final material = await _material();
    if (material == null) {
      _publishStatus();
      throw ControlException('keys_required', _keysProblem ?? 'нужен пароль');
    }
    try {
      final (keys, device) = await material.open(crypto);
      try {
        return await body(keys, device);
      } finally {
        keys.dispose();
        device?.dispose();
      }
    } finally {
      if (!identical(material, _memoryKeys)) material.dispose();
    }
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
    _watchPower(job);
    if (kind == JobKind.backup) {
      _retrySoon = false;
      unawaited(
        systemEvents.inhibitSleep('идёт бэкап').then((inhibit) {
          if (identical(_job, job)) {
            job.inhibit = inhibit;
          } else {
            unawaited(inhibit?.release());
          }
        }),
      );
    }
    _publishStatus();
    unawaited(
      _execute(job, keys, params).whenComplete(() {
        _powerWatch?.cancel();
        _powerWatch = null;
        unawaited(job.inhibit?.release());
        if (!identical(keys, _memoryKeys)) keys.dispose();
        _job = null;
        _jobDone = null;
        completer.complete();
        _reschedule();
        unawaited(_checkHealth());
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
        kind: job.kind.name,
        trigger: job.trigger,
        startedAt: job.startedAt,
        finishedAt: DateTime.now(),
        outcome: result.$1,
        result: result.$2,
      );
      if (job.kind == JobKind.backup) state.interrupted = null;
    } on CancelledException {
      // Незаконченный бэкап продолжится после паузы или перезапуска.
      record = JobRecord(
        kind: job.kind.name,
        trigger: job.trigger,
        startedAt: job.startedAt,
        finishedAt: DateTime.now(),
        outcome: JobOutcome.cancelled,
        result: {
          if (job.paused) 'reason': 'paused',
          if (job.onBattery) 'reason': 'on_battery',
          if (job.asleep) 'reason': 'sleep',
          if (job.kind == JobKind.backup) 'continues': true,
        },
      );
    } on Object catch (e, st) {
      final message = _describe(e);
      _log.warning(
        LogEvent('job_failed', {'kind': job.kind.name, 'reason': message}),
        e is CoreException || e is SessionException ? null : e,
        e is CoreException || e is SessionException ? null : st,
      );
      record = JobRecord(
        kind: job.kind.name,
        trigger: job.trigger,
        startedAt: job.startedAt,
        finishedAt: DateTime.now(),
        outcome: JobOutcome.failed,
        error: message,
      );
      // Повтор — по расписанию через retryMinutes, а не сразу.
      if (job.kind == JobKind.backup) state.interrupted = null;
    }
    state
      ..record(job.kind.name, record)
      ..save(paths.state);
    _log.info(
      LogEvent('job_finished', {
        'kind': job.kind.name,
        'outcome': record.outcome.name,
        ...record.result,
      }),
    );
    _control.publish('job_finished', {...record.toJson()});
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
    final excludes = [...config.excludes, ...settings.excludeRulesList];
    // Оценка объёма — параллельно, в своём isolate: обход синхронный.
    unawaited(
      _estimate(settings.paths, excludes).then<void>(
        (e) => job.estimate = e,
        onError: (Object e) {
          _log.fine(LogEvent('estimate_failed', {'reason': '$e'}));
        },
      ),
    );
    // Пул из 2 isolate, как у cli backup (docs/benchmarks.md, раздел 1.6.3).
    final encoder = await IsolateSegmentEncoder.start(2);
    final BackupResult result;
    try {
      result = await runBackup(
        crypto: crypto,
        keys: session.keys,
        index: session.index,
        fragments: session.fragments,
        objects: session.objects,
        placer: session.placer,
        paths: settings.paths,
        deviceId: config.deviceId,
        excludes: ExcludeRules(excludes),
        params: config.durability,
        encoder: encoder,
        cancel: job.cancel,
        progressInterval: const Duration(milliseconds: 500),
        onProgress: (p) => _progress(job, _backupProgress(job, p)),
      );
    } finally {
      await encoder.close();
    }
    // Снимок сохранён: очистка ниже уже не продолжение этого бэкапа.
    state
      ..interrupted = null
      ..save(paths.state);
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
        'excluded': result.report.excluded,
        'skipped': result.report.skipped.length,
        'skippedFiles': [
          for (final e in result.report.skipped.take(100))
            {'path': e.path, 'reason': e.reason.name, 'detail': ?e.detail},
        ],
        'warnings': [for (final w in result.warnings) w.name],
        'retention': await _cleanup(session, config),
      },
    );
  }

  Map<String, Object?> _backupProgress(RunningJob job, BackupProgress p) {
    final total = job.estimate;
    final ms = p.elapsed.inMilliseconds;
    final rate = ms < 1000 ? null : p.bytes * 1000 ~/ ms;
    final left = total == null ? null : total.bytes - p.bytes;
    return {
      'files': p.files,
      'bytes': p.bytes,
      'bytesRead': p.bytesRead,
      'newBytes': p.newBytes,
      'segmentsStored': p.segmentsStored,
      'elapsedMs': ms,
      'totalFiles': ?total?.files,
      'totalBytes': ?total?.bytes,
      'bytesPerSecond': ?rate,
      if (left != null && rate != null && rate > 0)
        'etaMs': (left < 0 ? 0 : left) * 1000 ~/ rate,
    };
  }

  /// Оценка объёма в отдельном isolate: обход синхронный (FFI к libc).
  Future<BackupEstimate> _estimate(List<String> roots, List<String> rules) =>
      Isolate.run(
        () => estimateBackup(
          roots,
          excludes: ExcludeRules(rules),
          maxEntries: 10000000,
        ),
      );

  /// Очистка по политике хранения после бэкапа (5.3.5): лишние снимки
  /// устройства — `forget`, затем сборка мусора. Ошибка очистки не делает
  /// бэкап неудачным: снимок уже сохранён, следующий бэкап повторит
  /// очистку.
  Future<Map<String, Object?>?> _cleanup(
    Session session,
    AppConfig config,
  ) async {
    final policy = config.retention;
    if (policy == null) return null;
    try {
      final report = await forgetByPolicy(
        catalog: _catalog(session),
        policy: policy,
        deviceId: config.deviceId,
      );
      final out = <String, Object?>{
        'kept': report.kept.length,
        'forgotten': report.forgotten.length,
      };
      if (report.forgotten.isNotEmpty) {
        final gc = await collectGarbage(
          crypto: crypto,
          keys: session.keys,
          index: session.index,
          fragments: session.fragments,
          objects: session.objects,
          releaser: session.releaser,
          locator: session.locator,
        );
        out
          ..['segmentsDeleted'] = gc.segmentsDeleted
          ..['bytesFreed'] = gc.bytesFreed
          ..['fragmentErrors'] = gc.fragmentErrors.length;
      }
      _log.info(LogEvent('retention', out));
      return out;
    } on CoreException catch (e) {
      _log.warning(LogEvent('retention_failed', {'reason': e.message}));
      return {'error': e.message};
    } on SessionException catch (e) {
      _log.warning(LogEvent('retention_failed', {'reason': e.message}));
      return {'error': e.message};
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
    final originalLocation = params['originalLocation'] == true;
    final target = params['target'] as String?;
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
      target: originalLocation ? null : Directory(target!),
      originalLocation: originalLocation,
      paths: paths,
      existing: _existingFiles(params),
      renameSuffix: params['renameSuffix'] as String? ?? 'restored',
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
        'waitingPaths': p.waitingPaths,
        'waitingReason': p.waitingReason,
        'nextRetryMs': p.nextRetry?.inMilliseconds,
        'waitLeftMs': p.waitLeft?.inMilliseconds,
        'segmentsFetched': p.segmentsFetched,
        'etaMs': p.eta?.inMilliseconds,
        'elapsedMs': p.elapsed.inMilliseconds,
      }),
    );
    return (
      result.isComplete ? JobOutcome.ok : JobOutcome.partial,
      <String, Object?>{
        'snapshotId': bytesToHex(id),
        'target': target,
        'originalLocation': originalLocation,
        'files': result.files,
        'directories': result.directories,
        'bytes': result.bytes,
        'skippedExisting': result.skippedExisting.length,
        'skippedPaths': result.skippedExisting.take(100).toList(),
        'renamed': [
          for (final (from, to) in result.renamed.take(100))
            {'path': from, 'restoredAs': to},
        ],
        'renamedCount': result.renamed.length,
        'errors': [
          for (final (path, reason) in result.errors.take(100))
            {'path': path, 'reason': reason},
        ],
      },
    );
  }

  /// Что делать с существующими файлами: `existing` (`skip`,
  /// `overwrite`, `keepBoth`), иначе прежний флаг `overwrite`.
  static ExistingFiles _existingFiles(Map<String, Object?> params) =>
      switch (params['existing']) {
        'skip' => ExistingFiles.skip,
        'overwrite' => ExistingFiles.overwrite,
        'keepBoth' => ExistingFiles.keepBoth,
        _ when params['overwrite'] == true => ExistingFiles.overwrite,
        _ => ExistingFiles.skip,
      };

  /// Проверка параметров `restore` до запуска задания.
  static void _checkRestore(Map<String, Object?> params) {
    final target = params['target'];
    if (params['originalLocation'] != true &&
        (target is! String || !Directory(target).isAbsolute)) {
      throw const ControlException(
        'bad_request',
        'target — абсолютный путь папки назначения, '
            'или originalLocation: true',
      );
    }
    final existing = params['existing'];
    if (existing != null &&
        !const {'skip', 'overwrite', 'keepBoth'}.contains(existing)) {
      throw const ControlException(
        'bad_request',
        'existing — skip, overwrite или keepBoth',
      );
    }
    final suffix = params['renameSuffix'];
    if (suffix != null &&
        (suffix is! String ||
            suffix.isEmpty ||
            suffix.length > 40 ||
            suffix.contains(RegExp(r'[/\\\x00-\x1f]')))) {
      throw const ControlException(
        'bad_request',
        'renameSuffix — до 40 символов без разделителей пути',
      );
    }
    final paths = params['paths'];
    if (paths != null &&
        (paths is! List<Object?> || paths.any((p) => p is! String))) {
      throw const ControlException('bad_request', 'paths — список строк');
    }
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

  /// Прочитанные каталоги снимков для постраничного `tree`: каталог на
  /// миллион файлов не перечитывается на каждой странице. Снимки не
  /// меняются, поэтому кеш не устаревает; `lock` его очищает.
  final _dirCache = <String, List<pb.Node>>{};
  static const _dirCacheSize = 16;

  /// Каталог снимка: `path` — имена от корня, `offset` и `limit` — для
  /// ленивой загрузки больших каталогов (5.4.1).
  Future<Map<String, Object?>> _tree(Map<String, Object?> params) {
    final path = _namePath(params['path'] ?? const <Object?>[]);
    final offset = params['offset'] ?? 0;
    final limit = params['limit'] ?? 1000;
    if (offset is! int ||
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
      final key = '${bytesToHex(id)}\u0000${path.join('\u0000')}';
      var nodes = _dirCache.remove(key);
      if (nodes == null) {
        nodes = await _browser(session).list(id, path);
        if (_dirCache.length >= _dirCacheSize) {
          _dirCache.remove(_dirCache.keys.first);
        }
      }
      _dirCache[key] = nodes;
      return {
        'total': nodes.length,
        'entries': [
          for (final n in nodes.skip(offset).take(limit)) _nodeJson(n),
        ],
      };
    });
  }

  /// Поиск по имени в снимке (5.4.1): `query` — часть имени или шаблон
  /// с `*` и `?`, `under` — каталог, `limit` — до 1000.
  Future<Map<String, Object?>> _search(Map<String, Object?> params) {
    final query = params['query'];
    final under = _namePath(params['under'] ?? const <Object?>[]);
    final limit = params['limit'] ?? 200;
    if (query is! String ||
        query.trim().isEmpty ||
        query.length > 200 ||
        limit is! int ||
        limit < 1 ||
        limit > 1000) {
      throw const ControlException(
        'bad_request',
        'query — от 1 до 200 символов, 1 ≤ limit ≤ 1000',
      );
    }
    return _query((session) async {
      final id = await _snapshotId(session, params['snapshot']);
      final watch = Stopwatch()..start();
      final found = await _browser(session)
          .search(id, query.trim(), under: under, limit: limit);
      return {
        'matches': [
          for (final m in found.matches) {'path': m.path, ..._nodeJson(m.node)},
        ],
        'truncated': found.truncated,
        'scanned': found.scanned,
        'elapsedMs': watch.elapsedMilliseconds,
      };
    });
  }

  /// Версии пути во всех снимках (5.4.1), от старых к новым.
  Future<Map<String, Object?>> _versions(Map<String, Object?> params) {
    final path = _namePath(params['path']);
    if (path.isEmpty) {
      throw const ControlException('bad_request', 'path — не пустой');
    }
    return _query((session) async {
      final listing = await _catalog(session).list();
      final versions = await _browser(session)
          .versions(listing.snapshots, path);
      return {
        'versions': [
          for (final v in versions)
            {
              'snapshot': bytesToHex(v.snapshot.snapshotId),
              'createdAt': DateTime.fromMillisecondsSinceEpoch(
                v.snapshot.createdAtUnixMs.toInt(),
                isUtc: true,
              ).toIso8601String(),
              'hostname': v.snapshot.hostname,
              'present': v.node != null,
              'changed': v.changed,
              if (v.node case final n?) ..._nodeJson(n),
            },
        ],
        'warnings': [for (final w in listing.warnings) w.name],
      };
    });
  }

  SnapshotBrowser _browser(Session session) => SnapshotBrowser(
    crypto: crypto,
    keys: session.keys,
    index: session.index,
    fragments: session.fragments,
    objects: session.objects,
    locator: session.locator,
  );

  static List<String> _namePath(Object? path) {
    if (path is! List<Object?> || path.any((p) => p is! String)) {
      throw const ControlException('bad_request', 'path — список имён');
    }
    return path.cast<String>();
  }

  static Map<String, Object?> _nodeJson(pb.Node n) => {
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
  };

  // --- Локальный API ------------------------------------------------------

  Map<String, Object?> statusJson() => {
    'version': appVersion,
    'daemonApiVersion': daemonApiVersion,
    'status': status.name,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'home': paths.home.dir.path,
    'configured': paths.home.initialized,
    'job': _job?.toJson(),
    'nextBackupAt': _nextAt?.toUtc().toIso8601String(),
    'nextVerifyAt': _nextVerifyAt?.toUtc().toIso8601String(),
    'interrupted': state.interrupted != null,
    'lastBackup': state.lastBackup?.toJson(),
    'lastOkBackupAt': state.lastOkBackupAt?.toUtc().toIso8601String(),
    'lastVerify': state.lastVerify?.toJson(),
    'lastRestore': state.lastRestore?.toJson(),
    'health': health.toJson(),
    'keys': _keysJson(),
    'settings': _settingsJson(),
  };

  /// Здоровье бэкапа сейчас (5.3.4).
  HealthReport get health => assessHealth(settings, state);

  /// Настройки агента и политика хранения из `config.json`.
  Map<String, Object?> _settingsJson() {
    final json = settings.toJson();
    if (paths.home.initialized) {
      try {
        json['retention'] = AppConfig.load(paths.home).retention?.toJson();
      } on ConfigException {
        // Испорченный config.json покажет первое же задание.
      }
    }
    return json;
  }

  /// После задания: событие `health` при перемене и уведомление ОС, когда
  /// данные требуют внимания (один раз на одно и то же состояние).
  Future<void> _checkHealth() async {
    final report = health;
    final signature = report.signature;
    if (signature != _healthSignature) {
      _healthSignature = signature;
      _control.publish('health', report.toJson());
    }
    if (report.state != HealthState.attention) {
      if (state.notifiedHealth != null) {
        state
          ..notifiedHealth = null
          ..save(paths.state);
      }
      return;
    }
    if (state.notifiedHealth == signature) return;
    final reasons = [
      for (final r in report.reasons)
        if (r.attention) r.message,
    ];
    final shown = await notifier.notify(
      'Бэкап требует внимания',
      reasons.join('\n'),
      critical: report.reasons.any((r) => r.code == 'unrecoverable'),
    );
    _log.warning(
      LogEvent('health_attention', {'reasons': reasons, 'notified': shown}),
    );
    state
      ..notifiedHealth = signature
      ..save(paths.state);
  }

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
          final patch = {...params};
          final retention = patch.containsKey('retention');
          final policy = patch.remove('retention');
          final AgentSettings next;
          final RetentionPolicy? nextPolicy;
          try {
            next = settings.merge(patch);
            nextPolicy = switch (policy) {
              null => null,
              final Map<String, Object?> m => RetentionPolicy.fromJson(m),
              _ => throw const ConfigException(
                key: 'retention',
                reason: 'нужен объект или null',
              ),
            };
          } on ConfigException catch (e) {
            throw ControlException('bad_request', e.message);
          }
          if (retention) {
            if (!paths.home.initialized) {
              throw const ControlException(
                'not_configured',
                'нет учётной записи на этом устройстве',
              );
            }
            AppConfig.load(paths.home)
              ..retention = nextPolicy
              ..save(paths.home);
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
              'hours': ?next.hours?.toJson(),
              'onlyOnAcPower': next.onlyOnAcPower,
              if (retention) 'retention': nextPolicy?.toJson(),
            }),
          );
          _waitingForPower = false;
          _reschedule();
          unawaited(_checkHealth());
        }
        return _settingsJson();
      case 'estimate':
        return await _estimateJson(params);
      case 'history':
        return _history(params);
      case 'backup':
        return {'started': await _run(JobKind.backup, 'manual')};
      case 'verify':
        return {'started': await _run(JobKind.verify, 'manual', params)};
      case 'restore':
        _checkRestore(params);
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
      case 'search':
        return await _search(params);
      case 'versions':
        return await _versions(params);
      case 'health':
        return health.toJson();
      case 'unlock':
        return await _unlock(params);
      case 'lock':
        _dirCache.clear();
        _memoryKeys?.dispose();
        _memoryKeys = null;
        return {'keys': _keysJson()};
      case 'forget_keys':
        _dirCache.clear();
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
        if (method.startsWith('account.')) {
          return await _account.handle(method, params);
        }
        if (method.startsWith('keeper.')) {
          return await _keeper.handle(method, params);
        }
        throw ControlException('unknown_method', 'неизвестный метод $method');
    }
  }

  /// Оценка объёма: папки и исключения из [params] или из настроек.
  Future<Map<String, Object?>> _estimateJson(
    Map<String, Object?> params,
  ) async {
    final AgentSettings draft;
    try {
      draft = settings.merge({
        for (final key in ['paths', 'excludes', 'excludePresets'])
          if (params.containsKey(key)) key: params[key],
      });
    } on ConfigException catch (e) {
      throw ControlException('bad_request', e.message);
    }
    for (final p in draft.paths) {
      if (!Directory(p).isAbsolute) {
        throw ControlException('bad_request', 'путь не абсолютный: $p');
      }
    }
    final common = paths.home.initialized
        ? AppConfig.load(paths.home).excludes
        : const <String>[];
    final watch = Stopwatch()..start();
    final estimate = await _estimate(draft.paths, [
      ...common,
      ...draft.excludeRulesList,
    ]);
    return {...estimate.toJson(), 'elapsedMs': watch.elapsedMilliseconds};
  }

  /// История заданий от новых к старым: `kind` — только такие, `limit` —
  /// не больше (по умолчанию 50).
  Map<String, Object?> _history(Map<String, Object?> params) {
    final kind = params['kind'];
    final limit = params['limit'] ?? 50;
    if ((kind != null && kind is! String) ||
        limit is! int ||
        limit < 1 ||
        limit > AgentState.historyLimit) {
      throw const ControlException(
        'bad_request',
        'kind — backup, verify или restore; 1 ≤ limit ≤ 100',
      );
    }
    return {
      'jobs': [
        for (final r
            in state.history.reversed
                .where((r) => kind == null || r.kind == kind)
                .take(limit))
          r.toJson(),
      ],
    };
  }

  // --- Остановка ----------------------------------------------------------

  void _signal(ProcessSignal signal) => unawaited(stop(reason: '$signal'));

  /// Остановка: задание отменяется (бэкап продолжится при следующем
  /// запуске), затем закрываются API и журнал.
  Future<void> stop({String reason = 'request'}) => _stopping ??= _stop(reason);

  Future<void> _stop(String reason) async {
    _log.info(LogEvent('stopping', {'reason': reason}));
    _timer?.cancel();
    _wakeTimer?.cancel();
    _powerWatch?.cancel();
    _job?.cancel.cancel();
    _publishStatus();
    await idle;
    await _systemSub?.cancel();
    await systemEvents.close();
    for (final s in _signals) {
      await s.cancel();
    }
    await _control.close();
    _account.dispose();
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
