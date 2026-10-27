import 'package:cli/cli.dart';
import 'package:core/core.dart';
import 'package:daemon_kit/daemon_kit.dart';
import 'package:logging/logging.dart';

/// Ключи открыты: сохранить их для фоновой работы (как `unlock`) и
/// запустить расписание. Возвращает `remembered` и `reason`.
typedef AdoptKeys = Future<Map<String, Object?>> Function(
  AccountKeys keys,
  DeviceKeys? device, {
  required bool remember,
});

/// Тело с ключами агента (без пароля); ключей нет — `keys_required`.
typedef WithKeys = Future<Map<String, Object?>> Function(
  Future<Map<String, Object?>> Function(AccountKeys, DeviceKeys?) body,
);

/// Методы `account.*` локального API агента (задачи 5.2.1–5.2.3,
/// `docs/ops/agent.md`, раздел «Учётная запись»): создание учётной записи,
/// вход по паролю и по фразе, фраза, устройства, пароль, копия ключа.
/// Ключи создаёт и хранит агент; приложение видит только фразу — чтобы
/// показать её пользователю.
final class AccountApi {
  new({required this.ops, required this.adopt, required this.withKeys});

  final AccountOps ops;
  final AdoptKeys adopt;
  final WithKeys withKeys;

  static final _log = Logger('agent.account');

  /// Фраза для новой учётной записи от `account.new_phrase` до
  /// `account.create`.
  RecoveryPhrase? _draft;

  /// Идёт операция, меняющая учётную запись.
  bool _busy = false;

  /// Сколько слов фразы приложение должно вернуть в `account.create`
  /// (У-2: фраза записана).
  static const wordsToConfirm = 3;

  Future<Map<String, Object?>> handle(
    String method,
    Map<String, Object?> params,
  ) async {
    try {
      return switch (method) {
        'account.info' => _info(),
        'account.new_phrase' => _newPhrase(),
        'account.create' => await _exclusive(() => _create(params)),
        'account.login' => await _exclusive(() => _login(params)),
        'account.recover' => await _exclusive(() => _recover(params)),
        'account.phrase' => await _phrase(params),
        'account.devices' => await _devices(),
        'account.revoke' => await _revoke(params),
        'account.passwd' => await _exclusive(() => _passwd(params)),
        'account.key_copy' => await _exclusive(() => _keyCopy(params)),
        _ => throw ControlException(
          'unknown_method',
          'неизвестный метод $method',
        ),
      };
    } on AccountException catch (e) {
      throw ControlException(e.code, e.message);
    } on SessionException catch (e) {
      throw ControlException(e.usage ? 'bad_request' : 'failed', e.message);
    } on ConfigException catch (e) {
      throw ControlException('bad_request', e.message);
    } on CoreException catch (e) {
      throw ControlException('failed', e.message);
    }
  }

  Future<Map<String, Object?>> _exclusive(
    Future<Map<String, Object?>> Function() body,
  ) async {
    if (_busy) {
      throw const ControlException(
        'busy',
        'уже идёт операция с учётной записью',
      );
    }
    _busy = true;
    try {
      return await body();
    } finally {
      _busy = false;
    }
  }

  /// Учётная запись на устройстве: без ключей, по `config.json`.
  Map<String, Object?> _info() {
    if (!ops.home.initialized) return {'configured': false};
    final config = AppConfig.load(ops.home);
    return {
      'configured': true,
      'coordinator': config.coordinator,
      'login': config.login,
      'keyCopy': config.keyCopy,
      'deviceId': bytesToHex(config.deviceId),
      'hasPhrase': ops.keyStore.hasPhrase,
    };
  }

  Map<String, Object?> _newPhrase() {
    ops.requireEmptyHome();
    _draft?.dispose();
    final phrase = _draft = RecoveryPhrase.generate(ops.crypto);
    return {'words': phrase.words, 'confirm': wordsToConfirm};
  }

  /// Новые настройки по параметрам: адрес координатора и его УЦ, способ
  /// хранения фрагментов (по умолчанию — по сети), проверка подсетей; без
  /// координатора — папки-«узлы» и папка объектов (по умолчанию в каталоге
  /// программы).
  AppConfig _config(Map<String, Object?> params) {
    final coordinator = _optional<String>(params, 'coordinator');
    final fragments = _optional<String>(params, 'fragments');
    return ops.newConfig(
      coordinator: coordinator == null || coordinator.isEmpty
          ? null
          : coordinator,
      coordinatorCa: _optional<String>(params, 'ca'),
      fragments: fragments == null
          ? FragmentsMode.network
          : FragmentsMode.parse(fragments),
      distinctSubnets: _optional<bool>(params, 'subnetCheck') ?? true,
      nodes: _optional<String>(params, 'nodes'),
      objects: _optional<String>(params, 'objects'),
    );
  }

