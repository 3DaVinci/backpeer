import 'dart:io';
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:cli/src/app_config.dart';
import 'package:cli/src/context.dart';
import 'package:core/core.dart';
import 'package:protocol/protocol.dart' as pb;

/// Общие флаги хранилищ для init, register, login и recover; с
/// [coordinator] — адрес координатора и его УЦ.
void _storageOptions(Command<int> command, {bool coordinator = false}) {
  command.argParser
    ..addOption(
      'nodes',
      help:
          'Папка с папками-«узлами» (по умолчанию <home>/nodes); с '
          'координатором — папка узлов-заглушек (node stub)',
    )
    ..addOption('node-count', help: 'Число папок-«узлов»', defaultsTo: '20')
    ..addOption(
      'objects',
      help: 'Папка объектов — заглушка координатора (по умолчанию <home>/objects)',
    )
    ..addOption(
      'k',
      help: 'Фрагментов данных',
      defaultsTo: '${DurabilityParameters.defaultK}',
    )
    ..addOption(
      'n',
      help: 'Всего фрагментов',
      defaultsTo: '${DurabilityParameters.defaultN}',
    )
    ..addOption(
      'repair-threshold',
      help: 'Порог ремонта',
      defaultsTo: '${DurabilityParameters.defaultRepairThreshold}',
    );
  if (coordinator) coordinatorOptions(command);
}

/// Флаги адреса координатора.
void coordinatorOptions(Command<int> command, {bool mandatory = false}) {
  command.argParser
    ..addOption(
      'coordinator',
      help: 'Адрес координатора: https://… (http — только localhost)',
      mandatory: mandatory,
    )
    ..addOption(
      'ca',
      help: 'Сертификат УЦ координатора в PEM (тестовый стенд со своим УЦ)',
    );
}

int _int(ArgResults args, String name) {
  final value = int.tryParse(args.option(name)!);
  if (value == null) throw UsageException('--$name: нужно целое число', '');
  return value;
}

AppConfig _newConfig(CliContext ctx, ArgResults args, CryptoProvider crypto) {
  final coordinator = args.options.contains('coordinator')
      ? args.option('coordinator')
      : null;
  return AppConfig(
    nodes: args.option('nodes') ?? '${ctx.home.dir.path}/nodes',
    nodeCount: _int(args, 'node-count'),
    objects: args.option('objects') ?? '${ctx.home.dir.path}/objects',
    durability: DurabilityParameters(
      k: _int(args, 'k'),
      n: _int(args, 'n'),
      repairThreshold: _int(args, 'repair-threshold'),
    ),
    deviceId: crypto.randomBytes(32),
    coordinator: coordinator,
    coordinatorCa: coordinator == null ? null : args.option('ca'),
  )..check();
}

/// Имя для входа из `--login`; недопустимое — ошибка вызова.
String loginOption(ArgResults args) {
  final login = LoginName.normalize(args.option('login')!);
  if (login == null) {
    throw UsageException(
      '--login: 3–32 символа a–z, 0–9, «.», «_», «-», первый — буква или '
          'цифра',
      '',
    );
  }
  return login;
}

/// Каталог программы ещё пуст.
void _requireEmptyHome(CliContext ctx) {
  if (ctx.home.keysFile.existsSync()) {
    throw CliException('В ${ctx.home.dir.path} уже есть учётная запись');
  }
}

/// Новая фраза: показать, проверить три слова (У-2).
RecoveryPhrase _newPhrase(CliContext ctx, CryptoProvider crypto) {
  final phrase = RecoveryPhrase.generate(crypto);
  final words = phrase.words;
  ctx.report
    ..info('Фраза восстановления — единственный способ вернуть данные, ')
    ..info('если пароль забыт. Запишите её на бумаге и храните отдельно:')
    ..info('')
    ..event('phrase', {'words': words});
  for (var i = 0; i < words.length; i += 4) {
    ctx.report.info(
      [
        for (var j = i; j < i + 4; j++)
          '${(j + 1).toString().padLeft(2)}. ${words[j].padRight(10)}',
      ].join(' '),
    );
  }
  ctx.report.info('');
  _checkWords(ctx, words);
  return phrase;
}

