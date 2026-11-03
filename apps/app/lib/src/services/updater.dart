import 'dart:ffi' show Abi;
import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:daemon_kit/daemon_kit.dart' show ServiceException;

/// Что делать с загруженным пакетом обновления (docs/spec/updates.md,
/// раздел 6). Платформозависимо; установка — после корректной остановки
/// фоновых процессов ([Updater.restart]).
abstract interface class UpdateInstaller {
  /// Как пакет будет поставлен, для человека.
  String get description;

  /// Ставит пакет [package] из [bytes] (хэш уже проверен). Возвращает
  /// описание сделанного для пользователя.
  Future<String> apply(UpdatePackage package, Uint8List bytes);
}

/// Для `.deb`/`.rpm` и до готовности установщиков macOS (5.7.2) и Windows
/// (5.7.1): автоматической установки нет, пользователю сообщается о новой
/// версии. Пакет не скачивается зря.
final class NotifyingInstaller implements UpdateInstaller {
  const new();

  @override
  String get description => 'уведомление о новой версии';

  @override
  Future<String> apply(UpdatePackage package, Uint8List bytes) async =>
      'новая версия загружена и проверена; установите её из пакета '
      '(${package.url})';
}

/// Linux AppImage: заменить файл образа и перезапустить службы новой
/// версией. Фактическое применение — на вызывающем (через [Updater.restart]
/// и `PersistentDaemons`); здесь — запись образа на место `$APPIMAGE`.
final class AppImageInstaller implements UpdateInstaller {
  new({Map<String, String>? environment})
    : _appImage = (environment ?? Platform.environment)['APPIMAGE'];

  final String? _appImage;

  @override
  String get description => 'замена образа AppImage';

  @override
  Future<String> apply(UpdatePackage package, Uint8List bytes) async {
    final target = _appImage;
    if (target == null) {
      throw const ServiceException('приложение запущено не из AppImage');
    }
    final file = File(target);
    // Запущенный образ — монтирование; файл на диске можно заменить.
    // Программа и службы перезапускаются после (вызывающий).
    File('${file.path}.new-$pid')
      ..writeAsBytesSync(bytes, flush: true)
      ..renameSync(file.path);
    return 'образ обновлён; перезапустите приложение';
  }
}

/// Проверка и применение обновлений приложения и фоновых процессов
/// (задача 5.8.2). Только проверяет подпись и хэш (ядро — [UpdateClient]) и
/// оркеструет установку: остановить процессы корректно, поставить пакет,
/// перезапустить.
final class Updater {
  new({
    required this.client,
    required this.currentVersion,
    required this.installId,
    required this.platform,
    required this.installer,
    required this.restart,
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
  /// продолжением при следующем запуске) и поднимает их снова. Вызывается
  /// после загрузки и проверки пакета, до установки.
  final Future<void> Function() restart;

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
  /// процессы, ставит и перезапускает. Порядок гарантирует: подменённый
  /// пакет отклоняется до остановки процессов и установки.
  Future<String> apply(UpdateManifest manifest) async {
    final package = manifest.packageFor(platform, arch);
    if (package == null) {
      final what = '${platform.name}${arch == null ? '' : '/$arch'}';
      throw PreconditionException('в манифесте нет сборки для $what');
    }
    final bytes = await client.download(package);
    await restart();
    return await installer.apply(package, bytes);
  }
}
