import 'dart:io';
import 'dart:typed_data';

import 'package:cli/src/app_config.dart';
import 'package:cli/src/session.dart';
import 'package:core/core.dart';
import 'package:protocol/protocol.dart' as pb;

/// Ошибка операции с учётной записью: [code] — для программ (локальный API
/// агента бэкапа, `docs/ops/agent.md`), [message] — для человека.
final class AccountException implements Exception {
  const new(this.code, this.message);

  /// `exists`, `no_coordinator`, `login_taken`, `unauthenticated`,
  /// `wrong_password`, `weak_password`, `bad_phrase`, `no_phrase`,
  /// `too_many_devices`, `current_device`, `not_found`, `rate_limited`,
  /// `unavailable`, `failed`.
  final String code;
  final String message;

  @override
  String toString() => message;
}

/// Устройство учётной записи из `ListDevices` с проверенным сертификатом.
typedef AccountDevice = ({
  String deviceId,
  DateTime addedAt,
  DateTime? revokedAt,
  bool current,
});

/// Операции с учётной записью без ввода-вывода (задачи 2.8.3, 5.2): создание,
/// вход по паролю, восстановление по фразе, устройства, пароль, копия
/// ключа на координаторе. Общие для CLI и агента бэкапа: CLI спрашивает
/// пароль и фразу в консоли, агент получает их от приложения.
///
/// Методы, возвращающие ключи, передают их во владение вызывающему.
final class AccountOps {
  new({
    required this.home,
    required this.crypto,
    required this.software,
    this.argon2 = const Argon2Params(),
  });

  final AppHome home;
  final CryptoProvider crypto;

  /// Имя и версия программы для координатора.
  final String software;
  final Argon2Params argon2;

  DeviceKeyStore get keyStore =>
      DeviceKeyStore(home.keysFile, crypto, params: argon2);

  /// Настройки нового устройства: папки по умолчанию в каталоге программы,
  /// новый идентификатор устройства.
  AppConfig newConfig({
    String? coordinator,
    String? coordinatorCa,
    String? nodes,
    int nodeCount = 20,
    String? objects,
    DurabilityParameters? durability,
    FragmentsMode fragments = FragmentsMode.folders,
    bool distinctSubnets = true,
  }) => AppConfig(
    nodes: nodes ?? '${home.dir.path}/nodes',
    nodeCount: nodeCount,
    objects: objects ?? '${home.dir.path}/objects',
    durability: durability ?? DurabilityParameters(),
    deviceId: crypto.randomBytes(32),
    coordinator: coordinator,
    coordinatorCa: coordinator == null ? null : coordinatorCa,
    fragments: fragments,
    distinctSubnets: distinctSubnets,
  )..check();

  /// Каталог программы ещё пуст.
  void requireEmptyHome() {
    if (home.keysFile.existsSync()) {
      throw AccountException(
        'exists',
        'В ${home.dir.path} уже есть учётная запись',
      );
    }
  }

  /// Новый пароль по требованиям `PasswordPolicy` (crypto.md, раздел 4.3):
  /// слабый не принимается, средний — только с [acceptWeak].
  static void checkNewPassword(
    String password, {
    List<String> userInputs = const [],
    bool acceptWeak = false,
  }) {
    final a = PasswordPolicy.assess(password, userInputs: userInputs);
    if (a.verdict == PasswordVerdict.rejected ||
        (a.verdict == PasswordVerdict.weak && !acceptWeak)) {
      throw AccountException(
        'weak_password',
        a.verdict == PasswordVerdict.rejected
            ? 'пароль не принят: слишком простой'
            : 'пароль средней стойкости: нужно явное согласие',
      );
    }
  }

  /// Разбор фразы восстановления.
  static RecoveryPhrase parsePhrase(String text) {
    try {
      return RecoveryPhrase.parse(text);
    } on DataFormatException catch (e) {
      throw AccountException(
        'bad_phrase',
        'Фраза не разобрана: ${e.detail ?? e.problem.description}',
      );
    } on IntegrityException {
      throw const AccountException(
        'bad_phrase',
        'Фраза с ошибкой: не сходится контрольная сумма',
      );
    }
  }

  /// Клиент координатора из настроек [config].
  CoordinatorClient client(AppConfig config, {DeviceKeys? device}) {
    final url = config.coordinator;
    if (url == null) {
      throw const AccountException(
        'no_coordinator',
        'Устройство работает без координатора (init); команда недоступна',
      );
    }
    return openCoordinatorClient(
      url,
      crypto: crypto,
      ca: config.coordinatorCa,
      device: device,
      userAgent: software,
    );
  }

