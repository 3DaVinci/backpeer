import 'dart:io';

import 'package:core/src/pipeline/segment_packer.dart';
import 'package:core/src/snapshot/exclude_rules.dart';
import 'package:core/src/snapshot/fs_entry.dart';
import 'package:core/src/snapshot/walker.dart';

/// Оценка объёма бэкапа до его запуска (задача 5.3.1).
final class BackupEstimate {
  int files = 0;
  int directories = 0;

  /// Сумма размеров файлов — сколько прочитает первый бэкап. В сети займёт
  /// больше: n/k от сжатых и уникальных данных (`durability.md`).
  int bytes = 0;

  /// Исключено правилами.
  int excluded = 0;

  /// Пропущено: особые файлы, нет доступа.
  final List<SkippedEntry> skipped = [];

  /// Обход остановлен по [estimateBackup] `maxEntries`.
  bool truncated = false;

  Map<String, Object?> toJson({int maxSkipped = 100}) => {
    'files': files,
    'directories': directories,
    'bytes': bytes,
    'excluded': excluded,
    'skipped': skipped.length,
    'skippedFiles': [
      for (final s in skipped.take(maxSkipped))
        {'path': s.path, 'reason': s.reason.name, 'detail': ?s.detail},
    ],
    'truncated': truncated,
  };
}

/// Обходит [paths] с правилами [excludes], как бэкап, но только читает
/// метаданные: файлы не открываются. Обход синхронный (FFI к libc) —
/// длинный обход лучше запускать в отдельном isolate. [maxEntries] —
/// предел числа элементов; [cancel] проверяется каждые 1000 элементов.
BackupEstimate estimateBackup(
  List<String> paths, {
  ExcludeRules excludes = ExcludeRules.none,
  int? maxEntries,
  CancellationToken? cancel,
  FileSystemReader? fs,
}) {
  final walker = TreeWalker(fs: fs, excludes: excludes);
  final estimate = BackupEstimate();
  var seen = 0;
  outer:
  for (final path in paths) {
    final raw = TreeWalker.rootPath(path);
    final FsEntry root;
    try {
      root = walker.root(raw);
    } on FileSystemException catch (e) {
      walker.report.skipped.add(
        SkippedEntry(path, SkipReason.error, e.osError?.message ?? e.message),
      );
      continue;
    }
    if (root.kind == EntryKind.file) {
      estimate
        ..files += 1
        ..bytes += root.size;
      continue;
    }
    if (root.kind != EntryKind.directory) continue;
    estimate.directories++;
    for (final item in walker.walk(raw)) {
      if (++seen % 1000 == 0) cancel?.check();
      if (maxEntries != null && seen > maxEntries) {
        estimate.truncated = true;
        break outer;
      }
      switch (item.entry.kind) {
        case EntryKind.file:
          estimate
            ..files += 1
            ..bytes += item.entry.size;
        case EntryKind.directory:
          estimate.directories++;
        case EntryKind.symlink || EntryKind.other:
          break;
      }
    }
  }
  estimate
    ..excluded = walker.report.excluded
    ..skipped.addAll(walker.report.skipped);
  return estimate;
}
