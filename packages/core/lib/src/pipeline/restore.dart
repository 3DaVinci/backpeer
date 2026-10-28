import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:core/src/chunking/chunk_id.dart';
import 'package:core/src/crypto/account_keys.dart';
import 'package:core/src/crypto/crypto_provider.dart';
import 'package:core/src/errors.dart';
import 'package:core/src/pipeline/segment_packer.dart';
import 'package:core/src/pipeline/segment_reader.dart';
import 'package:core/src/snapshot/fs_entry.dart';
import 'package:core/src/snapshot/fs_writer.dart';
import 'package:core/src/snapshot/manifest_objects.dart';
import 'package:core/src/snapshot/snapshot_catalog.dart';
import 'package:core/src/snapshot/walker.dart';
import 'package:core/src/storage/fragment_store.dart';
import 'package:core/src/storage/local_index.dart';
import 'package:core/src/storage/object_store.dart';
import 'package:core/src/storage/placement.dart';
import 'package:protocol/protocol.dart' as pb;

/// Итог восстановления.
final class RestoreResult {
  int files = 0;
  int directories = 0;
  int symlinks = 0;
  int bytes = 0;
  int segmentsFetched = 0;

  /// Уже существующие пути, которые не перезаписаны (без `overwrite`).
  final List<String> skippedExisting = [];

  /// Восстановлены рядом с существующими под другим именем
  /// ([ExistingFiles.keepBoth]): исходный путь и новый.
  final List<(String, String)> renamed = [];

  /// Пути, которые не удалось восстановить, и причина.
  final List<(String, String)> errors = [];

  /// Метаданные, которые нельзя восстановить: владелец без прав root.
  bool ownersRestored = false;

  bool get isComplete => errors.isEmpty && skippedExisting.isEmpty;
}

/// Что делать с файлом, который уже есть на месте восстанавливаемого
/// (задача 5.4.2). Каталоги не заменяются: восстановление идёт внутрь
/// существующего.
enum ExistingFiles {
  /// Оставить существующий, восстановленный не записывать.
  skip,

  /// Заменить существующий.
  overwrite,

  /// Оставить существующий, восстановленный записать рядом:
  /// `отчёт (restored).txt`, `отчёт (restored 2).txt`.
  keepBoth,
}

/// Ожидание узлов при восстановлении (задача 3.9.3; durability.md,
/// раздел 3): фрагменты сегмента, которых сейчас меньше k, появятся,
/// когда узлы выйдут в сеть.
final class RestoreWait {
  const new({
    this.maxWait = Duration.zero,
    this.retryInterval = const Duration(seconds: 30),
  });

  /// Не ждать: недоступный сегмент — сразу ошибка файла.
  static const none = RestoreWait();

  /// Сколько ждать недостающие фрагменты после первого прохода.
  final Duration maxWait;

  /// Как часто повторять отложенные файлы.
  final Duration retryInterval;

  bool get enabled => maxWait > Duration.zero;
}

/// Прогресс восстановления.
final class RestoreProgress {
  const new({
    required this.files,
    required this.bytes,
    required this.totalBytes,
    required this.segmentsFetched,
    required this.waitingFiles,
    required this.nextRetry,
    required this.waitLeft,
    required this.elapsed,
    this.waitingPaths = const [],
    this.waitingReason,
  });

  final int files;

  /// Байт файлов записано.
  final int bytes;

  /// Байт файлов в снимке; при восстановлении части путей — `null`.
  final int? totalBytes;
  final int segmentsFetched;

  /// Файлов и каталогов, отложенных до появления узлов.
  final int waitingFiles;

  /// Первые из отложенных (не больше пяти) — чтобы показать, чего ждём.
  final List<String> waitingPaths;

  /// Почему отложен первый из ожидающих: например, у сегмента меньше k
  /// фрагментов на узлах в сети.
  final String? waitingReason;

  /// Через сколько повтор отложенных; `null` — сейчас не ждём.
  final Duration? nextRetry;

  /// Сколько ещё готовы ждать узлы; `null` — ожидание не началось.
  final Duration? waitLeft;
  final Duration elapsed;

  /// Скорость записи, байт в секунду.
  double get rate =>
      elapsed.inMicroseconds == 0 ? 0 : bytes / elapsed.inMicroseconds * 1e6;

