import 'package:agent/agent.dart' show ClientServices;
import 'package:app/src/services/preferences.dart';
import 'package:app/src/services/updater.dart';
import 'package:core/core.dart';
import 'package:daemon_kit/daemon_kit.dart' show UserServices;

/// Управление обновлениями для приложения (задача 5.8.2): проверка по
/// [UpdateClient] из `core` и применение через [Updater]. В тестах —
/// подделка; настоящая — [OsUpdater].
abstract interface class UpdateControl {
  /// Есть ли обновление; `null` — нет или не в доле раскатки. Ошибки
  /// подписи и сети не проглатываются.
  Future<UpdateManifest?> check();

  /// Загружает пакет, проверяет хэш, корректно останавливает фоновые
  /// процессы, ставит и перезапускает.
  Future<String> apply(UpdateManifest manifest);
}

/// Настоящее управление обновлениями: клиент из `core` с ключом обновлений
/// ([UpdateKeys]) и установка на этой ОС. [baseUri] — адрес обновлений;
/// `null` — обновления не настроены ([check] отвечает «нет»).
final class OsUpdater implements UpdateControl {
  new({
    required this.baseUri,
    required this.currentVersion,
    required this.preferences,
    required this.services,
    required this.installAgent,
    this.platform,
    this.arch,
  });

  final Uri? baseUri;
  final ProductVersion currentVersion;
  final Preferences preferences;
  final UserServices services;

  /// Переустановка службы агента после замены программ (из фоновой работы
  /// приложения, `OsBackground`).
  final Future<void> Function() installAgent;

  final UpdatePlatform? platform;
  final String? arch;

  UpdateInstaller _installer() {
    if ((platform ?? Updater.currentPlatform()) == UpdatePlatform.linux) {
      return AppImageInstaller();
    }
    // .deb/.rpm и до готовности установщиков macOS/Windows — уведомление.
    return const NotifyingInstaller();
  }

  Future<Updater> _updater() async {
    final crypto = await SodiumCryptoProvider.load();
    final client = UpdateClient(
      crypto: crypto,
      acceptedKeys: [UpdateKeys.devPublicKey()],
    );
    return Updater(
      client: client,
      currentVersion: currentVersion,
      installId: preferences.installId,
      platform: platform ?? Updater.currentPlatform(),
      arch: arch ?? Updater.currentArch(),
      installer: _installer(),
      restart: _restart,
    );
  }

  /// Корректная остановка фоновых процессов перед заменой программ:
  /// службы получают SIGTERM, агент отменяет задание (бэкап продолжится при
  /// следующем запуске — ADR-008), затем агент ставится заново.
  Future<void> _restart() async {
    for (final name in [ClientServices.nodeName, ClientServices.agentName]) {
      await services.stop(name).catchError((_) {});
    }
    await installAgent();
  }

  @override
  Future<UpdateManifest?> check() async {
    final uri = baseUri;
    if (uri == null) return null;
    final channel = preferences.betaChannel
        ? UpdateChannel.beta
        : UpdateChannel.stable;
    return await (await _updater()).check(baseUri: uri, channel: channel);
  }

  @override
  Future<String> apply(UpdateManifest manifest) async =>
      await (await _updater()).apply(manifest);
}