/// Ввод трёх случайных слов — проверка, что фраза записана (У-2).
void _checkWords(CliContext ctx, List<String> words) {
  final positions = <int>{};
  while (positions.length < 3) {
    positions.add(ctx.random.nextInt(words.length));
  }
  for (final p in positions.toList()..sort()) {
    for (var attempt = 0; ; attempt++) {
      final answer = ctx.console.ask('Слово №${p + 1}: ')?.trim().toLowerCase();
      if (answer == null) throw const CliException('Проверка фразы прервана');
      if (answer == words[p]) break;
      if (attempt == 2) {
        throw const CliException('Слово введено неверно трижды');
      }
      ctx.console.err('Неверно, ещё раз.');
    }
  }
}

/// Понятное сообщение для ошибки координатора при работе с учётной записью.
Never coordinatorFailure(CoordinatorException e, {String? unauthenticated}) {
  final message = switch (e.code) {
    pb.ErrorCode.ERROR_CODE_UNAUTHENTICATED when unauthenticated != null =>
      unauthenticated,
    pb.ErrorCode.ERROR_CODE_RATE_LIMITED =>
      'координатор просит подождать'
          '${e.retryAfter == null ? '' : ' ${_duration(e.retryAfter!)}'}',
    pb.ErrorCode.ERROR_CODE_UNAVAILABLE => 'координатор недоступен',
    _ => e.message,
  };
  throw CliException(message);
}

String _duration(Duration d) => d.inMinutes >= 1
    ? '${d.inMinutes} мин'
    : '${(d.inMilliseconds / 1000).ceil()} с';

final class InitCommand extends CliCommand {
  new(super.ctx) {
    _storageOptions(this);
  }

  @override
  String get name => 'init';

  @override
  String get description =>
      'Создать учётную запись без координатора: фраза восстановления, '
      'пароль, настройки.';

  @override
  Future<int> run() async {
    _requireEmptyHome(ctx);
    final crypto = await ctx.crypto();
    final config = _newConfig(ctx, argResults!, crypto);
    final phrase = _newPhrase(ctx, crypto);
    final password = ctx.newPassword();
    final keys = await AccountKeys.fromPhrase(phrase, crypto);
    await (await ctx.keyStore()).create(keys, password, phrase: phrase);
    config.save(ctx.home);
    ctx.index().close();
    ctx.report
      ..info(
        'Учётная запись создана: '
        '${bytesToHex(keys.accountId).substring(0, 16)}… '
        '(${config.durability}).',
      )
      ..result({
        'accountId': bytesToHex(keys.accountId),
        ...config.durability.toConfig(),
      });
    keys.dispose();
    phrase.dispose();
    return ExitCode.ok;
  }
}

/// Новая учётная запись на координаторе (задача 2.8.3; protocol.md,
/// раздел 4.7): как init, плюс ключи устройства, сертификат устройства и
/// `RegisterAccount` — с копией мастер-ключа под паролем (вход по паролю на
/// новом устройстве) или без неё (`--no-key-copy`, модель угроз, К-3).
/// Файлы пишутся только после ответа координатора.
final class RegisterCommand extends CliCommand {
  new(super.ctx) {
    _storageOptions(this);
    coordinatorOptions(this, mandatory: true);
    argParser
      ..addOption(
        'login',
        help: 'Имя для входа по паролю на новом устройстве',
        mandatory: true,
      )
      ..addFlag(
        'key-copy',
        defaultsTo: true,
        help:
            'Хранить на координаторе копию мастер-ключа под паролем (вход по '
            'паролю на новом устройстве). Без неё — только по фразе',
      );
  }

  @override
  String get name => 'register';

  @override
  String get description =>
      'Создать учётную запись на координаторе: фраза, пароль, это '
      'устройство.';

