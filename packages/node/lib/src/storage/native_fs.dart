import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Сбрасывает на диск запись каталога [path] (`fsync` дескриптора
/// каталога): после переименования файла в каталоге новое имя переживает
/// обрыв питания. На Windows не нужен и не делается: NTFS журналирует
/// метаданные, а открыть каталог для `FlushFileBuffers` без Win32-флагов
/// нельзя.
void fsyncDirectory(String path) {
  if (Platform.isWindows) return;
  final native = path.toNativeUtf8();
  try {
    final fd = _posix.open(native, _oRdonly);
    if (fd < 0) {
      throw FileSystemException('open каталога для fsync не удался', path);
    }
    try {
      if (_posix.fsync(fd) != 0) {
        throw FileSystemException('fsync каталога не удался', path);
      }
    } finally {
      _posix.close(fd);
    }
  } finally {
    malloc.free(native);
  }
}

/// Сколько байт на диске с [path] доступно этому процессу (без резерва
/// суперпользователя) или `null`, если платформа не поддержана: Linux и
/// macOS 64-бит, Windows.
int? diskAvailableBytes(String path) {
  if (Platform.isWindows) return _windowsAvailable(path);
  if (sizeOf<IntPtr>() != 8) return null;
  final native = path.toNativeUtf8();
  final buffer = calloc<Uint8>(_statBufferSize);
  try {
    if (Platform.isMacOS) {
      // struct statfs (64-битный inode): f_bsize u32 @0, f_iosize @4,
      // f_blocks @8, f_bfree @16, f_bavail @24 — u64.
      if (_posix.statfs!(native, buffer) != 0) {
        throw FileSystemException('statfs не удался', path);
      }
      final bytes = buffer.cast<Uint32>().value;
      return (buffer + 24).cast<Uint64>().value * bytes;
    }
    // struct statvfs (glibc и musl, 64 бита): f_bsize @0, f_frsize @8,
    // f_blocks @16, f_bfree @24, f_bavail @32.
    if (_posix.statvfs!(native, buffer) != 0) {
      throw FileSystemException('statvfs не удался', path);
    }
    final fragment = (buffer + 8).cast<Uint64>().value;
    return (buffer + 32).cast<Uint64>().value * fragment;
  } finally {
    calloc.free(buffer);
    malloc.free(native);
  }
}

int _windowsAvailable(String path) {
  final native = path.toNativeUtf16();
  final available = calloc<Uint64>();
  try {
    if (_getDiskFreeSpaceEx(native, available, nullptr, nullptr) == 0) {
      throw FileSystemException('GetDiskFreeSpaceExW не удался', path);
    }
    return available.value;
  } finally {
    calloc.free(available);
    malloc.free(native);
  }
}

/// С запасом: `struct statfs` на macOS — около 2,2 КиБ, `statvfs` — 112 байт.
const _statBufferSize = 4096;
const _oRdonly = 0;

typedef _PathBufferDart = int Function(Pointer<Utf8>, Pointer<Uint8>);

final class _Posix {
  new(DynamicLibrary lib)
    : open = lib
          .lookupFunction<
            Int32 Function(Pointer<Utf8>, Int32),
            int Function(Pointer<Utf8>, int)
          >('open'),
      fsync = lib.lookupFunction<Int32 Function(Int32), int Function(int)>(
        'fsync',
      ),
      close = lib.lookupFunction<Int32 Function(Int32), int Function(int)>(
        'close',
      ),
      statvfs = Platform.isLinux ? _lookupStat(lib, ['statvfs']) : null,
      // На macOS x86_64 нужный вариант — `statfs$INODE64`, на arm64 он
      // единственный и называется `statfs`.
      statfs = Platform.isMacOS
          ? _lookupStat(lib, [r'statfs$INODE64', 'statfs'])
          : null;

  final int Function(Pointer<Utf8>, int) open;
  final int Function(int) fsync;
  final int Function(int) close;
  final _PathBufferDart? statvfs;
  final _PathBufferDart? statfs;

  static _PathBufferDart _lookupStat(DynamicLibrary lib, List<String> names) {
    for (final name in names) {
      if (lib.providesSymbol(name)) {
        return lib.lookupFunction<
          Int32 Function(Pointer<Utf8>, Pointer<Uint8>),
          _PathBufferDart
        >(name);
      }
    }
    throw UnsupportedError('нет функции ${names.join(' или ')}');
  }
}

final _Posix _posix = _Posix(DynamicLibrary.process());

final int Function(
  Pointer<Utf16>,
  Pointer<Uint64>,
  Pointer<Uint64>,
  Pointer<Uint64>,
)
_getDiskFreeSpaceEx = DynamicLibrary.open('kernel32.dll')
    .lookupFunction<
      Int32 Function(
        Pointer<Utf16>,
        Pointer<Uint64>,
        Pointer<Uint64>,
        Pointer<Uint64>,
      ),
      int Function(
        Pointer<Utf16>,
        Pointer<Uint64>,
        Pointer<Uint64>,
        Pointer<Uint64>,
      )
    >('GetDiskFreeSpaceExW');
