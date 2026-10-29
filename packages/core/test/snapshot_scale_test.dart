// Снимок на много файлов без создания их на диске: синтетическая файловая
// система за интерфейсом FileSystemReader, все файлы пустые (их содержимое
// не читается). Проверяется память на построение деревьев.
//
// По умолчанию — 100 тыс. файлов; 1 млн — FS_LARGE_TESTS=1.
//
// Тег serial: тест меряет RSS всего процесса, а dart test запускает
// тестовые файлы параллельно в одном процессе — рядом идущие файлы
// добавили бы свою память. Такие тесты идут отдельным прогоном с -j 1
// (скрипт melos coverage-serial).
@Tags(['serial'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:test/test.dart';

final class _SyntheticFs implements FileSystemReader {
  new(this.directories, this.filesPerDirectory);

  final int directories;
  final int filesPerDirectory;

  @override
  int get separator => 0x2F;

  @override
  List<Uint8List> list(Uint8List directory) {
    final depth = directory.where((b) => b == 0x2F).length;
    if (depth == 1) {
      return [for (var d = 0; d < directories; d++) _name('d$d')];
    }
    return [
      for (var f = 0; f < filesPerDirectory; f++)
        _name('file-with-a-reasonably-long-name-$f.txt'),
    ];
  }

  @override
  FsEntry stat(Uint8List path, Uint8List name) {
    final depth = path.where((b) => b == 0x2F).length;
    // Время зависит от пути, чтобы деревья каталогов различались и не
    // схлопывались дедупликацией.
    var hash = 0;
    for (final b in path) {
      hash = (hash * 31 + b) & 0xFFFFFFFF;
    }
    return FsEntry(
      name: name,
      kind: depth <= 2 ? EntryKind.directory : EntryKind.file,
      size: 0,
      mtimeNs: 1792000000000000000 + hash,
      ctimeNs: 1792000000000000000,
      mode: 420,
      uid: 1000,
      gid: 1000,
      inode: path.length,
    );
  }

  @override
  Uint8List readLink(Uint8List path) => throw UnimplementedError();

  static Uint8List _name(String s) => Uint8List.fromList(s.codeUnits);
}

/// Хранит только идентификаторы: память — на деревья, а не на чанки.
final class _CountingSink implements ChunkSink {
  final Set<ChunkId> ids = {};
  int bytes = 0;

  @override
  bool contains(ChunkId id) => ids.contains(id);

  @override
  Future<bool> add(ChunkId id, ChunkType type, Uint8List data) async {
    bytes += data.length;
    return ids.add(id);
  }
}

void main() {
  final large = Platform.environment['FS_LARGE_TESTS'] == '1';
  final directories = large ? 1000 : 100;

  test(
    'снимок ${directories * 1000} файлов: память на деревья ограничена',
    () async {
      final crypto = await SodiumCryptoProvider.load();
      final sink = _CountingSink();
      final index = LocalIndex.inMemory();
      final builder = TreeBuilder(
        walker: TreeWalker(fs: _SyntheticFs(directories, 1000)),
        cdc: FastCdc(GearTable.derive(crypto, SecretBytes(Uint8List(32)))),
        hasher: ChunkIdHasher(crypto, SecretBytes(Uint8List(32))),
        sink: sink,
        index: index,
      );
      final baseline = ProcessInfo.currentRss;
      final watch = Stopwatch()..start();
      final root = await builder.buildRoot(['/v']);
      final growth = ProcessInfo.maxRss - baseline;
      stdout.writeln(
        '${builder.stats.files} файлов, ${sink.ids.length} чанков деревьев '
        '(${sink.bytes >> 20} МиБ), ${watch.elapsed.inSeconds} с, '
        'рост пиковой RSS ${growth >> 20} МиБ',
      );
      expect(root, isNotEmpty);
      expect(builder.stats.files, directories * 1000);
      expect(builder.stats.filesRead, 0);
      expect(sink.ids.length, greaterThan(directories));
      // Деревья держатся в памяти по одному каталогу на уровень, поэтому
      // рост не зависит от числа каталогов.
      expect(growth, lessThan(256 * 1024 * 1024));
      index.close();
    },
    timeout: const Timeout(Duration(minutes: 20)),
  );
}