  /// Оценка оставшегося времени по средней скорости; не из чего считать
  /// или ждём узлы — `null`.
  Duration? get eta {
    final total = totalBytes;
    if (total == null || rate <= 0 || nextRetry != null) return null;
    final left = total - bytes;
    if (left <= 0) return Duration.zero;
    return Duration(microseconds: (left / rate * 1e6).round());
  }
}

/// Восстановление снимка целиком или отдельных путей в [target]
/// (задача 1.6.4). Корни снимка (исходные пути) раскладываются в [target]
/// по полному пути: `/home/u/data` → `<target>/home/u/data`.
///
/// [originalLocation] — на исходное место (по пути из снимка), [target]
/// тогда не нужен (задача 5.4.2).
///
/// [paths] — выбранные пути в исходном виде (`/home/u/data/sub`); пусто —
/// весь снимок. С уже существующими файлами поступает [existing]; без него —
/// заменяет при [overwrite], иначе пропускает. Для выбранных путей объём
/// считается заранее по деревьям снимка — для доли и оставшегося времени.
/// Ошибки отдельных файлов (например, недоступный сегмент) не прерывают
/// восстановление и попадают в [RestoreResult.errors].
///
/// С [wait] файл или каталог, сегменту которого не хватает фрагментов,
/// откладывается: восстанавливается всё, что можно, затем отложенные
/// повторяются каждые `retryInterval`, пока не получатся или не выйдет
/// `maxWait` (каждый повтор заново спрашивает `LocateSegment` — узлы и
/// свежие талоны). Корневое дерево без всего остального не прочитать —
/// его ждут сразу. Метаданные каталогов над отложенными ставятся заново
/// после докачки. [onProgress] вызывается каждые [progressInterval].
Future<RestoreResult> runRestore({
  required CryptoProvider crypto,
  required AccountKeys keys,
  required LocalIndex index,
  required FragmentStore fragments,
  required ObjectStore objects,
  required Uint8List snapshotId,
  Directory? target,
  bool originalLocation = false,
  SegmentLocator? locator,
  List<String> paths = const [],
  bool overwrite = false,
  ExistingFiles? existing,
  String renameSuffix = 'restored',
  CancellationToken? cancel,
  FileSystemWriter? writer,
  RestoreWait wait = RestoreWait.none,
  void Function(RestoreProgress)? onProgress,
  Duration progressInterval = const Duration(milliseconds: 250),
}) async {
  if (target == null && !originalLocation) {
    throw ArgumentError('нужен target или originalLocation');
  }
  final watch = Stopwatch()..start();
  final catalog = SnapshotCatalog(
    crypto: crypto,
    manifestKey: keys.manifestKey,
    store: objects,
    index: index,
  );
  final snapshot = await catalog.get(snapshotId);
  final restorer = _Restorer(
    reader: SegmentReader(
      crypto: crypto,
      keys: keys,
      index: index,
      store: fragments,
      locator: locator,
    ),
    writer: writer ?? FileSystemWriter.forPlatform(),
    fs: TreeWalker.defaultFileSystem(),
    selected: [for (final p in paths) _normalize(p)],
    existing:
        existing ?? (overwrite ? ExistingFiles.overwrite : ExistingFiles.skip),
    renameSuffix: renameSuffix,
    cancel: cancel ?? CancellationToken(),
    separator: Platform.isWindows ? 0x5C : 0x2F,
    wait: wait,
  );
  var totalBytes = paths.isEmpty && snapshot.hasStats()
      ? snapshot.stats.bytes.toInt()
      : null;
  void progress() => onProgress?.call(
    RestoreProgress(
      files: restorer.result.files,
      bytes: restorer.result.bytes,
      totalBytes: totalBytes,
      segmentsFetched: restorer.reader.segmentsFetched,
      waitingFiles: restorer.deferred.length,
      waitingPaths: [for (final d in restorer.deferred.take(5)) d.show],
      waitingReason: restorer.deferred.firstOrNull?.error,
      nextRetry: restorer.nextRetry?.difference(DateTime.now()),
      waitLeft: restorer.deadline?.difference(DateTime.now()),
      elapsed: watch.elapsed,
    ),
  );
  final timer = onProgress == null
      ? null
      : Timer.periodic(progressInterval, (_) => progress());
  try {
    target?.createSync(recursive: true);
    final root = await restorer.waitFor(
      () => restorer.tree(_ids(snapshot.rootTree)),
    );
    if (paths.isNotEmpty) totalBytes = await restorer.selectedBytes(root);
    await _restoreRoots(restorer, root, originalLocation ? null : target);
    await restorer.retryDeferred();
    progress();
  } finally {
    timer?.cancel();
  }
  restorer.result
    ..segmentsFetched = restorer.reader.segmentsFetched
    ..ownersRestored = restorer.writer.canChangeOwner;
  return restorer.result;
}

