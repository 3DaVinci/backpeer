import 'dart:io';
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:cli/src/account_ops.dart';
import 'package:cli/src/app_config.dart';
import 'package:cli/src/context.dart';
import 'package:core/core.dart';

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

AppConfig _newConfig(AccountOps ops, ArgResults args) => ops.newConfig(
  nodes: args.option('nodes'),
  nodeCount: _int(args, 'node-count'),
  objects: args.option('objects'),
  durability: DurabilityParameters(
    k: _int(args, 'k'),
    n: _int(args, 'n'),
    repairThreshold: _int(args, 'repair-threshold'),
  ),
  coordinator: args.options.contains('coordinator')
      ? args.option('coordinator')
      : null,
  coordinatorCa: args.options.contains('ca') ? args.option('ca') : null,
);

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
    final ops = await ctx.accountOps();
    ops.requireEmptyHome();
    final config = _newConfig(ops, argResults!);
    final phrase = _newPhrase(ctx, ops.crypto);
    final password = ctx.newPassword();
    final (keys, _) = await ops.create(
      config: config,
      phrase: phrase,
      password: password,
    );
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
    final ops = await ctx.accountOps();
    ops.requireEmptyHome();
    final args = argResults!;
    final login = loginOption(args);
    final config = _newConfig(ops, args)..login = login;
    // Адрес проверяется до показа фразы.
    ops.client(config).close();
    final phrase = _newPhrase(ctx, ops.crypto);
    final password = ctx.newPassword();
    try {
      final (keys, device) = await ops.create(
        config: config,
        phrase: phrase,
        password: password,
        keyCopy: args.flag('key-copy'),
      );
      final copy = config.keyCopy == true;
      ctx.report
        ..info(
          'Учётная запись $login создана на ${config.coordinator}: '
          '${bytesToHex(keys.accountId).substring(0, 16)}…'
          '${copy ? '' : '; копии ключа на координаторе нет — '
                    'на новом устройстве только по фразе'}.',
        )
        ..result({
          'accountId': bytesToHex(keys.accountId),
          'login': login,
          'deviceId': bytesToHex(device!.deviceId),
          'keyCopy': copy,
          ...config.durability.toConfig(),
        });
      keys.dispose();
      device.dispose();
      return ExitCode.ok;
    } finally {
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
    final ops = await ctx.accountOps();
    ops.requireEmptyHome();
    final config = _newConfig(ops, argResults!);
    if (config.coordinator != null) ops.client(config).close();
    final text =
        ctx.env['FS_PHRASE'] ??
        ctx.console.askSecret('Фраза восстановления (24 слова): ');
    if (text == null) throw const CliException('Фраза не введена');
    final phrase = AccountOps.parsePhrase(text);
    try {
      final password = ctx.newPassword();
      final (keys, device) = await ops.recover(
        config: config,
        phrase: phrase,
        password: password,
      );
      return await restoreIndex(ctx, ops, config, keys, device);
    } finally {
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
    final ops = await ctx.accountOps();
    ops.requireEmptyHome();
    final args = argResults!;
    final config = _newConfig(ops, args)..login = loginOption(args);
    ops.client(config).close();
    final (keys, device) = await ops.login(
      config: config,
      password: ctx.password(),
    );
    return await restoreIndex(ctx, ops, config, keys, device);
  }
}

/// Локальный индекс из объектов-индексов и итог команды (recover, login).
/// Ключи освобождаются.
Future<int> restoreIndex(
  CliContext ctx,
  AccountOps ops,
  AppConfig config,
  AccountKeys keys,
  DeviceKeys? device,
) async {
  try {
    final report = await ops.restoreIndex(config, keys, device);
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
    keys.dispose();
    device?.dispose();
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
    final ops = await ctx.accountOps();
    if (!ops.keyStore.hasPhrase) {
      throw const CliException('Копии фразы на этом устройстве нет');
    }
    final phrase = await ops.phrase(ctx.password());
    final words = phrase.words;
    for (var i = 0; i < words.length; i++) {
      ctx.report.info('${(i + 1).toString().padLeft(2)}. ${words[i]}');
    }
    ctx.report.result({'words': words});
    phrase.dispose();
    return ExitCode.ok;
  }
}

