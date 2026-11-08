// Задачи 5.6.1, 5.7.2: приложение выходит из состояния «служба агента
// числится работающей, а подключиться не к чему». Агент может зависнуть
// (перестал отвечать по сокету) или потерять свой сокет — например, пакет
// запустили прямо из образа .dmg, а потом образ отключили. В таких случаях
// служба перезапускается, но не чаще раза в минуту.

import 'dart:io';

import 'package:app/src/services/background.dart';
import 'package:app/src/services/process_link.dart';
import 'package:daemon_kit/daemon_kit.dart';
import 'package:flutter_test/flutter_test.dart';

/// Службы ОС в памяти: что поставлено, что запущено и сколько раз
/// останавливали и запускали.
final class MemoryServices implements UserServices {
  final Map<String, ServiceSpec> installed = {'agent': _agentSpec};
  final Set<String> running = {'agent'};
  int stopCalls = 0;
  int startCalls = 0;
  int restarts = 0;

  static const _agentSpec = ServiceSpec(
    name: 'agent',
    description: 'агент',
    executable: '/bin/true',
    arguments: ['run'],
  );

  @override
  String get kind => 'memory';

  @override
  bool get available => true;

  @override
  String serviceName(String name) => '$servicePrefix-$name';

  @override
  Future<ServiceState> state(String name) async => !installed.containsKey(name)
      ? ServiceState.notInstalled
      : running.contains(name)
      ? ServiceState.running
      : ServiceState.stopped;

  @override
  Future<void> install(ServiceSpec spec, {bool start = true}) async {
    installed[spec.name] = spec;
    if (start) running.add(spec.name);
  }

  @override
  Future<void> uninstall(String name) async {
    installed.remove(name);
    running.remove(name);
  }

  @override
  Future<void> start(String name) async {
    startCalls++;
    running.add(name);
  }

  @override
  Future<void> stop(String name) async {
    stopCalls++;
    running.remove(name);
  }

  @override
  Future<void> restart(String name) async {
    restarts++;
    running.add(name);
  }
}

void main() {
  late Directory dir;
  late MemoryServices services;
  late OsBackground background;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('fs-heal-');
    services = MemoryServices();
    background = OsBackground(
      services: services,
      loginItem: LoginItem.forPlatform(environment: {'HOME': dir.path}),
      bundle: null,
      environment: {'HOME': dir.path},
    );
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('связь есть — службу не трогаем', () async {
    expect(await background.healAgent(LinkState.connected), isFalse);
    expect(services.restarts, 0);
  });

  test('служба запущена, связи нет три проверки подряд — перезапуск', () async {
    final at = DateTime(2026, 11, 7, 23);
    expect(await background.healAgent(LinkState.unavailable, now: at), isFalse);
    expect(await background.healAgent(LinkState.unavailable, now: at), isFalse);
    expect(services.restarts, 0);

    expect(await background.healAgent(LinkState.unavailable, now: at), isTrue);
    expect(services.restarts, 1);
    expect(services.running, contains('agent'));
    expect(background.problem, isNull);
  });

  test('счётчик сбрасывается, когда связь вернулась', () async {
    final at = DateTime(2026, 11, 7, 23);
    await background.healAgent(LinkState.unavailable, now: at);
    await background.healAgent(LinkState.unavailable, now: at);
    await background.healAgent(LinkState.connected, now: at);
    expect(await background.healAgent(LinkState.unavailable, now: at), isFalse);
    expect(services.restarts, 0);
  });

  test('повторный перезапуск — не чаще раза в минуту', () async {
    final at = DateTime(2026, 11, 7, 23);
    for (var i = 0; i < 3; i++) {
      await background.healAgent(LinkState.unavailable, now: at);
    }
    expect(services.restarts, 1);

    for (var i = 0; i < 3; i++) {
      await background.healAgent(
        LinkState.unavailable,
        now: at.add(const Duration(seconds: 30)),
      );
    }
    expect(services.restarts, 1, reason: 'кулдаун ещё не прошёл');

    for (var i = 0; i < 3; i++) {
      await background.healAgent(
        LinkState.unavailable,
        now: at.add(const Duration(minutes: 2)),
      );
    }
    expect(services.restarts, 2);
  });

  test('связь ещё устанавливается — тоже повод перезапустить', () async {
    final at = DateTime(2026, 11, 7, 23);
    for (var i = 0; i < 3; i++) {
      await background.healAgent(LinkState.connecting, now: at);
    }
    expect(services.restarts, 1);
  });

  test('служба не запущена — перезапускать нечего', () async {
    services.running.remove('agent');
    final at = DateTime(2026, 11, 7, 23);
    for (var i = 0; i < 3; i++) {
      expect(
        await background.healAgent(LinkState.unavailable, now: at),
        isFalse,
      );
    }
    expect(services.restarts, 0);
  });
}
