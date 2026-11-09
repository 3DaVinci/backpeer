import 'dart:async';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:agent/agent.dart' show ClientServices;
import 'package:app/src/app.dart';
import 'package:app/src/app_scope.dart';
import 'package:app/src/services/background.dart';
import 'package:app/src/services/crash_reporter.dart';
import 'package:app/src/services/endpoints.dart';
import 'package:app/src/services/preferences.dart';
import 'package:app/src/services/process_link.dart';
import 'package:app/src/services/tray.dart';
import 'package:app/src/services/update_config.dart';
import 'package:app/src/services/update_control.dart';
import 'package:app/src/services/update_controller.dart';
import 'package:daemon_kit/daemon_kit.dart';
import 'package:flutter/material.dart';

void main() {
  // Каналу значка в трее нужна привязка до runApp.
  WidgetsFlutterBinding.ensureInitialized();
  final endpoints = Endpoints.resolve();
  final agent = ProcessLink(
    connect: () => ControlClient.connect(endpoints.agent),
    // Все события агента: status, progress, job_finished, keys_required.
    subscribe: const [],
    // События приходят и так, но опрос нужен, чтобы заметить молчащий
    // процесс: зависший агент соединение не рвёт, а событий не шлёт.
    poll: const Duration(seconds: 15),
  )..start();
  final node = ProcessLink(
    connect: () => ControlClient.connect(endpoints.node),
    // У node событий нет — опрос.
    poll: const Duration(seconds: 5),
  )..start();
  final preferences = Preferences.load(
    File('${endpoints.home.dir.path}/app/preferences.json'),
  );
  final tray = ChannelTrayHost();
  final background = OsBackground.forPlatform();

  // Автообновление (5.8.2): адрес и ключ вшиты в сборку. Нет их (запуск из
  // исходников) или версия не стабильная — обновления не проверяются.
  final updateConfig = UpdateConfig.resolve();
  final updates = updateConfig == null
      ? null
      : UpdateController(
          control: OsUpdater(
            baseUri: updateConfig.baseUri,
            currentVersion: updateConfig.currentVersion,
            preferences: preferences,
            acceptedKeys: updateConfig.acceptedKeys,
            stopServices: () async {
              await background.stopService(ClientServices.agentName);
              await background.stopService(ClientServices.nodeName);
            },
            appExecutable: Platform.resolvedExecutable,
          ),
          preferences: preferences,
          canApply: () {
            final status = agent.status;
            // Нет связи — бэкап не идёт; первый запуск без учётной записи и
            // идущий бэкап обновление не прерывают.
            if (status == null) return true;
            return status['configured'] == true && status['job'] == null;
          },
        );

  // Отчёты о сбоях (5.9.3): только с согласия пользователя и без путей и
  // ключей — очистка внутри CrashReporter.
  final crashReporter = CrashReporter(
    file: File('${endpoints.home.dir.path}/app/crash-reports.jsonl'),
  );
  void report(Object error, StackTrace stack) {
    if (preferences.crashReports) {
      unawaited(crashReporter.capture(error, stack));
    }
  }

  FlutterError.onError = (details) =>
      report(details.exception, details.stack ?? StackTrace.current);
  PlatformDispatcher.instance.onError = (error, stack) {
    report(error, stack);
    return true;
  };

  runApp(
    App(
      services: AppServices(
        agent: agent,
        node: node,
        coordinator: endpoints.coordinator,
        preferences: preferences,
        tray: tray,
        background: background,
        updates: updates,
      ),
    ),
  );
  // Служба агента и значок при входе (5.6.1, 5.6.2) — после первого кадра:
  // каналу значка нужен движок.
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await background.ensure(
      wantService: preferences.backgroundService,
      wantAutostart: preferences.trayAtLogin,
      trayAvailable: await tray.available(),
    );
    updates?.start();
  });
  // Связь с агентом пропала, а служба ОС числится работающей — перезапустить
  // её: агент мог зависнуть или потерять свой сокет. Без этого приложение
  // остаётся в состоянии «агент запущен, но подключиться не к чему» до
  // перезапуска вручную.
  Timer.periodic(OsBackground.healInterval, (_) {
    unawaited(background.healAgent(agent.state));
  });
}
