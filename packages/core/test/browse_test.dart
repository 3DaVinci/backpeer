// Просмотр снимка (задача 5.4.1): поиск по имени, версии файла между
// снимками и открытие каталогов большого дерева без чтения всего снимка.
//
// Большое дерево — синтетическая файловая система: 100 тыс. пустых файлов,
// 1 млн — FS_LARGE_TESTS=1.

import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:protocol/protocol.dart' as pb;
import 'package:test/test.dart';

/// `/v/d<i>/file-<j>.txt`: [directories] каталогов по [filesPerDirectory]
/// пустых файлов.
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
    return [for (var f = 0; f < filesPerDirectory; f++) _name('file-$f.txt')];
  }

  @override
  FsEntry stat(Uint8List path, Uint8List name) {
    final depth = path.where((b) => b == 0x2F).length;
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
      mode: depth <= 2 ? 493 : 420,
      uid: 1000,
      gid: 1000,
      inode: path.length,
    );
  }

  @override
  Uint8List readLink(Uint8List path) => throw UnimplementedError();

  static Uint8List _name(String s) => Uint8List.fromList(s.codeUnits);
}

void main() {
  late CryptoProvider crypto;
  late AccountKeys keys;
  setUpAll(() async {
    crypto = await SodiumCryptoProvider.load();
    keys = await AccountKeys.fromPhrase(
      RecoveryPhrase.fromEntropy(Uint8List(32)..[7] = 3),
      crypto,
    );
  });

  late Directory dir;
  late LocalIndex index;
  late LocalFolderStore nodes;
  late LocalObjectStore objects;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('fs-browse-');
    index = LocalIndex.open('${dir.path}/index.db');
    nodes = LocalFolderStore(
      Directory('${dir.path}/nodes'),
      crypto,
      nodeCount: 20,
    );
    objects = LocalObjectStore(Directory('${dir.path}/objects'));
  });
  tearDown(() {
    index.close();
    dir.deleteSync(recursive: true);
  });

  SnapshotBrowser browser() => SnapshotBrowser(
    crypto: crypto,
    keys: keys,
    index: index,
    fragments: nodes,
    objects: objects,
  );

  Future<pb.Snapshot> backup(List<String> paths, {FileSystemReader? fs}) async {
    final result = await runBackup(
      crypto: crypto,
      keys: keys,
      index: index,
      fragments: nodes,
      objects: objects,
      paths: paths,
      deviceId: Uint8List(32),
      fs: fs,
    );
    return result.snapshot;
  }

  Uint8List idOf(pb.Snapshot s) => Uint8List.fromList(s.snapshotId);

  group('поиск и версии', () {
    late Directory data;
    setUp(() {
      data = Directory('${dir.path}/data')..createSync();
      File('${data.path}/Отчёт 2026.odt').writeAsStringSync('первый');
      File('${data.path}/notes.txt').writeAsStringSync('n');
      File('${data.path}/sub/deep/ОТЧЁТ-итог.txt')
        ..createSync(recursive: true)
        ..writeAsStringSync('итог');
      File('${data.path}/sub/photo.jpg').writeAsStringSync('jpg');
    });

    test('часть имени без учёта регистра, шаблон, каталог', () async {
      final snap = await backup([data.path]);
      final b = browser();
      final found = await b.search(idOf(snap), 'отчёт');
      expect(
        [for (final m in found.matches) m.path.skip(1).join('/')],
        ['Отчёт 2026.odt', 'sub/deep/ОТЧЁТ-итог.txt'],
      );
      expect(found.matches.first.path.first, data.path);
      expect(found.truncated, isFalse);

      final glob = await b.search(idOf(snap), '*.txt');
      expect([
        for (final m in glob.matches) m.path.last,
      ], unorderedEquals(['notes.txt', 'ОТЧЁТ-итог.txt']));
      // Шаблон — имя целиком: «*.tx» не находит «.txt».
      expect((await b.search(idOf(snap), '*.tx')).matches, isEmpty);

      final under = await b.search(idOf(snap), 'o', under: [data.path, 'sub']);
      expect([for (final m in under.matches) m.path.last], ['photo.jpg']);

      final limited = await b.search(idOf(snap), 't', limit: 1);
      expect(limited.matches, hasLength(1));
      expect(limited.truncated, isTrue);
    });

    test('версии файла: изменился, не изменился, удалён, вернулся', () async {
      final file = File('${data.path}/notes.txt');
      final s1 = await backup([data.path]);
      final s2 = await backup([data.path]);
      file.writeAsStringSync('вторая версия');
      final s3 = await backup([data.path]);
      file.deleteSync();
      final s4 = await backup([data.path]);
      file.writeAsStringSync('вторая версия');
      final s5 = await backup([data.path]);

      final versions = await browser().versions(
        [s1, s2, s3, s4, s5],
        [data.path, 'notes.txt'],
      );
      final size = file.lengthSync();
      expect(
        [for (final v in versions) v.node?.size.toInt()],
        [1, 1, size, null, size],
      );
      expect(
        [for (final v in versions) v.changed],
        [
          true,
          false,
          true,
          false,
          // Вернулся с тем же содержимым, что был до удаления.
          false,
        ],
      );
      expect(
        [for (final v in versions) idOf(v.snapshot)],
        [
          for (final s in [s1, s2, s3, s4, s5]) idOf(s),
        ],
      );
    });

    test('нет каталога в старом снимке — версии нет, не ошибка', () async {
      final s1 = await backup([data.path]);
      File('${data.path}/new/inner.txt')
        ..createSync(recursive: true)
        ..writeAsStringSync('x');
      final s2 = await backup([data.path]);
      final versions = await browser().versions(
        [s1, s2],
        [data.path, 'new', 'inner.txt'],
      );
      expect([for (final v in versions) v.node == null], [true, false]);
      expect(versions.last.changed, isTrue);
    });
  });

  final large = Platform.environment['FS_LARGE_TESTS'] == '1';
  final directories = large ? 1000 : 100;
  test('снимок ${directories * 1000} файлов: каталог открывается без чтения '
      'всего дерева', () async {
    final snap = await backup(['/v'], fs: _SyntheticFs(directories, 1000));
    final b = browser();
    final watch = Stopwatch()..start();
    final roots = await b.list(idOf(snap), const []);
    final top = await b.list(idOf(snap), const ['/v']);
    final opened = await b.list(idOf(snap), const ['/v', 'd7']);
    final openMs = watch.elapsedMilliseconds;
    stdout.writeln(
      '${directories * 1000} файлов: корень и два каталога за $openMs мс',
    );
    expect(roots.single.type, pb.NodeType.NODE_TYPE_DIRECTORY);
    expect(top, hasLength(directories));
    expect(opened, hasLength(1000));
    // Ориентир «без зависания»: открытие не зависит от размера снимка.
    expect(openMs, lessThan(5000));

    watch.reset();
    final found = await b.search(idOf(snap), 'file-999.txt', limit: 5);
    stdout.writeln(
      'поиск: ${found.scanned} узлов за ${watch.elapsedMilliseconds} мс',
    );
    expect(found.matches, hasLength(5));
    expect(found.truncated, isTrue);
    expect(found.matches.first.path, ['/v', 'd0', 'file-999.txt']);
  }, timeout: const Timeout(Duration(minutes: 20)));
}