  @override
  Future<int> run() async {
    _requireEmptyHome(ctx);
    final args = argResults!;
    final login = loginOption(args);
    final crypto = await ctx.crypto();
    final config = _newConfig(ctx, args, crypto)..login = login;
    final client = await ctx.client(
      config.coordinator!,
      ca: config.coordinatorCa,
    );
    final phrase = _newPhrase(ctx, crypto);
    final password = ctx.newPassword();
    final keys = await AccountKeys.fromPhrase(phrase, crypto);
    final device = await DeviceKeys.generate(crypto);
    try {
      final copy = args.flag('key-copy')
          ? await KeyCopy.create(
              crypto,
              keys: keys,
              password: password,
              params: ctx.argon2,
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
          throw CliException('Имя $login занято, выберите другое');
        }
        coordinatorFailure(e);
      }
      config
        ..deviceId = device.deviceId
        ..keyCopy = copy.enabled;
      await (await ctx.keyStore()).create(
        keys,
        password,
        phrase: phrase,
        device: device,
      );
      config.save(ctx.home);
      ctx.index().close();
      ctx.report
        ..info(
          'Учётная запись $login создана на ${config.coordinator}: '
          '${bytesToHex(keys.accountId).substring(0, 16)}…'
          '${copy.enabled ? '' : '; копии ключа на координаторе нет — '
                    'на новом устройстве только по фразе'}.',
        )
        ..result({
          'accountId': bytesToHex(keys.accountId),
          'login': login,
          'deviceId': bytesToHex(device.deviceId),
          'keyCopy': copy.enabled,
          ...config.durability.toConfig(),
        });
      return ExitCode.ok;
    } finally {
      client.close();
      keys.dispose();
      device.dispose();
      phrase.dispose();
    }
  }
}

final class RecoverCommand extends CliCommand {
  new(super.ctx) {
    _storageOptions(this, coordinator: true);
  }

  @override
  String get name => 'recover';

  @override
  String get description =>
      'Восстановить учётную запись на этом устройстве по фразе '
      '(с --coordinator — добавить устройство на координаторе).';

  @override
  Future<int> run() async {
    _requireEmptyHome(ctx);
    final crypto = await ctx.crypto();
    final config = _newConfig(ctx, argResults!, crypto);
    final text =
        ctx.env['FS_PHRASE'] ??
        ctx.console.askSecret('Фраза восстановления (24 слова): ');
    if (text == null) throw const CliException('Фраза не введена');
    final RecoveryPhrase phrase;
    try {
      phrase = RecoveryPhrase.parse(text);
    } on DataFormatException catch (e) {
      throw CliException(
        'Фраза не разобрана: ${e.detail ?? e.problem.description}',
      );
    } on IntegrityException {
      throw const CliException(
        'Фраза с ошибкой: не сходится контрольная сумма',
      );
    }
    final keys = await AccountKeys.fromPhrase(phrase, crypto);
    final url = config.coordinator;
    final client = url == null
        ? null
        : await ctx.client(url, ca: config.coordinatorCa);
    DeviceKeys? device;
    try {
      final password = ctx.newPassword();
      if (client != null) {
        device = await DeviceKeys.generate(crypto);
        await addDevice(ctx, client, keys, device);
        config.deviceId = device.deviceId;
      }
      await (await ctx.keyStore()).create(
        keys,
        password,
        phrase: phrase,
        device: device,
      );
      config.save(ctx.home);
      final objects = client == null
          ? LocalObjectStore(Directory(config.objects))
          : CoordinatorObjectStore(
              await ctx.client(url!, ca: config.coordinatorCa, device: device),
            );
      return await restoreIndex(ctx, keys, objects);
    } finally {
      client?.close();
      keys.dispose();
      device?.dispose();
      phrase.dispose();
    }
  }
}

/// Вход на новом устройстве по паролю (задача 2.8.3; protocol.md, раздел
/// 4.7): KeyBundle с координатора, новые ключи устройства и `AddDevice`,
/// локальный индекс из объектов-индексов. Копии фразы на устройстве не
/// будет: `show-phrase` здесь недоступна.
final class LoginCommand extends CliCommand {
  new(super.ctx) {
    _storageOptions(this);
    coordinatorOptions(this, mandatory: true);
    argParser.addOption('login', help: 'Имя для входа', mandatory: true);
  }

  @override
  String get name => 'login';

  @override
  String get description =>
      'Войти на новом устройстве по имени и паролю (нужна копия ключа на '
      'координаторе).';

