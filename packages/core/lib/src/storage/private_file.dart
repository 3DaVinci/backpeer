import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// Атомарная запись файла, доступного только владельцу: временный файл
/// рядом, права до записи содержимого, затем переименование поверх.
///
/// Права: 0600 на Linux и macOS (`chmod` из libc); на Windows —
/// наследование прав отключается и доступ остаётся только текущему
/// пользователю (`icacls`).
void writePrivateFileAtomic(File file, Uint8List bytes) {
  file.parent.createSync(recursive: true);
  final temp = File('${file.path}.tmp-$pid');
  if (temp.existsSync()) temp.deleteSync();
  temp.createSync(exclusive: true);
  try {
    restrictToOwner(temp.path);
    final raf = temp.openSync(mode: FileMode.writeOnly);
    try {
      raf
        ..writeFromSync(bytes)
        ..flushSync();
    } finally {
      raf.closeSync();
    }
    temp.renameSync(file.path);
  } on Object {
    if (temp.existsSync()) temp.deleteSync();
    rethrow;
  }
}

/// Оставляет доступ к файлу только владельцу.
void restrictToOwner(String path) {
  if (Platform.isWindows) {
    final user = Platform.environment['USERNAME'];
    if (user == null || user.isEmpty) {
      throw const FileSystemException('Не задан USERNAME для icacls');
    }
    final result = Process.runSync('icacls', [
      path,
      '/inheritance:r',
      '/grant:r',
      '$user:F',
    ]);
    if (result.exitCode != 0) {
      throw FileSystemException(
        'icacls: ${result.stderr}${result.stdout}'.trim(),
        path,
      );
    }
    return;
  }
  setUnixFileMode(path, _ownerReadWrite);
}

/// Права файла [mode] через `chmod` из libc (Linux и macOS). В Dart нет
/// восьмеричных литералов: 0660 — `432`, 0600 — `384`.
void setUnixFileMode(String path, int mode) {
  if (Platform.isWindows) {
    throw UnsupportedError('chmod недоступен на Windows');
  }
  final native = path.toNativeUtf8();
  try {
    final rc = _chmod(native, mode);
    if (rc != 0) {
      throw FileSystemException(
        'chmod ${mode.toRadixString(8).padLeft(4, '0')} не удался',
        path,
      );
    }
  } finally {
    malloc.free(native);
  }
}

const _ownerReadWrite = 384; // 0600

typedef _ChmodDart = int Function(Pointer<Utf8> path, int mode);

// mode_t: 32 бита на Linux, 16 бит на macOS.
final _ChmodDart _chmod = Platform.isMacOS
    ? DynamicLibrary.process()
          .lookupFunction<Int32 Function(Pointer<Utf8>, Uint16), _ChmodDart>(
            'chmod',
          )
    : DynamicLibrary.process()
          .lookupFunction<Int32 Function(Pointer<Utf8>, Uint32), _ChmodDart>(
            'chmod',
          );
