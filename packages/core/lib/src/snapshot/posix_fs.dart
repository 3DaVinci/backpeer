import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:core/src/snapshot/fs_entry.dart';
import 'package:ffi/ffi.dart';

/// [FileSystemReader] на libc через FFI для Linux и macOS. `dart:io` здесь не
/// годится: имена не в UTF-8 он декодирует с потерями (такой файл потом не
/// открыть), а `FileStat` не даёт uid, gid, inode и наносекунд.
///
/// Раскладки `struct stat` и `struct dirent` различаются: Linux x86_64,
/// Linux с общей раскладкой (aarch64) и macOS (64-битный inode).
final class PosixFileSystem implements FileSystemReader {
  factory() {
    final layout = switch (Abi.current()) {
      Abi.linuxX64 => _Layout.linuxX64,
      Abi.linuxArm64 => _Layout.linuxGeneric,
      Abi.macosArm64 || Abi.macosX64 => _Layout.macos,
      final abi => throw UnsupportedError('PosixFileSystem: $abi'),
    };
    return PosixFileSystem._(_Libc(layout), layout);
  }

  new _(this._libc, this._layout);

  final _Libc _libc;
  final _Layout _layout;

  @override
  int get separator => 0x2F;

  @override
  List<Uint8List> list(Uint8List directory) {
    final path = _cString(directory);
    try {
      final dir = _libc.opendir(path);
      if (dir == nullptr) throw _error('opendir', directory);
      try {
        final names = <Uint8List>[];
        while (true) {
          final entry = _libc.readdir(dir);
          if (entry == nullptr) break;
          final name = _readCString(entry.cast<Uint8>() + _layout.direntName);
          if (_isDotOrDotDot(name)) continue;
          names.add(name);
        }
        return names;
      } finally {
        _libc.closedir(dir);
      }
    } finally {
      malloc.free(path);
    }
  }

  @override
  FsEntry stat(Uint8List path, Uint8List name) {
    final cPath = _cString(path);
    final buffer = calloc<Uint8>(_layout.statSize);
    try {
      if (_libc.lstat(cPath, buffer) != 0) throw _error('lstat', path);
      final view = buffer.asTypedList(_layout.statSize);
      final data = ByteData.sublistView(view);
      final l = _layout;
      final rawMode = l.modeIs16
          ? data.getUint16(l.mode, Endian.host)
          : data.getUint32(l.mode, Endian.host);
      return FsEntry(
        name: name,
        kind: switch (rawMode & 0xF000) {
          0x8000 => EntryKind.file,
          0x4000 => EntryKind.directory,
          0xA000 => EntryKind.symlink,
          _ => EntryKind.other,
        },
        size: data.getInt64(l.size, Endian.host),
        mtimeNs: _timespec(data, l.mtime),
        ctimeNs: _timespec(data, l.ctime),
        mode: rawMode & 0xFFF,
        uid: data.getUint32(l.uid, Endian.host),
        gid: data.getUint32(l.gid, Endian.host),
        inode: data.getUint64(l.inode, Endian.host),
        device: l.deviceIs32
            ? data.getInt32(l.device, Endian.host)
            : data.getUint64(l.device, Endian.host),
      );
    } finally {
      calloc.free(buffer);
      malloc.free(cPath);
    }
  }

  @override
  Uint8List readLink(Uint8List path) {
    final cPath = _cString(path);
    const capacity = 4096;
    final buffer = malloc<Uint8>(capacity);
    try {
      final length = _libc.readlink(cPath, buffer, capacity);
      if (length < 0) throw _error('readlink', path);
      return Uint8List.fromList(buffer.asTypedList(length));
    } finally {
      malloc
        ..free(buffer)
        ..free(cPath);
    }
  }

  FileSystemException _error(String call, Uint8List path) {
    final errno = _libc.errno();
    return FileSystemException(
      '$call: ${_errnoText(errno)}',
      utf8.decode(path, allowMalformed: true),
      OSError(_errnoText(errno), errno),
    );
  }
}

int _timespec(ByteData data, int offset) =>
    data.getInt64(offset, Endian.host) * 1000000000 +
    data.getInt64(offset + 8, Endian.host);

bool _isDotOrDotDot(Uint8List name) =>
    (name.length == 1 && name[0] == 0x2E) ||
    (name.length == 2 && name[0] == 0x2E && name[1] == 0x2E);

String _errnoText(int errno) => switch (errno) {
  1 => 'операция не разрешена',
  2 => 'нет такого файла или каталога',
  13 => 'доступ запрещён',
  20 => 'не каталог',
  40 || 62 => 'слишком много уровней символических ссылок',
  _ => 'ошибка $errno',
};

Pointer<Uint8> _cString(Uint8List bytes) {
  final p = malloc<Uint8>(bytes.length + 1);
  p.asTypedList(bytes.length + 1)
    ..setAll(0, bytes)
    ..[bytes.length] = 0;
  return p;
}

Uint8List _readCString(Pointer<Uint8> p) {
  var length = 0;
  while (p[length] != 0) {
    length++;
  }
  return Uint8List.fromList(p.asTypedList(length));
}

