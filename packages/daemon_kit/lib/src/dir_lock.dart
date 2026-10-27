import 'dart:io';

/// Исключительная блокировка папки одним процессом: файл [file] с
/// `lockSync` (на Windows он же не даёт удалить файл), внутри — pid для
/// диагностики. Блокировку снимает ОС и при `kill -9`.
final class DirLock {
  new _(this.file, this._raf);

  /// Захватывает [file]; занят другим процессом — [FileSystemException]
  /// с текстом [busy] и путём [owner] (по умолчанию — папка файла).
  factory acquire(File file, {required String busy, String? owner}) {
    file.parent.createSync(recursive: true);
    final raf = file.openSync(mode: FileMode.append);
    try {
      raf.lockSync();
    } on FileSystemException {
      raf.closeSync();
      throw FileSystemException(busy, owner ?? file.parent.path);
    }
    raf
      ..truncateSync(0)
      ..setPositionSync(0)
      ..writeStringSync('$pid\n')
      ..flushSync();
    return DirLock._(file, raf);
  }

  final File file;
  final RandomAccessFile _raf;

  void release() {
    try {
      _raf
        ..truncateSync(0)
        ..unlockSync()
        ..closeSync();
    } on FileSystemException {
      // Уже закрыт.
    }
  }
}
