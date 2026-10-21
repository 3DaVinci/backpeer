import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:core/src/snapshot/dart_io_fs.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('fs-walk-'));
  tearDown(() {
    if (!Platform.isWindows) {
      Process.runSync('chmod', ['-R', 'u+rwx', dir.path]);
    }
    dir.deleteSync(recursive: true);
  });

  group('ExcludeRules совпадает с git check-ignore', () {
    const patterns = [
      '# комментарий',
      '*.tmp',
      '!keep.tmp',
      'build/',
      '/root-only.txt',
      'docs/*.md',
      '!docs/README.md',
      '**/cache/**',
      'logs/**/debug.log',
      'a?c',
      '[0-9]*.bak',
      r'\#hash',
      'trailing-space   ',
      'node_modules',
    ];
    const paths = [
      ('x.tmp', false),
      ('sub/y.tmp', false),
      ('keep.tmp', false),
      ('sub/keep.tmp', false),
      ('build', true),
      ('build', false),
      ('sub/build', true),
      ('build/out.o', false),
      ('root-only.txt', false),
      ('sub/root-only.txt', false),
      ('docs/a.md', false),
      ('docs/README.md', false),
      ('docs/sub/a.md', false),
      ('cache/x', false),
      ('a/cache/x', false),
      ('cache', true),
      ('logs/debug.log', false),
      ('logs/a/b/debug.log', false),
      ('other/logs/debug.log', false),
      ('abc', false),
      ('abbc', false),
      ('sub/axc', false),
      ('1.bak', false),
      ('x1.bak', false),
      ('#hash', false),
      ('trailing-space', false),
      ('node_modules', true),
      ('src/node_modules/pkg/index.js', false),
      ('plain.txt', false),
    ];

    test('все пары шаблон × путь', () {
      final git = Process.runSync('git', ['--version']);
      if (git.exitCode != 0) markTestSkipped('нет git');
      final repo = Directory('${dir.path}/repo')..createSync();
      Process.runSync('git', ['init', '-q'], workingDirectory: repo.path);
      File('${repo.path}/.gitignore').writeAsStringSync(patterns.join('\n'));
      for (final (path, isDir) in paths) {
        if (isDir) {
          Directory('${repo.path}/$path').createSync(recursive: true);
        } else if (!FileSystemEntity.isDirectorySync('${repo.path}/$path')) {
          File('${repo.path}/$path').createSync(recursive: true);
        }
      }
      final rules = ExcludeRules(patterns);
      final mismatches = <String>[];
      for (final (path, isDir) in paths) {
        if (!isDir && FileSystemEntity.isDirectorySync('${repo.path}/$path')) {
          continue; // путь занят каталогом из другой пары
        }
        final result = Process.runSync('git', [
          'check-ignore',
          '-q',
          '--no-index',
          if (isDir) '$path/' else path,
        ], workingDirectory: repo.path);
        final gitIgnored = result.exitCode == 0;
        if (_excludedWithParents(rules, path, isDir) != gitIgnored) {
          mismatches.add('$path${isDir ? '/' : ''}: git $gitIgnored');
        }
      }
      expect(mismatches, isEmpty);
    });

    test('регистр', () {
      expect(
        ExcludeRules(['*.TMP']).excludes('a.tmp', isDirectory: false),
        isFalse,
      );
      expect(
        ExcludeRules([
          '*.TMP',
        ], caseSensitive: false).excludes('a.tmp', isDirectory: false),
        isTrue,
      );
    });
  });

  group('TreeWalker', () {
    late Uint8List root;
    setUp(() {
      root = TreeWalker.rootPath(dir.path);
      File('${dir.path}/b.txt').writeAsStringSync('b');
      File('${dir.path}/a.txt').writeAsStringSync('aa');
      File('${dir.path}/sub/deep/z.txt').createSync(recursive: true);
      File('${dir.path}/sub/x.tmp').writeAsStringSync('');
      Directory('${dir.path}/empty').createSync();
      Link('${dir.path}/link-to-sub').createSync('sub');
      Link('${dir.path}/dangling').createSync('missing');
    });

    test('порядок, виды, ссылки не разыменовываются, исключения', () {
      final walker = TreeWalker(excludes: ExcludeRules(['*.tmp']));
      final items = walker.walk(root).toList();
      expect(items.map((i) => i.relative), [
        'a.txt',
        'b.txt',
        'dangling',
        'empty',
        'link-to-sub',
        'sub',
        'sub/deep',
        'sub/deep/z.txt',
      ]);
      final byName = {for (final i in items) i.relative: i.entry};
      expect(byName['a.txt']!.kind, EntryKind.file);
      expect(byName['a.txt']!.size, 2);
      expect(byName['sub']!.kind, EntryKind.directory);
      expect(byName['link-to-sub']!.kind, EntryKind.symlink);
      expect(byName['dangling']!.kind, EntryKind.symlink);
      expect(
        utf8.decode(
          walker.readLink(walker.join(root, utf8.encode('link-to-sub')))!,
        ),
        'sub',
      );
      expect(walker.report.excluded, 1);
      expect(walker.report.isClean, isTrue);
    });

    test('метаданные Unix: права, uid, наносекунды', () {
      final file = File('${dir.path}/a.txt');
      Process.runSync('chmod', ['640', file.path]);
      final entry = TreeWalker()
          .list(root, '')
          .firstWhere((e) => utf8.decode(e.name) == 'a.txt');
      expect(entry.mode, 416); // 0640
      final id = Process.runSync('id', ['-u']).stdout.toString().trim();
      expect(entry.uid, int.parse(id));
      expect(entry.inode, isNot(0));
      expect(
        entry.mtimeNs ~/ 1000,
        file.statSync().modified.microsecondsSinceEpoch,
      );
    }, testOn: '!windows');

    test('имя не в UTF-8 сохраняется байтами и читается', () {
      final name = Uint8List.fromList([0xFF, 0xFE, 0x2D, 0x62]);
      final path = TreeWalker().join(root, name);
      File.fromRawPath(path).writeAsStringSync('raw');
      final walker = TreeWalker();
      final entry = walker.list(root, '').firstWhere((e) => e.name[0] == 0xFF);
      expect(entry.name, name);
      expect(entry.kind, EntryKind.file);
      expect(
        File.fromRawPath(walker.join(root, entry.name)).readAsStringSync(),
        'raw',
      );
    }, testOn: 'linux');

    test('сокет и FIFO пропускаются с записью в отчёт', () async {
      Process.runSync('mkfifo', ['${dir.path}/fifo']);
      final server = await ServerSocket.bind(
        InternetAddress('${dir.path}/sock', type: InternetAddressType.unix),
        0,
      );
      addTearDown(server.close);
      final walker = TreeWalker();
      final names = walker.list(root, '').map((e) => utf8.decode(e.name));
      expect(names, isNot(contains('fifo')));
      expect(names, isNot(contains('sock')));
      expect(
        walker.report.skipped.map((s) => (s.path.split('/').last, s.reason)),
        unorderedEquals([
          ('fifo', SkipReason.special),
          ('sock', SkipReason.special),
        ]),
      );
    }, testOn: '!windows');

    test(
      'нечитаемый каталог не прерывает обход',
      () {
        Process.runSync('chmod', ['000', '${dir.path}/sub']);
        final walker = TreeWalker();
        final items = walker.walk(root).map((i) => i.relative).toList();
        expect(items, containsAll(['a.txt', 'b.txt', 'sub']));
        expect(items, isNot(contains('sub/deep')));
        expect(walker.report.skipped.single.reason, SkipReason.error);
        expect(
          walker.report.skipped.single.detail,
          contains('доступ запрещён'),
        );
      },
      testOn: '!windows',
      skip: Process.runSync('id', ['-u']).stdout.toString().trim() == '0'
          ? 'root читает любой каталог'
          : false,
    );
  });

  test('DartIoFileSystem даёт тот же список и виды', () {
    File('${dir.path}/f').writeAsStringSync('12345');
    Directory('${dir.path}/d').createSync();
    Link('${dir.path}/l').createSync('f');
    final root = TreeWalker.rootPath(dir.path);
    final a = TreeWalker(fs: const DartIoFileSystem()).list(root, '');
    final b = TreeWalker().list(root, '');
    expect(
      a.map((e) => (utf8.decode(e.name), e.kind)),
      b.map((e) => (utf8.decode(e.name), e.kind)),
    );
    expect(a.first.size, 0); // d — каталог
    expect(a[1].size, 5);
  });
}

/// Как git: путь исключён, если исключён он сам или любой каталог выше.
bool _excludedWithParents(ExcludeRules rules, String path, bool isDir) {
  final parts = path.split('/');
  for (var i = 1; i < parts.length; i++) {
    if (rules.excludes(parts.take(i).join('/'), isDirectory: true)) return true;
  }
  return rules.excludes(path, isDirectory: isDir);
}
