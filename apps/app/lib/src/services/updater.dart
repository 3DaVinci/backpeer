import 'dart:ffi' show Abi;
import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:daemon_kit/daemon_kit.dart' show ServiceException;

/// Результат установки обновления.
final class UpdateOutcome {
  const new({this.restartRequired = false, this.url});

  /// Установка сделана, приложение должно перезапуститься (установщик уже
  /// запущен и сам поднимет новую версию).
  final bool restartRequired;

  /// Автоматической установки нет: новая версия доступна по адресу.
  final String? url;
}

/// Что делать с загруженным пакетом обновления (docs/spec/updates.md,
/// раздел 6). Платформозависимо; остановка фоновых процессов — до вызова
/// [Updater.apply], установка и перезапуск — здесь.
abstract interface class UpdateInstaller {
  /// Как пакет будет поставлен, для человека.
  String get description;

  /// Нужно ли скачивать пакет. Для `.deb`/`.rpm` и macOS вне
  /// `/Applications` — нет: клиент только показывает адрес.
  bool get needsDownload => true;

  /// Ставит пакет [package] из [bytes] (хэш уже проверен; при
  /// [needsDownload] `false` — пустые байты).
  Future<UpdateOutcome> apply(UpdatePackage package, Uint8List bytes);
}

/// Запуск вспомогательной программы, которая переживёт приложение. В тестах
/// — подделка.
typedef HelperStarter = Future<void> Function(
  String executable,
  List<String> arguments,
);

Future<void> _startHelper(String executable, List<String> arguments) async {
  await Process.start(executable, arguments, mode: ProcessStartMode.detached);
}

/// Для `.deb`/`.rpm` и случаев, когда автоматической установки нет:
/// сообщаем адрес пакета.
final class NotifyingInstaller implements UpdateInstaller {
  const new();

  @override
  String get description => 'уведомление о новой версии';

  @override
  bool get needsDownload => false;

  @override
  Future<UpdateOutcome> apply(UpdatePackage package, Uint8List bytes) async =>
      UpdateOutcome(url: package.url.toString());
}

/// Linux AppImage: заменить файл образа и перезапустить приложение новой
/// версией. Службы к этому моменту остановлены ([Updater.stop]); новая
/// версия при запуске обновит постоянную копию программ
/// (`PersistentDaemons`) и снова поставит службы.
final class AppImageInstaller implements UpdateInstaller {
  new({String? appImage, this.startHelper = _startHelper})
    : _appImage = appImage ?? Platform.environment['APPIMAGE'];

  final String? _appImage;
  final HelperStarter startHelper;

  @override
  String get description => 'замена образа AppImage';

  @override
  bool get needsDownload => true;

  @override
  Future<UpdateOutcome> apply(UpdatePackage package, Uint8List bytes) async {
    final target = _appImage;
    if (target == null) {
      throw const ServiceException('приложение запущено не из AppImage');
    }
    final file = File(target);
    final mode = file.existsSync() ? file.statSync().mode & 0x1FF : 0x1ED;
    final temp = File('${file.path}.new-$pid')
      ..writeAsBytesSync(bytes, flush: true);
    if (!Platform.isWindows) setUnixFileMode(temp.path, mode);
    temp.renameSync(file.path);
    // Запуск нового образа — отдельной оболочкой: она переживёт выход
    // приложения и дождётся, пока старый процесс отпустит файл.
    await startHelper('/bin/sh', [
      '-c',
      appImageUpdateScript(pid: pid, image: file.path),
    ]);
    return const UpdateOutcome(restartRequired: true);
  }
}

/// Скрипт перезапуска AppImage (вынесен для тестов).
String appImageUpdateScript({required int pid, required String image}) =>
    'while kill -0 $pid 2>/dev/null; do sleep 0.2; done\n'
    'exec ${_shQuote(image)}\n';