  @override
  Future<int> run() async {
    _requireEmptyHome(ctx);
    final args = argResults!;
    final login = loginOption(args);
    final crypto = await ctx.crypto();
    final config = _newConfig(ctx, args, crypto)
      ..login = login
      ..keyCopy = true;
    final client = await ctx.client(
      config.coordinator!,
      ca: config.coordinatorCa,
    );
    final password = ctx.password();
    final AccountKeys keys;
    try {
      (keys, _) = await loginWithPassword(
        client,
        crypto,
        login: login,
        password: password,
      );
    } on CoordinatorException catch (e) {
      client.close();
      coordinatorFailure(
        e,
        unauthenticated:
            'Неверное имя или пароль, либо вход по паролю для этой учётной '
            'записи выключен (тогда — recover по фразе)',
      );
    } on CoreException catch (e) {
      client.close();
      throw CliException('Копия ключа с координатора не открыта: ${e.message}');
    }
    final device = await DeviceKeys.generate(crypto);
    try {
      await addDevice(ctx, client, keys, device);
      config.deviceId = device.deviceId;
      await (await ctx.keyStore()).create(keys, password, device: device);
      config.save(ctx.home);
      return await restoreIndex(
        ctx,
        keys,
        CoordinatorObjectStore(
          await ctx.client(
            config.coordinator!,
            ca: config.coordinatorCa,
            device: device,
          ),
        ),
      );
    } finally {
      client.close();
      keys.dispose();
      device.dispose();
    }
  }
}

/// `AddDevice`: новое устройство учётной записи на координаторе.
Future<void> addDevice(
  CliContext ctx,
  CoordinatorClient client,
  AccountKeys keys,
  DeviceKeys device,
) async {
  final crypto = await ctx.crypto();
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
      throw const CliException(
        'У учётной записи уже 5 устройств: отзовите ненужное (cli revoke) '
        'на другом устройстве',
      );
    }
    coordinatorFailure(
      e,
      unauthenticated: 'учётная запись не зарегистрирована на координаторе',
    );
  }
}

/// Локальный индекс из объектов-индексов и итог команды (recover, login).
Future<int> restoreIndex(
  CliContext ctx,
  AccountKeys keys,
  ObjectStore objects,
) async {
  final index = ctx.index();
  try {
    final report = await recoverIndex(
      crypto: await ctx.crypto(),
      manifestKey: keys.manifestKey,
      store: objects,
      index: index,
    );
    ctx.report.info(
      'Учётная запись восстановлена: '
      '${bytesToHex(keys.accountId).substring(0, 16)}…; '
      'индексов ${report.indexesRead}, сегментов ${report.segmentsAdded}.',
    );
    for (final (id, e) in report.unreadable) {
      ctx.report.warn(
        'Индекс ${bytesToHex(id).substring(0, 16)} не прочитан: ${e.message}',
        {'index': bytesToHex(id)},
      );
    }
    final code = report.unreadable.isEmpty ? ExitCode.ok : ExitCode.partial;
    ctx.report.result({
      'accountId': bytesToHex(keys.accountId),
      'indexes': report.indexesRead,
      'segments': report.segmentsAdded,
      'unreadable': report.unreadable.length,
    }, exitCode: code);
    return code;
  } finally {
    index.close();
    if (objects case CoordinatorObjectStore(:final client)) client.close();
  }
}

final class ShowPhraseCommand extends CliCommand {
  new(super.ctx);

  @override
  String get name => 'show-phrase';

  @override
  String get description => 'Показать фразу восстановления (по паролю).';

  @override
  Future<int> run() async {
    final store = await ctx.keyStore();
    if (!store.hasPhrase) {
      throw const CliException('Копии фразы на этом устройстве нет');
    }
    final RecoveryPhrase phrase;
    try {
      phrase = await store.unlockPhrase(ctx.password());
    } on IntegrityException {
      throw const CliException('Неверный пароль');
    }
    final words = phrase.words;
    for (var i = 0; i < words.length; i++) {
      ctx.report.info('${(i + 1).toString().padLeft(2)}. ${words[i]}');
    }
    ctx.report.result({'words': words});
    phrase.dispose();
    return ExitCode.ok;
  }
}

final class ConfigCommand extends CliCommand {
  new(super.ctx) {
    argParser
      ..addOption('nodes', help: 'Папка с папками-«узлами»')
      ..addOption('node-count', help: 'Число папок-«узлов»')
      ..addOption('objects', help: 'Папка объектов')
      ..addOption(
        'coordinator',
        help: 'Новый адрес того же координатора (https://…)',
      )
      ..addOption('ca', help: 'Сертификат УЦ координатора в PEM')
      ..addMultiOption(
        'exclude',
        help: 'Добавить правило исключения (.gitignore)',
      )
      ..addFlag(
        'clear-excludes',
        help: 'Убрать все правила исключения',
        negatable: false,
      );
  }

  @override
  String get name => 'config';

  @override
  String get description =>
      'Показать или изменить настройки '
      '(параметры k и n меняются только при init).';

