import 'dart:io';

import 'package:app/src/app.dart';
import 'package:app/src/app_scope.dart';
import 'package:app/src/services/endpoints.dart';
import 'package:app/src/services/preferences.dart';
import 'package:app/src/services/process_link.dart';
import 'package:daemon_kit/daemon_kit.dart';
import 'package:flutter/material.dart';

void main() {
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
  runApp(
    App(
      services: AppServices(
        agent: agent,
        node: node,
        coordinator: endpoints.coordinator,
        preferences: Preferences.load(
          File('${endpoints.home.dir.path}/app/preferences.json'),
        ),
      ),
    ),
  );
}
