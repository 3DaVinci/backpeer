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
    final crypto = await ctx.crypto();
    final session = await ctx.session(config);
    // Пул из 2 isolate: ~71 МБ/с и ~350 МиБ памяти (docs/benchmarks.md,
    // раздел 1.6.3).
    final encoder = await IsolateSegmentEncoder.start(2);
    final cancel = CancellationToken();
    final sigint = ProcessSignal.sigint.watch().listen((_) {
      ctx.report.warn('Остановка… готовые сегменты сохранятся.');
      cancel.cancel();
    });
    try {
      final result = await runBackup(
        crypto: crypto,
        keys: session.keys,
        index: session.index,
        fragments: session.fragments,
        objects: session.objects,
        placer: session.placer,
        paths: [for (final p in paths) Directory(p).absolute.path],
        deviceId: config.deviceId,
        excludes: ExcludeRules([
          ...config.excludes,
          ...argResults!.multiOption('exclude'),
        ]),
        params: config.durability,
        encoder: encoder,
        cancel: cancel,
        onProgress: (p) => ctx.report.progress(
          {
            'files': p.files,
            'bytesRead': p.bytesRead,
            'newBytes': p.newBytes,
            'segmentsStored': p.segmentsStored,
            'elapsedMs': p.elapsed.inMilliseconds,
          },
          'файлов ${p.files}, прочитано ${_size(p.bytesRead)}, '
          'новых ${_size(p.newBytes)}, сегментов ${p.segmentsStored}, '
          '${_size(p.readRate.round())}/с',
        ),
      );
      ctx.console.progress('');
      final st = result.stats;
      ctx.report.info(
        'Снимок ${_shortId(result.snapshot.snapshotId)}: файлов ${st.files}, '
        '${_size(st.bytes)}, новых ${_size(st.newBytes)} '
        '(${st.newChunks} чанков, ${result.segmentsStored} сегментов).',
      );
      for (final w in result.warnings) {
        ctx.report.warn('Внимание: ${_warning(w)}.', {'rollback': w.name});
      }
      for (final skipped in result.report.skipped) {
        ctx.report.warn('Пропущено: $skipped', {
          'path': skipped.path,
          'reason': skipped.reason.name,
          'detail': skipped.detail,
        });
      }
      final code = result.report.isClean ? ExitCode.ok : ExitCode.partial;
      ctx.report.result({
        'snapshotId': bytesToHex(result.snapshot.snapshotId),
        'sequence': result.snapshot.sequence.toInt(),
        'files': st.files,
        'directories': st.directories,
        'bytes': st.bytes,
        'newChunks': st.newChunks,
        'newBytes': st.newBytes,
        'segments': result.segmentsStored,
        'skipped': result.report.skipped.length,
        'excluded': result.report.excluded,
      }, exitCode: code);
      return code;
    } on CancelledException {
      throw const CliException(
        'Бэкап остановлен; следующий запуск продолжит без повторной отправки',
        ExitCode.cancelled,
      );
    } finally {
      await encoder.close();
      await sigint.cancel();
      session.close();
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
    final session = await ctx.session(ctx.config());
    try {
      final listing = await SnapshotCatalog(
        crypto: await ctx.crypto(),
        manifestKey: session.keys.manifestKey,
        store: session.objects,
        index: session.index,
      ).list();
      if (listing.snapshots.isEmpty) ctx.report.info('Снимков нет.');
      final rows = <Map<String, Object?>>[];
      for (final snap in listing.snapshots) {
        final created = DateTime.fromMillisecondsSinceEpoch(
          snap.createdAtUnixMs.toInt(),
        );
        final date = created.toLocal().toString().substring(0, 19);
        ctx.report.info(
          '${_shortId(snap.snapshotId)}  №${snap.sequence}  $date  '
          '${snap.hostname}  ${snap.paths.join(', ')}  '
          'файлов ${snap.stats.files}, ${_size(snap.stats.bytes.toInt())}',
        );
        rows.add({
          'id': bytesToHex(snap.snapshotId),
          'sequence': snap.sequence.toInt(),
          'createdAt': created.toUtc().toIso8601String(),
          'hostname': snap.hostname,
          'paths': snap.paths,
          'files': snap.stats.files.toInt(),
          'bytes': snap.stats.bytes.toInt(),
          'parent': snap.parentSnapshotId.isEmpty
              ? null
              : bytesToHex(snap.parentSnapshotId),
        });
      }
      for (final w in listing.warnings) {
        ctx.report.warn('Внимание: ${_warning(w)}.', {'rollback': w.name});
      }
      for (final (id, e) in listing.unreadable) {
        ctx.report.warn('Снимок ${_shortId(id)} не прочитан: ${e.message}', {
          'snapshotId': bytesToHex(id),
        });
      }
      final code = listing.warnings.isEmpty && listing.unreadable.isEmpty
          ? ExitCode.ok
          : ExitCode.partial;
      ctx.report.result({'snapshots': rows}, exitCode: code);
      return code;
    } finally {
      session.close();
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
    final crypto = await ctx.crypto();
    final session = await ctx.session(ctx.config());
    try {
      final catalog = SnapshotCatalog(
        crypto: crypto,
        manifestKey: session.keys.manifestKey,
        store: session.objects,
        index: session.index,
      );
      final id = await _resolve(catalog, rest.first);
      final result = await runRestore(
        crypto: crypto,
        keys: session.keys,
        index: session.index,
        fragments: session.fragments,
        objects: session.objects,
        locator: session.locator,
        snapshotId: id,
        target: Directory(argResults!.option('to')!),
        paths: rest.skip(1).toList(),
        overwrite: argResults!.flag('overwrite'),
      );
      ctx.report.info(
        'Восстановлено: файлов ${result.files} (${_size(result.bytes)}), '
        'каталогов ${result.directories}, ссылок ${result.symlinks}.',
      );
      if (result.skippedExisting.isNotEmpty) {
        ctx.report.warn(
          'Не перезаписаны (уже есть, см. --overwrite): '
          '${result.skippedExisting.length}',
          {'existing': result.skippedExisting},
        );
      }
      for (final (path, reason) in result.errors) {
        ctx.report.warn('Не восстановлено: $path: $reason', {
          'path': path,
          'reason': reason,
        });
      }
      if (!result.ownersRestored && !Platform.isWindows) {
        ctx.report.info('Владелец файлов не менялся: нужны права root.');
      }
      final code = result.isComplete ? ExitCode.ok : ExitCode.partial;
      ctx.report.result({
        'snapshotId': bytesToHex(id),
        'files': result.files,
        'directories': result.directories,
        'symlinks': result.symlinks,
        'bytes': result.bytes,
        'skippedExisting': result.skippedExisting.length,
        'errors': result.errors.length,
        'ownersRestored': result.ownersRestored,
      }, exitCode: code);
      return code;
    } finally {
      session.close();
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
    final session = await ctx.session(config);
    try {
      final report = await runVerify(
        crypto: await ctx.crypto(),
        keys: session.keys,
        index: session.index,
        fragments: session.fragments,
        locator: session.locator,
        full: argResults!.flag('full'),
        params: config.durability,
      );
      ctx.report.info(
        'Сегментов ${report.segments}, фрагментов ${report.fragments}: '
        '${report.isHealthy ? 'всё в порядке' : 'есть проблемы'}.',
      );
      for (final p in report.problems) {
        ctx.report.warn('Фрагмент: $p', {
          'segmentId': bytesToHex(p.segmentId),
          'fragment': p.index,
          'node': p.node,
          'error': p.error.message,
        });
      }
      for (final id in report.atRisk) {
        ctx.report.warn('В риске (нужен ремонт): сегмент ${_shortId(id)}', {
          'atRisk': bytesToHex(id),
        });
      }
      for (final (id, e) in report.unrecoverable) {
        ctx.report.warn(
          'Не восстановить: сегмент ${_shortId(id)}: ${e.message}',
          {'unrecoverable': bytesToHex(id)},
        );
      }
      final code = report.unrecoverable.isNotEmpty
          ? ExitCode.error
          : report.isHealthy
          ? ExitCode.ok
          : ExitCode.partial;
      ctx.report.result({
        'full': argResults!.flag('full'),
        'segments': report.segments,
        'fragments': report.fragments,
        'healthy': report.isHealthy,
        'problems': report.problems.length,
        'atRisk': report.atRisk.length,
        'unrecoverable': report.unrecoverable.length,
      }, exitCode: code);
      return code;
    } finally {
      session.close();
    }
  }
}

final class ForgetCommand extends CliCommand {
  new(super.ctx);

  @override
  String get name => 'forget';

  @override
  String get description =>
      'Удалить снимок (место освободит сборка мусора: cli gc).';

  @override
  String get invocation => 'cli forget <снимок>';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 1) throw UsageException('Укажите один снимок', usage);
    final session = await ctx.session(ctx.config());
    try {
      final catalog = SnapshotCatalog(
        crypto: await ctx.crypto(),
        manifestKey: session.keys.manifestKey,
        store: session.objects,
        index: session.index,
      );
      final id = await _resolve(catalog, rest.single);
      await catalog.forget(id);
      ctx.report
        ..info('Снимок ${_shortId(id)} удалён.')
        ..result({'snapshotId': bytesToHex(id)});
      return ExitCode.ok;
    } finally {
      session.close();
    }
  }
}