  @override
  Future<int> run() async {
    final config = ctx.config();
    final a = argResults!;
    var changed = false;
    if (a.option('nodes') case final String v) {
      config.nodes = v;
      changed = true;
    }
    if (a.option('node-count') != null) {
      config.nodeCount = _int(a, 'node-count');
      changed = true;
    }
    if (a.option('objects') case final String v) {
      config.objects = v;
      changed = true;
    }
    if (a.option('coordinator') case final String v) {
      if (config.coordinator == null) {
        throw const CliException(
          'Устройство создано без координатора (init); перейти на '
          'координатор можно только новой учётной записью (register)',
        );
      }
      config.coordinator = v;
      changed = true;
    }
    if (a.option('ca') case final String v) {
      config.coordinatorCa = v.isEmpty ? null : v;
      changed = true;
    }
    if (a.flag('clear-excludes')) {
      config.excludes = [];
      changed = true;
    }
    if (a.multiOption('exclude').isNotEmpty) {
      config.excludes = [...config.excludes, ...a.multiOption('exclude')];
      changed = true;
    }
    if (changed) config.save(ctx.home);
    ctx.report
      ..info('Каталог программы: ${ctx.home.dir.path}')
      ..info(
        config.coordinator == null
            ? 'Папки-«узлы»: ${config.nodes} (${config.nodeCount})\n'
                  'Папка объектов: ${config.objects}'
            : 'Координатор: ${config.coordinator}'
                  '${config.login == null ? '' : ', имя ${config.login}'}'
                  '${switch (config.keyCopy) {
                    true => ', копия ключа есть',
                    false => ', копии ключа нет',
                    null => '',
                  }}\n'
                  'Узлы-заглушки: ${config.nodes}',
      )
      ..info('Надёжность: ${config.durability}')
      ..info('Устройство: ${bytesToHex(config.deviceId).substring(0, 16)}…')
      ..info(
        'Исключения: '
        '${config.excludes.isEmpty ? 'нет' : config.excludes.join(', ')}',
      )
      ..result({'home': ctx.home.dir.path, ...config.toJson()});
    return ExitCode.ok;
  }
}

/// Сертификат узла-хранителя (задача 2.6.1; protocol.md, разделы 4.9, 6):
/// владелец подписывает открытые ключи узла ключом учётной записи. Узел
/// предъявляет сертификат координатору в `RegisterNode`.
final class NodeCertCommand extends CliCommand {
  new(super.ctx) {
    argParser
      ..addOption(
        'node-id',
        help: 'Открытый ключ Ed25519 узла, 64 hex-символа',
        mandatory: true,
      )
      ..addOption(
        'node-dh',
        help: 'Открытый ключ X25519 узла, 64 hex-символа',
        mandatory: true,
      )
      ..addOption(
        'out',
        help: 'Файл для сертификата (fs.v1.Signed в Protobuf)',
        mandatory: true,
      );
  }

  @override
  String get name => 'node-cert';

  @override
  String get description =>
      'Выпустить сертификат узла-хранителя ключом учётной записи.';

  @override
  Future<int> run() async {
    final a = argResults!;
    final nodeId = _key(a, 'node-id');
    final nodeDh = _key(a, 'node-dh');
    final out = File(a.option('out')!);
    if (out.existsSync()) throw CliException('Файл ${out.path} уже есть');
    final crypto = await ctx.crypto();
    final keys = await ctx.unlock();
    try {
      final signed = await NodeCertificates.issue(
        crypto,
        keys,
        nodeId: nodeId,
        nodeDh: nodeDh,
        issuedAt: DateTime.now(),
      );
      out.writeAsBytesSync(signed.writeToBuffer(), flush: true);
      ctx.report
        ..info(
          'Сертификат узла ${bytesToHex(nodeId).substring(0, 16)}… '
          'записан в ${out.path}.',
        )
        ..result({
          'nodeId': bytesToHex(nodeId),
          'accountId': bytesToHex(keys.accountId),
          'file': out.path,
        });
      return ExitCode.ok;
    } finally {
      keys.dispose();
    }
  }

  static Uint8List _key(ArgResults args, String name) {
    try {
      final bytes = hexToBytes(args.option(name)!);
      if (bytes.length == 32) return bytes;
    } on FormatException {
      // ниже — общая ошибка
    }
    throw UsageException('--$name: нужно 32 байта в hex', '');
  }
}
