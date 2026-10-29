import 'dart:io';

import 'package:app/src/app.dart';
import 'package:app/src/app_scope.dart';
import 'package:app/src/services/background.dart';
import 'package:app/src/services/endpoints.dart';
import 'package:app/src/services/preferences.dart';
import 'package:app/src/services/process_link.dart';
import 'package:app/src/services/tray.dart';
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
  runApp(
    App(
      services: AppServices(
        agent: agent,
        node: node,
        coordinator: endpoints.coordinator,
        preferences: preferences,
        tray: tray,
        background: background,
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
  });
}