/// Windows: запускает загруженный установщик Inno Setup молча, после него —
/// приложение. Установщик сам снимает старые службы и кладёт новые
/// программы (`backpeer.iss`, `PrepareToInstall`).
///
/// Приложение к этому моменту должно завершиться: скрипт ждёт PID, поэтому
/// файлы не заняты. Службы останавливает [Updater.stop], а также
/// `agent uninstall` внутри установщика.
final class WindowsInstaller implements UpdateInstaller {
  new({required this.appExecutable, this.startHelper = _startHelper});

  final String appExecutable;
  final HelperStarter startHelper;

  @override
  String get description => 'установщик Windows';

  @override
  bool get needsDownload => true;

  @override
  Future<UpdateOutcome> apply(UpdatePackage package, Uint8List bytes) async {
    final dir = Directory.systemTemp.createTempSync('backpeer-update-');
    final name = _packageFileName(package.url, fallback: 'backpeer-setup.exe');
    final installer = File('${dir.path}${Platform.pathSeparator}$name')
      ..writeAsBytesSync(bytes, flush: true);
    await startHelper('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-WindowStyle',
      'Hidden',
      '-Command',
      windowsUpdateScript(
        pid: pid,
        installer: installer.path,
        app: appExecutable,
        tempDir: dir.path,
      ),
    ]);
    return const UpdateOutcome(restartRequired: true);
  }
}

/// Команда PowerShell для установки обновления Windows (вынесена для
/// тестов): дождаться выхода приложения, поставить установщик молча,
/// запустить новую версию, убрать временные файлы.
String windowsUpdateScript({
  required int pid,
  required String installer,
  required String app,
  required String tempDir,
}) {
  String ps(String s) => "'${s.replaceAll("'", "''")}'";
  const arguments = ['/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-'];
  return 'Wait-Process -Id $pid -ErrorAction SilentlyContinue; '
      'Start-Process -FilePath ${ps(installer)} '
      '-ArgumentList @(${arguments.map(ps).join(',')}) -Wait; '
      'Start-Process -FilePath ${ps(app)}; '
      'Remove-Item -LiteralPath ${ps(installer)} -Force '
      '-ErrorAction SilentlyContinue; '
      'Remove-Item -LiteralPath ${ps(tempDir)} -Recurse -Force '
      '-ErrorAction SilentlyContinue';
}

/// macOS: смонтировать загруженный `.dmg`, дождаться выхода приложения,
/// заменить `.app` и открыть новую версию. Работает, только если пакет
/// лежит в `/Applications`; из образа или перенесённого пакета (App
/// Translocation) автоматическая замена не делается — возвращается адрес
/// `.dmg` для ручной установки.
final class MacDmgInstaller implements UpdateInstaller {
  new({required this.appExecutable, this.startHelper = _startHelper});

  /// `.../Backpeer.app/Contents/MacOS/backpeer`.
  final String appExecutable;
  final HelperStarter startHelper;

  /// `.../Backpeer.app`.
  String get appBundle => File(appExecutable).parent.parent.parent.path;

  @override
  String get description => 'установка из .dmg';

  @override
  bool get needsDownload => appBundle.startsWith('/Applications/');

  @override
  Future<UpdateOutcome> apply(UpdatePackage package, Uint8List bytes) async {
    if (!appBundle.startsWith('/Applications/')) {
      return UpdateOutcome(url: package.url.toString());
    }
    final file = File(
      '${Directory.systemTemp.path}/backpeer-${package.size}.dmg',
    )..writeAsBytesSync(bytes, flush: true);
    await startHelper('/bin/sh', [
      '-c',
      macUpdateScript(pid: pid, dmg: file.path, appBundle: appBundle),
    ]);
    return const UpdateOutcome(restartRequired: true);
  }
}

