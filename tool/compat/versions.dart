// Проверка совместимости версий протокола между двумя сборками (задача
// 3.11.1): узел и клиент из старого и нового дерева репозитория проходят
// рукопожатие и договариваются о версии, а если общей версии нет —
// получают понятный отказ `VERSION_UNSUPPORTED`.
//
//   dart run tool/compat/versions.dart --old ПУТЬ --new ПУТЬ [--json]
//
// «Сборки» — два рабочих дерева репозитория: в CI это текущая ветка и база
// слияния с `main`. Собеседник — `packages/cli/tool/compat_peer.dart` из
// соответствующего дерева: он говорит те же `Hello` и Noise XX, что
// настоящие узел и клиент, но без координатора и фрагментов. Версии
// задаются ключом `--versions`, поэтому можно изобразить сборку, которая
// понимает только версию 2, — так проверяется и путь «общей версии нет».
//
// Код возврата 1 — расхождение с ожиданием (регрессия совместимости).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Сколько ждать, пока собеседник начнёт слушать или ответит.
const _timeout = Duration(seconds: 120);

Future<void> main(List<String> arguments) async {
  final options = _Options(List.of(arguments));
  final oldTree = options.value('--old');
  final newTree = options.value('--new');
  final json = options.flag('--json');
  if (oldTree == null || newTree == null) {
    stderr.writeln('нужны --old ПУТЬ и --new ПУТЬ');
    exitCode = 64;
    return;
  }

  // Собеседник должен быть в обоих деревьях: в старом его может не быть —
  // тогда копируем из текущего. Зависимости старого дерева ставим сами.
  for (final tree in {oldTree, newTree}) {
    await _prepare(tree);
  }

  final cases = <_Case>[
    _Case(
      'старая сборка понимает новую',
      node: oldTree,
      nodeVersions: '1',
      client: newTree,
      clientVersions: '1',
      expect: 1,
    ),
    _Case(
      'новая сборка понимает старую',
      node: newTree,
      nodeVersions: '1',
      client: oldTree,
      clientVersions: '1',
      expect: 1,
    ),
    _Case(
      'новая сборка с версией 2 совместима со старой',
      node: newTree,
      nodeVersions: '1,2',
      client: oldTree,
      clientVersions: '1',
      expect: 1,
    ),
    _Case(
      'выбирается наибольшая общая версия',
      node: newTree,
      nodeVersions: '1,2',
      client: newTree,
      clientVersions: '1,2',
      expect: 2,
    ),
    _Case(
      'старая сборка сама с собой',
      node: oldTree,
      nodeVersions: '1',
      client: oldTree,
      clientVersions: '1',
      expect: 1,
    ),
    _Case(
      'нет общей версии: новая сборка знает только 2',
      node: newTree,
      nodeVersions: '2',
      client: oldTree,
      clientVersions: '1',
      expect: null,
    ),
    _Case(
      'нет общей версии: старая сборка не знает версию 2',
      node: oldTree,
      nodeVersions: '1',
      client: newTree,
      clientVersions: '2',
      expect: null,
    ),
  ];

  var failed = 0;
  final results = <Map<String, Object?>>[];
  for (final c in cases) {
    final result = await _runCase(c);
    if (!result.ok) failed++;
    results.add({...result.toJson(), 'case': c.name, 'ok': result.ok});
    if (!json) {
      stdout.writeln('${result.ok ? '✓' : '✗'} ${c.name}: ${result.detail}');
    }
  }
  if (json) {
    stdout.writeln(
      jsonEncode({'cases': results, 'failed': failed, 'total': cases.length}),
    );
  } else {
    stdout.writeln(
      failed == 0
          ? 'Совместимость версий: все ${cases.length} проверок прошли'
          : 'Совместимость версий: провалено $failed из ${cases.length}',
    );
  }
  exitCode = failed == 0 ? 0 : 1;
}

