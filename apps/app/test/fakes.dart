import 'dart:async';

import 'package:app/src/app.dart';
import 'package:app/src/app_scope.dart';
import 'package:app/src/services/background.dart';
import 'package:app/src/services/folder_picker.dart';
import 'package:app/src/services/preferences.dart';
import 'package:app/src/services/process_link.dart';
import 'package:app/src/services/tray.dart';
import 'package:app/src/services/update_controller.dart';
import 'package:daemon_kit/daemon_kit.dart';
import 'package:flutter/material.dart';

/// Фоновый процесс для виджет-тестов: состояние задаёт тест, вызовы
/// записываются и отвечают функцией [answer].
final class FakeProcess extends ChangeNotifier implements BackgroundProcess {
  new({this.state = LinkState.connected, this.status, this.answer});

  @override
  LinkState state;

  @override
  Map<String, Object?>? status;

  @override
  String? problem;

  final calls = <(String, Map<String, Object?>)>[];
  Future<Map<String, Object?>> Function(String, Map<String, Object?>)? answer;
  final _events = StreamController<ControlEvent>.broadcast();

  @override
  Stream<ControlEvent> get events => _events.stream;

  /// Событие процесса, как от настоящего агента.
  void emit(String name, Map<String, Object?> data) =>
      _events.add(ControlEvent(name, data));

  /// Параметры последнего вызова [method].
  Map<String, Object?> last(String method) =>
      calls.lastWhere((c) => c.$1 == method).$2;

  void update({LinkState? state, Map<String, Object?>? status}) {
    if (state != null) this.state = state;
    if (status != null) this.status = status;
    notifyListeners();
  }

  @override
  Future<Map<String, Object?>> call(
    String method, [
    Map<String, Object?> params = const {},
    Duration timeout = const Duration(seconds: 10),
  ]) async {
    calls.add((method, params));
    if (state != LinkState.connected) {
      throw const ControlException('unavailable', 'нет связи');
    }
    return await answer?.call(method, params) ?? const {};
  }
}

/// Состояние агента, как в `docs/ops/agent.md`.
Map<String, Object?> agentStatus({
  String status = 'idle',
  Map<String, Object?>? job,
  Map<String, Object?>? lastBackup,
  String? nextBackupAt,
  bool interrupted = false,
  bool configured = true,
  Map<String, Object?>? health,
  Map<String, Object?>? lastVerify,
  Map<String, Object?> settings = const {},
}) => {
  'status': status,
  'configured': configured,
  'job': job,
  'lastBackup': lastBackup,
  'nextBackupAt': nextBackupAt,
  'interrupted': interrupted,
  'lastVerify': lastVerify,
  'health': health ?? {'state': 'ok', 'reasons': <Object?>[]},
  'settings': {
    'paths': ['/home/user/Документы'],
    'excludes': <String>[],
    'excludePresets': ['temporary', 'caches', 'trash'],
    'intervalMinutes': 60,
    'retryMinutes': 10,
    'hours': null,
    'onlyOnAcPower': false,
    'verifyIntervalHours': 24,
    'retention': {
      'last': 1,
      'hourly': 24,
      'daily': 7,
      'weekly': 4,
      'monthly': 12,
    },
    ...settings,
  },
};

Map<String, Object?> nodeStatus() => {
  'state': 'running',
  'quotaBytes': 2 << 40,
  'usedBytes': 3 << 30,
  'fragments': 1200,
  'connections': 3,
  'reachability': {'reachable': true},
};

Widget testApp(
  BackgroundProcess agent,
  BackgroundProcess node, {
  Preferences? preferences,
  FolderPicker? pickFolder,
  TrayHost? tray,
  BackgroundControl? background,
  UpdateController? updates,
}) => App(
  services: AppServices(
    agent: agent,
    node: node,
    preferences: preferences ?? Preferences(),
    pickFolder: pickFolder ?? ({initialDirectory}) async => null,
    tray: tray,
    background: background,
    updates: updates,
  ),
);

/// Значок в трее для тестов: последнее меню и команды от теста.
final class FakeTray implements TrayHost {
  new({this.isAvailable = true});

  bool isAvailable;
  String? status;
  List<TrayItem> items = const [];
  int menus = 0;
  final _actions = StreamController<String>.broadcast();

  void tap(String id) => _actions.add(id);

  TrayItem item(String id) => items.firstWhere((i) => i.id == id);

  @override
  Stream<String> get actions => _actions.stream;

  @override
  Future<bool> available() async => isAvailable;

  @override
  Future<void> setMenu(String status, List<TrayItem> items) async {
    this.status = status;
    this.items = items;
    menus++;
  }
}

/// Службы ОС для тестов.
final class FakeBackground extends ChangeNotifier implements BackgroundControl {
  new({
    this.available = true,
    this.agentState = ServiceState.running,
    this.nodeState = ServiceState.running,
  });

  @override
  bool available;

  @override
  ServiceState? agentState;

  @override
  ServiceState? nodeState;

  @override
  bool autostart = false;

  @override
  String? problem;

  final calls = <String>[];

  @override
  String get kind => 'fake';

  @override
  Future<void> refresh() async => notifyListeners();

  @override
  Future<void> installAgent() async {
    calls.add('install');
    agentState = ServiceState.running;
    notifyListeners();
  }

  @override
  Future<void> uninstallAgent() async {
    calls.add('uninstall');
    agentState = ServiceState.notInstalled;
    notifyListeners();
  }

  @override
  Future<void> startService(String name) async {
    calls.add('start $name');
    _set(name, ServiceState.running);
    notifyListeners();
  }

  @override
  Future<void> stopService(String name) async {
    calls.add('stop $name');
    _set(name, ServiceState.stopped);
    notifyListeners();
  }

  @override
  Future<void> restartService(String name) async {
    calls.add('restart $name');
    _set(name, ServiceState.running);
    notifyListeners();
  }

  void _set(String name, ServiceState state) {
    switch (name) {
      case 'agent':
        agentState = state;
      case 'node':
        nodeState = state;
    }
  }

  @override
  Future<void> setAutostart({required bool enabled}) async {
    calls.add('autostart $enabled');
    autostart = enabled;
    notifyListeners();
  }
}