/// Скрипт замены `.app` из `.dmg` (вынесен для тестов).
String macUpdateScript({
  required int pid,
  required String dmg,
  required String appBundle,
}) {
  final parent = File(appBundle).parent.path;
  final name = appBundle.split(Platform.pathSeparator).last;
  final newApp = '$parent/.$name.new-';
  const template = r'''
while kill -0 __PID__ 2>/dev/null; do sleep 0.5; done
mount=$(mktemp -d /tmp/backpeer-update.XXXXXX) || exit 1
hdiutil attach -quiet -nobrowse -readonly -mountpoint "$mount" __DMG__ || { rmdir "$mount"; exit 1; }
new=__NEW__$$
ditto "$mount/__NAME__" "$new" || { hdiutil detach -quiet "$mount"; rm -rf "$new"; rmdir "$mount"; exit 1; }
hdiutil detach -quiet "$mount"
rmdir "$mount"
rm -rf __APP__ || exit 1
mv "$new" __APP__ || exit 1
open __APP__
rm -f __DMG__
''';
  return template
      .replaceAll('__PID__', '$pid')
      .replaceAll('__DMG__', _shQuote(dmg))
      .replaceAll('__NEW__', _shQuote(newApp))
      .replaceAll('__NAME__', name.replaceAll('"', r'\"'))
      .replaceAll('__APP__', _shQuote(appBundle));
}

/// Проверка и применение обновлений приложения и фоновых процессов
/// (задача 5.8.2). Только проверяет подпись и хэш (ядро — [UpdateClient]) и
/// оркеструет установку: остановить процессы, поставить пакет, перезапустить.
final class Updater {
  new({
    required this.client,
    required this.currentVersion,
    required this.installId,
    required this.platform,
    required this.installer,
    required this.stop,
    this.arch,
  });

  final UpdateClient client;
  final ProductVersion currentVersion;

  /// Идентификатор установки для раскатки (docs/spec/updates.md, раздел 5).
  final Uint8List installId;

  final UpdatePlatform platform;

  /// `x64`/`arm64`; `null` — любая.
  final String? arch;

  final UpdateInstaller installer;

  /// Корректно останавливает фоновые процессы (агент — с отменой задания и
  /// продолжением при следующем запуске) до замены программ. Вызывается
  /// после загрузки и проверки пакета.
  final Future<void> Function() stop;

  /// Для текущей ОС: платформа и архитектура из `dart:io`/FFI.
  static UpdatePlatform currentPlatform() => switch (Platform.operatingSystem) {
    'linux' => UpdatePlatform.linux,
    'macos' => UpdatePlatform.macos,
    'windows' => UpdatePlatform.windows,
    _ => throw StateError('неизвестная ОС ${Platform.operatingSystem}'),
  };

  static String? currentArch() {
    final abi = '${Abi.current()}';
    return abi.endsWith('arm64') ? 'arm64' : 'x64';
  }

  /// Есть ли обновление для меня; `null` — нет (или не в доле раскатки).
  /// Ошибки подписи и сети не проглатываются — их показывает вызывающий.
  Future<UpdateManifest?> check({
    required Uri baseUri,
    required UpdateChannel channel,
  }) => client.check(
    baseUri: baseUri,
    channel: channel,
    currentVersion: currentVersion,
    installId: installId,
  );

  /// Загружает пакет [manifest] для [platform], проверяет хэш, останавливает
  /// процессы и ставит. Порядок гарантирует: подменённый пакет отклоняется до
  /// остановки процессов и установки.
  Future<UpdateOutcome> apply(UpdateManifest manifest) async {
    final package = manifest.packageFor(platform, arch);
    if (package == null) {
      final what = '${platform.name}${arch == null ? '' : '/$arch'}';
      throw PreconditionException('в манифесте нет сборки для $what');
    }
    final bytes = installer.needsDownload
        ? await client.download(package)
        : Uint8List(0);
    if (installer.needsDownload) await stop();
    return await installer.apply(package, bytes);
  }
}

/// Имя файла из URL пакета; для временного файла на диске.
String _packageFileName(Uri url, {required String fallback}) {
  final last = url.pathSegments.isEmpty ? '' : url.pathSegments.last;
  return last.isEmpty ? fallback : last;
}

/// Строка для `sh -c`: в одинарных кавычках, кавычка — `'\''`.
String _shQuote(String s) => "'${s.replaceAll("'", r"'\''")}'";
