import 'dart:io';
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:cli/src/context.dart';
import 'package:core/core.dart';

String _size(int bytes) {
  const units = ['Б', 'КиБ', 'МиБ', 'ГиБ', 'ТиБ'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return unit == 0 ? '$bytes Б' : '${value.toStringAsFixed(1)} ${units[unit]}';
}

String _shortId(List<int> id) => bytesToHex(id).substring(0, 12);

String _warning(RollbackWarning w) => switch (w) {
  RollbackWarning.sequenceRegressed =>
    'список снимков старше известного устройству — возможен откат',
  RollbackWarning.lastSnapshotMissing =>
    'в списке нет последнего снимка этого устройства',
};

final class BackupCommand extends CliCommand {
  new(super.ctx) {
    argParser.addMultiOption(
      'exclude',
      abbr: 'e',
      help: 'Правило исключения (.gitignore), в дополнение к настройкам',
    );
  }

  @override
  String get name => 'backup';

  @override
  String get description => 'Сделать снимок указанных папок.';

  @override
  String get invocation => 'cli backup <папка>...';

  @override
  Future<int> run() async {
    final paths = argResults!.rest;
    if (paths.isEmpty) throw UsageException('Укажите папки', usage);
    final config = ctx.config();
    final keys = await ctx.unlock();
    final crypto = await ctx.crypto();
    final index = ctx.index();
    // Пул из 2 isolate: ~71 МБ/с и ~350 МиБ памяти (docs/benchmarks.md,
    // раздел 1.6.3).
    final encoder = await IsolateSegmentEncoder.start(2);
    final cancel = CancellationToken();
    final sigint = ProcessSignal.sigint.watch().listen((_) {
      ctx.console.err('\nОстанавливаюсь… готовые сегменты сохранятся.');
      cancel.cancel();
    });
    try {
      final result = await runBackup(
        crypto: crypto,
        keys: keys,
        index: index,
        fragments: await ctx.fragments(config),
        objects: ctx.objects(config),
        paths: [for (final p in paths) Directory(p).absolute.path],
        deviceId: config.deviceId,
        excludes: ExcludeRules([
          ...config.excludes,
          ...argResults!.multiOption('exclude'),
        ]),
        params: config.durability,
        encoder: encoder,
        cancel: cancel,
        onProgress: (p) => ctx.console.progress(
          'файлов ${p.files}, прочитано ${_size(p.bytesRead)}, '
          'новых ${_size(p.newBytes)}, сегментов ${p.segmentsStored}, '
          '${_size(p.readRate.round())}/с',
        ),
      );
      ctx.console.progress('');
      final s = result.stats;
      ctx.console.out(
        'Снимок ${_shortId(result.snapshot.snapshotId)}: файлов ${s.files}, '
        '${_size(s.bytes)}, новых ${_size(s.newBytes)} '
        '(${s.newChunks} чанков, ${result.segmentsStored} сегментов).',
      );
      for (final w in result.warnings) {
        ctx.console.err('Внимание: ${_warning(w)}.');
      }
      for (final skipped in result.report.skipped) {
        ctx.console.err('Пропущено: $skipped');
      }
      return result.report.isClean ? ExitCode.ok : ExitCode.partial;
    } on CancelledException {
      throw const CliException(
        'Бэкап остановлен; следующий запуск продолжит без повторной отправки',
      );
    } finally {
      await encoder.close();
      await sigint.cancel();
      index.close();
      keys.dispose();
    }
  }
}

final class SnapshotsCommand extends CliCommand {
  new(super.ctx);

  @override
  String get name => 'snapshots';

  @override
  String get description => 'Список снимков.';

  @override
  Future<int> run() async {
    final config = ctx.config();
    final keys = await ctx.unlock();
    final index = ctx.index();
    try {
      final listing = await SnapshotCatalog(
        crypto: await ctx.crypto(),
        manifestKey: keys.manifestKey,
        store: ctx.objects(config),
        index: index,
      ).list();
      if (listing.snapshots.isEmpty) ctx.console.out('Снимков нет.');
      for (final s in listing.snapshots) {
        final date = DateTime.fromMillisecondsSinceEpoch(
          s.createdAtUnixMs.toInt(),
        ).toLocal().toString().substring(0, 19);
        ctx.console.out(
          '${_shortId(s.snapshotId)}  №${s.sequence}  $date  ${s.hostname}  '
          '${s.paths.join(', ')}  файлов ${s.stats.files}, '
          '${_size(s.stats.bytes.toInt())}',
        );
      }
      for (final w in listing.warnings) {
        ctx.console.err('Внимание: ${_warning(w)}.');
      }
      for (final (id, e) in listing.unreadable) {
        ctx.console.err('Снимок ${_shortId(id)} не прочитан: ${e.message}');
      }
      return listing.warnings.isEmpty && listing.unreadable.isEmpty
          ? ExitCode.ok
          : ExitCode.partial;
    } finally {
      index.close();
      keys.dispose();
    }
  }
}

final class RestoreCommand extends CliCommand {
  new(super.ctx) {
    argParser
      ..addOption('to', abbr: 't', help: 'Папка назначения', mandatory: true)
      ..addFlag(
        'overwrite',
        help: 'Перезаписывать существующие файлы',
        negatable: false,
      );
  }

  @override
  String get name => 'restore';

  @override
  String get description =>
      'Восстановить снимок целиком или выбранные пути (в исходном виде).';

  @override
  String get invocation => 'cli restore <снимок> [путь...] --to <папка>';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.isEmpty) throw UsageException('Укажите снимок', usage);
    final config = ctx.config();
    final keys = await ctx.unlock();
    final crypto = await ctx.crypto();
    final index = ctx.index();
    try {
      final objects = ctx.objects(config);
      final catalog = SnapshotCatalog(
        crypto: crypto,
        manifestKey: keys.manifestKey,
        store: objects,
        index: index,
      );
      final id = await _resolve(catalog, rest.first);
      final result = await runRestore(
        crypto: crypto,
        keys: keys,
        index: index,
        fragments: await ctx.fragments(config),
        objects: objects,
        snapshotId: id,
        target: Directory(argResults!.option('to')!),
        paths: rest.skip(1).toList(),
        overwrite: argResults!.flag('overwrite'),
      );
      ctx.console.out(
        'Восстановлено: файлов ${result.files} (${_size(result.bytes)}), '
        'каталогов ${result.directories}, ссылок ${result.symlinks}.',
      );
      if (result.skippedExisting.isNotEmpty) {
        ctx.console.err(
          'Не перезаписаны (уже есть, см. --overwrite): '
          '${result.skippedExisting.length}',
        );
      }
      for (final (path, reason) in result.errors) {
        ctx.console.err('Не восстановлено: $path: $reason');
      }
      if (!result.ownersRestored && !Platform.isWindows) {
        ctx.console.out('Владелец файлов не менялся: нужны права root.');
      }
      return result.isComplete ? ExitCode.ok : ExitCode.partial;
    } finally {
      index.close();
      keys.dispose();
    }
  }
}

