import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:cli/src/app_config.dart';
import 'package:cli/src/commands/account.dart';
import 'package:cli/src/context.dart';
import 'package:core/core.dart';
import 'package:protocol/protocol.dart' as pb;

/// Настройки с координатором, ключи и клиент для команд, которые
/// подписывает ключ учётной записи (protocol.md, раздел 4.3).
Future<(AppConfig, AccountKeys, DeviceKeys, CoordinatorClient)> _account(
  CliContext ctx,
) async {
  final config = ctx.config();
  final url = config.coordinator;
  if (url == null) {
    throw const CliException(
      'Устройство работает без координатора (init); команда недоступна',
    );
  }
  final (keys, device) = await ctx.unlockWithDevice();
  if (device == null) {
    keys.dispose();
    throw const CliException('На этом устройстве нет ключей устройства');
  }
  return (
    config,
    keys,
    device,
    await ctx.client(url, ca: config.coordinatorCa, device: device),
  );
}

/// Устройство из списка `ListDevices` с проверенным сертификатом.
typedef _Device = ({pb.DeviceCertificate? certificate, pb.DeviceInfo info});

Future<List<_Device>> _devices(
  CliContext ctx,
  CoordinatorClient client,
  AccountKeys keys,
) async {
  final crypto = await ctx.crypto();
  final pb.ListDevicesResponse response;
  try {
    response = await client.listDevices(accountKey: keys.accountSign);
  } on CoordinatorException catch (e) {
    coordinatorFailure(e);
  }
  final out = <_Device>[];
  for (final info in response.devices) {
    pb.DeviceCertificate? cert;
    try {
      // Сертификат проверяется: список отдаёт координатор, ему не доверяют.
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
    out.add((certificate: cert, info: info));
  }
  return out;
}

String _date(int ms) =>
    DateTime.fromMillisecondsSinceEpoch(ms)
        .toLocal()
        .toString()
        .substring(0, 16);

/// Список устройств учётной записи (`ListDevices`).
final class DevicesCommand extends CliCommand {
  new(super.ctx);

  @override
  String get name => 'devices';

  @override
  String get description => 'Устройства учётной записи на координаторе.';

  @override
  Future<int> run() async {
    final (_, keys, device, client) = await _account(ctx);
    try {
      final rows = <Map<String, Object?>>[];
      var forged = 0;
      for (final d in await _devices(ctx, client, keys)) {
        final cert = d.certificate;
        if (cert == null) {
          forged++;
          ctx.report.warn(
            'Устройство с неверным сертификатом в ответе координатора',
          );
          continue;
        }
        final id = bytesToHex(cert.deviceSign);
        final current = constantTimeEquals(cert.deviceSign, device.deviceId);
        final revoked = d.info.revokedAtUnixMs.toInt();
        final added = d.info.addedAtUnixMs.toInt();
        ctx.report.info(
          '${id.substring(0, 16)}  добавлено ${_date(added)}'
          '${revoked == 0 ? '' : '  отозвано ${_date(revoked)}'}'
          '${current ? '  (это устройство)' : ''}',
        );
        rows.add({
          'deviceId': id,
          'addedAt': DateTime.fromMillisecondsSinceEpoch(
            added,
            isUtc: true,
          ).toIso8601String(),
          'revokedAt': revoked == 0
              ? null
              : DateTime.fromMillisecondsSinceEpoch(
                  revoked,
                  isUtc: true,
                ).toIso8601String(),
          'current': current,
        });
      }
      final code = forged == 0 ? ExitCode.ok : ExitCode.partial;
      ctx.report.result({'devices': rows, 'invalid': forged}, exitCode: code);
      return code;
    } finally {
      client.close();
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
    final prefix = rest.single.toLowerCase();
    final (_, keys, device, client) = await _account(ctx);
    try {
      final found = [
        for (final d in await _devices(ctx, client, keys))
          if (d.certificate case final pb.DeviceCertificate cert
              when bytesToHex(cert.deviceSign).startsWith(prefix))
            cert,
      ];
      final cert = switch (found) {
        [final c] => c,
        [] => throw CliException(
          'Устройство $prefix не найдено',
          ExitCode.usage,
        ),
        _ => throw CliException(
          'Префикс $prefix подходит к ${found.length} устройствам',
          ExitCode.usage,
        ),
      };
      if (constantTimeEquals(cert.deviceSign, device.deviceId)) {
        throw const CliException(
          'Это устройство; отзовите его с другого устройства',
          ExitCode.usage,
        );
      }
      final crypto = await ctx.crypto();
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
      final id = bytesToHex(cert.deviceSign);
      ctx.report
        ..info('Устройство ${id.substring(0, 16)} отозвано.')
        ..result({'deviceId': id});
      return ExitCode.ok;
    } finally {
      client.close();
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
    final config = ctx.config();
    final store = await ctx.keyStore();
    final old = ctx.password('Текущий пароль: ');
    final AccountKeys keys;
    final DeviceKeys? device;
    try {
      (keys, device) = await store.unlockWithDevice(old);
    } on IntegrityException {
      throw const CliException('Неверный пароль');
    }
    try {
      final password = ctx.newPassword();
      final url = config.coordinator;
      var remote = false;
      // Сначала координатор: если он откажет, локальный пароль остаётся
      // прежним и обе копии открываются одним паролем.
      if (url != null && config.keyCopy == true) {
        final client = await ctx.client(url, ca: config.coordinatorCa);
        try {
          await _setKeyCopy(
            client,
            keys,
            await KeyCopy.create(
              await ctx.crypto(),
              keys: keys,
              password: password,
              params: ctx.argon2,
            ),
          );
          remote = true;
        } finally {
          client.close();
        }
      }
      await store.changePassword(old, password);
      if (url != null && config.keyCopy == null) {
        ctx.report.warn(
          'Неизвестно, есть ли на координаторе копия ключа под старым '
          'паролем: выполните cli key-copy on или cli key-copy off',
        );
      }
      ctx.report
        ..info(
          remote
              ? 'Пароль изменён здесь и в копии ключа на координаторе.'
              : 'Пароль изменён на этом устройстве.',
        )
        ..result({'keyCopyUpdated': remote});
      return ExitCode.ok;
    } finally {
      keys.dispose();
      device?.dispose();
    }
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
    final url = config.coordinator;
    if (url == null) {
      throw const CliException(
        'Устройство работает без координатора (init); команда недоступна',
      );
    }
    final store = await ctx.keyStore();
    final password = ctx.password();
    final AccountKeys keys;
    final DeviceKeys? device;
    try {
      (keys, device) = await store.unlockWithDevice(password);
    } on IntegrityException {
      throw const CliException('Неверный пароль');
    }
    final client = await ctx.client(url, ca: config.coordinatorCa);
    try {
      await _setKeyCopy(
        client,
        keys,
        enable
            ? await KeyCopy.create(
                await ctx.crypto(),
                keys: keys,
                password: password,
                params: ctx.argon2,
              )
            : KeyCopy.none,
      );
      config
        ..keyCopy = enable
        ..save(ctx.home);
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
    } finally {
      client.close();
      keys.dispose();
      device?.dispose();
    }
  }
}

Future<void> _setKeyCopy(
  CoordinatorClient client,
  AccountKeys keys,
  KeyCopy copy,
) async {
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
  }
}