  /// Новая учётная запись по фразе [phrase] и паролю [password]. Без
  /// координатора — только ключи и настройки (`cli init`); с ним
  /// (`config.login` обязателен) — ещё ключи устройства, сертификат и
  /// `RegisterAccount` с копией мастер-ключа под паролем или без неё
  /// ([keyCopy] = `false`, модель угроз, К-3). Файлы пишутся только после
  /// ответа координатора.
  Future<(AccountKeys, DeviceKeys?)> create({
    required AppConfig config,
    required RecoveryPhrase phrase,
    required String password,
    bool keyCopy = true,
  }) async {
    requireEmptyHome();
    final keys = await AccountKeys.fromPhrase(phrase, crypto);
    DeviceKeys? device;
    try {
      if (config.coordinator != null) {
        final login = config.login!;
        device = await DeviceKeys.generate(crypto);
        final client = this.client(config);
        try {
          final copy = keyCopy
              ? await KeyCopy.create(
                  crypto,
                  keys: keys,
                  password: password,
                  params: argon2,
                )
              : KeyCopy.none;
          try {
            await client.registerAccount(
              pb.RegisterAccountRequest(
                deviceCertificate: await DeviceCertificates.issue(
                  crypto,
                  keys,
                  device,
                  issuedAt: DateTime.now(),
                ),
                login: login,
                keyBundle: copy.keyBundle,
                authVerifier: copy.authVerifier,
              ),
              accountKey: keys.accountSign,
            );
          } on CoordinatorException catch (e) {
            if (e.code == pb.ErrorCode.ERROR_CODE_ALREADY_EXISTS) {
              throw AccountException(
                'login_taken',
                'Имя $login занято, выберите другое',
              );
            }
            coordinatorFailure(e);
          }
          config
            ..deviceId = device.deviceId
            ..keyCopy = copy.enabled;
        } finally {
          client.close();
        }
      }
      await keyStore.create(keys, password, phrase: phrase, device: device);
      config.save(home);
      LocalIndex.open(home.indexPath).close();
      return (keys, device);
    } on Object {
      keys.dispose();
      device?.dispose();
      rethrow;
    }
  }

  /// Вход на новом устройстве по имени `config.login` и паролю (protocol.md,
  /// раздел 4.7): KeyBundle с координатора, новые ключи устройства и
  /// `AddDevice`. Копии фразы на устройстве не будет. Локальный индекс —
  /// [restoreIndex].
  Future<(AccountKeys, DeviceKeys)> login({
    required AppConfig config,
    required String password,
  }) async {
    requireEmptyHome();
    final login = config.login!;
    config.keyCopy = true;
    final client = this.client(config);
    try {
      final AccountKeys keys;
      try {
        (keys, _) = await loginWithPassword(
          client,
          crypto,
          login: login,
          password: password,
        );
      } on CoordinatorException catch (e) {
        coordinatorFailure(
          e,
          unauthenticated:
              'Неверное имя или пароль, либо вход по паролю для этой учётной '
              'записи выключен (тогда — recover по фразе)',
        );
      } on CoreException catch (e) {
        throw AccountException(
          'failed',
          'Копия ключа с координатора не открыта: ${e.message}',
        );
      }
      final device = await DeviceKeys.generate(crypto);
      try {
        await _addDevice(client, keys, device);
        config.deviceId = device.deviceId;
        await keyStore.create(keys, password, device: device);
        config.save(home);
        return (keys, device);
      } on Object {
        keys.dispose();
        device.dispose();
        rethrow;
      }
    } finally {
      client.close();
    }
  }

  /// Учётная запись на этом устройстве по фразе; с координатором — новое
  /// устройство (`AddDevice`). Локальный индекс — [restoreIndex].
  Future<(AccountKeys, DeviceKeys?)> recover({
    required AppConfig config,
    required RecoveryPhrase phrase,
    required String password,
  }) async {
    requireEmptyHome();
    final keys = await AccountKeys.fromPhrase(phrase, crypto);
    DeviceKeys? device;
    try {
      if (config.coordinator != null) {
        device = await DeviceKeys.generate(crypto);
        final client = this.client(config);
        try {
          await _addDevice(client, keys, device);
        } finally {
          client.close();
        }
        config.deviceId = device.deviceId;
      }
      await keyStore.create(keys, password, phrase: phrase, device: device);
      config.save(home);
      return (keys, device);
    } on Object {
      keys.dispose();
      device?.dispose();
      rethrow;
    }
  }

