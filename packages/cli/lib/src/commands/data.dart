import 'dart:io';
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:cli/src/commands/account.dart';
import 'package:cli/src/commands/status.dart';
import 'package:cli/src/context.dart';
import 'package:core/core.dart';

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
          'файлов ${p.files}, прочитано ${formatSize(p.bytesRead)}, '
          'новых ${formatSize(p.newBytes)}, сегментов ${p.segmentsStored}, '
          '${formatSize(p.readRate.round())}/с',
        ),
      );
      ctx.console.progress('');
      final st = result.stats;
      ctx.report.info(
        'Снимок ${_shortId(result.snapshot.snapshotId)}: файлов ${st.files}, '
        '${formatSize(st.bytes)}, новых ${formatSize(st.newBytes)} '
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
      await session.close();
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
          'файлов ${snap.stats.files}, ${formatSize(snap.stats.bytes.toInt())}',
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
      await session.close();
    }
  }
}

String _restoreLine(RestoreProgress p) {
  final total = p.totalBytes;
  final line = StringBuffer(
    'файлов ${p.files}, ${formatSize(p.bytes)}'
    '${total == null ? '' : ' из ${formatSize(total)}'}, '
    '${formatSize(p.rate.round())}/с',
  );
  if (p.eta case final Duration eta) line.write(', осталось ${_duration(eta)}');
  if (p.waitingFiles > 0) {
    line.write(', ждут узлов: ${p.waitingFiles}');
    if (p.nextRetry case final Duration next) {
      line.write(', повтор через ${_duration(next)}');
    }
    if (p.waitLeft case final Duration left) {
      line.write(', ждём ещё до ${_duration(left)}');
    }
  }
  return line.toString();
}

String _duration(Duration d) {
  if (d.isNegative) return '0 с';
  if (d.inHours > 0) return '${d.inHours} ч ${d.inMinutes % 60} мин';
  if (d.inMinutes > 0) return '${d.inMinutes} мин ${d.inSeconds % 60} с';
  return '${d.inSeconds} с';
}

final class RestoreCommand extends CliCommand {
  new(super.ctx) {
    argParser
      ..addOption('to', abbr: 't', help: 'Папка назначения', mandatory: true)
      ..addFlag(
        'overwrite',
        help: 'Перезаписывать существующие файлы',
        negatable: false,
      )
      ..addOption(
        'wait',
        help:
            'Сколько минут ждать узлы, если фрагментов сегмента пока не '
            'хватает (0 — не ждать)',
        defaultsTo: '0',
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
      final minutes = int.tryParse(argResults!.option('wait')!);
      if (minutes == null || minutes < 0) {
        throw UsageException('--wait: нужно число минут', usage);
      }
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
        // Повтор — LocateSegment на каждый отложенный сегмент и попытки
        // подключиться к узлам: раз в 10 секунд не нагружает координатор.
        wait: RestoreWait(
          maxWait: Duration(minutes: minutes),
          retryInterval: const Duration(seconds: 10),
        ),
        onProgress: (p) => ctx.report.progress({
          'files': p.files,
          'bytes': p.bytes,
          'totalBytes': p.totalBytes,
          'segmentsFetched': p.segmentsFetched,
          'waitingFiles': p.waitingFiles,
          'nextRetryMs': p.nextRetry?.inMilliseconds,
          'etaMs': p.eta?.inMilliseconds,
          'elapsedMs': p.elapsed.inMilliseconds,
        }, _restoreLine(p)),
      );
      ctx.console.progress('');
      ctx.report.info(
        'Восстановлено: файлов ${result.files} (${formatSize(result.bytes)}), '
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
      await session.close();
    }
  }
}

final class VerifyCommand extends CliCommand {
  new(super.ctx) {
    argParser
      ..addFlag(
        'full',
        help: 'Прочитать и проверить все фрагменты (долго)',
        negatable: false,
      )
      ..addFlag(
        'audits',
        help:
            'Быстро по данным координатора: живые фрагменты и аудиты, '
            'без обращения к узлам',
        negatable: false,
      )
      ..addOption(
        'sample',
        valueHelp: 'N',
        help:
            'Тестовое восстановление N случайных сегментов: прочитать, '
            'собрать, расшифровать и сверить чанки',
      )
      ..addOption(
        'every',
        valueHelp: 'ДНЕЙ',
        help:
            'Для запуска по расписанию: проверить, только если такая же '
            'проверка была больше ДНЕЙ назад',
      );
  }