  String? _loginName(Map<String, Object?> params, AppConfig config) {
    final raw = _optional<String>(params, 'login');
    if (config.coordinator == null) return null;
    final login = raw == null ? null : LoginName.normalize(raw);
    if (login == null) {
      throw const ControlException(
        'bad_request',
        'login: 3–32 символа a–z, 0–9, «.», «_», «-», первый — буква или '
            'цифра',
      );
    }
    return login;
  }

  Future<Map<String, Object?>> _create(Map<String, Object?> params) async {
    ops.requireEmptyHome();
    final config = _config(params);
    config.login = _loginName(params, config);
    final password = _required<String>(params, 'password');
    AccountOps.checkNewPassword(
      password,
      userInputs: [?config.login],
      acceptWeak: _optional<bool>(params, 'acceptWeak') ?? false,
    );
    final phrase = _draft;
    if (phrase == null) {
      throw const ControlException(
        'phrase_not_confirmed',
        'сначала account.new_phrase',
      );
    }
    _checkConfirmation(phrase.words, params['confirm']);
    final (keys, device) = await ops.create(
      config: config,
      phrase: phrase,
      password: password,
      keyCopy: _optional<bool>(params, 'keyCopy') ?? true,
    );
    _draft = null;
    phrase.dispose();
    _log.info(
      LogEvent('account_created', {
        'coordinator': config.coordinator != null,
        'keyCopy': config.keyCopy,
      }),
    );
    return {
      'accountId': bytesToHex(keys.accountId),
      'deviceId': bytesToHex(config.deviceId),
      'keyCopy': config.keyCopy,
      ...await _adopt(keys, device, params),
    };
  }

  /// Подтверждение фразы: `{"номер слова с 1": "слово"}`, не меньше
  /// [wordsToConfirm] слов, все верные.
  static void _checkConfirmation(List<String> words, Object? confirm) {
    var matched = 0;
    if (confirm is Map<String, Object?>) {
      for (final MapEntry(:key, :value) in confirm.entries) {
        final i = int.tryParse(key);
        if (i == null || i < 1 || i > words.length || value is! String) {
          matched = -1;
          break;
        }
        if (value.trim().toLowerCase() != words[i - 1]) {
          matched = -1;
          break;
        }
        matched++;
      }
    }
    if (matched < wordsToConfirm) {
      throw const ControlException(
        'phrase_not_confirmed',
        'фраза не подтверждена: слова не совпадают',
      );
    }
  }

  Future<Map<String, Object?>> _login(Map<String, Object?> params) async {
    ops.requireEmptyHome();
    final config = _config(params);
    if (config.coordinator == null) {
      throw const ControlException(
        'bad_request',
        'вход по паролю — только с координатором (coordinator)',
      );
    }
    config.login = _loginName(params, config);
    final (keys, device) = await ops.login(
      config: config,
      password: _required<String>(params, 'password'),
    );
    _log.info(const LogEvent('account_login'));
    return await _restored(config, keys, device, params);
  }

  Future<Map<String, Object?>> _recover(Map<String, Object?> params) async {
    ops.requireEmptyHome();
    final config = _config(params);
    final password = _required<String>(params, 'password');
    AccountOps.checkNewPassword(
      password,
      acceptWeak: _optional<bool>(params, 'acceptWeak') ?? false,
    );
    final phrase = AccountOps.parsePhrase(_required<String>(params, 'phrase'));
    try {
      final (keys, device) = await ops.recover(
        config: config,
        phrase: phrase,
        password: password,
      );
      _log.info(
        LogEvent('account_recovered', {
          'coordinator': config.coordinator != null,
        }),
      );
      return await _restored(config, keys, device, params);
    } finally {
      phrase.dispose();
    }
  }

  /// После входа: локальный индекс из объектов-индексов, ключи — агенту.
  /// Индекс не прочитан — учётная запись уже на устройстве, ошибка
  /// возвращается в `indexError`: индекс восстановится при следующем
  /// бэкапе или сборке мусора.
  Future<Map<String, Object?>> _restored(
    AppConfig config,
    AccountKeys keys,
    DeviceKeys? device,
    Map<String, Object?> params,
  ) async {
    Map<String, Object?> index;
    try {
      final report = await ops.restoreIndex(config, keys, device);
      index = {
        'indexes': report.indexesRead,
        'segments': report.segmentsAdded,
        'unreadable': report.unreadable.length,
      };
    } on CoreException catch (e) {
      index = {'indexError': e.message};
    } on SessionException catch (e) {
      index = {'indexError': e.message};
    }
    return {
      'accountId': bytesToHex(keys.accountId),
      'deviceId': bytesToHex(config.deviceId),
      'keyCopy': config.keyCopy,
      ...index,
      ...await _adopt(keys, device, params),
    };
  }