/// Готовит дерево к запуску собеседника: `dart pub get`, если зависимостей
/// ещё нет, и файл собеседника, если его в этом дереве не было.
///
/// Копируется только сам собеседник: протокол и `core` берутся из дерева,
/// поэтому у старой сборки проверяется именно её код.
Future<void> _prepare(String tree) async {
  final config = File('$tree/.dart_tool/package_config.json');
  if (!config.existsSync()) {
    stderr.writeln('• $tree: dart pub get');
    final error = await _pubGet(tree);
    if (error != null) {
      // `dart pub get` не всегда возможен (нет Flutter SDK для пакета
      // приложения, кеш SDK только для чтения). Набор зависимостей у
      // деревьев один и тот же — lockfile общий, — поэтому берём готовую
      // раскладку текущего дерева: пути в ней относительные для пакетов
      // рабочего пространства и ведут в это дерево.
      stderr.writeln(
        '• $tree: pub get не прошёл ($error), берём раскладку '
        'текущего дерева',
      );
      final source = File('.dart_tool/package_config.json');
      if (!source.existsSync()) {
        throw StateError(
          'нет ${source.path}: поставьте зависимости или запускайте из '
          'корня репозитория с готовым .dart_tool',
        );
      }
      await config.parent.create(recursive: true);
      await source.copy(config.path);
      stderr.writeln(
        '• $tree: package_config.json скопирован из текущего дерева',
      );
    }
  }
  final target = File('$tree/packages/cli/tool/compat_peer.dart');
  if (target.existsSync()) return;
  final source = File('packages/cli/tool/compat_peer.dart');
  if (!source.existsSync()) {
    throw StateError('нет ${source.path}: запускать из корня репозитория');
  }
  await target.parent.create(recursive: true);
  await source.copy(target.path);
  stderr.writeln('• $tree: собеседник скопирован из текущего дерева');
}

/// `dart pub get` деревом; `null` — успех, иначе первая строка ошибки.
Future<String?> _pubGet(String tree) async {
  final result = await Process.run(
    _pubDart(),
    ['pub', 'get', '--enforce-lockfile'],
    workingDirectory: tree,
    environment: {'HOME': _home()},
  ).timeout(const Duration(minutes: 10));
  if (result.exitCode == 0) return null;
  final err = '${result.stderr}'.trim();
  if (err.isEmpty) return 'код ${result.exitCode}';
  return err.contains('Flutter SDK is not available')
      ? 'нет Flutter SDK'
      : err.split('\n').first;
}

/// Чем ставить зависимости: `dart` из Flutter SDK, если он есть рядом.
String _pubDart() {
  final explicit = Platform.environment['FS_PUB_DART'];
  if (explicit != null) return explicit;
  final flutter = File('.fvm/flutter_sdk/bin/dart');
  return flutter.existsSync() ? flutter.absolute.path : 'dart';
}

final class _Case {
  const new(
    this.name, {
    required this.node,
    required this.nodeVersions,
    required this.client,
    required this.clientVersions,
    required this.expect,
  });

  final String name;
  final String node;
  final String nodeVersions;
  final String client;
  final String clientVersions;

  /// Ожидаемая версия; `null` — ожидается отказ «нет общей версии».
  final int? expect;
}

final class _Outcome {
  const new({required this.ok, required this.detail});

  final bool ok;
  final String detail;

  Map<String, Object?> toJson() => {'ok': ok, 'detail': detail};
}

/// Поднимает узел одной сборки, подключается клиентом другой, гасит узел.
Future<_Outcome> _runCase(_Case c) async {
  final _Node node;
  try {
    node = await _startNode(c.node, c.nodeVersions);
  } on Object catch (e) {
    return _Outcome(ok: false, detail: 'узел не поднялся: $e');
  }
  try {
    final reply = await _connect(
      c.client,
      c.clientVersions,
      port: node.port,
      nodeId: node.nodeId,
    );
    return _judge(c, reply);
  } on Object catch (e) {
    return _Outcome(ok: false, detail: 'клиент не ответил: $e');
  } finally {
    node.stop();
  }
}

