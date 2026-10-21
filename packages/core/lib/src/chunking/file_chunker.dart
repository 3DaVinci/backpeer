import 'dart:io';
import 'dart:typed_data';

import 'package:core/src/chunking/fastcdc.dart';
import 'package:core/src/errors.dart';

/// Событие потоковой нарезки файла.
sealed class FileChunkEvent {
  const new();
}

/// Очередной чанк. [data] — собственная копия, буфер чтения не держит.
final class ChunkRead extends FileChunkEvent {
  const new(this.offset, this.data);

  final int offset;
  final Uint8List data;
}

/// Файл изменился во время чтения; чанки текущей попытки нужно
/// отбросить, чтение начинается заново.
final class ReadRestarted extends FileChunkEvent {
  const new(this.attempt);

  /// Номер следующей попытки, с 2.
  final int attempt;
}

/// Нарезает файл на чанки FastCDC потоком, не загружая его целиком.
///
/// Память — окно [bufferSize] (не меньше [FastCdc.maxSize]) и чанки, ещё
/// не обработанные получателем: поток ставится на паузу вместе с ним.
/// Граница режется, только когда в окне не меньше `maxSize` байт или весь
/// остаток файла, поэтому результат не зависит от размера окна.
///
/// Размер и время изменения файла сверяются до и после чтения. При
/// расхождении — [ReadRestarted] и новая попытка; после [maxAttempts]
/// неудачных — [SourceChangedException].
///
/// [stamp] снимает размер и время файла; по умолчанию — `File.statSync`.
/// Для имён не в UTF-8 `dart:io` его не найдёт, поэтому обход передаёт
/// свой `lstat`.
Stream<FileChunkEvent> chunkFile(
  File file,
  FastCdc cdc, {
  int bufferSize = 16 * 1024 * 1024,
  int maxAttempts = 3,
  FileSnapshot Function()? stamp,
}) {
  if (bufferSize < FastCdc.maxSize) {
    throw ArgumentError.value(bufferSize, 'bufferSize', 'меньше maxSize');
  }
  RangeError.checkValueInInterval(maxAttempts, 1, 100, 'maxAttempts');
  return _chunkFile(
    file,
    cdc,
    bufferSize,
    maxAttempts,
    stamp ?? () => _snapshot(file),
  );
}

Stream<FileChunkEvent> _chunkFile(
  File file,
  FastCdc cdc,
  int bufferSize,
  int maxAttempts,
  FileSnapshot Function() stamp,
) async* {
  final buffer = Uint8List(bufferSize);
  for (var attempt = 1; ; attempt++) {
    final before = stamp();
    final raf = await file.open();
    var consistent = true;
    try {
      var offset = 0; // смещение начала окна в файле
      var start = 0; // начало необработанных данных в буфере
      var end = 0; // конец данных в буфере
      var eof = false;
      while (true) {
        if (!eof && end - start < FastCdc.maxSize) {
          if (start > 0) {
            buffer.setRange(0, end - start, buffer, start);
            end -= start;
            start = 0;
          }
          while (end < buffer.length) {
            final read = await raf.readInto(buffer, end);
            if (read == 0) {
              eof = true;
              break;
            }
            end += read;
          }
        }
        if (start == end) break;
        final size = cdc.cut(buffer, start, end);
        yield ChunkRead(
          offset,
          Uint8List.fromList(buffer.sublist(start, start + size)),
        );
        start += size;
        offset += size;
      }
      consistent = offset == before.size;
    } finally {
      await raf.close();
    }
    if (consistent && stamp() == before) return;
    if (attempt >= maxAttempts) {
      throw SourceChangedException(path: file.path, attempts: attempt);
    }
    yield ReadRestarted(attempt + 1);
  }
}

/// Размер и время файла для обнаружения изменений во время чтения.
typedef FileSnapshot = ({int size, int mtimeNs, int ctimeNs});

FileSnapshot _snapshot(File file) {
  final stat = file.statSync();
  return (
    size: stat.size,
    mtimeNs: stat.modified.microsecondsSinceEpoch * 1000,
    ctimeNs: stat.changed.microsecondsSinceEpoch * 1000,
  );
}
