// Запуск хранителя: программа ищется только рядом с агентом, а не по имени
// в PATH. Глобально установленный Node.js называется так же (`node`):
// подставленный вместо демона, он падает на аргументах `run --data …`, а
// приложение показывает «служба не запустилась» (задача 5.5.2).

import 'dart:io';

import 'package:agent/agent.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;
  late String agentExe;
  late String nodeJs;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('fs-node-find-');
    // «Установленный глобально Node.js» — `node` в PATH.
    final bin = Directory('${dir.path}/usr/local/bin')
      ..createSync(recursive: true);
    nodeJs = '${bin.path}/node';
    File(nodeJs).writeAsStringSync('#!/bin/sh\necho "v20.0.0"\n');
    agentExe = '${dir.path}/app/daemons/agent/bin/agent';
    File(agentExe).createSync(recursive: true);
  });

  tearDown(() => dir.deleteSync(recursive: true));

  test('Node.js из PATH не подставляется вместо программы хранителя', () {
    expect(
      ProcessNodeLauncher.find({
        'PATH': '${dir.path}/usr/local/bin',
        'HOME': dir.path,
      }, selfExecutable: agentExe),
      isNull,
      reason: 'поиск по PATH — это и был бы конфликт имён с Node.js',
    );
  });

  test('программа находится в бандле рядом с агентом, а не в PATH', () {
    final bundle = File('${dir.path}/app/daemons/node/bin/node')
      ..createSync(recursive: true);
    expect(
      ProcessNodeLauncher.find({
        'PATH': '${dir.path}/usr/local/bin',
        'HOME': dir.path,
      }, selfExecutable: agentExe),
      bundle.resolveSymbolicLinksSync(),
    );
  });

  test('бандл сборки: build/bin/<ОС>-<арх>/node/bundle/bin/node', () {
    final bundle = File('${dir.path}/build/bin/linux-x64/node/bundle/bin/node')
      ..createSync(recursive: true);
    // Агент рядом — как в настоящей сборке: без него не пройти по `..`.
    final self = '${dir.path}/build/bin/linux-x64/agent/bundle/bin/agent';
    File(self).createSync(recursive: true);
    expect(
      ProcessNodeLauncher.find({'HOME': dir.path}, selfExecutable: self),
      bundle.resolveSymbolicLinksSync(),
    );
  });

  test('FS_NODE_EXECUTABLE главнее бандла: путь можно указать явно', () {
    final bundle = File('${dir.path}/app/daemons/node/bin/node')
      ..createSync(recursive: true);
    expect(
      ProcessNodeLauncher.find({
        'FS_NODE_EXECUTABLE': bundle.path,
      }, selfExecutable: agentExe),
      bundle.path,
    );
  });
}
