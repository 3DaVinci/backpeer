import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:agent/src/keeper.dart';
import 'package:agent/src/paths.dart';
import 'package:agent/src/secrets/secret_store.dart';
import 'package:cli/cli.dart';
import 'package:core/core.dart';
import 'package:daemon_kit/daemon_kit.dart';

/// Папка с бандлами фоновых процессов `dart build cli` («бинарник +
/// `lib/`»): в пакете приложения — `daemons/<программа>/bin/<программа>`,
/// в сборке `tool/build_exe.dart` — `build/bin/<ОС>-<арх>/<программа>/
/// bundle/bin/<программа>`. Задачи 5.6.1, 5.7.3.
final class DaemonBundle {
  new(this.root);

  /// `FS_DAEMONS_DIR`; иначе `daemons/` рядом с исполняемым файлом
  /// приложения [appExecutable]; иначе сборка `build/bin/<ОС>-<арх>/` в
  /// [workingDirectory] и выше (запуск из исходников). Нет — `null`.
  static DaemonBundle? locate({
    Map<String, String>? environment,
    String? appExecutable,
    String? workingDirectory,
  }) {
    final env = environment ?? Platform.environment;
    bool ok(DaemonBundle b) => b.executable('agent') != null;
    if (env['FS_DAEMONS_DIR'] case final dir? when dir.isNotEmpty) {
      final bundle = DaemonBundle(dir);
      return ok(bundle) ? bundle : null;
    }
    final exe = File(appExecutable ?? Platform.resolvedExecutable);
    final packaged = DaemonBundle('${exe.parent.path}/daemons');
    if (ok(packaged)) return packaged;
    final platform = '${Platform.operatingSystem}-${_arch()}';
    var dir = Directory(workingDirectory ?? Directory.current.path).absolute;
    for (var i = 0; i < 4; i++) {
      final built = DaemonBundle('${dir.path}/build/bin/$platform');
      if (ok(built)) return built;
      if (dir.parent.path == dir.path) break;
      dir = dir.parent;
    }
    return null;
  }

  final String root;

  /// Исполняемый файл [program] (`agent`, `node`, `cli`); нет — `null`.
  String? executable(String program) {
    final name = Platform.isWindows ? '$program.exe' : program;
    for (final path in [
      '$root/$program/bin/$name',
      '$root/$program/bundle/bin/$name',
    ]) {
      if (File(path).existsSync()) return File(path).absolute.path;
    }
    return null;
  }

  static String _arch() {
    final abi = '${Abi.current()}';
    return abi.endsWith('arm64') ? 'arm64' : 'x64';
  }
}

/// AppImage монтируется по временному пути (`/tmp/.mount_…`), поэтому
/// службы не могут указывать на программы внутри него: бандлы копируются
/// в постоянное место, `~/.local/lib/file-storage/daemons` (задача 5.7.3).
/// Копия заменяется целиком переименованием: работающие процессы
/// дорабатывают со старыми файлами.
final class PersistentDaemons {
  new({required this.target});

  factory forUser([Map<String, String>? environment]) {
    final env = environment ?? Platform.environment;
    return PersistentDaemons(
      target: Directory('${env['HOME']}/.local/lib/$servicePrefix/daemons'),
    );
  }

  final Directory target;

  File get _version => File('${target.path}/VERSION');

  /// Нужна ли копия: программа запущена из AppImage (`APPIMAGE`).
  static bool needed([Map<String, String>? environment]) =>
      (environment ?? Platform.environment)['APPIMAGE'] != null;

  /// Копирует [source], если в [target] другая версия; `true` — копия
  /// обновлена (службы нужно перезапустить).
  bool sync(DaemonBundle source, String version) {
    if (_version.existsSync() &&
        _version.readAsStringSync().trim() == version &&
        DaemonBundle(target.path).executable('agent') != null) {
      return false;
    }
    final parent = target.parent..createSync(recursive: true);
    final fresh = Directory('${parent.path}/daemons.new-$pid');
    if (fresh.existsSync()) fresh.deleteSync(recursive: true);
    _copy(Directory(source.root), fresh);
    File('${fresh.path}/VERSION').writeAsStringSync('$version\n');
    final old = Directory('${parent.path}/daemons.old-$pid');
    if (target.existsSync()) target.renameSync(old.path);
    fresh.renameSync(target.path);
    if (old.existsSync()) old.deleteSync(recursive: true);
    return true;
  }

  static void _copy(Directory from, Directory to) {
    to.createSync(recursive: true);
    for (final entity in from.listSync(followLinks: false)) {
      final name = entity.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
      final dest = '${to.path}/$name';
      if (entity is Directory) {
        _copy(entity, Directory(dest));
      } else if (entity is File) {
        entity.copySync(dest);
        if (!Platform.isWindows) {
          final mode = entity.statSync().mode & 0x1FF;
          setUnixFileMode(dest, mode);
        }
      } else if (entity is Link) {
        Link(dest).createSync(entity.targetSync());
      }
    }
  }

  void remove() {
    final dir = target.parent;
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }
}

/// Службы фоновых процессов клиента (задача 5.6.1, ADR-011): агент
/// бэкапа — всегда, хранитель — пока включена роль. Пути — к программам,
/// которые останутся на месте: в пакете или в постоянной копии
/// ([PersistentDaemons]).
final class ClientServices {
  new({required this.services, this.home});

