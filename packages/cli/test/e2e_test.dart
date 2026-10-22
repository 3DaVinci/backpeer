// Сквозные тесты через CLI (задача 1.8.1): сбои хранителей и координатора
// изображаются порчей папок-«узлов» и папки объектов на диске.

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cli/cli.dart';
import 'package:test/test.dart';

final class _Console implements Console {
  new([this.answer]);

  final String? Function(String prompt, List<String> out)? answer;
  final List<String> lines = [];
  final List<String> errors = [];

  @override
  void out(String line) => lines.add(line);

  @override
  void err(String line) => errors.add(line);

  @override
  String? ask(String prompt) => answer?.call(prompt, lines);

  @override
  String? askSecret(String prompt) => answer?.call(prompt, lines);

  @override
  void progress(String line) {}

  List<Map<String, Object?>> get events => [
    for (final l in lines) jsonDecode(l) as Map<String, Object?>,
  ];

  Map<String, Object?> get result => events.last;

  Iterable<Map<String, Object?>> get warnings =>
      events.where((e) => e['type'] == 'warning');
}

void main() {
  late Directory dir;
  late Directory data;
  late Map<String, String> env;
  late List<String> phrase;

  Future<(int, _Console)> cli(
    List<String> args, {
    Map<String, String>? environment,
    String? Function(String, List<String>)? answer,
  }) async {
    final console = _Console(answer);
    final code = await runCli(
      ['--json', ...args],
      console: console,
      environment: environment ?? env,
    );
    return (code, console);
  }

  String home() => env['FS_HOME']!;

  /// Файлы фрагментов всех узлов.
  List<File> fragments() => [
    for (final e in Directory('${home()}/nodes').listSync(recursive: true))
      if (e is File && e.path.endsWith('.frag')) e,
  ];

  void flipByte(File file, int offset) {
    final bytes = file.readAsBytesSync();
    bytes[offset % bytes.length] ^= 0x01;
    file.writeAsBytesSync(bytes);
  }

  Future<String> backup() async {
    final (code, out) = await cli(['backup', data.path]);
    expect(code, ExitCode.ok, reason: out.lines.join('\n'));
    return out.result['snapshotId']! as String;
  }

  Future<String> restored(
    String snapshot, {
    Map<String, String>? environment,
  }) async {
    final target = Directory('${dir.path}/out-${Random().nextInt(1 << 30)}');
    final (code, out) = await cli([
      'restore',
      snapshot.substring(0, 12),
      '--to',
      target.path,
    ], environment: environment);
    expect(code, ExitCode.ok, reason: out.lines.join('\n'));
    return '${target.path}${data.path}';
  }

  void expectSameTree(String original, String copy) {
    final a = Directory(original)
        .listSync(recursive: true)
        .whereType<File>()
        .toList();
    expect(a, isNotEmpty);
    for (final f in a) {
      final rel = f.path.substring(original.length);
      expect(
        File('$copy$rel').readAsBytesSync(),
        f.readAsBytesSync(),
        reason: rel,
      );
    }
    final b = Directory(copy).listSync(recursive: true).whereType<File>();
    expect(b.length, a.length);
  }

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('fs-e2e-');
    env = {
      'FS_HOME': '${dir.path}/home',
      'FS_PASSWORD': 'correct horse battery staple',
      'FS_ARGON2_FAST': '1',
    };
    final (code, out) = await cli(
      ['init'],
      answer: (prompt, lines) {
        final m = RegExp(r'Слово №(\d+)').firstMatch(prompt);
        if (m == null) return null;
        final words =
            (jsonDecode(lines.first) as Map<String, Object?>)['words']! as List;
        return words[int.parse(m[1]!) - 1] as String;
      },
    );
    expect(code, ExitCode.ok, reason: out.errors.join('\n'));
    phrase =
        ((jsonDecode(out.lines.first) as Map<String, Object?>)['words']!
                as List)
            .cast<String>();

    data = Directory('${dir.path}/data')..createSync();
    final random = Random(7);
    for (var i = 0; i < 3; i++) {
      File('${data.path}/big$i.bin').writeAsBytesSync(
        Uint8List.fromList(List.generate(2 << 20, (_) => random.nextInt(256))),
      );
    }
    File('${data.path}/docs/note.txt')
      ..createSync(recursive: true)
      ..writeAsStringSync('первая версия');
    File('${data.path}/docs/other.txt').writeAsStringSync('не меняется');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test(
    'потеря n − k папок-«узлов»: восстановление полное, verify — риск',
    () async {
      final snapshot = await backup();
      for (var i = 0; i < 10; i++) {
        Directory(
          '${home()}/nodes/node-${(i * 2 + 1).toString().padLeft(2, '0')}',
        ).deleteSync(recursive: true);
      }
      expectSameTree(data.path, await restored(snapshot));

      final (code, out) = await cli(['verify']);
      expect(code, ExitCode.partial);
      expect(out.result['atRisk'], greaterThan(0));
      expect(out.result['unrecoverable'], 0);

      // Ещё одна папка — данных уже не собрать.
      Directory('${home()}/nodes/node-00').deleteSync(recursive: true);
      expect((await cli(['verify'])).$1, ExitCode.error);
      final (restoreCode, _) = await cli([
        'restore',
        snapshot.substring(0, 12),
        '--to',
        '${dir.path}/lost',
      ]);
      expect(restoreCode, ExitCode.error);
    },
  );

  test('повреждённый фрагмент: виден только verify --full', () async {
    final snapshot = await backup();
    final victim = fragments().first;
    flipByte(victim, 5000);

    expect((await cli(['verify'])).$1, ExitCode.ok);
    final (code, out) = await cli(['verify', '--full']);
    expect(code, ExitCode.partial);
    expect(out.result['problems'], 1);
    expect(out.warnings.single['error'], contains('Меркла'));

    expectSameTree(data.path, await restored(snapshot));
  });

  test(
    'повреждённый объект снимка: список предупреждает, восстановление — ошибка',
    () async {
      final snapshot = await backup();
      final object = Directory('${home()}/objects/snapshot')
          .listSync()
          .whereType<File>()
          .single;
      flipByte(object, 100);

      final (listCode, list) = await cli(['snapshots']);
      expect(listCode, ExitCode.partial);
      expect(list.warnings.single['snapshotId'], snapshot);
      expect(list.result['snapshots'], isEmpty);

      final (code, out) = await cli([
        'restore',
        snapshot.substring(0, 12),
        '--to',
        '${dir.path}/out',
      ]);
      expect(code, ExitCode.error);
      expect(out.result['message'], contains('не сошлась проверка'));
    },
  );

  test(
    'повреждённый индекс: новое устройство видит это, остальное работает',
    () async {
      final first = await backup();
      File('${data.path}/docs/note.txt').writeAsStringSync('вторая версия');
      final second = await backup();
      // Портим индекс второго бэкапа (более поздний файл).
      final indexes =
          Directory('${home()}/objects/index')
              .listSync()
              .whereType<File>()
              .toList()
            ..sort(
              (a, b) => a.statSync().modified.compareTo(b.statSync().modified),
            );
      expect(indexes, hasLength(2));
      flipByte(indexes.last, 120);

      final other = {
        ...env,
        'FS_HOME': '${dir.path}/new-device',
        'FS_PHRASE': phrase.join(' '),
      };
      final (code, out) = await cli([
        'recover',
        '--nodes',
        '${home()}/nodes',
        '--objects',
        '${home()}/objects',
      ], environment: other);
      expect(code, ExitCode.partial);
      expect(out.result['unreadable'], 1);
      // Первый снимок восстанавливается целиком по уцелевшему индексу.
      final copy = await restored(first, environment: other);
      expect(File('$copy/docs/note.txt').readAsStringSync(), 'первая версия');
      // Второму не хватает сегментов из испорченного индекса.
      final (restoreCode, _) = await cli([
        'restore',
        second.substring(0, 12),
        '--to',
        '${dir.path}/second',
      ], environment: other);
      expect(restoreCode, isNot(ExitCode.ok));
    },
  );

  test(
    'второй бэкап после правки одного файла: только его чанки и деревья',
    () async {
      await backup();
      File('${data.path}/docs/note.txt').writeAsStringSync('вторая версия');
      final (code, out) = await cli(['backup', data.path]);
      expect(code, ExitCode.ok);
      final r = out.result;
      // Чанк файла + деревья docs, корня бэкапа и корня снимка.
      expect(r['newChunks'], 4);
      expect(r['newBytes']! as int, lessThan(4096));
      expect(r['segments'], 1);
      expect(r['files'], 5);

      final (_, list) = await cli(['snapshots']);
      final snaps = (list.result['snapshots']! as List)
          .cast<Map<String, Object?>>();
      expect(snaps, hasLength(2));
      expect(snaps.last['parent'], snaps.first['id']);
    },
  );

  test('новое устройство по фразе: всё восстанавливается', () async {
    final snapshot = await backup();
    final other = {
      ...env,
      'FS_HOME': '${dir.path}/new-device',
      'FS_PHRASE': phrase.join(' '),
      'FS_PASSWORD': 'другой пароль на новом устройстве',
    };
    final (code, out) = await cli([
      'recover',
      '--nodes',
      '${home()}/nodes',
      '--objects',
      '${home()}/objects',
    ], environment: other);
    expect(code, ExitCode.ok, reason: out.lines.join('\n'));
    expect(
      (await cli(['verify', '--full'], environment: other)).$1,
      ExitCode.ok,
    );
    expectSameTree(data.path, await restored(snapshot, environment: other));

    // Бэкап с нового устройства не загружает уже сохранённое.
    final (backupCode, backupOut) = await cli([
      'backup',
      data.path,
    ], environment: other);
    expect(backupCode, ExitCode.ok);
    expect(backupOut.result['segments'], 0);
  });
}