/// Сборка мусора (задача 2.7.4; manifest.md, раздел 7): удаляет сегменты,
/// на которые не ссылается ни один снимок.
final class GcCommand extends CliCommand {
  new(super.ctx) {
    argParser.addFlag(
      'dry-run',
      negatable: false,
      help: 'Только посчитать, ничего не удалять',
    );
  }

  @override
  String get name => 'gc';

  @override
  String get description =>
      'Сборка мусора: удалить сегменты, не нужные ни одному снимку. '
      'Не запускайте одновременно с бэкапом на другом устройстве.';

  @override
  Future<int> run() async {
    final dryRun = argResults!.flag('dry-run');
    final session = await ctx.session(ctx.config());
    try {
      final report = await collectGarbage(
        crypto: await ctx.crypto(),
        keys: session.keys,
        index: session.index,
        fragments: session.fragments,
        objects: session.objects,
        releaser: session.releaser,
        locator: session.locator,
        dryRun: dryRun,
      );
      for (final (location, e) in report.fragmentErrors) {
        ctx.report.warn(
          'Фрагмент ${_shortId(location.fragmentId)} на ${location.node} '
          'не удалён: ${e.message}',
          {'fragment': bytesToHex(location.fragmentId)},
        );
      }
      ctx.report.info(
        dryRun
            ? 'Снимков ${report.snapshots}; можно удалить сегментов: '
                  '${report.segmentsDeleted}, останется ${report.segmentsLive}.'
            : 'Снимков ${report.snapshots}; удалено сегментов '
                  '${report.segmentsDeleted}, фрагментов '
                  '${report.fragmentsDeleted} (${report.bytesFreed} байт); '
                  'осталось сегментов ${report.segmentsLive}.',
      );
      final code = report.fragmentErrors.isEmpty
          ? ExitCode.ok
          : ExitCode.partial;
      ctx.report.result({
        'dryRun': dryRun,
        'snapshots': report.snapshots,
        'segmentsDeleted': report.segmentsDeleted,
        'segmentsLive': report.segmentsLive,
        'fragmentsDeleted': report.fragmentsDeleted,
        'bytesFreed': report.bytesFreed,
        'indexesRewritten': report.indexesRewritten,
        'fragmentErrors': report.fragmentErrors.length,
      }, exitCode: code);
      return code;
    } finally {
      session.close();
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
