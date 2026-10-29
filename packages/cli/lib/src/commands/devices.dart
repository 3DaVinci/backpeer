import 'package:args/command_runner.dart';
import 'package:cli/src/account_ops.dart';
import 'package:cli/src/app_config.dart';
import 'package:cli/src/context.dart';
import 'package:core/core.dart';

/// Настройки с координатором и ключи для команд, которые подписывает ключ
/// учётной записи (protocol.md, раздел 4.3).
Future<(AccountOps, AppConfig, AccountKeys, DeviceKeys)> _account(
  CliContext ctx,
) async {
  final ops = await ctx.accountOps();
  final config = ctx.config();
  if (config.coordinator == null) {
    throw const CliException(
      'Устройство работает без координатора (init); команда недоступна',
    );
  }
  final (keys, device) = await ctx.unlockWithDevice();
  if (device == null) {
    keys.dispose();
    throw const CliException('На этом устройстве нет ключей устройства');
  }
  return (ops, config, keys, device);
}

String _date(DateTime t) => t.toLocal().toString().substring(0, 16);

/// Список устройств учётной записи (`ListDevices`).
final class DevicesCommand extends CliCommand {
  new(super.ctx);

  @override
  String get name => 'devices';

  @override
  String get description => 'Устройства учётной записи на координаторе.';

  @override
  Future<int> run() async {
    final (ops, config, keys, device) = await _account(ctx);
    try {
      final (:devices, :invalid) = await ops.devices(config, keys, device);
      for (var i = 0; i < invalid; i++) {
        ctx.report.warn(
          'Устройство с неверным сертификатом в ответе координатора',
        );
      }
      for (final d in devices) {
        ctx.report.info(
          '${d.deviceId.substring(0, 16)}  добавлено ${_date(d.addedAt)}'
          '${d.revokedAt == null ? '' : '  отозвано ${_date(d.revokedAt!)}'}'
          '${d.current ? '  (это устройство)' : ''}',
        );
      }
      final code = invalid == 0 ? ExitCode.ok : ExitCode.partial;
      ctx.report.result({
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
      }, exitCode: code);
      return code;
    } finally {
      keys.dispose();
      device.dispose();
    }
  }
}

/// Отзыв устройства (`RevokeDevice`): потерянное или украденное устройство
/// больше не получает доступа к координатору и талонов.
final class RevokeCommand extends CliCommand {
  new(super.ctx);

  @override
  String get name => 'revoke';

  @override
  String get description =>
      'Отозвать другое устройство учётной записи (по началу '
      'идентификатора из cli devices).';

  @override
  String get invocation => 'cli revoke <устройство>';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 1 || rest.single.length < 4) {
      throw UsageException(
        'Укажите устройство: не меньше 4 символов идентификатора',
        usage,
      );
    }
    final (ops, config, keys, device) = await _account(ctx);
    try {
      final id = await ops.revoke(config, keys, device, rest.single);
      ctx.report
        ..info('Устройство ${id.substring(0, 16)} отозвано.')
        ..result({'deviceId': id});
      return ExitCode.ok;
    } finally {
      keys.dispose();
      device.dispose();
    }
  }
}

/// Смена пароля: локальная копия ключей и, если включена, копия на
/// координаторе (`SetKeyBundle`, protocol.md, раздел 4.7).
final class PasswdCommand extends CliCommand {
  new(super.ctx);

  @override
  String get name => 'passwd';

  @override
  String get description =>
      'Сменить пароль на этом устройстве и копию ключа на координаторе.';

  @override
  Future<int> run() async {
    final ops = await ctx.accountOps();
    final config = ctx.config();
    final old = ctx.password('Текущий пароль: ');
    // Пароль проверяется до вопроса о новом.
    final (keys, device) = await ops.unlock(old);
    keys.dispose();
    device?.dispose();
    final (:keyCopyUpdated, :keyCopyUnknown) = await ops.changePassword(
      config,
      old,
      ctx.newPassword(),
    );
    if (keyCopyUnknown) {
      ctx.report.warn(
        'Неизвестно, есть ли на координаторе копия ключа под старым '
        'паролем: выполните cli key-copy on или cli key-copy off',
      );
    }
    ctx.report
      ..info(
        keyCopyUpdated
            ? 'Пароль изменён здесь и в копии ключа на координаторе.'
            : 'Пароль изменён на этом устройстве.',
      )
      ..result({'keyCopyUpdated': keyCopyUpdated});
    return ExitCode.ok;
  }
}

/// Копия мастер-ключа на координаторе: включить (вход по паролю на новом
/// устройстве) или выключить (только по фразе; модель угроз, К-3).
final class KeyCopyCommand extends CliCommand {
  new(super.ctx);

  @override
  String get name => 'key-copy';

  @override
  String get description =>
      'Включить (on) или выключить (off) копию мастер-ключа на координаторе.';

  @override
  String get invocation => 'cli key-copy on|off';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    final enable = switch (rest) {
      ['on'] => true,
      ['off'] => false,
      _ => throw UsageException('Укажите on или off', usage),
    };
    final config = ctx.config();
    if (config.coordinator == null) {
      throw const CliException(
        'Устройство работает без координатора (init); команда недоступна',
      );
    }
    final ops = await ctx.accountOps();
    await ops.setKeyCopy(config, ctx.password(), enabled: enable);
    ctx.report
      ..info(
        enable
            ? 'Копия ключа под паролем сохранена на координаторе: вход на '
                  'новом устройстве — cli login.'
            : 'Копия ключа удалена с координатора: новое устройство — '
                  'только по фразе (cli recover).',
      )
      ..result({'keyCopy': enable});
    return ExitCode.ok;
  }
}