  @override
  String get name => 'verify';

  @override
  String get description =>
      'Проверить сохранённые сегменты: на месте ли фрагменты '
      '(--full — целы ли, --audits — по аудитам координатора, '
      '--sample — тестовое восстановление выборки).';

  @override
  Future<int> run() async {
    final args = argResults!;
    final sample = _positive(args.option('sample'), '--sample');
    final every = _positive(args.option('every'), '--every');
    final modes = [
      if (args.flag('full')) VerifyMode.full,
      if (args.flag('audits')) VerifyMode.audits,
      if (sample != null) VerifyMode.sample,
    ];
    if (modes.length > 1) {
      throw UsageException(
        '--full, --audits и --sample — разные проверки, укажите одну',
        usage,
      );
    }
    final mode = modes.firstOrNull ?? VerifyMode.exists;
    final config = ctx.config();
    final session = await ctx.session(config);
    try {
      final now = DateTime.now().toUtc();
      final last = session.index.lastVerify(mode);
      if (every != null &&
          last != null &&
          now.difference(last.at) < Duration(days: every)) {
        ctx.report.info(
          'Проверка «${verifyModeName(mode)}» была ${formatTime(last.at)}; '
          'следующая — после '
          '${formatTime(last.at.add(Duration(days: every)))}.',
        );
        ctx.report.result({
          'mode': mode.name,
          'skipped': true,
          'lastAt': last.at.toIso8601String(),
        });
        return ExitCode.ok;
      }
      final VerifyReport report;
      var sampled = 0;
      switch (mode) {
        case VerifyMode.audits:
          final client =
              session.client ??
              (throw const CliException(
                'Проверка по аудитам — только с координатором',
              ));
          try {
            report = await runAuditVerify(index: session.index, client: client);
          } on CoordinatorException catch (e) {
            coordinatorFailure(e);
          }
        case VerifyMode.exists || VerifyMode.full || VerifyMode.sample:
          List<Uint8List>? segments;
          if (sample != null) {
            segments = session.index.storedSegments()..shuffle(ctx.random);
            if (segments.length > sample) segments.length = sample;
            sampled = segments.length;
          }
          report = await runVerify(
            crypto: await ctx.crypto(),
            keys: session.keys,
            index: session.index,
            fragments: session.fragments,
            locator: session.locator,
            full: mode != VerifyMode.exists,
            segments: segments,
            params: config.durability,
          );
      }
      session.index.recordVerify(report.toRecord(mode, now));
      _print(mode, report);
      final code = report.unrecoverable.isNotEmpty
          ? ExitCode.error
          : report.isHealthy
          ? ExitCode.ok
          : ExitCode.partial;
      ctx.report.result({
        'mode': mode.name,
        'skipped': false,
        'full': mode == VerifyMode.full || mode == VerifyMode.sample,
        'segments': report.segments,
        'fragments': report.fragments,
        'healthy': report.isHealthy,
        'problems': report.problems.length,
        'atRisk': report.atRisk.length,
        'unrecoverable': report.unrecoverable.length,
        if (mode == VerifyMode.sample) 'sampled': sampled,
        if (mode == VerifyMode.audits) ...{
          'unaudited': report.unaudited.length,
          'repairing': report.repairing,
        },
      }, exitCode: code);
      return code;
    } finally {
      await session.close();
    }
  }

  void _print(VerifyMode mode, VerifyReport report) {
    final what = mode == VerifyMode.audits ? 'живых фрагментов' : 'фрагментов';
    ctx.report.info(
      '${_capitalized(verifyModeName(mode))}: сегментов ${report.segments}, '
      '$what ${report.fragments}: '
      '${report.isHealthy ? 'всё в порядке' : 'есть проблемы'}.',
    );
    if (mode == VerifyMode.audits) {
      final audited = report.segments - report.unaudited.length;
      ctx.report.info(
        '  с фрагментами, проверенными аудитом за 30 суток: $audited из '
        '${report.segments}; ремонтируются: ${report.repairing}',
      );
    }
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
  }

  int? _positive(String? value, String flag) {
    if (value == null) return null;
    final n = int.tryParse(value);
    if (n == null || n < 1) {
      throw UsageException('$flag — целое число больше 0', usage);
    }
    return n;
  }

  static String _capitalized(String s) =>
      s.substring(0, 1).toUpperCase() + s.substring(1);
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
      await session.close();
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
      await session.close();
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