_Outcome _judge(_Case c, Map<String, Object?> reply) {
  final version = reply['version'];
  final error = reply['error'];
  final expect = c.expect;
  if (expect == null) {
    if (version == null) {
      return _Outcome(ok: true, detail: 'отказ: $error');
    }
    return _Outcome(
      ok: false,
      detail: 'ожидался отказ, а выбрана версия $version',
    );
  }
  if (version == expect) return _Outcome(ok: true, detail: 'версия $version');
  return _Outcome(
    ok: false,
    detail: 'ожидалась версия $expect, получено ${version ?? 'отказ: $error'}',
  );
}

final class _Node {
  const new({required this.port, required this.nodeId, required this.process});

  final int port;
  final String nodeId;
  final Process process;

  void stop() => process.kill();
}

Future<_Node> _startNode(String tree, String versions) async {
  final process = await Process.start(
    _dart(),
    ['run', 'tool/compat_peer.dart', 'node', '--versions', versions, '--json'],
    workingDirectory: '$tree/packages/cli',
    environment: {'HOME': _home()},
  );
  final lines = StreamIterator(
    process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
  );
  final stderrText = StringBuffer();
  process.stderr.transform(utf8.decoder).listen(stderrText.write);

  try {
    while (await lines.moveNext().timeout(_timeout)) {
      final reply = _jsonIn(lines.current);
      final port = reply?['listening'];
      final nodeId = reply?['node_id'];
      if (port is int && nodeId is String) {
        return _Node(port: port, nodeId: nodeId, process: process);
      }
    }
  } on TimeoutException {
    process.kill();
    throw StateError('узел молчит ${_timeout.inSeconds} с');
  } finally {
    await lines.cancel();
  }
  process.kill();
  throw StateError('узел завершился: ${'$stderrText'.trim()}');
}

Future<Map<String, Object?>> _connect(
  String tree,
  String versions, {
  required int port,
  required String nodeId,
}) async {
  final result = await Process.run(
    _dart(),
    [
      'run',
      'tool/compat_peer.dart',
      'client',
      '--to',
      '127.0.0.1:$port',
      '--node-id',
      nodeId,
      '--versions',
      versions,
      '--json',
    ],
    workingDirectory: '$tree/packages/cli',
    environment: {'HOME': _home()},
  ).timeout(_timeout);
  final reply = _jsonIn('${result.stdout}');
  if (reply == null) {
    throw StateError(
      'клиент завершился с кодом ${result.exitCode}: '
      '${'${result.stderr}'.trim().split('\n').last}',
    );
  }
  return reply;
}

/// JSON-объект из вывода собеседника: `dart run` печатает перед ним
/// служебные строки (например, «Running build hooks...»).
Map<String, Object?>? _jsonIn(String text) {
  final start = text.indexOf('{');
  if (start < 0) return null;
  final end = text.lastIndexOf('}');
  if (end <= start) return null;
  try {
    final decoded = jsonDecode(text.substring(start, end + 1));
    return decoded is Map<String, Object?> ? decoded : null;
  } on FormatException {
    return null;
  }
}

String _dart() =>
    Platform.environment['FS_DART'] ?? Platform.resolvedExecutable;

/// Домашний каталог для служебных файлов Dart: в CI — обычный.
String _home() =>
    Platform.environment['FS_COMPAT_HOME'] ?? Platform.environment['HOME']!;

final class _Options {
  new(this._rest);

  final List<String> _rest;

  bool flag(String name) {
    final i = _rest.indexOf(name);
    if (i < 0) return false;
    _rest.removeAt(i);
    return true;
  }

  String? value(String name) {
    final i = _rest.indexOf(name);
    if (i < 0 || i + 1 >= _rest.length) return null;
    final value = _rest[i + 1];
    _rest.removeRange(i, i + 2);
    return value;
  }
}
