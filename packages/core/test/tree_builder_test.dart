import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:protocol/protocol.dart' as pb;
import 'package:test/test.dart';
import 'package:test_vectors/test_vectors.dart';

void main() {
  late CryptoProvider crypto;
  late FastCdc cdc;
  late ChunkIdHasher hasher;
  setUpAll(() async {
    crypto = await SodiumCryptoProvider.load();
    cdc = FastCdc(GearTable.derive(crypto, SecretBytes(Uint8List(32))));
    hasher = ChunkIdHasher(crypto, SecretBytes(Uint8List(32)..[0] = 1));
  });

  late Directory dir;
  late MemoryChunkSink sink;
  late LocalIndex index;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('fs-tree-');
    sink = MemoryChunkSink();
    index = LocalIndex.inMemory();
  });
  tearDown(() {
    index.close();
    dir.deleteSync(recursive: true);
  });

  TreeBuilder builder({ExcludeRules excludes = ExcludeRules.none}) =>
      TreeBuilder(
        walker: TreeWalker(excludes: excludes),
        cdc: cdc,
        hasher: hasher,
        sink: sink,
        index: index,
      );

  Uint8List join(List<ChunkId> ids) {
    final out = BytesBuilder(copy: false);
    for (final id in ids) {
      out.add(sink.chunks[id]!.$2);
    }
    return out.toBytes();
  }

  pb.Tree tree(List<ChunkId> ids) {
    for (final id in ids) {
      expect(sink.chunks[id]!.$1, ChunkType.tree);
    }
    final bytes = join(ids);
    final parsed = pb.Tree.fromBuffer(bytes);
    // Каноническая сериализация: разбор и повторная запись дают те же байты.
    expect(parsed.writeToBuffer(), bytes);
    return parsed;
  }

  List<ChunkId> ids(List<List<int>> raw) => raw.map(ChunkId.new).toList();

  void populate() {
    File('${dir.path}/b.txt').writeAsStringSync('b' * 10);
    File('${dir.path}/a.bin').writeAsBytesSync(splitmix64Bytes(1, 3 << 20));
    File('${dir.path}/sub/deep/z.txt').createSync(recursive: true);
    File('${dir.path}/sub/y.txt').writeAsStringSync('yy');
    Link('${dir.path}/link').createSync('sub/y.txt');
  }

  test('структура дерева и содержимое файлов', () async {
    populate();
    final b = builder();
    final root = tree(await b.buildRoot([dir.path]));
    final top = root.nodes.single;
    expect(utf8.decode(top.name), dir.path);
    expect(top.type, pb.NodeType.NODE_TYPE_DIRECTORY);

    final level1 = tree(ids(top.subtree));
    expect(level1.nodes.map((n) => utf8.decode(n.name)), [
      'a.bin',
      'b.txt',
      'link',
      'sub',
    ]);
    final a = level1.nodes[0];
    expect(a.type, pb.NodeType.NODE_TYPE_FILE);
    expect(a.size.toInt(), 3 << 20);
    expect(a.content.length, greaterThan(1));
    expect(join(ids(a.content)), File('${dir.path}/a.bin').readAsBytesSync());
    expect(utf8.decode(level1.nodes[2].symlinkTarget), 'sub/y.txt');
    expect(level1.nodes[2].type, pb.NodeType.NODE_TYPE_SYMLINK);

    final sub = tree(ids(level1.nodes[3].subtree));
    final deep = tree(ids(sub.nodes.first.subtree));
    final empty = deep.nodes.single;
    expect(utf8.decode(empty.name), 'z.txt');
    expect(empty.content, isEmpty, reason: 'пустой файл — пустой content');
    expect(empty.mtimeNs.toInt(), isNot(0));
    if (!Platform.isWindows) expect(empty.mode, isNot(0));

    expect(b.stats.files, 4);
    expect(b.stats.directories, 3);
    expect(b.stats.filesRead, 4);
    expect(b.stats.bytes, (3 << 20) + 12);
  });

  test(
    'второй снимок неизменённой папки: без чтения и без новых чанков',
    () async {
      populate();
      final first = await builder().buildRoot([dir.path]);
      final second = builder();
      final again = await second.buildRoot([dir.path]);
      expect(again, first);
      expect(second.stats.filesRead, 0);
      expect(second.stats.newChunks, 0);
      expect(second.stats.files, 4);
    },
  );

  test(
    'правка одного файла: новые только его чанки и деревья до корня',
    () async {
      populate();
      await builder().buildRoot([dir.path]);
      final before = sink.chunks.length;
      // Другой размер — штамп точно изменится независимо от точности mtime.
      File('${dir.path}/sub/y.txt').writeAsStringSync('changed');
      final b = builder();
      await b.buildRoot([dir.path]);
      expect(b.stats.filesRead, 1);
      // 1 чанк файла + деревья sub, корня бэкапа и корня снимка.
      expect(b.stats.newChunks, 4);
      expect(sink.chunks.length, before + 4);
    },
  );

  test('исключения и несколько корней', () async {
    populate();
    final other = Directory.systemTemp.createTempSync('fs-tree2-');
    addTearDown(() => other.deleteSync(recursive: true));
    File('${other.path}/o.txt').writeAsStringSync('o');
    final b = builder(excludes: ExcludeRules(['*.bin', 'deep/']));
    final root = tree(await b.buildRoot([other.path, dir.path]));
    final names = root.nodes.map((n) => utf8.decode(n.name)).toList();
    expect(names, [dir.path, other.path]..sort());
    final mine = root.nodes.firstWhere((n) => utf8.decode(n.name) == dir.path);
    final level1 = tree(ids(mine.subtree));
    expect(level1.nodes.map((n) => utf8.decode(n.name)), [
      'b.txt',
      'link',
      'sub',
    ]);
    expect(b.walker.report.excluded, 2);
  });

  test('недоступный корень попадает в отчёт', () async {
    final b = builder();
    final root = tree(await b.buildRoot(['${dir.path}/missing']));
    expect(root.nodes, isEmpty);
    expect(b.stats.skipped, 1);
  });

  test('имя не в UTF-8 сохраняется байтами', () async {
    final name = Uint8List.fromList([0xFF, 0x41]);
    final path = TreeWalker().join(TreeWalker.rootPath(dir.path), name);
    File.fromRawPath(path).writeAsStringSync('raw');
    final root = tree(await builder().buildRoot([dir.path]));
    final node = tree(ids(root.nodes.single.subtree)).nodes.single;
    expect(node.name, name);
    expect(utf8.decode(join(ids(node.content))), 'raw');
  }, testOn: 'linux');

  test('большой каталог занимает несколько чанков дерева', () async {
    final big = Directory('${dir.path}/big')..createSync();
    final long = 'x' * 180;
    for (var i = 0; i < 8000; i++) {
      File('${big.path}/$long-$i').createSync();
    }
    final b = builder();
    final root = tree(await b.buildRoot([dir.path]));
    final top = tree(ids(root.nodes.single.subtree));
    final bigNode = top.nodes.single;
    expect(bigNode.subtree.length, greaterThan(1));
    final listing = tree(ids(bigNode.subtree));
    expect(listing.nodes, hasLength(8000));
    final names = listing.nodes.map((n) => n.name).toList();
    for (var i = 1; i < names.length; i++) {
      expect(
        compareBytes(
          Uint8List.fromList(names[i - 1]),
          Uint8List.fromList(names[i]),
        ),
        lessThan(0),
      );
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