/// Корни снимка в [target] по полному пути или, без [target], — на их
/// исходные места.
Future<void> _restoreRoots(
  _Restorer restorer,
  pb.Tree root,
  Directory? target,
) async {
  for (final node in root.nodes) {
    final original = utf8.decode(node.name, allowMalformed: true);
    final logical = _normalize(original);
    if (!restorer.wanted(logical)) continue;
    Uint8List path;
    if (target == null) {
      path = utf8.encode(Directory(original).absolute.path);
    } else {
      final relative = logical
          .replaceFirst(RegExp('^/+'), '')
          .replaceAll(':', '');
      path = utf8.encode(target.absolute.path);
      for (final part in relative.split('/').where((p) => p.isNotEmpty)) {
        path = restorer.join(path, utf8.encode(part));
      }
    }
    // Каталоги над корнем бэкапа создаются как есть, без метаданных.
    Directory.fromRawPath(path).parent.createSync(recursive: true);
    await restorer.node(node, path, logical);
  }
}

/// Отложенный до появления узлов файл или каталог и каталоги над ним.
typedef _Deferred = ({
  pb.Node node,
  Uint8List path,
  String logical,
  String show,
  String error,
  List<_Dir> parents,
});

typedef _Dir = ({pb.Node node, Uint8List path, String logical});

final class _Restorer {
  new({
    required this.reader,
    required this.writer,
    required this.fs,
    required this.selected,
    required this.existing,
    required this.renameSuffix,
    required this.cancel,
    required this.separator,
    required this.wait,
  });

  final SegmentReader reader;
  final FileSystemWriter writer;
  final FileSystemReader fs;
  final List<String> selected;
  final ExistingFiles existing;
  final String renameSuffix;
  final CancellationToken cancel;
  final int separator;
  final RestoreWait wait;
  final RestoreResult result = RestoreResult();

  /// Отложенные до появления узлов.
  List<_Deferred> deferred = [];

  /// Каталоги, в которых сейчас идёт восстановление.
  final List<_Dir> _dirs = [];

  /// Каталоги над отложенными, по пути.
  final Map<String, _Dir> _touched = {};

  /// Когда кончится ожидание; `null` — ещё не ждём.
  DateTime? deadline;

  /// Когда следующий повтор; `null` — сейчас не ждём.
  DateTime? nextRetry;

  /// Сегменту не хватает фрагментов или координатор временно недоступен:
  /// узлы могут выйти в сеть позже.
  static bool _transient(CoreException e) => switch (e) {
    InsufficientShardsException() => true,
    CoordinatorException(:final code) =>
      code == pb.ErrorCode.ERROR_CODE_UNAVAILABLE ||
          code == pb.ErrorCode.ERROR_CODE_RATE_LIMITED,
    _ => false,
  };

  DateTime _deadline() => deadline ??= DateTime.now().add(wait.maxWait);

  /// Пауза до следующего повтора; ожидание вышло — `false`.
  Future<bool> _pause() async {
    final left = _deadline().difference(DateTime.now());
    if (left <= Duration.zero) return false;
    final pause = left < wait.retryInterval ? left : wait.retryInterval;
    final until = nextRetry = DateTime.now().add(pause);
    try {
      while (DateTime.now().isBefore(until)) {
        cancel.check();
        final rest = until.difference(DateTime.now());
        await Future<void>.delayed(
          rest < const Duration(milliseconds: 200)
              ? rest
              : const Duration(milliseconds: 200),
        );
      }
    } finally {
      nextRetry = null;
    }
    cancel.check();
    return true;
  }

  /// [read], повторяемое, пока сегментов не хватает и ожидание не вышло.
  Future<T> waitFor<T>(Future<T> Function() read) async {
    for (;;) {
      try {
        return await read();
      } on CoreException catch (e) {
        if (!wait.enabled || !_transient(e) || !await _pause()) rethrow;
      }
    }
  }