  Future<void> _addDevice(
    CoordinatorClient client,
    AccountKeys keys,
    DeviceKeys device,
  ) async {
    try {
      await client.addDevice(
        pb.AddDeviceRequest(
          deviceCertificate: await DeviceCertificates.issue(
            crypto,
            keys,
            device,
            issuedAt: DateTime.now(),
          ),
        ),
        accountKey: keys.accountSign,
      );
    } on CoordinatorException catch (e) {
      if (e.code == pb.ErrorCode.ERROR_CODE_QUOTA_EXCEEDED) {
        throw const AccountException(
          'too_many_devices',
          'У учётной записи уже 5 устройств: отзовите ненужное на другом '
              'устройстве',
        );
      }
      coordinatorFailure(
        e,
        unauthenticated: 'учётная запись не зарегистрирована на координаторе',
      );
    }
  }

  /// Локальный индекс из объектов-индексов (новое устройство, recover,
  /// login).
  Future<RecoveryReport> restoreIndex(
    AppConfig config,
    AccountKeys keys,
    DeviceKeys? device,
  ) async {
    final client = config.coordinator == null
        ? null
        : this.client(config, device: device);
    final objects = client == null
        ? LocalObjectStore(Directory(config.objects))
        : CoordinatorObjectStore(client);
    final index = LocalIndex.open(home.indexPath);
    try {
      return await recoverIndex(
        crypto: crypto,
        manifestKey: keys.manifestKey,
        store: objects,
        index: index,
      );
    } finally {
      index.close();
      client?.close();
    }
  }

  /// Фраза восстановления по паролю (если её копия есть на устройстве).
  Future<RecoveryPhrase> phrase(String password) async {
    final store = keyStore;
    if (!store.hasPhrase) {
      throw const AccountException(
        'no_phrase',
        'Копии фразы на этом устройстве нет',
      );
    }
    try {
      return await store.unlockPhrase(password);
    } on IntegrityException {
      throw const AccountException('wrong_password', 'Неверный пароль');
    }
  }

  /// Ключи учётной записи и устройства по паролю.
  Future<(AccountKeys, DeviceKeys?)> unlock(String password) async {
    try {
      return await keyStore.unlockWithDevice(password);
    } on IntegrityException {
      throw const AccountException('wrong_password', 'Неверный пароль');
    }
  }

  /// Устройства учётной записи (`ListDevices`); сертификаты проверяются —
  /// список отдаёт координатор, ему не доверяют. `invalid` — сколько
  /// устройств пришло с неверным сертификатом.
  Future<({List<AccountDevice> devices, int invalid})> devices(
    AppConfig config,
    AccountKeys keys,
    DeviceKeys device,
  ) async {
    final client = this.client(config, device: device);
    try {
      final out = <AccountDevice>[];
      var invalid = 0;
      for (final (cert, info) in await _listDevices(client, keys)) {
        if (cert == null) {
          invalid++;
          continue;
        }
        final revoked = info.revokedAtUnixMs.toInt();
        out.add((
          deviceId: bytesToHex(cert.deviceSign),
          addedAt: DateTime.fromMillisecondsSinceEpoch(
            info.addedAtUnixMs.toInt(),
            isUtc: true,
          ),
          revokedAt: revoked == 0
              ? null
              : DateTime.fromMillisecondsSinceEpoch(revoked, isUtc: true),
          current: constantTimeEquals(cert.deviceSign, device.deviceId),
        ));
      }
      return (devices: out, invalid: invalid);
    } finally {
      client.close();
    }
  }

  Future<List<(pb.DeviceCertificate?, pb.DeviceInfo)>> _listDevices(
    CoordinatorClient client,
    AccountKeys keys,
  ) async {
    final pb.ListDevicesResponse response;
    try {
      response = await client.listDevices(accountKey: keys.accountSign);
    } on CoordinatorException catch (e) {
      coordinatorFailure(e);
    }
    final out = <(pb.DeviceCertificate?, pb.DeviceInfo)>[];
    for (final info in response.devices) {
      pb.DeviceCertificate? cert;
      try {
        if (constantTimeEquals(info.certificate.signer, keys.accountId)) {
          cert = await SignedMessages.open(
            crypto,
            info.certificate,
            context: DeviceCertificates.signingContext,
            object: DeviceCertificates.signingContext,
            parse: pb.DeviceCertificate.fromBuffer,
          );
          if (!constantTimeEquals(cert.accountId, keys.accountId) ||
              cert.deviceSign.length != CryptoProvider.keyLength) {
            cert = null;
          }
        }
      } on CoreException {
        cert = null;
      }
      out.add((cert, info));
    }
    return out;
  }

