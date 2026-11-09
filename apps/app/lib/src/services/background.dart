import 'dart:async';
import 'dart:io';

import 'package:agent/agent.dart';
import 'package:app/src/services/process_link.dart' show LinkState;
import 'package:core/core.dart' show appVersion;
import 'package:daemon_kit/daemon_kit.dart';
import 'package:flutter/foundation.dart';

/// Фоновая работа для экрана «Настройки» (задачи 5.6.1, 5.6.2): служба ОС
/// агента бэкапа и запуск значка при входе. Хранителя ставит службой сам
/// агент при включении роли.
abstract interface class BackgroundControl implements Listenable {
  /// Службы ОС есть и программы агента найдены — службу можно ставить.
  bool get available;

  /// Чем: `systemd`, `launchd`, `task-scheduler`, `none`.
  String get kind;

  /// `null` — ещё не узнали.
  ServiceState? get agentState;

  /// Служба хранителя; `notInstalled` — роль не включалась.
  ServiceState? get nodeState;

  /// Значок запускается при входе.
  bool get autostart;

  /// Последняя ошибка установки или удаления.
  String? get problem;

  Future<void> refresh();

  Future<void> installAgent();

  Future<void> uninstallAgent();

  /// Запустить установленную службу ([ClientServices.agentName] или
  /// [ClientServices.nodeName]).
  Future<void> startService(String name);

  /// Остановить: сначала нормально, через локальный API процесса, затем
  /// менеджером служб (зависший процесс).
  Future<void> stopService(String name);

  Future<void> restartService(String name);

  Future<void> setAutostart({required bool enabled});
}

/// [BackgroundControl] для этой ОС: службы — [UserServices], запуск при
/// входе — [LoginItem]. Программы агента и хранителя — из пакета
/// приложения ([DaemonBundle]); из AppImage они сначала копируются в
/// постоянное место ([PersistentDaemons], задача 5.7.3).
final class OsBackground extends ChangeNotifier implements BackgroundControl {
  new({
    required this.services,
    required this.loginItem,
    required this.bundle,
    this.home,
    this.persistent,
    this.version = appVersion,
    Map<String, String>? environment,
  }) : _env = environment ?? Platform.environment;

  factory forPlatform({Map<String, String>? environment}) {
    final env = environment ?? Platform.environment;
    return OsBackground(
      services: UserServices.forPlatform(environment: env),
      loginItem: LoginItem.forPlatform(environment: env),
      bundle: DaemonBundle.locate(environment: env),
      home: env['FS_HOME'],
      persistent: PersistentDaemons.needed(env)
          ? PersistentDaemons.forUser(env)
          : null,
      environment: env,
    );
  }

  final UserServices services;
  final LoginItem loginItem;

  /// Программы из пакета; `null` — не найдены (запуск из исходников без
  /// `tool/build_exe.dart`).
  final DaemonBundle? bundle;

  /// Каталог программы не по умолчанию (`FS_HOME`).
  final String? home;
  final PersistentDaemons? persistent;
  final String version;
  final Map<String, String> _env;

  @override
  ServiceState? agentState;

  @override
  ServiceState? nodeState;

  @override
  String? problem;

  @override
  bool get available => services.available && bundle != null;

  @override
  String get kind => services.kind;

  @override
  bool get autostart => loginItem.enabled;

  ClientServices get _client =>
      ClientServices(services: services, home: home, environment: _env);

  @override
  Future<void> refresh() async {
    try {
      agentState = await _client.agentState();
      nodeState = await _client.nodeState();
    } on ServiceException catch (e) {
      problem = e.message;
    }
    notifyListeners();
  }

  /// Сколько проверок подряд связь с агентом должна быть недоступна,
  /// прежде чем перезапускать службу.
  static const healAfter = 3;

  /// Как часто приложение проверяет связь для [healAgent].
  static const healInterval = Duration(seconds: 15);

  /// Не перезапускать службу чаще, чем раз в это время.
  static const healCooldown = Duration(minutes: 1);

  int _unavailable = 0;
  DateTime? _lastHeal;

  /// Служба ОС числится работающей, а связи с агентом нет: перезапускаем
  /// её. Так приложение выходит из состояния «агент запущен, но
  /// подключиться не к чему» — агент завис (не отвечает по сокету) или
  /// потерял свой сокет (пакет отключили, файл удалили). [link] — состояние
  /// связи ([LinkState.connected] — связь есть), [now] — для тестов.
  /// `true` — служба перезапущена.
  Future<bool> healAgent(LinkState link, {DateTime? now}) async {
    if (link == LinkState.connected) {
      _unavailable = 0;
      return false;
    }
    _unavailable++;
    if (_unavailable < healAfter) return false;
    final at = now ?? DateTime.now();
    if (_lastHeal case final last? when at.difference(last) < healCooldown) {
      return false;
    }
    await refresh();
    // Службы нет или она стоит — работу с ней делает сам пользователь.
    if (agentState != ServiceState.running) return false;
    _lastHeal = at;
    _unavailable = 0;
    try {
      // Перезапуск, а не stop + start: у launchd `bootout` и `bootstrap`
      // подряд иногда не срабатывают, и служба осталась бы выгруженной.
      await services.restart(ClientServices.agentName);
      problem = null;
      return true;
    } on ServiceException catch (e) {
      problem = e.message;
      return false;
    } finally {
      notifyListeners();
      unawaited(refresh());
    }
  }

