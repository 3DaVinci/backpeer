import 'dart:io';

import 'package:agent/agent.dart';
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

  /// Значок запускается при входе.
  bool get autostart;

  /// Последняя ошибка установки или удаления.
  String? get problem;

  Future<void> refresh();

  Future<void> installAgent();

  Future<void> uninstallAgent();

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
  String? problem;

  @override
  bool get available => services.available && bundle != null;

  @override
  String get kind => services.kind;

  @override
  bool get autostart => loginItem.enabled;

  ClientServices get _client => ClientServices(services: services, home: home);

  @override
  Future<void> refresh() async {
    try {
      agentState = await _client.agentState();
    } on ServiceException catch (e) {
      problem = e.message;
    }
    notifyListeners();
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