  /// Повторяет отложенные, пока они не получатся или не выйдет ожидание;
  /// оставшиеся — ошибки. Затем заново ставит метаданные каталогов над
  /// отложенными: запись в каталог меняет его mtime.
  Future<void> retryDeferred() async {
    while (deferred.isNotEmpty && await _pause()) {
      final round = deferred;
      deferred = [];
      for (final d in round) {
        _dirs
          ..clear()
          ..addAll(d.parents);
        await node(d.node, d.path, d.logical);
      }
      _dirs.clear();
    }
    for (final d in deferred) {
      result.errors.add((d.show, d.error));
    }
    deferred = [];
    final order = _touched.values.toList()
      ..sort((a, b) => b.path.length.compareTo(a.path.length));
    for (final dir in order) {
      if (!_whole(dir.logical)) continue;
      try {
        _metadata(dir.node, dir.path, isSymlink: false);
      } on FileSystemException catch (e) {
        result.errors.add((
          utf8.decode(dir.path, allowMalformed: true),
          e.osError?.message ?? e.message,
        ));
      }
    }
  }

  /// Узел входит в выбор сам или ведёт к выбранному (предок).
  bool wanted(String logical) =>
      selected.isEmpty ||
      selected.any(
        (s) =>
            s == logical ||
            s.startsWith('$logical/') ||
            logical.startsWith('$s/'),
      );

  /// Выбран целиком (сам или потомок выбранного).
  bool _whole(String logical) =>
      selected.isEmpty ||
      selected.any((s) => s == logical || logical.startsWith('$s/'));

  /// Объём файлов выбранных путей по деревьям снимка; дерево не
  /// прочитать (узлы не в сети) — `null`: доля и оставшееся время не
  /// показываются, восстановление само подождёт узлы.
  Future<int?> selectedBytes(pb.Tree root) async {
    var total = 0;
    Future<void> walk(pb.Tree tree, String? parent) async {
      for (final node in tree.nodes) {
        cancel.check();
        final name = utf8.decode(node.name, allowMalformed: true);
        final logical = parent == null ? _normalize(name) : '$parent/$name';
        if (!wanted(logical)) continue;
        if (node.type == pb.NodeType.NODE_TYPE_DIRECTORY) {
          await walk(await this.tree(_ids(node.subtree)), logical);
        } else if (node.type == pb.NodeType.NODE_TYPE_FILE && _whole(logical)) {
          total += node.size.toInt();
        }
      }
    }

    try {
      await walk(root, null);
      return total;
    } on CoreException {
      return null;
    }
  }

  Future<pb.Tree> tree(List<ChunkId> ids) async {
    final out = BytesBuilder(copy: false);
    for (final id in ids) {
      out.add(await reader.chunk(id));
    }
    final bytes = out.takeBytes();
    return ManifestObjects.parseMessage<pb.Tree>(
      'tree',
      () => pb.Tree.fromBuffer(bytes),
    );
  }

  Future<void> node(pb.Node node, Uint8List path, String logical) async {
    cancel.check();
    final show = utf8.decode(path, allowMalformed: true);
    try {
      switch (node.type) {
        case pb.NodeType.NODE_TYPE_DIRECTORY:
          await _directory(node, path, logical);
        case pb.NodeType.NODE_TYPE_FILE:
          if (!_whole(logical)) return;
          await _file(node, path, show);
        case pb.NodeType.NODE_TYPE_SYMLINK:
          if (!_whole(logical)) return;
          _symlink(node, path, show);
        case pb.NodeType.NODE_TYPE_UNSPECIFIED:
          result.errors.add((show, 'узел без типа'));
      }
    } on CancelledException {
      rethrow;
    } on CoreException catch (e) {
      if (wait.enabled && _transient(e)) {
        for (final d in _dirs) {
          _touched[utf8.decode(d.path, allowMalformed: true)] = d;
        }
        deferred.add((
          node: node,
          path: path,
          logical: logical,
          show: show,
          error: e.message,
          parents: List.of(_dirs),
        ));
      } else {
        result.errors.add((show, e.message));
      }
    } on FileSystemException catch (e) {
      result.errors.add((show, e.osError?.message ?? e.message));
    }
  }

  Future<void> _directory(pb.Node node, Uint8List path, String logical) async {
    Directory.fromRawPath(path).createSync(recursive: true);
    final children = await tree(_ids(node.subtree));
    _dirs.add((node: node, path: path, logical: logical));
    try {
      for (final child in children.nodes) {
        final name = utf8.decode(child.name, allowMalformed: true);
        final childLogical = '$logical/$name';
        if (!wanted(childLogical)) continue;
        await this.node(
          child,
          join(path, Uint8List.fromList(child.name)),
          childLogical,
        );
      }
    } finally {
      _dirs.removeLast();
    }
    result.directories++;
    // Метаданные каталога — после содержимого: запись детей меняет mtime.
    if (_whole(logical)) _metadata(node, path, isSymlink: false);
  }

