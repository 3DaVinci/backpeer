import 'dart:ffi' show Abi;
import 'dart:io';
import 'dart:typed_data';

import 'package:app/src/services/update_log.dart';
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
/// Приложение к этому моменту должно завершиться: скрипт ждёт его, поэтому
/// файлы не заняты. Службы останавливает [Updater.stop], а также
/// `agent uninstall` внутри установщика.
///
/// Скрипт пишется файлом (`update.ps1`) и запускается с `-File`, а не длинной
/// строкой `-Command`: уходит класс ошибок с экранированием, а запуск
/// повторяется вручную один в один. Каждый шаг скрипт пишет в журнал, итог
/// попытки — в `update-result.json` рядом с ним: приложение покажет его при
/// следующем запуске. Иначе неудачная установка выглядела бы как «обновлений
/// нет» — именно так и вёл себя Windows до 13.11.2026.
final class WindowsInstaller implements UpdateInstaller {
  new({required this.appExecutable, this.startHelper = _startHelper, this.log});

  final String appExecutable;
  final HelperStarter startHelper;

  /// Журнал и итог обновления; `null` — во временном каталоге рядом с
  /// установщиком (там итог не переживёт уборку).
  final UpdateLog? log;

  @override
  String get description => 'установщик Windows';

  @override
  bool get needsDownload => true;

  @override
  Future<UpdateOutcome> apply(UpdatePackage package, Uint8List bytes) async {
    final dir = Directory.systemTemp.createTempSync('backpeer-update-');
    final sep = Platform.pathSeparator;
    final updateLog = UpdateLog(
      log: log?.log ?? File('${dir.path}${sep}update.log'),
      result: log?.result ?? File('${dir.path}${sep}update-result.json'),
    );
    final name = _packageFileName(package.url, fallback: 'backpeer-setup.exe');
    final installer = File('${dir.path}$sep$name')
      ..writeAsBytesSync(bytes, flush: true);
    final text = windowsUpdateScript(
      pid: pid,
      installer: installer.path,
      app: appExecutable,
      tempDir: dir.path,
      logPath: updateLog.log?.path ?? '',
      resultPath: updateLog.result?.path ?? '',
    );
    // BOM: Windows PowerShell 5.1 читает файл без BOM как ANSI, и русские
    // сообщения в журнале превращаются в мусор.
    final script = File('${dir.path}${sep}update.ps1')
      ..writeAsStringSync('\uFEFF$text');
    updateLog.write('скрипт запуска: ${script.path}');
    await startHelper('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-ExecutionPolicy',
      'Bypass',
      '-WindowStyle',
      'Hidden',
      '-File',
      script.path,
    ]);
    updateLog.write('оболочка запущена, приложение выходит');
    return const UpdateOutcome(restartRequired: true);
  }
}

