import 'dart:io';
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:cli/src/app_config.dart';
import 'package:cli/src/context.dart';
import 'package:core/core.dart';

/// Общие флаги хранилищ для init и recover.
void _storageOptions(Command<int> command) {
  command.argParser
    ..addOption(
      'nodes',
      help: 'Папка с папками-«узлами» (по умолчанию <home>/nodes)',
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
}

int _int(ArgResults args, String name) {
  final value = int.tryParse(args.option(name)!);
  if (value == null) throw UsageException('--$name: нужно целое число', '');
  return value;
}

AppConfig _newConfig(CliContext ctx, ArgResults args, CryptoProvider crypto) =>
    AppConfig(
      nodes: args.option('nodes') ?? '${ctx.home.dir.path}/nodes',
      nodeCount: _int(args, 'node-count'),
      objects: args.option('objects') ?? '${ctx.home.dir.path}/objects',
      durability: DurabilityParameters(
        k: _int(args, 'k'),
        n: _int(args, 'n'),
        repairThreshold: _int(args, 'repair-threshold'),
      ),
      deviceId: crypto.randomBytes(32),
    )..check();

final class InitCommand extends CliCommand {
  new(super.ctx) {
    _storageOptions(this);
  }

  @override
  String get name => 'init';

  @override
  String get description =>
      'Создать учётную запись: фраза восстановления, пароль, настройки.';

  @override
  Future<int> run() async {
    if (ctx.home.keysFile.existsSync()) {
      throw CliException('В ${ctx.home.dir.path} уже есть учётная запись');
    }
    final crypto = await ctx.crypto();
    final config = _newConfig(ctx, argResults!, crypto);
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
    _checkWords(words);
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

  /// Ввод трёх случайных слов — проверка, что фраза записана (У-2).
  void _checkWords(List<String> words) {
    final positions = <int>{};
    while (positions.length < 3) {
      positions.add(ctx.random.nextInt(words.length));
    }
    for (final p in positions.toList()..sort()) {
      for (var attempt = 0; ; attempt++) {
        final answer = ctx.console
            .ask('Слово №${p + 1}: ')
            ?.trim()
            .toLowerCase();
        if (answer == null) throw const CliException('Проверка фразы прервана');
        if (answer == words[p]) break;
        if (attempt == 2) {
          throw const CliException('Слово введено неверно трижды');
        }
        ctx.console.err('Неверно, ещё раз.');
      }
    }
  }
}

final class RecoverCommand extends CliCommand {
  new(super.ctx) {
    _storageOptions(this);
  }

  @override
  String get name => 'recover';

  @override
  String get description =>
      'Восстановить учётную запись на этом устройстве по фразе.';

  @override
  Future<int> run() async {
    if (ctx.home.keysFile.existsSync()) {
      throw CliException('В ${ctx.home.dir.path} уже есть учётная запись');
    }
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
    final password = ctx.newPassword();
    final keys = await AccountKeys.fromPhrase(phrase, crypto);
    await (await ctx.keyStore()).create(keys, password, phrase: phrase);
    config.save(ctx.home);
    final index = ctx.index();
    try {
      final report = await recoverIndex(
        crypto: crypto,
        manifestKey: keys.manifestKey,
        store: ctx.objects(config),
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
      keys.dispose();
      phrase.dispose();
    }
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
      ..info('Папки-«узлы»: ${config.nodes} (${config.nodeCount})')
      ..info('Папка объектов: ${config.objects}')
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
