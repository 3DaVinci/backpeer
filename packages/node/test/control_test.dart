import 'dart:convert';
import 'dart:io';

import 'package:node/node.dart';
import 'package:node/src/control/control_endpoint.dart' show currentUid;
import 'package:node/src/control/control_wire.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;
  late ControlEndpoint endpoint;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('fs-node-ctl-');
    endpoint = ControlEndpoint.forDataDir(dir.path);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<Map<String, Object?>> echo(
    String method,
    Map<String, Object?> params,
  ) async => switch (method) {
    'echo' => params,
    'fail' => throw const ControlException('bad_request', 'плохо'),
    'crash' => throw StateError('секрет'),
    _ => throw ControlException('unknown_method', method),
  };

  test('запрос и ответ, ошибки метода, внутренняя ошибка без текста', () async {
    final server = await ControlServer.bind(endpoint, echo);
    final client = await NodeControlClient.connect(endpoint);
    expect(await client.call('echo', {'a': 1}), {'a': 1});
    // Несколько запросов подряд по одному соединению.
    final many = await Future.wait([
      for (var i = 0; i < 10; i++) client.call('echo', {'i': i}),
    ]);
    expect([for (final m in many) m['i']], List.generate(10, (i) => i));
    await expectLater(
      client.call('fail'),
      throwsA(
        isA<ControlException>().having((e) => e.code, 'code', 'bad_request'),
      ),
    );
    await expectLater(
      client.call('crash'),
      throwsA(
        isA<ControlException>()
            .having((e) => e.code, 'code', 'internal')
            .having((e) => e.message, 'message', isNot(contains('секрет'))),
      ),
    );
    await client.close();
    await server.close();
    expect(File(endpoint.socketPath).existsSync(), isFalse);
  });

  test('демон не запущен — unavailable', () async {
    await expectLater(
      NodeControlClient.connect(endpoint),
      throwsA(
        isA<ControlException>().having((e) => e.code, 'code', 'unavailable'),
      ),
    );
  });

  test(
    'Unix: каталог 0700, сокет 0600; второй сервер на том же сокете — ошибка',
    () async {
      final server = await ControlServer.bind(endpoint, echo);
      expect(endpoint.runDir.statSync().mode & 511, 448);
      expect(File(endpoint.socketPath).statSync().mode & 511, 384);
      await expectLater(
        ControlServer.bind(endpoint, echo),
        throwsA(isA<FileSystemException>()),
      );
      await server.close();
    },
    skip: Platform.isWindows ? 'Unix-сокет' : false,
  );

  test('оставшийся от прошлого запуска сокет заменяется', () async {
    // Процесс, упавший с открытым сокетом, оставляет файл, на котором
    // никто не слушает (Dart удаляет файл при закрытии сокета).
    endpoint.runDir.createSync(recursive: true);
    final ProcessResult result;
    try {
      final script =
          'import socket; '
          'socket.socket(socket.AF_UNIX).bind("${endpoint.socketPath}")';
      result = await Process.run('python3', ['-c', script]);
    } on ProcessException {
      markTestSkipped('нужен python3');
      return;
    }
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(
      FileSystemEntity.typeSync(endpoint.socketPath),
      FileSystemEntityType.unixDomainSock,
    );
    final server = await ControlServer.bind(endpoint, echo);
    final client = await NodeControlClient.connect(endpoint);
    expect(await client.call('echo'), isEmpty);
    await client.close();
    await server.close();
  }, skip: Platform.isWindows ? 'Unix-сокет' : false);

  test('чужой пользователь ОС не подключается (SO_PEERCRED)', () async {
    // Сервер ждёт другого пользователя — наш процесс для него «чужой».
    final server = await ControlServer.bind(
      endpoint,
      echo,
      allowedUid: currentUid() + 1,
    );
    final client = await NodeControlClient.connect(endpoint);
    await expectLater(
      client.call('echo'),
      throwsA(
        isA<ControlException>().having((e) => e.code, 'code', 'unavailable'),
      ),
    );
    await client.close();
    await server.close();
  }, skip: Platform.isLinux ? false : 'SO_PEERCRED — только Linux');

  test('строка длиннее предела и не JSON обрывают соединение', () async {
    final server = await ControlServer.bind(endpoint, echo);
    for (final payload in [
      List.filled(ControlWire.maxLine + 10, 0x61),
      utf8.encode('не json\n'),
      utf8.encode('[1]\n'),
    ]) {
      final socket = await Socket.connect(
        InternetAddress(endpoint.socketPath, type: InternetAddressType.unix),
        0,
      );
      socket.add(payload);
      final reply = await socket.fold<List<int>>([], (a, b) => a..addAll(b));
      expect(reply, isEmpty);
      socket.destroy();
    }
    // Сервер продолжает работать.
    final client = await NodeControlClient.connect(endpoint);
    expect(await client.call('echo', {'x': 'y'}), {'x': 'y'});
    await client.close();
    await server.close();
  }, skip: Platform.isWindows ? 'Unix-сокет' : false);
}