  /// Ключи переходят агенту и освобождаются.
  Future<Map<String, Object?>> _adopt(
    AccountKeys keys,
    DeviceKeys? device,
    Map<String, Object?> params,
  ) async {
    try {
      return await adopt(
        keys,
        device,
        remember: _optional<bool>(params, 'remember') ?? true,
      );
    } finally {
      keys.dispose();
      device?.dispose();
    }
  }

  Future<Map<String, Object?>> _phrase(Map<String, Object?> params) async {
    _requireAccount();
    final phrase = await ops.phrase(_required<String>(params, 'password'));
    try {
      return {'words': phrase.words};
    } finally {
      phrase.dispose();
    }
  }

  /// Настройки с координатором и ключи устройства для методов, которые
  /// подписывает ключ учётной записи.
  Future<Map<String, Object?>> _signed(
    Future<Map<String, Object?>> Function(
      AppConfig config,
      AccountKeys keys,
      DeviceKeys device,
    )
    body,
  ) {
    _requireAccount();
    final config = AppConfig.load(ops.home);
    if (config.coordinator == null) {
      throw const AccountException(
        'no_coordinator',
        'устройство работает без координатора',
      );
    }
    return withKeys((keys, device) {
      if (device == null) {
        throw const AccountException(
          'no_coordinator',
          'на этом устройстве нет ключей устройства',
        );
      }
      return body(config, keys, device);
    });
  }

  Future<Map<String, Object?>> _devices() =>
      _signed((config, keys, device) async {
        final (:devices, :invalid) = await ops.devices(config, keys, device);
        return {
          'devices': [
            for (final d in devices)
              {
                'deviceId': d.deviceId,
                'addedAt': d.addedAt.toIso8601String(),
                'revokedAt': d.revokedAt?.toIso8601String(),
                'current': d.current,
              },
          ],
          'invalid': invalid,
        };
      });

  Future<Map<String, Object?>> _revoke(Map<String, Object?> params) {
    final prefix = _required<String>(params, 'device');
    if (prefix.length < 4) {
      throw const ControlException(
        'bad_request',
        'device: не меньше 4 символов идентификатора',
      );
    }
    return _signed((config, keys, device) async {
      final id = await ops.revoke(config, keys, device, prefix);
      _log.info(LogEvent('device_revoked', {'device': id.substring(0, 16)}));
      return {'deviceId': id};
    });
  }

  Future<Map<String, Object?>> _passwd(Map<String, Object?> params) async {
    _requireAccount();
    final config = AppConfig.load(ops.home);
    final old = _required<String>(params, 'password');
    final password = _required<String>(params, 'newPassword');
    // Неверный старый пароль — раньше, чем оценка нового.
    final (keys, device) = await ops.unlock(old);
    keys.dispose();
    device?.dispose();
    AccountOps.checkNewPassword(
      password,
      userInputs: [?config.login],
      acceptWeak: _optional<bool>(params, 'acceptWeak') ?? false,
    );
    final (:keyCopyUpdated, :keyCopyUnknown) = await ops.changePassword(
      config,
      old,
      password,
    );
    _log.info(LogEvent('password_changed', {'keyCopyUpdated': keyCopyUpdated}));
    return {'keyCopyUpdated': keyCopyUpdated, 'keyCopyUnknown': keyCopyUnknown};
  }

  Future<Map<String, Object?>> _keyCopy(Map<String, Object?> params) async {
    _requireAccount();
    final enabled = _required<bool>(params, 'enabled');
    await ops.setKeyCopy(
      AppConfig.load(ops.home),
      _required<String>(params, 'password'),
      enabled: enabled,
    );
    _log.info(LogEvent('key_copy_changed', {'enabled': enabled}));
    return {'keyCopy': enabled};
  }

  void _requireAccount() {
    if (!ops.home.initialized) {
      throw const ControlException(
        'not_configured',
        'нет учётной записи на этом устройстве',
      );
    }
  }

  void dispose() {
    _draft?.dispose();
    _draft = null;
  }

  static T _required<T extends Object>(
    Map<String, Object?> params,
    String key,
  ) => switch (params[key]) {
    final T value => value,
    _ => throw ControlException('bad_request', 'нужен параметр $key ($T)'),
  };

  static T? _optional<T extends Object>(
    Map<String, Object?> params,
    String key,
  ) => switch (params[key]) {
    null => null,
    final T value => value,
    _ => throw ControlException('bad_request', 'параметр $key: нужен $T'),
  };
}