String _fragmentsLine(AppConfig config) {
  if (!config.usesNetwork) return 'Узлы-заглушки: ${config.nodes}';
  return config.distinctSubnets
      ? 'Фрагменты: по сети'
      : 'Фрагменты: по сети (подсети узлов не проверяются)';
}

/// Предел скорости для вывода: «без предела» или байт в секунду.
String _limit(int bytesPerSecond) =>
    bytesPerSecond <= 0 ? 'без предела' : '$bytesPerSecond Б/с';

/// Предел скорости из командной строки: 0 — без предела, не больше 1 ГиБ/с.
int _limitOption(ArgResults a, String name) {
  final value = _int(a, name);
  if (value < 0 || value > 1 << 30) {
    throw CliException(
      '--$name: от 0 до ${1 << 30} байт в секунду (0 — без предела)',
      ExitCode.usage,
    );
  }
  return value;
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
      ..addOption(
        'fragments',
        help: 'Куда идут фрагменты с координатором',
        allowed: [for (final m in FragmentsMode.values) m.name],
        allowedHelp: {
          FragmentsMode.folders.name: 'папки-«узлы» (node stub)',
          FragmentsMode.network.name:
              'узлы-хранители по сети: TCP, UDP после сведения, relay',
        },
      )
      ..addOption(
        'subnet-check',
        help:
            'Проверять, что узлы сегмента в разных подсетях '
            '(off — только для стенда)',
        allowed: ['on', 'off'],
      )
      ..addMultiOption(
        'exclude',
        help: 'Добавить правило исключения (.gitignore)',
      )
      ..addFlag(
        'clear-excludes',
        help: 'Убрать все правила исключения',
        negatable: false,
      )
      ..addOption(
        'upload-limit',
        help: 'Предел отдачи в сеть, байт в секунду (0 — без предела)',
      )
      ..addOption(
        'download-limit',
        help: 'Предел приёма из сети, байт в секунду (0 — без предела)',
      );
    for (final (name, what) in _keepOptions) {
      argParser.addOption(
        'keep-$name',
        help: 'Политика хранения: сколько $what снимков хранить',
      );
    }
    argParser.addFlag(
      'keep-all',
      help: 'Хранить все снимки (без очистки по политике)',
      negatable: false,
    );
  }

  static const _keepOptions = [
    ('last', 'последних'),
    ('hourly', 'почасовых'),
    ('daily', 'дневных'),
    ('weekly', 'недельных'),
    ('monthly', 'месячных'),
  ];

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
    if (a.option('fragments') case final String v) {
      config.fragments = FragmentsMode.parse(v);
      changed = true;
    }
    if (a.option('subnet-check') case final String v) {
      config.distinctSubnets = v == 'on';
      changed = true;
    }
    if (a.option('upload-limit') != null) {
      config.uploadBytesPerSecond = _limitOption(a, 'upload-limit');
      changed = true;
    }
    if (a.option('download-limit') != null) {
      config.downloadBytesPerSecond = _limitOption(a, 'download-limit');
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
    if (a.flag('keep-all')) {
      config.retention = null;
      changed = true;
    }
    final keep = {
      for (final (name, _) in _keepOptions)
        if (a.option('keep-$name') != null) name: _int(a, 'keep-$name'),
    };
    if (keep.isNotEmpty) {
      try {
        config.retention = RetentionPolicy.fromJson({
          ...?config.retention?.toJson(),
          ...keep,
        });
      } on ConfigException catch (e) {
        throw CliException(e.message, ExitCode.usage);
      }
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
                  '${_fragmentsLine(config)}',
      )
      ..info('Надёжность: ${config.durability}')
      ..info('Устройство: ${bytesToHex(config.deviceId).substring(0, 16)}…')
      ..info('Хранение снимков: ${config.retention ?? 'все'}')
      ..info(
        config.usesNetwork
            ? 'Пределы сети: отдача ${_limit(config.uploadBytesPerSecond)}, '
                  'приём ${_limit(config.downloadBytesPerSecond)}'
            : 'Пределы сети: не действуют (фрагменты в папках-«узлах»)',
      )
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