/// Скрипт установки обновления Windows (вынесен для тестов): дождаться
/// выхода приложения, поставить установщик молча, записать итог, запустить
/// новую версию и убрать временные файлы. Ожидание — опросом процесса, а не
/// `Wait-Process`: приложение выходит через 2 секунды после запуска
/// оболочки, и `Wait-Process` по исчезнувшему PID рискует оборвать скрипт до
/// установки.
String windowsUpdateScript({
  required int pid,
  required String installer,
  required String app,
  required String tempDir,
  required String logPath,
  required String resultPath,
}) {
  String ps(String s) => "'${s.replaceAll("'", "''")}'";
  const template = r'''
$ErrorActionPreference = 'Stop'
$log = __LOG__
$result = __RESULT__
$installer = __INSTALLER__
$app = __APP__
$tempDir = __TEMPDIR__
$setupLog = Join-Path $tempDir 'setup.log'
$utf8 = [System.Text.UTF8Encoding]::new($false)
$code = $null

function Write-Log([string] $text) {
  try {
    $now = (Get-Date).ToUniversalTime()
    $line = '{0:o} {1}' -f $now, $text
    [System.IO.File]::AppendAllText($log, $line + "`r`n", $utf8)
  } catch { }
}

function Write-Result([bool] $ok, [string] $stage, [string] $message) {
  try {
    $data = [ordered]@{
      ok = $ok
      stage = $stage
      message = $message
      at = (Get-Date).ToUniversalTime().ToString('o')
      log = $log
      installer = $installer
      app = $app
      setupLog = $setupLog
      pid = __PID__
    }
    $json = $data | ConvertTo-Json -Compress
    [System.IO.File]::WriteAllText($result, $json, $utf8)
  } catch {
    Write-Log ('итог не записан: ' + $_)
  }
}

Write-Log 'старт: ждём выход приложения __PID__'
Write-Result $false 'started' 'обновление не завершилось'
try {
  $deadline = (Get-Date).AddMinutes(2)
  while ((Get-Process -Id __PID__ -ErrorAction SilentlyContinue) -and
         ((Get-Date) -lt $deadline)) {
    Start-Sleep -Milliseconds 300
  }
  if (Get-Process -Id __PID__ -ErrorAction SilentlyContinue) {
    Write-Log 'приложение не завершилось за 2 минуты'
    Write-Result $false 'wait' 'приложение не завершилось за 2 минуты — установка не начата'
  } else {
    Write-Log 'приложение завершилось, запускаем установщик'
    # /LOG= в кавычках: в пути может быть пробел (имя пользователя Windows).
    $arguments = @(
      '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-',
      ('/LOG=`"' + $setupLog + '`"'))
    $process = Start-Process -FilePath $installer -PassThru -Wait -ArgumentList $arguments
    $code = $process.ExitCode
    Write-Log ('установщик завершился с кодом ' + $code + ', журнал: ' + $setupLog)
    if ($code -eq 0) {
      Write-Result $true 'done' 'обновление установлено'
    } else {
      Write-Result $false 'installer' ('установщик Windows завершился с кодом ' + $code)
    }
  }
} catch {
  Write-Log ('ошибка обновления: ' + $_)
  Write-Result $false 'error' ('ошибка обновления: ' + $_)
}

if ($code -eq 0) {
  Remove-Item -LiteralPath $installer -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
} else {
  Write-Log ('установщик оставлен для разбора: ' + $installer)
}
try {
  Start-Process -FilePath $app
  Write-Log 'приложение запущено'
} catch {
  Write-Log ('приложение не запущено: ' + $_)
}
''';
  return template
      .replaceAll('__PID__', '$pid')
      .replaceAll('__LOG__', ps(logPath))
      .replaceAll('__RESULT__', ps(resultPath))
      .replaceAll('__INSTALLER__', ps(installer))
      .replaceAll('__APP__', ps(app))
      .replaceAll('__TEMPDIR__', ps(tempDir));
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
    this.log,
  });

  final UpdateClient client;
  final ProductVersion currentVersion;

  /// Идентификатор установки для раскатки (docs/spec/updates.md, раздел 5).
  final Uint8List installId;

  final UpdatePlatform platform;

  /// `x64`/`arm64`; `null` — любая.
  final String? arch;

  final UpdateInstaller installer;

  /// Журнал обновления (см. [UpdateLog]); `null` — не вести.
  final UpdateLog? log;

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
      log?.write('обновление ${manifest.version}: нет сборки для $what');
      throw PreconditionException('в манифесте нет сборки для $what');
    }
    log?.write(
      'обновление $currentVersion → ${manifest.version}: '
      '${installer.description}',
    );
    final bytes = installer.needsDownload
        ? await client.download(package)
        : Uint8List(0);
    if (installer.needsDownload) {
      log?.write('пакет проверен, ${bytes.length} байт');
      await stop();
      log?.write('фоновые процессы остановлены');
    }
    final outcome = await installer.apply(package, bytes);
    log?.write(
      outcome.restartRequired
          ? 'установка запущена, приложение выходит'
          : 'автоматической установки нет: ${outcome.url}',
    );
    return outcome;
  }
}

/// Имя файла из URL пакета; для временного файла на диске.
String _packageFileName(Uri url, {required String fallback}) {
  final last = url.pathSegments.isEmpty ? '' : url.pathSegments.last;
  return last.isEmpty ? fallback : last;
}

/// Строка для `sh -c`: в одинарных кавычках, кавычка — `'\''`.
String _shQuote(String s) => "'${s.replaceAll("'", r"'\''")}'";
