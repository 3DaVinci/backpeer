import 'dart:io';
import 'dart:typed_data';

import 'package:app/src/services/preferences.dart';
import 'package:app/src/services/update_log.dart';
import 'package:app/src/services/updater.dart';
import 'package:core/core.dart';

/// Управление обновлениями для приложения (задача 5.8.2): проверка по
/// [UpdateClient] из `core` и применение через [Updater]. В тестах —
/// подделка; настоящая — [OsUpdater].
abstract interface class UpdateControl {
  /// Есть ли обновление; `null` — нет или не в доле раскатки. Ошибки
  /// подписи и сети не проглатываются.
  Future<UpdateManifest?> check();

  /// Загружает пакет, проверяет хэш, корректно останавливает фоновые
  /// процессы, ставит и перезапускает.
  Future<UpdateOutcome> apply(UpdateManifest manifest);

  /// Итог прошлой попытки обновления, если она не удалась: `null` — итога
  /// нет или обновление установилось. Сообщение показывается один раз.
  Future<String?> takeLastFailure();
}

/// Настоящее управление обновлениями: клиент из `core` с ключом обновлений
/// из сборки приложения (`UPDATE_PUBLIC_KEY`, см. `update_config.dart`) и
/// установка на этой ОС. [baseUri] — база обновлений (`UPDATE_BASE_URL`,
/// для GitHub — `.../releases/latest/download`); `null` — обновления не
/// настроены.
final class OsUpdater implements UpdateControl {
  new({
    required this.baseUri,
    required this.currentVersion,
    required this.preferences,
    required this.acceptedKeys,
    required this.stopServices,
    required this.appExecutable,
    this.updateLog,
    this.platform,
    this.arch,
  });

  final Uri? baseUri;
  final ProductVersion currentVersion;
  final Preferences preferences;

  /// Допустимые открытые ключи обновлений (обычно один; при ротации —
  /// текущий и следующий, docs/spec/updates.md, раздел 2).
  final List<Uint8List> acceptedKeys;

  /// Останавливает фоновые процессы перед заменой программ. Приложение
  /// после установки запускает установщик (Windows/macOS) или новый образ
  /// AppImage; службы ставит уже новая версия.
  final Future<void> Function() stopServices;

  /// Путь к `backpeer.exe` в установленной папке (Windows) или к
  /// `.../Backpeer.app/Contents/MacOS/backpeer` (macOS).
  final String appExecutable;

  final UpdatePlatform? platform;
  final String? arch;

  /// Журнал и итог обновления (`<home>/app/update.log`,
  /// `update-result.json`); `null` — не вести.
  final UpdateLog? updateLog;

  UpdateInstaller _installer() {
    return switch (platform ?? Updater.currentPlatform()) {
      UpdatePlatform.windows => WindowsInstaller(
        appExecutable: appExecutable,
        log: updateLog,
      ),
      UpdatePlatform.macos => MacDmgInstaller(appExecutable: appExecutable),
      UpdatePlatform.linux =>
        Platform.environment['APPIMAGE'] != null
            ? AppImageInstaller()
            : const NotifyingInstaller(),
    };
  }

  Future<Updater> _updater() async {
    final crypto = await SodiumCryptoProvider.load();
    final client = UpdateClient(crypto: crypto, acceptedKeys: acceptedKeys);
    return Updater(
      client: client,
      currentVersion: currentVersion,
      installId: preferences.installId,
      platform: platform ?? Updater.currentPlatform(),
      arch: arch ?? Updater.currentArch(),
      installer: _installer(),
      stop: stopServices,
      log: updateLog,
    );
  }

  @override
  Future<UpdateManifest?> check() async {
    final uri = baseUri;
    if (uri == null) return null;
    final channel = preferences.betaChannel
        ? UpdateChannel.beta
        : UpdateChannel.stable;
    final updater = await _updater();
    try {
      return await updater.check(baseUri: uri, channel: channel);
    } finally {
      updater.client.close();
    }
  }

  @override
  Future<UpdateOutcome> apply(UpdateManifest manifest) async {
    final updater = await _updater();
    try {
      return await updater.apply(manifest);
    } finally {
      updater.client.close();
    }
  }

  @override
  Future<String?> takeLastFailure() async => updateLog?.takeResult();
}