/// Смещения полей в `struct stat` и `struct dirent`.
enum _Layout {
  // glibc x86_64: dev, ino, nlink (u64), mode, uid, gid (u32), pad, rdev,
  // size, blksize, blocks (64), atim, mtim, ctim (timespec), 3 × reserved.
  linuxX64(
    statSize: 144,
    device: 0,
    deviceIs32: false,
    inode: 8,
    mode: 24,
    modeIs16: false,
    uid: 28,
    gid: 32,
    size: 48,
    mtime: 88,
    ctime: 104,
    direntName: 19,
    symbolSuffix: '',
    lxstatVersion: 1,
  ),

  // asm-generic (aarch64): dev, ino (u64), mode, nlink, uid, gid (u32),
  // rdev, pad (u64), size (i64), blksize, pad (i32), blocks, atim, mtim, ctim.
  linuxGeneric(
    statSize: 128,
    device: 0,
    deviceIs32: false,
    inode: 8,
    mode: 16,
    modeIs16: false,
    uid: 24,
    gid: 28,
    size: 48,
    mtime: 88,
    ctime: 104,
    direntName: 19,
    symbolSuffix: '',
    lxstatVersion: 0,
  ),

  // macOS, 64-битный inode: dev (i32), mode, nlink (u16), ino (u64), uid,
  // gid (u32), rdev (i32), atime, mtime, ctime, birthtime (timespec), size.
  // dirent: ino, seekoff (u64), reclen, namlen (u16), type (u8), name.
  macos(
    statSize: 144,
    device: 0,
    deviceIs32: true,
    inode: 8,
    mode: 4,
    modeIs16: true,
    uid: 16,
    gid: 20,
    size: 96,
    mtime: 48,
    ctime: 64,
    direntName: 21,
    symbolSuffix: r'$INODE64',
    lxstatVersion: -1,
  );

  new({
    required this.statSize,
    required this.device,
    required this.deviceIs32,
    required this.inode,
    required this.mode,
    required this.modeIs16,
    required this.uid,
    required this.gid,
    required this.size,
    required this.mtime,
    required this.ctime,
    required this.direntName,
    required this.symbolSuffix,
    required this.lxstatVersion,
  });

  final int statSize;
  final int device;
  final bool deviceIs32;
  final int inode;
  final int mode;
  final bool modeIs16;
  final int uid;
  final int gid;
  final int size;
  final int mtime;
  final int ctime;
  final int direntName;

  /// На macOS x86_64 функции с 64-битным inode имеют суффикс `$INODE64`.
  final String symbolSuffix;

  /// Версия для `__lxstat` в glibc до 2.33, где `lstat` не экспортируется.
  final int lxstatVersion;
}

typedef _OpendirC = Pointer<Void> Function(Pointer<Uint8>);
typedef _ReaddirC = Pointer<Void> Function(Pointer<Void>);
typedef _ClosedirC = Int32 Function(Pointer<Void>);
typedef _LstatC = Int32 Function(Pointer<Uint8>, Pointer<Uint8>);
typedef _LxstatC = Int32 Function(Int32, Pointer<Uint8>, Pointer<Uint8>);
typedef _ReadlinkC = IntPtr Function(Pointer<Uint8>, Pointer<Uint8>, IntPtr);
typedef _ErrnoC = Pointer<Int32> Function();

final class _Libc {
  factory(_Layout layout) {
    final lib = DynamicLibrary.process();
    final suffix = Abi.current() == Abi.macosX64 ? layout.symbolSuffix : '';
    final int Function(Pointer<Uint8>, Pointer<Uint8>) lstat;
    if (lib.providesSymbol('lstat$suffix')) {
      lstat = lib
          .lookupFunction<
            _LstatC,
            int Function(Pointer<Uint8>, Pointer<Uint8>)
          >('lstat$suffix');
    } else {
      final lxstat = lib
          .lookupFunction<
            _LxstatC,
            int Function(int, Pointer<Uint8>, Pointer<Uint8>)
          >('__lxstat');
      lstat = (path, buffer) => lxstat(layout.lxstatVersion, path, buffer);
    }
    final errnoPointer = lib.lookupFunction<_ErrnoC, Pointer<Int32> Function()>(
      Platform.isMacOS ? '__error' : '__errno_location',
    );
    return _Libc._(
      opendir: lib
          .lookupFunction<_OpendirC, Pointer<Void> Function(Pointer<Uint8>)>(
            'opendir$suffix',
          ),
      readdir: lib
          .lookupFunction<_ReaddirC, Pointer<Void> Function(Pointer<Void>)>(
            'readdir$suffix',
          ),
      closedir: lib.lookupFunction<_ClosedirC, int Function(Pointer<Void>)>(
        'closedir',
      ),
      lstat: lstat,
      readlink: lib
          .lookupFunction<
            _ReadlinkC,
            int Function(Pointer<Uint8>, Pointer<Uint8>, int)
          >('readlink'),
      errno: () => errnoPointer().value,
    );
  }

  new _({
    required this.opendir,
    required this.readdir,
    required this.closedir,
    required this.lstat,
    required this.readlink,
    required this.errno,
  });

  final Pointer<Void> Function(Pointer<Uint8>) opendir;
  final Pointer<Void> Function(Pointer<Void>) readdir;
  final int Function(Pointer<Void>) closedir;
  final int Function(Pointer<Uint8>, Pointer<Uint8>) lstat;
  final int Function(Pointer<Uint8>, Pointer<Uint8>, int) readlink;
  final int Function() errno;
}