  /// Агент — `agent` служба; хранитель — `node`.
  static const agentName = 'agent';
  static const nodeName = 'node';

  final UserServices services;

  /// Каталог программы не по умолчанию (`FS_HOME`, `--home`) — передаётся
  /// агенту аргументом.
  final String? home;

  ServiceSpec agentSpec(String executable) => ServiceSpec(
    name: agentName,
    description: 'File Storage: агент бэкапа',
    executable: executable,
    arguments: [
      'run',
      if (home case final h?) ...['--home', h],
    ],
  );

  static ServiceSpec nodeSpec(String executable, String dataDir) => ServiceSpec(
    name: nodeName,
    description: 'File Storage: хранитель',
    executable: executable,
    arguments: ['run', '--data', dataDir],
  );

  Future<void> installAgent(String executable) =>
      services.install(agentSpec(executable));

  Future<ServiceState> agentState() => services.state(agentName);

  Future<ServiceState> nodeState() => services.state(nodeName);

  /// Остановить и удалить обе службы.
  Future<void> uninstallAll() async {
    await services.uninstall(nodeName);
    await services.uninstall(agentName);
  }
}

/// [NodeLauncher] службой ОС (задачи 5.6.1, 5.6.4): хранитель живёт сам
/// по себе — переживает перезапуск агента и выход пользователя (с
/// [Linger]), перезапускается после сбоя. Нет менеджера служб —
/// отдельным процессом ([ProcessNodeLauncher]).
final class ServiceNodeLauncher implements NodeLauncher {
  new({required this.services, required this.executable});

  final UserServices services;

  @override
  final String? executable;

  @override
  String get kind => services.kind;

  @override
  Future<bool> start(String dataDir) async {
    final exe = executable;
    if (exe == null) return false;
    await services.install(ClientServices.nodeSpec(exe, dataDir));
    return true;
  }

  @override
  Future<void> disable() => services.uninstall(ClientServices.nodeName);
}

/// Удаление клиента с компьютера (задача 5.7.3): остановить и удалить
/// службы, запуск значка при входе, работу без входа (если её включил
/// агент), постоянную копию программ AppImage. Данные и ключи остаются;
/// [purge] — удалить и их: каталог программы, папку данных узла и запись
/// в хранилище ОС. Возвращает, что сделано, — для вывода.
Future<List<String>> uninstallClient({
  required AppHome home,
  required String nodeDataDir,
  required UserServices services,
  required LoginItem loginItem,
  Linger? linger,
  PersistentDaemons? persistent,
  SecretStore? secrets,
  bool purge = false,
}) async {
  final done = <String>[];
  for (final name in [ClientServices.nodeName, ClientServices.agentName]) {
    if (await services.state(name) == ServiceState.notInstalled) continue;
    await services.uninstall(name);
    done.add('служба ${services.serviceName(name)} удалена');
  }
  // Без служб (или запущены вручную) — остановить через локальный API.
  for (final (endpoint, lock) in [
    (AgentPaths(home).endpoint(), AgentPaths(home).lock),
    (
      ControlEndpoint.forDataDir(nodeDataDir, process: 'хранитель'),
      File('$nodeDataDir/node.lock'),
    ),
  ]) {
    if (await stopViaControl(endpoint, lock)) {
      done.add('остановлен процесс ${lock.parent.path}');
    }
  }
  final keeper = KeeperSettings.load(AgentPaths(home).keeper);
  if (linger != null && keeper != null && keeper.lingerByAgent) {
    final problem = await linger.disable();
    done.add(
      problem == null
          ? 'работа служб без входа выключена'
          : 'работу служб без входа выключить не удалось: $problem',
    );
  }
  if (loginItem.enabled) {
    await loginItem.disable();
    done.add('запуск при входе выключен');
  }
  if (persistent != null && persistent.target.existsSync()) {
    persistent.remove();
    done.add('удалена копия программ ${persistent.target.parent.path}');
  }
  if (purge) {
    try {
      await (secrets ?? SecretStore.forPlatform()).delete(
        home.dir.absolute.path,
      );
      done.add('ключ агента удалён из хранилища ОС');
    } on SecretStoreException catch (e) {
      done.add('ключ агента в хранилище ОС не удалён: ${e.message}');
    }
    for (final dir in [home.dir, Directory(nodeDataDir)]) {
      if (!dir.existsSync()) continue;
      dir.deleteSync(recursive: true);
      done.add('удалена папка ${dir.path}');
    }
    if (keeper != null && keeper.storageDir != nodeDataDir) {
      final storage = Directory(keeper.storageDir);
      if (storage.existsSync()) {
        storage.deleteSync(recursive: true);
        done.add('удалена папка фрагментов ${storage.path}');
      }
    }
  }
  return done;
}

/// Остановить процесс методом `stop` и дождаться, пока он отпустит
/// блокировку; `true` — был запущен.
Future<bool> stopViaControl(ControlEndpoint endpoint, File lock) async {
  final ControlClient client;
  try {
    client = await ControlClient.connect(endpoint);
  } on ControlException {
    return false;
  }
  try {
    await client.call('stop');
  } on ControlException {
    // Уже останавливается.
  } finally {
    await client.close();
  }
  for (var i = 0; i < 300; i++) {
    try {
      DirLock.acquire(lock, busy: '').release();
      return true;
    } on FileSystemException {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }
  return true;
}
