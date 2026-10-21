import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:core/src/snapshot/fs_entry.dart';

/// [FileSystemReader] на `dart:io` — для Windows, где имена приходят в
/// UTF-16 и декодируются без потерь. Имя — UTF-8 от имени в UTF-16.
/// uid, gid, inode и права не заполняются: их в `dart:io` нет.
/// Атрибуты Windows (скрытый, системный, только чтение) пока не читаются —
/// для них нужен `GetFileAttributesW` через FFI.
final class DartIoFileSystem implements FileSystemReader {
  const new();

  @override
  int get separator => Platform.isWindows ? 0x5C : 0x2F;

  @override
  List<Uint8List> list(Uint8List directory) {
    final dir = Directory(_string(directory));
    final prefix = dir.path.length + 1;
    return [
      for (final e in dir.listSync(followLinks: false))
        utf8.encode(e.path.substring(prefix)),
    ];
  }

  @override
  FsEntry stat(Uint8List path, Uint8List name) {
    final p = _string(path);
    final type = FileSystemEntity.typeSync(p, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      throw FileSystemException('Нет такого файла или каталога', p);
    }
    final kind = switch (type) {
      FileSystemEntityType.file => EntryKind.file,
      FileSystemEntityType.directory => EntryKind.directory,
      FileSystemEntityType.link => EntryKind.symlink,
      _ => EntryKind.other,
    };
    if (kind == EntryKind.symlink) {
      return FsEntry(name: name, kind: kind, size: 0, mtimeNs: 0, ctimeNs: 0);
    }
    final stat = FileStat.statSync(p);
    return FsEntry(
      name: name,
      kind: kind,
      size: kind == EntryKind.file ? stat.size : 0,
      mtimeNs: stat.modified.microsecondsSinceEpoch * 1000,
      ctimeNs: stat.changed.microsecondsSinceEpoch * 1000,
      mode: Platform.isWindows ? 0 : stat.mode & 0xFFF,
    );
  }

  @override
  Uint8List readLink(Uint8List path) =>
      utf8.encode(Link(_string(path)).targetSync());

  static String _string(Uint8List bytes) => utf8.decode(bytes);
}
