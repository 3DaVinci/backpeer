import 'dart:async';

import 'package:app/src/app.dart';
import 'package:app/src/app_scope.dart';
import 'package:app/src/services/preferences.dart';
import 'package:app/src/services/process_link.dart';
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
}) => {
  'status': status,
  'configured': configured,
  'job': job,
  'lastBackup': lastBackup,
  'nextBackupAt': nextBackupAt,
  'interrupted': interrupted,
  'settings': {
    'paths': ['/home/user/Документы'],
    'excludes': <String>[],
    'intervalMinutes': 60,
    'retryMinutes': 10,
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
}) => App(
  services: AppServices(
    agent: agent,
    node: node,
    preferences: preferences ?? Preferences(),
  ),
);