  /// Путь для записи с учётом [existing]; `null` — пропустить.
  Uint8List? _destination(Uint8List path, String show) {
    final kind = _kind(path);
    if (kind == null) return path;
    switch (existing) {
      case ExistingFiles.skip:
        result.skippedExisting.add(show);
        return null;
      case ExistingFiles.overwrite:
        if (kind == EntryKind.directory) {
          Directory.fromRawPath(path).deleteSync(recursive: true);
        }
        return path;
      case ExistingFiles.keepBoth:
        final free = _freeName(path);
        result.renamed.add((show, utf8.decode(free, allowMalformed: true)));
        return free;
    }
  }

  /// `имя (restored).ext`, `имя (restored 2).ext`… — первое свободное.
  Uint8List _freeName(Uint8List path) {
    final cut = path.lastIndexOf(separator) + 1;
    final name = path.sublist(cut);
    // Расширение — после последней точки, но не у скрытых `.name`.
    var dot = name.lastIndexOf(0x2E);
    if (dot <= 0) dot = name.length;
    for (var n = 1; ; n++) {
      final mark = utf8.encode(
        n == 1 ? ' ($renameSuffix)' : ' ($renameSuffix $n)',
      );
      final candidate = Uint8List.fromList([
        ...path.sublist(0, cut),
        ...name.sublist(0, dot),
        ...mark,
        ...name.sublist(dot),
      ]);
      if (_kind(candidate) == null) return candidate;
    }
  }

  Future<void> _file(pb.Node node, Uint8List original, String show) async {
    final path = _destination(original, show);
    if (path == null) return;
    final tempPath = Uint8List.fromList([
      ...path,
      ...utf8.encode('.fs-restore-tmp'),
    ]);
    final temp = File.fromRawPath(tempPath);
    final out = temp.openSync(mode: FileMode.write);
    var written = 0;
    try {
      for (final id in _ids(node.content)) {
        final data = await reader.chunk(id);
        out.writeFromSync(data);
        written += data.length;
      }
    } on Object {
      out.closeSync();
      writer.unlink(tempPath);
      rethrow;
    }
    out.closeSync();
    if (written != node.size.toInt()) {
      writer.unlink(tempPath);
      throw const IntegrityException(
        object: 'file',
        check: IntegrityCheck.hash,
      );
    }
    // rename поверх: файл или ссылка на месте заменяются атомарно.
    writer.rename(tempPath, path);
    _metadata(node, path, isSymlink: false);
    result.files++;
    result.bytes += written;
  }

  void _symlink(pb.Node node, Uint8List original, String show) {
    final path = _destination(original, show);
    if (path == null) return;
    if (identical(path, original) && _kind(path) != null) writer.unlink(path);
    writer.symlink(path, Uint8List.fromList(node.symlinkTarget));
    _metadata(node, path, isSymlink: true);
    result.symlinks++;
  }

  /// Что уже лежит по пути (без разыменования ссылок); `null` — ничего.
  EntryKind? _kind(Uint8List path) {
    try {
      return fs.stat(path, path).kind;
    } on FileSystemException {
      return null;
    }
  }

  void _metadata(pb.Node node, Uint8List path, {required bool isSymlink}) {
    if (writer.canChangeOwner) {
      writer.setOwner(path, node.uid, node.gid, isSymlink: isSymlink);
    }
    if (!isSymlink && node.mode != 0) writer.setMode(path, node.mode);
    writer.setMtime(path, node.mtimeNs.toInt(), isSymlink: isSymlink);
  }

  Uint8List join(Uint8List directory, Uint8List name) {
    final out = Uint8List(directory.length + 1 + name.length)
      ..setAll(0, directory)
      ..[directory.length] = separator
      ..setAll(directory.length + 1, name);
    return out;
  }
}

List<ChunkId> _ids(List<List<int>> raw) => [for (final r in raw) ChunkId(r)];

/// Путь из снимка в логический вид с `/` и без `/` в конце.
String _normalize(String path) {
  var p = path.replaceAll(r'\', '/');
  while (p.length > 1 && p.endsWith('/')) {
    p = p.substring(0, p.length - 1);
  }
  return p;
}
