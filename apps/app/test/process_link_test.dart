import 'dart:io';

import 'package:app/src/services/process_link.dart';
import 'package:daemon_kit/daemon_kit.dart';
import 'package:flutter_test/flutter_test.dart';

/// [ProcessLink] против настоящего [ControlServer]: связь, события и
/// перезапуск процесса (задача 5.1.1). Без виджетов — настоящие сокеты.
void main() {
  late Directory dir;
  late ControlEndpoint endpoint;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('fs-app-link-');
    endpoint = ControlEndpoint.forDataDir(dir.path, process: 'агент бэкапа');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<void> until(bool Function() ready, String what) async {
    for (var i = 0; i < 200 && !ready(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    expect(ready(), isTrue, reason: what);
  }

  test('переживает перезапуск процесса: переподключение, свежий status, '
      'события', () async {
    var generation = 1;
    String? job;
    Future<ControlServer> serve() => ControlServer.bind(
      endpoint,
      (method, params) async => switch (method) {
        'status' => {'generation': generation, 'job': ?job},
        'backup' => {'started': true},
        _ => throw ControlException('unknown_method', method),
      },
    );
    final link = ProcessLink(
      connect: () => ControlClient.connect(endpoint),
      subscribe: const [],
      retry: const Duration(milliseconds: 20),
      maxRetry: const Duration(milliseconds: 100),
    );
    addTearDown(link.dispose);
    var notified = 0;
    link
      ..addListener(() => notified++)
      ..start();
    // Процесса ещё нет.
    await until(() => link.state == LinkState.unavailable, 'нет процесса');
    expect(link.problem, contains('не запущен'));
    await expectLater(link.call('backup'), throwsA(isA<ControlException>()));

    var server = await serve();
    await until(() => link.state == LinkState.connected, 'подключились');
    expect(link.status, {'generation': 1});
    expect(await link.call('backup'), {'started': true});

    // Событие status обновляет состояние без запроса.
    final events = <String>[];
    link.events.listen((e) => events.add(e.name));
    job = 'backup';
    server.publish('status', {'generation': 1, 'job': job});
    await until(() => link.status?['job'] == 'backup', 'событие status');
    server.publish('progress', {'files': 1});
    await until(() => events.contains('progress'), 'событие progress');

    // Перезапуск процесса.
    await server.close();
    await until(() => link.state != LinkState.connected, 'разрыв замечен');
    expect(link.status, isNotNull, reason: 'последнее известное остаётся');
    generation = 2;
    server = await serve();
    addTearDown(server.close);
    await until(
      () =>
          link.state == LinkState.connected && link.status?['generation'] == 2,
      'переподключились',
    );
    // После переподключения подписка восстановлена.
    server.publish('progress', {'files': 2});
    await until(
      () => events.where((e) => e == 'progress').length == 2,
      'события после перезапуска',
    );
    expect(notified, greaterThan(3));
  });

  test('опрос status для процесса без событий', () async {
    var used = 0;
    final server = await ControlServer.bind(
      endpoint,
      (method, params) async => {'usedBytes': used},
    );
    addTearDown(server.close);
    final link = ProcessLink(
      connect: () => ControlClient.connect(endpoint),
      poll: const Duration(milliseconds: 20),
    )..start();
    addTearDown(link.dispose);
    await until(() => link.state == LinkState.connected, 'подключились');
    used = 42;
    await until(() => link.status?['usedBytes'] == 42, 'опрос');
  });
}
