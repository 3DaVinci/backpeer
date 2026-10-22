import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// Запись метаданных при восстановлении. Пути и цели ссылок — байты ОС.
abstract interface class FileSystemWriter {
  /// Символическая ссылка [path] → [target].
  void symlink(Uint8List path, Uint8List target);

  /// Права (`mode & 0o7777`); для ссылок не вызывается.
  void setMode(Uint8List path, int mode);

  /// Время изменения с наносекундами; у ссылки — у самой ссылки.
  void setMtime(Uint8List path, int mtimeNs, {required bool isSymlink});

  /// Владелец; `false` — не поддерживается или нет прав (не root).
  bool setOwner(Uint8List path, int uid, int gid, {required bool isSymlink});

  /// Переименование поверх существующего (атомарно в пределах тома).
  void rename(Uint8List from, Uint8List to);

  /// Удаляет файл или ссылку (не каталог).
  void unlink(Uint8List path);

  /// Создан ли процесс с правами менять владельца файлов.
  bool get canChangeOwner;

  static FileSystemWriter forPlatform() =>
      Platform.isWindows ? const _DartIoWriter() : PosixFileWriter();
}

/// [FileSystemWriter] на libc через FFI (Linux, macOS).
final class PosixFileWriter implements FileSystemWriter {
  factory() {
    final lib = DynamicLibrary.process();
    final mac = Platform.isMacOS;
    return PosixFileWriter._(
      symlinkC: lib
          .lookupFunction<
            Int32 Function(Pointer<Uint8>, Pointer<Uint8>),
            int Function(Pointer<Uint8>, Pointer<Uint8>)
          >('symlink'),
      chmodC: mac
          ? lib.lookupFunction<
              Int32 Function(Pointer<Uint8>, Uint16),
              int Function(Pointer<Uint8>, int)
            >('chmod')
          : lib.lookupFunction<
              Int32 Function(Pointer<Uint8>, Uint32),
              int Function(Pointer<Uint8>, int)
            >('chmod'),
      utimensatC: lib
          .lookupFunction<
            Int32 Function(Int32, Pointer<Uint8>, Pointer<Int64>, Int32),
            int Function(int, Pointer<Uint8>, Pointer<Int64>, int)
          >('utimensat'),
      lchownC: lib
          .lookupFunction<
            Int32 Function(Pointer<Uint8>, Uint32, Uint32),
            int Function(Pointer<Uint8>, int, int)
          >('lchown'),
      geteuidC: lib.lookupFunction<Uint32 Function(), int Function()>(
        'geteuid',
      ),
      renameC: lib
          .lookupFunction<
            Int32 Function(Pointer<Uint8>, Pointer<Uint8>),
            int Function(Pointer<Uint8>, Pointer<Uint8>)
          >('rename'),
      unlinkC: lib
          .lookupFunction<
            Int32 Function(Pointer<Uint8>),
            int Function(Pointer<Uint8>)
          >('unlink'),
      atFdCwd: mac ? -2 : -100,
      atSymlinkNoFollow: mac ? 0x20 : 0x100,
    );
  }

  new _({
    required this.symlinkC,
    required this.chmodC,
    required this.utimensatC,
    required this.lchownC,
    required this.geteuidC,
    required this.renameC,
    required this.unlinkC,
    required this.atFdCwd,
    required this.atSymlinkNoFollow,
  });

  final int Function(Pointer<Uint8>, Pointer<Uint8>) symlinkC;
  final int Function(Pointer<Uint8>, int) chmodC;
  final int Function(int, Pointer<Uint8>, Pointer<Int64>, int) utimensatC;
  final int Function(Pointer<Uint8>, int, int) lchownC;
  final int Function() geteuidC;
  final int Function(Pointer<Uint8>, Pointer<Uint8>) renameC;
  final int Function(Pointer<Uint8>) unlinkC;
  final int atFdCwd;
  final int atSymlinkNoFollow;

  @override
  bool get canChangeOwner => geteuidC() == 0;

