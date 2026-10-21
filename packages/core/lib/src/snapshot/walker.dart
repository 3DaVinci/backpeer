import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:core/src/snapshot/dart_io_fs.dart';
import 'package:core/src/snapshot/exclude_rules.dart';
import 'package:core/src/snapshot/fs_entry.dart';
import 'package:core/src/snapshot/posix_fs.dart';

/// Почему элемент не попал в бэкап.
enum SkipReason {
  /// Сокет, устройство, FIFO.
  special,

  /// Ошибка доступа или чтения метаданных.
  error,
}

/// Пропущенный элемент для отчёта пользователю.
final class SkippedEntry {
  const new(this.path, this.reason, [this.detail]);

  /// Путь для показа (байты ОС, декодированные с заменой).
  final String path;
  final SkipReason reason;
  final String? detail;

  @override
  String toString() =>
      '$path: ${reason.name}${detail == null ? '' : ' ($detail)'}';
}

/// Отчёт обхода: пропущенное и число исключённых по правилам.
final class WalkReport {
  final List<SkippedEntry> skipped = [];
  int excluded = 0;

  bool get isClean => skipped.isEmpty;
}

/// Элемент обхода: полный путь (байты ОС), путь относительно корня (с `/`)
/// и метаданные.
typedef WalkItem = ({Uint8List path, String relative, FsEntry entry});

/// Обход папок для бэкапа (задача 1.5.1): символические ссылки не
/// разыменовываются, особые файлы пропускаются с записью в отчёт, ошибки
/// доступа к отдельным элементам не прерывают обход.
final class TreeWalker {
  new({
    FileSystemReader? fs,
    this.excludes = ExcludeRules.none,
    WalkReport? report,
  }) : fs = fs ?? defaultFileSystem(),
       report = report ?? WalkReport();

  /// Реализация для текущей ОС: FFI к libc на Linux и macOS, `dart:io` на
  /// Windows.
  static FileSystemReader defaultFileSystem() =>
      Platform.isWindows ? const DartIoFileSystem() : PosixFileSystem();

  final FileSystemReader fs;
  final ExcludeRules excludes;
  final WalkReport report;

  /// Путь корня, как его ввёл пользователь, в байты ОС.
  static Uint8List rootPath(String path) => utf8.encode(path);

  /// Метаданные корня. Ошибка — исключение: без корня бэкапа нет.
  FsEntry root(Uint8List path) => fs.stat(path, path);

  /// Содержимое каталога, отсортированное по имени побайтно (manifest.md,
  /// раздел 3). [relative] — путь каталога от корня (`''` для корня).
  /// Исключённые элементы не возвращаются; особые и недоступные — тоже, с
  /// записью в [report]. Если сам каталог не читается, возвращается пустой
  /// список и ошибка в отчёте.
  List<FsEntry> list(Uint8List directory, String relative) {
    final List<Uint8List> names;
    try {
      names = fs.list(directory);
    } on FileSystemException catch (e) {
      report.skipped.add(
        SkippedEntry(_show(directory), SkipReason.error, _message(e)),
      );
      return const [];
    }
    final entries = <FsEntry>[];
    for (final name in names) {
      final path = join(directory, name);
      final rel = relative.isEmpty
          ? utf8.decode(name, allowMalformed: true)
          : '$relative/${utf8.decode(name, allowMalformed: true)}';
      final FsEntry entry;
      try {
        entry = fs.stat(path, name);
      } on FileSystemException catch (e) {
        report.skipped.add(
          SkippedEntry(_show(path), SkipReason.error, _message(e)),
        );
        continue;
      }
      if (excludes.excludes(
        rel,
        isDirectory: entry.kind == EntryKind.directory,
      )) {
        report.excluded++;
        continue;
      }
      if (entry.kind == EntryKind.other) {
        report.skipped.add(SkippedEntry(_show(path), SkipReason.special));
        continue;
      }
      entries.add(entry);
    }
    entries.sort((a, b) => compareBytes(a.name, b.name));
    return entries;
  }

  /// Цель ссылки; ошибка — `null` и запись в отчёт.
  Uint8List? readLink(Uint8List path) {
    try {
      return fs.readLink(path);
    } on FileSystemException catch (e) {
      report.skipped.add(
        SkippedEntry(_show(path), SkipReason.error, _message(e)),
      );
      return null;
    }
  }

  /// Обход в глубину в порядке имён, начиная с содержимого [root].
  Iterable<WalkItem> walk(Uint8List root, [String relative = '']) sync* {
    for (final entry in list(root, relative)) {
      final path = join(root, entry.name);
      final rel = relative.isEmpty
          ? utf8.decode(entry.name, allowMalformed: true)
          : '$relative/${utf8.decode(entry.name, allowMalformed: true)}';
      yield (path: path, relative: rel, entry: entry);
      if (entry.kind == EntryKind.directory) yield* walk(path, rel);
    }
  }

  Uint8List join(Uint8List directory, Uint8List name) {
    final needsSeparator =
        directory.isNotEmpty && directory.last != fs.separator;
    final out = Uint8List(
      directory.length + name.length + (needsSeparator ? 1 : 0),
    )..setAll(0, directory);
    if (needsSeparator) out[directory.length] = fs.separator;
    out.setAll(out.length - name.length, name);
    return out;
  }

  static String _show(Uint8List path) =>
      utf8.decode(path, allowMalformed: true);

  static String _message(FileSystemException e) =>
      e.osError?.message ?? e.message;
}

/// Побайтное сравнение (порядок узлов дерева).
int compareBytes(Uint8List a, Uint8List b) {
  final n = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < n; i++) {
    if (a[i] != b[i]) return a[i] - b[i];
  }
  return a.length - b.length;
}