  /// При запуске приложения: служба агента и значок при входе, если
  /// пользователь их не выключал ([wantService], [wantAutostart]). Новая
  /// версия из AppImage — копия программ обновляется, службы
  /// перезапускаются.
  Future<void> ensure({
    required bool wantService,
    required bool wantAutostart,
    required bool trayAvailable,
  }) async {
    await refresh();
    if (!available) return;
    try {
      final updated = _syncPersistent();
      if (wantService && (agentState == ServiceState.notInstalled || updated)) {
        if (updated) {
          // Хранителя перезапустит агент своей программой новой версии.
          await services.stop(ClientServices.nodeName).catchError((_) {});
          await services.stop(ClientServices.agentName).catchError((_) {});
        }
        await _client.installAgent(_agentExecutable()!);
      }
      if (wantAutostart && trayAvailable && !loginItem.enabled) {
        await setAutostart(enabled: true);
      }
      problem = null;
    } on ServiceException catch (e) {
      problem = e.message;
    } on FileSystemException catch (e) {
      problem = '${e.message}: ${e.path}';
    }
    await refresh();
  }

  bool _syncPersistent() {
    final p = persistent;
    final b = bundle;
    if (p == null || b == null) return false;
    return p.sync(b, version);
  }

  /// Программа агента, на которую укажет служба: постоянная копия или
  /// пакет.
  String? _agentExecutable() {
    if (persistent case final p?) {
      return DaemonBundle(p.target.path).executable('agent');
    }
    return bundle?.executable('agent');
  }

  @override
  Future<void> installAgent() async {
    try {
      _syncPersistent();
      final exe = _agentExecutable();
      if (exe == null) throw const ServiceException('нет программы агента');
      await _client.installAgent(exe);
      problem = null;
    } on ServiceException catch (e) {
      problem = e.message;
    }
    await refresh();
  }

  @override
  Future<void> uninstallAgent() async {
    try {
      await services.uninstall(ClientServices.agentName);
      problem = null;
    } on ServiceException catch (e) {
      problem = e.message;
    }
    await refresh();
  }

  @override
  Future<void> startService(String name) => _act(() async {
    if (await services.state(name) == ServiceState.notInstalled) {
      throw ServiceException(
        name == ClientServices.agentName
            ? 'служба агента бэкапа не установлена'
            : 'служба хранителя не установлена — включите роль на экране '
                  '«Хранитель»',
      );
    }
    await services.start(name);
  });

  @override
  Future<void> stopService(String name) => _act(() async {
    await _stopProcess(name);
    // Менеджер служб — на случай зависшего процесса: у Windows это
    // `schtasks /End`, у systemd/launchd — остановка, если она ещё идёт.
    try {
      await services.stop(name);
    } on ServiceException {
      // Служба не установлена или уже остановлена.
    }
  });

  @override
  Future<void> restartService(String name) => _act(() async {
    if (await services.state(name) == ServiceState.notInstalled) {
      throw ServiceException(
        name == ClientServices.agentName
            ? 'служба агента бэкапа не установлена'
            : 'служба хранителя не установлена — включите роль на экране '
                  '«Хранитель»',
      );
    }
    // Нормальная остановка через локальный API, затем менеджер служб:
    // так демон успевает дописать сегмент и отпустить папку. Если он
    // завис, менеджер завершит его принудительно.
    await _stopProcess(name);
    await services.restart(name);
  });

  /// Останавливает процесс через локальный API. `false` — процесса нет
  /// или API недоступен; принудительная остановка — за менеджером служб.
  Future<bool> _stopProcess(String name) async {
    try {
      return switch (name) {
        ClientServices.agentName => await _client.stopAgentProcess(),
        ClientServices.nodeName => await _client.stopNodeProcess(),
        _ => false,
      };
    } on Object {
      return false;
    }
  }

  /// Выполнить действие со службой, записать ошибку и обновить состояние.
  Future<void> _act(Future<void> Function() body) async {
    try {
      await body();
      problem = null;
    } on ServiceException catch (e) {
      problem = e.message;
    }
    // Дать службе перейти в новое состояние. На Windows состояние задания
    // спрашивается через PowerShell, поэтому не опрашиваем в цикле: одна
    // пауза и одно обновление.
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await refresh();
  }

  @override
  Future<void> setAutostart({required bool enabled}) async {
    try {
      if (enabled) {
        // AppImage — сам файл образа: путь внутри него временный.
        final exe = _env['APPIMAGE'] ?? Platform.resolvedExecutable;
        await loginItem.enable(exe, const ['--hidden']);
      } else {
        await loginItem.disable();
      }
      problem = null;
    } on ServiceException catch (e) {
      problem = e.message;
    }
    notifyListeners();
  }
}