  @override
  void symlink(Uint8List path, Uint8List target) =>
      _with2(path, target, (p, t) {
        if (symlinkC(t, p) != 0) throw _error('symlink', path);
      });

  @override
  void rename(Uint8List from, Uint8List to) => _with2(from, to, (f, t) {
    if (renameC(f, t) != 0) throw _error('rename', to);
  });

  @override
  void unlink(Uint8List path) => _with(path, (p) {
    if (unlinkC(p) != 0) throw _error('unlink', path);
  });

  @override
  void setMode(Uint8List path, int mode) => _with(path, (p) {
    if (chmodC(p, mode & 0xFFF) != 0) throw _error('chmod', path);
  });

  @override
  void setMtime(Uint8List path, int mtimeNs, {required bool isSymlink}) =>
      _with(path, (p) {
        // times[0] — atime (UTIME_OMIT: не трогать), times[1] — mtime.
        final times = calloc<Int64>(4);
        try {
          times[0] = 0;
          times[1] = _utimeOmit;
          times[2] = mtimeNs ~/ 1000000000;
          times[3] = mtimeNs % 1000000000;
          final flags = isSymlink ? atSymlinkNoFollow : 0;
          if (utimensatC(atFdCwd, p, times, flags) != 0) {
            throw _error('utimensat', path);
          }
        } finally {
          calloc.free(times);
        }
      });

  @override
  bool setOwner(Uint8List path, int uid, int gid, {required bool isSymlink}) {
    if (!canChangeOwner) return false;
    return _with(path, (p) => lchownC(p, uid, gid) == 0);
  }

  // UTIME_OMIT: Linux ((1 << 30) - 2), macOS -2.
  static final int _utimeOmit = Platform.isMacOS ? -2 : (1 << 30) - 2;

  static T _with<T>(Uint8List path, T Function(Pointer<Uint8>) body) {
    final p = _cString(path);
    try {
      return body(p);
    } finally {
      malloc.free(p);
    }
  }

  static T _with2<T>(
    Uint8List a,
    Uint8List b,
    T Function(Pointer<Uint8>, Pointer<Uint8>) body,
  ) {
    final pa = _cString(a);
    final pb = _cString(b);
    try {
      return body(pa, pb);
    } finally {
      malloc
        ..free(pa)
        ..free(pb);
    }
  }

  static Pointer<Uint8> _cString(Uint8List bytes) {
    final p = malloc<Uint8>(bytes.length + 1);
    p.asTypedList(bytes.length + 1)
      ..setAll(0, bytes)
      ..[bytes.length] = 0;
    return p;
  }

  static FileSystemException _error(String call, Uint8List path) =>
      FileSystemException(
        '$call не удался',
        utf8.decode(path, allowMalformed: true),
      );
}

/// Windows: `dart:io`; права и владелец не восстанавливаются, время — с
/// точностью до миллисекунд.
final class _DartIoWriter implements FileSystemWriter {
  const new();

  @override
  bool get canChangeOwner => false;

  @override
  void symlink(Uint8List path, Uint8List target) =>
      Link(utf8.decode(path)).createSync(utf8.decode(target));

  @override
  void rename(Uint8List from, Uint8List to) =>
      File(utf8.decode(from)).renameSync(utf8.decode(to));

  @override
  void unlink(Uint8List path) {
    final p = utf8.decode(path);
    if (FileSystemEntity.isLinkSync(p)) {
      Link(p).deleteSync();
    } else {
      File(p).deleteSync();
    }
  }

  @override
  void setMode(Uint8List path, int mode) {}

  @override
  void setMtime(Uint8List path, int mtimeNs, {required bool isSymlink}) {
    if (isSymlink) return;
    final p = utf8.decode(path);
    final time = DateTime.fromMicrosecondsSinceEpoch(mtimeNs ~/ 1000);
    if (FileSystemEntity.isDirectorySync(p)) return;
    File(p).setLastModifiedSync(time);
  }

  @override
  bool setOwner(Uint8List path, int uid, int gid, {required bool isSymlink}) =>
      false;
}