final class VerifyCommand extends CliCommand {
  new(super.ctx) {
    argParser.addFlag(
      'full',
      help: 'Прочитать и проверить все фрагменты (долго)',
      negatable: false,
    );
  }

  @override
  String get name => 'verify';

  @override
  String get description =>
      'Проверить сохранённые сегменты: на месте ли фрагменты '
      '(--full — целы ли).';

  @override
  Future<int> run() async {
    final config = ctx.config();
    final keys = await ctx.unlock();
    final index = ctx.index();
    try {
      final report = await runVerify(
        crypto: await ctx.crypto(),
        keys: keys,
        index: index,
        fragments: await ctx.fragments(config),
        full: argResults!.flag('full'),
        params: config.durability,
      );
      ctx.console.out(
        'Сегментов ${report.segments}, фрагментов ${report.fragments}: '
        '${report.isHealthy ? 'всё в порядке' : 'есть проблемы'}.',
      );
      for (final p in report.problems) {
        ctx.console.err('Фрагмент: $p');
      }
      for (final id in report.atRisk) {
        ctx.console.err('В риске (нужен ремонт): сегмент ${_shortId(id)}');
      }
      for (final (id, e) in report.unrecoverable) {
        ctx.console.err(
          'Не восстановить: сегмент ${_shortId(id)}: ${e.message}',
        );
      }
      if (report.unrecoverable.isNotEmpty) return ExitCode.error;
      return report.isHealthy ? ExitCode.ok : ExitCode.partial;
    } finally {
      index.close();
      keys.dispose();
    }
  }
}

final class ForgetCommand extends CliCommand {
  new(super.ctx);

  @override
  String get name => 'forget';

  @override
  String get description =>
      'Удалить снимок (место освободит сборка мусора — позже).';

  @override
  String get invocation => 'cli forget <снимок>';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 1) throw UsageException('Укажите один снимок', usage);
    final config = ctx.config();
    final keys = await ctx.unlock();
    final index = ctx.index();
    try {
      final catalog = SnapshotCatalog(
        crypto: await ctx.crypto(),
        manifestKey: keys.manifestKey,
        store: ctx.objects(config),
        index: index,
      );
      final id = await _resolve(catalog, rest.single);
      await catalog.forget(id);
      ctx.console.out('Снимок ${_shortId(id)} удалён.');
      return ExitCode.ok;
    } finally {
      index.close();
      keys.dispose();
    }
  }
}

/// Снимок по началу идентификатора (не короче 4 hex-символов).
Future<Uint8List> _resolve(SnapshotCatalog catalog, String prefix) async {
  if (prefix.length < 4) {
    throw const CliException(
      'Укажите не меньше 4 символов идентификатора снимка',
      ExitCode.usage,
    );
  }
  final found = await catalog.matching(prefix);
  return switch (found) {
    [final id] => id,
    [] => throw CliException('Снимок $prefix не найден', ExitCode.usage),
    _ => throw CliException(
      'Префикс $prefix подходит к ${found.length} снимкам',
      ExitCode.usage,
    ),
  };
}
