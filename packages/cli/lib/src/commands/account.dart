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
    ctx.console
      ..out('Фраза восстановления — единственный способ вернуть данные, ')
      ..out('если пароль забыт. Запишите её на бумаге и храните отдельно:')
      ..out('');
    for (var i = 0; i < words.length; i += 4) {
      ctx.console.out(
        [
          for (var j = i; j < i + 4; j++)
            '${(j + 1).toString().padLeft(2)}. ${words[j].padRight(10)}',
        ].join(' '),
      );
    }
    ctx.console.out('');
    _checkWords(words);
    final password = ctx.newPassword();
    final keys = await AccountKeys.fromPhrase(phrase, crypto);
    await (await ctx.keyStore()).create(keys, password, phrase: phrase);
    config.save(ctx.home);
    ctx.index().close();
    ctx.console.out(
      'Учётная запись создана: ${bytesToHex(keys.accountId).substring(0, 16)}… '
      '(${config.durability}).',
    );
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
      ctx.console.out(
        'Учётная запись восстановлена: '
        '${bytesToHex(keys.accountId).substring(0, 16)}…; '
        'индексов ${report.indexesRead}, сегментов ${report.segmentsAdded}.',
      );
      for (final (id, e) in report.unreadable) {
        ctx.console.err(
          'Индекс ${bytesToHex(id).substring(0, 16)} не прочитан: ${e.message}',
        );
      }
      return report.unreadable.isEmpty ? ExitCode.ok : ExitCode.partial;
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
      ctx.console.out('${(i + 1).toString().padLeft(2)}. ${words[i]}');
    }
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
    ctx.console
      ..out('Каталог программы: ${ctx.home.dir.path}')
      ..out('Папки-«узлы»: ${config.nodes} (${config.nodeCount})')
      ..out('Папка объектов: ${config.objects}')
      ..out('Надёжность: ${config.durability}')
      ..out('Устройство: ${bytesToHex(config.deviceId).substring(0, 16)}…')
      ..out(
        'Исключения: '
        '${config.excludes.isEmpty ? 'нет' : config.excludes.join(', ')}',
      );
    return ExitCode.ok;
  }
}
