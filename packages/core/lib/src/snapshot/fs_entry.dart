import 'dart:typed_data';

/// Вид элемента каталога.
enum EntryKind {
  file,
  directory,
  symlink,

  /// Сокет, устройство, FIFO и прочие особые файлы: не сохраняются
  /// (manifest.md, раздел 3).
  other,
}

/// Элемент каталога с метаданными, без разыменования ссылок (`lstat`).
final class FsEntry {
  const new({
    required this.name,
    required this.kind,
    required this.size,
    required this.mtimeNs,
    required this.ctimeNs,
    this.mode = 0,
    this.uid = 0,
    this.gid = 0,
    this.inode = 0,
    this.device = 0,
    this.windowsAttributes = 0,
  });

  /// Имя как байты ОС: на Unix бывает не в UTF-8; на Windows — UTF-8 от
  /// имени в UTF-16.
  final Uint8List name;
  final EntryKind kind;
  final int size;
  final int mtimeNs;
  final int ctimeNs;

  /// Права и особые биты (`mode & 0o7777`); на Windows — 0.
  final int mode;
  final int uid;
  final int gid;

  /// Для кеша файлов и обнаружения жёстких ссылок; на Windows — 0.
  final int inode;
  final int device;

  /// Атрибуты файла Windows; на Unix — 0.
  final int windowsAttributes;
}

/// Доступ к файловой системе для обхода: имена и пути — байты ОС.
abstract interface class FileSystemReader {
  /// Имена в каталоге без `.` и `..`, в порядке ОС. Ошибка доступа —
  /// `FileSystemException`.
  List<Uint8List> list(Uint8List directory);

  /// Метаданные без разыменования ссылки. Ошибка — `FileSystemException`.
  FsEntry stat(Uint8List path, Uint8List name);

  /// Цель символической ссылки как байты ОС.
  Uint8List readLink(Uint8List path);

  /// Разделитель путей ОС.
  int get separator;
}