  /// Отзыв другого устройства (`RevokeDevice`) по началу идентификатора
  /// [prefix] (не короче 4 hex-символов). Возвращает полный идентификатор.
  Future<String> revoke(
    AppConfig config,
    AccountKeys keys,
    DeviceKeys device,
    String prefix,
  ) async {
    final p = prefix.toLowerCase();
    final client = this.client(config, device: device);
    try {
      final found = [
        for (final (cert, _) in await _listDevices(client, keys))
          if (cert != null && bytesToHex(cert.deviceSign).startsWith(p)) cert,
      ];
      final cert = switch (found) {
        [final c] => c,
        [] => throw AccountException('not_found', 'Устройство $p не найдено'),
        _ => throw AccountException(
          'not_found',
          'Префикс $p подходит к ${found.length} устройствам',
        ),
      };
      if (constantTimeEquals(cert.deviceSign, device.deviceId)) {
        throw const AccountException(
          'current_device',
          'Это устройство; отзовите его с другого устройства',
        );
      }
      try {
        await client.revokeDevice(
          pb.RevokeDeviceRequest(
            revocation: await DeviceCertificates.revoke(
              crypto,
              keys,
              deviceSign: Uint8List.fromList(cert.deviceSign),
              revokedAt: DateTime.now(),
            ),
          ),
          accountKey: keys.accountSign,
        );
      } on CoordinatorException catch (e) {
        coordinatorFailure(e);
      }
      return bytesToHex(cert.deviceSign);
    } finally {
      client.close();
    }
  }

  /// Смена пароля: сначала копия ключа на координаторе (если включена),
  /// затем локальная — если координатор откажет, обе копии открываются
  /// прежним паролем. `keyCopyUnknown` — неизвестно, есть ли на
  /// координаторе копия под старым паролем (устройство восстановлено по
  /// фразе).
  Future<({bool keyCopyUpdated, bool keyCopyUnknown})> changePassword(
    AppConfig config,
    String oldPassword,
    String newPassword,
  ) async {
    final (keys, device) = await unlock(oldPassword);
    try {
      var remote = false;
      if (config.coordinator != null && config.keyCopy == true) {
        await _setKeyCopy(
          config,
          keys,
          await KeyCopy.create(
            crypto,
            keys: keys,
            password: newPassword,
            params: argon2,
          ),
        );
        remote = true;
      }
      await keyStore.changePassword(oldPassword, newPassword);
      return (
        keyCopyUpdated: remote,
        keyCopyUnknown: config.coordinator != null && config.keyCopy == null,
      );
    } finally {
      keys.dispose();
      device?.dispose();
    }
  }

  /// Копия мастер-ключа на координаторе под паролем: включить (вход по
  /// паролю на новом устройстве) или выключить (только по фразе; модель
  /// угроз, К-3). Пароль нужен и для выключения: без него нет ключей.
  Future<void> setKeyCopy(
    AppConfig config,
    String password, {
    required bool enabled,
  }) async {
    if (config.coordinator == null) client(config);
    final (keys, device) = await unlock(password);
    try {
      await _setKeyCopy(
        config,
        keys,
        enabled
            ? await KeyCopy.create(
                crypto,
                keys: keys,
                password: password,
                params: argon2,
              )
            : KeyCopy.none,
      );
      config
        ..keyCopy = enabled
        ..save(home);
    } finally {
      keys.dispose();
      device?.dispose();
    }
  }

  Future<void> _setKeyCopy(
    AppConfig config,
    AccountKeys keys,
    KeyCopy copy,
  ) async {
    final client = this.client(config);
    try {
      await client.setKeyBundle(
        pb.SetKeyBundleRequest(
          keyBundle: copy.keyBundle,
          authVerifier: copy.authVerifier,
        ),
        accountKey: keys.accountSign,
      );
    } on CoordinatorException catch (e) {
      coordinatorFailure(e);
    } finally {
      client.close();
    }
  }
}

/// Понятная ошибка для ошибки координатора при работе с учётной записью.
Never coordinatorFailure(CoordinatorException e, {String? unauthenticated}) {
  throw switch (e.code) {
    pb.ErrorCode.ERROR_CODE_UNAUTHENTICATED when unauthenticated != null =>
      AccountException('unauthenticated', unauthenticated),
    pb.ErrorCode.ERROR_CODE_RATE_LIMITED => AccountException(
      'rate_limited',
      'координатор просит подождать'
          '${e.retryAfter == null ? '' : ' ${_duration(e.retryAfter!)}'}',
    ),
    pb.ErrorCode.ERROR_CODE_UNAVAILABLE => const AccountException(
      'unavailable',
      'координатор недоступен',
    ),
    _ => AccountException('failed', e.message),
  };
}

String _duration(Duration d) => d.inMinutes >= 1
    ? '${d.inMinutes} мин'
    : '${(d.inMilliseconds / 1000).ceil()} с';
