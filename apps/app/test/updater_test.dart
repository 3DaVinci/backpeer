// Проверка и применение обновлений в приложении (задача 5.8.2): порядок
// «загрузить → проверить → остановить процессы → установить», подменённый
// пакет отклоняется до остановки процессов и установки; платформенные
// установщики (Windows, macOS, AppImage).

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:app/src/services/update_log.dart';
import 'package:app/src/services/updater.dart';
import 'package:core/core.dart';
import 'package:daemon_kit/daemon_kit.dart' show ServiceException;
import 'package:flutter_test/flutter_test.dart';

Future<UpdateOutcome> _okInstall(
  UpdatePackage package,
  Uint8List bytes,
) async => const UpdateOutcome(restartRequired: true);

void main() {
  late CryptoProvider crypto;
  late Ed25519KeyPair devKey;
  late Uint8List payload;
  late String manifestJson;

  setUpAll(() async {
    crypto = await SodiumCryptoProvider.load();
    devKey = await crypto.ed25519FromSeed(
      SecretBytes(base64Decode('zLxiViV3qqs870oI1CqKSbYLMDWMzRxpuaXqc0Gemgs=')),
    );
    payload = Uint8List.fromList(List.generate(42, (i) => i));
    manifestJson = jsonEncode({
      'format': 1,
      'channel': 'stable',
      'version': '0.0.3',
      'minVersion': '0.0.2',
      'releasedAt': '2026-11-03T10:00:00Z',
      'rollout': 1,
      'packages': [
        {
          'platform': 'linux',
          'arch': null,
          'url': 'https://u.example/pkg',
          'sha256': bytesToHex(crypto.blake2b256(payload)),
          'size': 42,
        },
      ],
      'signer': base64Encode(devKey.publicKey),
    });
  });

  Updater updater({
    UpdateFetch? fetch,
    Future<UpdateOutcome> Function(UpdatePackage, Uint8List)? install,
    Future<void> Function()? stop,
    String? kind,
    String? arch,
  }) {
    final client = UpdateClient(
      crypto: crypto,
      acceptedKeys: [devKey.publicKey],
      fetch: fetch,
    );
    final installer = _FakeInstaller(install ?? _okInstall, kind: kind);
    return Updater(
      client: client,
      currentVersion: ProductVersion.parse('0.0.2'),
      installId: Uint8List(16),
      platform: UpdatePlatform.linux,
      arch: arch,
      installer: installer,
      stop: stop ?? () async {},
    );
  }

  test('apply: загрузка и проверка до остановки и установки', () async {
    final order = <String>[];
    final u = updater(
      fetch: (url) async {
        order.add('fetch:${url.path}');
        return payload;
      },
      install: (pkg, bytes) async {
        order.add('install');
        return const UpdateOutcome(restartRequired: true);
      },
      stop: () async {
        order.add('stop');
      },
    );
    final manifest = UpdateManifest.parse(manifestJson);
    final result = await u.apply(manifest);
    expect(result.restartRequired, isTrue);
    expect(order, ['fetch:/pkg', 'stop', 'install']);
  });

  test(
    'apply: подменённый пакет отклоняется до остановки и установки',
    () async {
      var stopped = false;
      var installed = false;
      final u = updater(
        fetch: (url) async => Uint8List.fromList([...payload, 0xFF]),
        install: (pkg, bytes) async {
          installed = true;
          return const UpdateOutcome();
        },
        stop: () async {
          stopped = true;
        },
      );
      final manifest = UpdateManifest.parse(manifestJson);
      await expectLater(u.apply(manifest), throwsA(isA<IntegrityException>()));
      expect(stopped, isFalse);
      expect(installed, isFalse);
    },
  );

  test('apply: нет сборки под платформу', () async {
    final u = updater(fetch: (url) async => payload);
    await expectLater(
      u.apply(
        UpdateManifest.parse(manifestJson.replaceFirst('"linux"', '"windows"')),
      ),
      throwsA(isA<PreconditionException>()),
    );
  });

  test('AppImage: заменяет образ, сохраняет права и запускает новую '
      'версию', () async {
    final dir = Directory.systemTemp.createTempSync('fs-appimage-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final image = File('${dir.path}/backpeer.AppImage')
      ..writeAsBytesSync([1, 2, 3]);
    setUnixFileMode(image.path, 0x1ED); // 0755
    String? helper;
    final installer = AppImageInstaller(
      appImage: image.path,
      startHelper: (executable, args) async {
        helper = '$executable ${args.join(' ')}';
      },
    );
    final outcome = await installer.apply(
      UpdatePackage(
        platform: UpdatePlatform.linux,
        arch: null,
        url: Uri.parse('https://u.example/app'),
        sha256: Uint8List(32),
        size: 4,
      ),
      Uint8List.fromList([9, 9, 9, 9]),
    );
    expect(outcome.restartRequired, isTrue);
    expect(image.readAsBytesSync(), [9, 9, 9, 9]);
    expect(image.statSync().mode & 0x1FF, 0x1ED);
    expect(helper, startsWith('/bin/sh -c '));
    expect(helper, contains(image.path));
  }, skip: Platform.isWindows ? 'права POSIX' : false);

  test('Windows: скрипт ждёт приложение, ставит молча, пишет журнал и '
      'проверяет код возврата', () {
    final script = windowsUpdateScript(
      pid: 42,
      installer: r"C:\Temp\setup's.exe",
      app: r'C:\Apps\backpeer.exe',
      tempDir: r'C:\Temp\upd',
      logPath: r'C:\Apps\update.log',
      resultPath: r'C:\Apps\update-result.json',
    );
    // Ожидание — опросом процесса: приложение выходит через 2 секунды после
    // запуска оболочки, и Wait-Process по исчезнувшему PID рисковал
    // оборвать скрипт до установки (5.8.2).
    expect(script, contains('Get-Process -Id 42'));
    expect(script, isNot(contains('Wait-Process')));
    expect(script, contains(r"'C:\Temp\setup''s.exe'"));
    expect(script, contains('/VERYSILENT'));
    // /LOG= в кавычках: в пути может быть пробел.
    expect(script, contains(r"""('/LOG=`"' + $setupLog + '`"')"""));
    // Код возврата установщика проверяется, а не игнорируется.
    expect(script, contains('-PassThru'));
    expect(script, contains(r'$process.ExitCode'));
    // След попытки — журнал и итог рядом с ним.
    expect(script, contains(r"'C:\Apps\update.log'"));
    expect(script, contains(r"'C:\Apps\update-result.json'"));
    expect(script, contains('Write-Result'));
    expect(script, contains(r"'C:\Apps\backpeer.exe'"));
    expect(script, contains('Remove-Item -LiteralPath'));
  });

  test(
    'Windows: установщик запускается файлом скрипта, а не -Command',
    () async {
      final dir = Directory.systemTemp.createTempSync('fs-update-win-');
      addTearDown(() => dir.deleteSync(recursive: true));
      String? executable;
      List<String>? arguments;
      final installer = WindowsInstaller(
        appExecutable: r'C:\Apps\backpeer.exe',
        startHelper: (exe, args) async {
          executable = exe;
          arguments = args;
        },
        log: UpdateLog(
          log: File('${dir.path}/update.log'),
          result: File('${dir.path}/update-result.json'),
        ),
      );
      final outcome = await installer.apply(
        UpdatePackage(
          platform: UpdatePlatform.windows,
          arch: 'x64',
          url: Uri.parse('https://u.example/Backpeer-Setup-0.0.7.exe'),
          sha256: Uint8List(32),
          size: 4,
        ),
        Uint8List.fromList([9, 9, 9, 9]),
      );
      final script = File(arguments!.last);
      addTearDown(() {
        if (script.parent.existsSync()) {
          script.parent.deleteSync(recursive: true);
        }
      });
      expect(outcome.restartRequired, isTrue);
      expect(executable, 'powershell.exe');
      expect(arguments, contains('-File'));
      expect(arguments!.last, endsWith('update.ps1'));
      final text = script.readAsStringSync();
      expect(text, contains('/VERYSILENT'));
      expect(text, contains(File('${dir.path}/update.log').path));
      // Установщик лежит рядом со скриптом под именем из манифеста.
      expect(
        File('${script.parent.path}/Backpeer-Setup-0.0.7.exe').existsSync(),
        isTrue,
      );
      expect(
        File('${dir.path}/update.log').readAsStringSync(),
        contains('оболочка запущена'),
      );
    },
  );

  test('итог прошлой попытки читается один раз и только для неудачи', () {
    final dir = Directory.systemTemp.createTempSync('fs-update-result-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/update-result.json');
    final log = UpdateLog(log: File('${dir.path}/update.log'), result: file);

    expect(log.takeResult(), isNull, reason: 'файла ещё нет');

    file.writeAsStringSync(
      '{"ok":false,"stage":"installer", '
      '"message":"установщик Windows завершился с кодом 7", '
      r'"log":"C:\\Apps\\update.log"}',
    );
    expect(
      log.takeResult(),
      r'установщик Windows завершился с кодом 7, журнал: C:\Apps\update.log',
    );
    expect(file.existsSync(), isFalse, reason: 'сообщение показывается раз');

    // Успешная установка — показывать нечего.
    file.writeAsStringSync('{"ok":true,"stage":"done"}');
    expect(log.takeResult(), isNull);
    expect(file.existsSync(), isFalse);

    // Оболочка начала установку и не сообщила итог — это тоже неудача.
    file.writeAsStringSync('{"ok":false,"stage":"started","message":""}');
    expect(log.takeResult(), 'обновление не завершилось');

    // PowerShell 5.1 может записать BOM.
    file.writeAsStringSync('\uFEFF{"ok":false,"message":"нет сети"}');
    expect(log.takeResult(), 'нет сети');
  });

  test(
    'Linux .deb: из манифеста берётся пакет .deb, а не образ AppImage',
    () async {
      final deb = Uint8List.fromList([7, 7, 7, 7]);
      final json = jsonEncode({
        'format': 1,
        'channel': 'stable',
        'version': '0.0.3',
        'minVersion': '0.0.2',
        'releasedAt': '2026-11-03T10:00:00Z',
        'rollout': 1,
        'packages': [
          {
            'platform': 'linux',
            'arch': 'x64',
            'url': 'https://u.example/backpeer-0.0.3-x86_64.AppImage',
            'sha256': bytesToHex(crypto.blake2b256(deb)),
            'size': 4,
          },
          {
            'platform': 'linux',
            'arch': 'x64',
            'url': 'https://u.example/backpeer_0.0.3_amd64.deb',
            'sha256': bytesToHex(crypto.blake2b256(deb)),
            'size': 4,
          },
        ],
        'signer': base64Encode(devKey.publicKey),
      });
      final fetched = <String>[];
      final u = updater(
        kind: 'deb',
        arch: 'x64',
        fetch: (url) async {
          fetched.add(url.path);
          return deb;
        },
      );
      await u.apply(UpdateManifest.parse(json));
      expect(fetched, ['/backpeer_0.0.3_amd64.deb']);
    },
  );

  test(
    'нет сборки своего вида — показываем адрес, но не ставим чужую',
    () async {
      final json = jsonEncode({
        'format': 1,
        'channel': 'stable',
        'version': '0.0.3',
        'minVersion': '0.0.2',
        'releasedAt': '2026-11-03T10:00:00Z',
        'rollout': 1,
        'packages': [
          {
            'platform': 'linux',
            'arch': 'x64',
            'url': 'https://u.example/backpeer-0.0.3-x86_64.AppImage',
            'sha256': '00' * 32,
            'size': 4,
          },
        ],
        'signer': base64Encode(devKey.publicKey),
      });
      var stopped = false;
      var installed = false;
      final u = updater(
        kind: 'deb',
        arch: 'x64',
        stop: () async => stopped = true,
        install: (package, bytes) async {
          installed = true;
          return const UpdateOutcome();
        },
      );
      final outcome = await u.apply(UpdateManifest.parse(json));
      expect(installed, isFalse);
      expect(stopped, isFalse, reason: 'останавливать процессы не нужно');
      expect(outcome.url, 'https://u.example/backpeer-0.0.3-x86_64.AppImage');
    },
  );

  test(
    'Linux .deb: пакет ставится через pkexec apt-get, затем перезапуск',
    () async {
      final dir = Directory.systemTemp.createTempSync('fs-update-deb-');
      addTearDown(() => dir.deleteSync(recursive: true));
      String? executable;
      List<String>? arguments;
      var helper = <String>[];
      final installer = DebInstaller(
        appExecutable: '/opt/backpeer/backpeer',
        run: (exe, args) async {
          executable = exe;
          arguments = args;
          return ProcessResult(1, 0, 'Чтение списков пакетов…', '');
        },
        startHelper: (exe, args) async => helper = [exe, ...args],
      );
      final outcome = await installer.apply(
        UpdatePackage(
          platform: UpdatePlatform.linux,
          arch: 'x64',
          url: Uri.parse('https://u.example/backpeer_0.0.8_amd64.deb'),
          sha256: Uint8List(32),
          size: 4,
        ),
        Uint8List.fromList([1, 2, 3, 4]),
      );
      expect(outcome.restartRequired, isTrue);
      expect(executable, '/usr/bin/pkexec');
      expect(arguments!.take(3), ['/usr/bin/apt-get', 'install', '-y']);
      expect(arguments!.last, endsWith('backpeer_0.0.8_amd64.deb'));
      expect(
        File(arguments!.last).existsSync(),
        isFalse,
        reason: 'убран после',
      );
      // Перезапуск — отдельной оболочкой, которая ждёт выхода приложения.
      expect(helper.first, '/bin/sh');
      expect(helper.last, contains('kill -0'));
      expect(helper.last, contains('/opt/backpeer/backpeer'));
    },
  );

  test('Linux .deb: ошибка установки — понятная причина', () async {
    final installer = DebInstaller(
      appExecutable: '/opt/backpeer/backpeer',
      run: (exe, args) async =>
          ProcessResult(1, 100, '', 'dpkg: ошибка: пакет сломан'),
      startHelper: (exe, args) async {},
    );
    await expectLater(
      installer.apply(
        UpdatePackage(
          platform: UpdatePlatform.linux,
          arch: 'x64',
          url: Uri.parse('https://u.example/backpeer_0.0.8_amd64.deb'),
          sha256: Uint8List(32),
          size: 4,
        ),
        Uint8List.fromList([1, 2, 3, 4]),
      ),
      throwsA(
        isA<ServiceException>().having(
          (e) => e.message,
          'message',
          allOf(contains('код 100'), contains('пакет сломан')),
        ),
      ),
    );
  });

  test('Linux .deb: без pkexec — сообщение с адресом пакета', () async {
    final installer = DebInstaller(
      appExecutable: '/opt/backpeer/backpeer',
      run: (exe, args) async =>
          throw ProcessException(exe, args, 'нет файла', 2),
      startHelper: (exe, args) async {},
    );
    await expectLater(
      installer.apply(
        UpdatePackage(
          platform: UpdatePlatform.linux,
          arch: 'x64',
          url: Uri.parse('https://u.example/backpeer_0.0.8_amd64.deb'),
          sha256: Uint8List(32),
          size: 4,
        ),
        Uint8List.fromList([1, 2, 3, 4]),
      ),
      throwsA(
        isA<ServiceException>().having(
          (e) => e.message,
          'message',
          allOf(contains('pkexec'), contains('.deb')),
        ),
      ),
    );
  });

  test('Linux .deb: установку узнаём по базе dpkg', () {
    final info = Directory.systemTemp.createTempSync('fs-dpkg-');
    addTearDown(() => info.deleteSync(recursive: true));
    expect(DebInstaller.installedFromDeb(info: info.path), isFalse);
    File('${info.path}/backpeer.list').writeAsStringSync('/opt/backpeer');
    expect(DebInstaller.installedFromDeb(info: info.path), isTrue);
  });

  test('macOS: скрипт монтирует .dmg, заменяет .app и открывает его', () {
    final script = macUpdateScript(
      pid: 7,
      dmg: '/tmp/back peer.dmg',
      appBundle: '/Applications/Backpeer.app',
    );
    expect(script, contains("'/tmp/back peer.dmg'"));
    expect(script, contains('hdiutil attach'));
    expect(script, contains("'/Applications/Backpeer.app'"));
    expect(script, contains('ditto '));
    expect(script, contains('open '));
  });
}

final class _FakeInstaller implements UpdateInstaller {
  new(this._apply, {this.kind});

  final Future<UpdateOutcome> Function(UpdatePackage, Uint8List) _apply;

  /// Вид сборки, который «ставит» подделка; `null` — любой.
  final String? kind;

  @override
  String get description => 'тест';

  @override
  String? get packageKind => kind;

  @override
  bool get needsDownload => true;

  @override
  Future<UpdateOutcome> apply(UpdatePackage package, Uint8List bytes) =>
      _apply(package, bytes);
}
