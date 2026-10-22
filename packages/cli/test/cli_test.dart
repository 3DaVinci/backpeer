import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cli/cli.dart';
import 'package:test/test.dart';

/// Консоль для тестов: отвечает на вопросы функцией, копит вывод.
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
}

/// Слова фразы из вывода `init` или `show-phrase`.
Map<int, String> _phraseWords(List<String> out) => {
  for (final line in out)
    for (final m in RegExp(r'(\d+)\. ([a-z]+)').allMatches(line))
      int.parse(m[1]!): m[2]!,
};

void main() {
  late Directory dir;
  late Map<String, String> env;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('fs-cli-');
    env = {
      'FS_HOME': '${dir.path}/home',
      'FS_PASSWORD': 'correct horse battery staple',
      'FS_ARGON2_FAST': '1',
    };
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<(int, _Console)> cli(
    List<String> args, {
    Map<String, String>? environment,
    String? Function(String, List<String>)? answer,
  }) async {
    final console = _Console(answer);
    final code = await runCli(
      args,
      console: console,
      environment: environment ?? env,
    );
    return (code, console);
  }

  /// Ответы для init: слова фразы по номерам из напечатанного.
  String? answerWords(String prompt, List<String> out) {
    final m = RegExp(r'Слово №(\d+)').firstMatch(prompt);
    return m == null ? null : _phraseWords(out)[int.parse(m[1]!)];
  }

  Future<List<String>> init() async {
    final (code, console) = await cli(['init'], answer: answerWords);
    expect(code, ExitCode.ok, reason: console.errors.join('\n'));
    final words = _phraseWords(console.lines);
    expect(words, hasLength(24));
    return [for (var i = 1; i <= 24; i++) words[i]!];
  }

  test('help у каждой команды', () async {
    for (final command in [
      'init',
      'recover',
      'backup',
      'snapshots',
      'restore',
      'verify',
      'forget',
      'show-phrase',
      'config',
    ]) {
      final (code, console) = await cli([command, '--help']);
      expect(code, ExitCode.ok, reason: command);
      expect(console.lines.join('\n'), contains('Usage:'), reason: command);
    }
  });

  test('неверный вызов — код 2', () async {
    expect((await cli(['no-such-command'])).$1, ExitCode.usage);
    expect((await cli(['backup'])).$1, isNot(ExitCode.ok));
  });

  test(
    'полный цикл: init, backup, snapshots, restore, verify, forget',
    () async {
      final words = await init();
      expect(
        (await cli(['init'], answer: answerWords)).$1,
        ExitCode.error,
        reason: 'уже создано',
      );

      final data = Directory('${dir.path}/data')..createSync();
      File('${data.path}/a.txt').writeAsStringSync('привет');
      File('${data.path}/sub/b.bin')
        ..createSync(recursive: true)
        ..writeAsBytesSync(List.generate(300000, (i) => i % 251));

      final (backupCode, backup) = await cli(['backup', data.path]);
      expect(backupCode, ExitCode.ok, reason: backup.errors.join('\n'));
      final snapshotId = RegExp('Снимок ([0-9a-f]{12})')
          .firstMatch(backup.lines.join('\n'))![1]!;

      final (listCode, list) = await cli(['snapshots']);
      expect(listCode, ExitCode.ok);
      expect(list.lines.single, startsWith(snapshotId));

      final target = '${dir.path}/out';
      final (restoreCode, restore) = await cli([
        'restore',
        snapshotId,
        '--to',
        target,
      ]);
      expect(restoreCode, ExitCode.ok, reason: restore.errors.join('\n'));
      expect(File('$target${data.path}/a.txt').readAsStringSync(), 'привет');
      expect(
        File('$target${data.path}/sub/b.bin').readAsBytesSync(),
        File('${data.path}/sub/b.bin').readAsBytesSync(),
      );
      // Повторно — без перезаписи: частичный успех.
      expect(
        (await cli(['restore', snapshotId, '--to', target])).$1,
        ExitCode.partial,
      );

      final (verifyCode, verify) = await cli(['verify', '--full']);
      expect(verifyCode, ExitCode.ok, reason: verify.errors.join('\n'));
      expect(verify.lines.single, contains('всё в порядке'));

      final (phraseCode, phrase) = await cli(['show-phrase']);
      expect(phraseCode, ExitCode.ok);
      final shown = _phraseWords(phrase.lines);
      expect([for (var i = 1; i <= 24; i++) shown[i]], words);

      expect((await cli(['forget', snapshotId])).$1, ExitCode.ok);
      expect((await cli(['snapshots'])).$2.lines.single, 'Снимков нет.');
    },
  );

  test('неверный пароль и короткий префикс снимка', () async {
    await init();
    final (code, console) = await cli(
      ['snapshots'],
      environment: {...env, 'FS_PASSWORD': 'wrong password!'},
    );
    expect(code, ExitCode.error);
    expect(console.errors.single, contains('Неверный пароль'));
    expect((await cli(['forget', 'ab'])).$1, ExitCode.usage);
  });

  test('recover на новом устройстве по фразе', () async {
    final words = await init();
    final data = Directory('${dir.path}/data')..createSync();
    File('${data.path}/a.txt').writeAsStringSync('данные');
    expect((await cli(['backup', data.path])).$1, ExitCode.ok);

    final home = env['FS_HOME']!;
    final other = {
      ...env,
      'FS_HOME': '${dir.path}/other-device',
      'FS_PHRASE': words.join(' '),
      'FS_PASSWORD': 'another long password',
    };
    final (code, console) = await cli([
      'recover',
      '--nodes',
      '$home/nodes',
      '--objects',
      '$home/objects',
    ], environment: other);
    expect(code, ExitCode.ok, reason: console.errors.join('\n'));
    expect(console.lines.single, contains('сегментов 1'));
    final list = (await cli(['snapshots'], environment: other)).$2.lines.single;
    final id = list.substring(0, 12);
    final target = '${dir.path}/out';
    expect(
      (await cli(['restore', id, '--to', target], environment: other)).$1,
      ExitCode.ok,
    );
    expect(File('$target${data.path}/a.txt').readAsStringSync(), 'данные');
  });

  test('config: показ и изменение исключений', () async {
    await init();
    final (code, console) = await cli(['config', '--exclude', '*.tmp']);
    expect(code, ExitCode.ok);
    expect(console.lines.last, contains('*.tmp'));
    expect(
      (await cli(['config', '--node-count', '5'])).$1,
      ExitCode.error,
      reason: 'меньше n',
    );
  });

  test('--version', () async {
    final (code, console) = await cli(['--version']);
    expect(code, ExitCode.ok);
    expect(console.lines.first, startsWith('cli '));
    expect(console.lines.last, startsWith('libsodium '));
  });

  group('--json', () {
    List<Map<String, Object?>> events(_Console console) => [
      for (final line in console.lines)
        jsonDecode(line) as Map<String, Object?>,
    ];

    test('каждая строка — JSON, последняя — result с exitCode', () async {
      final (initCode, initOut) = await cli(
        ['--json', 'init'],
        answer: (prompt, out) {
          final m = RegExp(r'Слово №(\d+)').firstMatch(prompt);
          if (m == null) return null;
          final phrase = events(_Console()..lines.addAll(out))
              .firstWhere((e) => e['type'] == 'phrase');
          return (phrase['words']! as List)[int.parse(m[1]!) - 1] as String;
        },
      );
      expect(initCode, ExitCode.ok, reason: initOut.errors.join('\n'));
      final initEvents = events(initOut);
      expect(initEvents.first['type'], 'phrase');
      expect(initEvents.last, containsPair('type', 'result'));
      expect(initEvents.last['accountId'], hasLength(64));

      final data = Directory('${dir.path}/data')..createSync();
      File('${data.path}/a.txt').writeAsStringSync('x');
      final (code, out) = await cli(['--json', 'backup', data.path]);
      expect(code, ExitCode.ok);
      final last = events(out).last;
      expect(last['type'], 'result');
      expect(last['exitCode'], 0);
      expect(last['files'], 1);
      expect(last['snapshotId'], hasLength(64));

      final list = events((await cli(['--json', 'snapshots'])).$2).last;
      final snaps = (list['snapshots']! as List).cast<Map<String, Object?>>();
      expect(snaps.single['id'], last['snapshotId']);
      expect(
        DateTime.parse(snaps.single['createdAt']! as String).isUtc,
        isTrue,
      );
    });

    test('ошибка — последняя строка error с тем же кодом', () async {
      final (code, out) = await cli(['--json', 'snapshots']);
      expect(code, ExitCode.error);
      final last = events(out).single;
      expect(last['type'], 'error');
      expect(last['exitCode'], ExitCode.error);
      expect(out.errors, isEmpty, reason: 'в режиме --json текст не выводится');

      final (usage, usageOut) = await cli(['--json', 'nonsense']);
      expect(usage, ExitCode.usage);
      expect(events(usageOut).single['exitCode'], ExitCode.usage);
    });

    test('частичный успех: result с exitCode 3 и предупреждения', () async {
      await init();
      final data = Directory('${dir.path}/data')..createSync();
      File('${data.path}/a.txt').writeAsStringSync('x');
      await cli(['backup', data.path]);
      final id = (await cli(['snapshots'])).$2.lines.single.substring(0, 12);
      await cli(['restore', id, '--to', '${dir.path}/out']);
      final (code, out) = await cli([
        '--json',
        'restore',
        id,
        '--to',
        '${dir.path}/out',
      ]);
      expect(code, ExitCode.partial);
      final all = events(out);
      expect(all.where((e) => e['type'] == 'warning'), isNotEmpty);
      expect(all.last, containsPair('exitCode', ExitCode.partial));
      expect(all.last['skippedExisting'], 1);
    });
  });

  test(
    'Ctrl+C посреди бэкапа — код 130, повторный запуск продолжает',
    () async {
      await init();
      final data = Directory('${dir.path}/big')..createSync();
      final random = Random(1);
      for (var i = 0; i < 12; i++) {
        File(
          '${data.path}/f$i.bin',
        ).writeAsBytesSync(List.generate(16 << 20, (_) => random.nextInt(256)));
      }
      final process = await Process.start(Platform.resolvedExecutable, [
        'run',
        'bin/cli.dart',
        'backup',
        data.path,
      ], environment: env);
      final stderrText = StringBuffer();
      process.stderr.transform(utf8.decoder).listen(stderrText.write);
      unawaited(process.stdout.drain<void>());
      // Ждём первого записанного фрагмента — бэкап точно идёт.
      final nodes = Directory('${env['FS_HOME']}/nodes/node-00');
      final deadline = DateTime.now().add(const Duration(minutes: 3));
      while (!(nodes.existsSync() &&
          nodes
              .listSync(recursive: true)
              .any((e) => e.path.endsWith('.frag')))) {
        if (DateTime.now().isAfter(deadline)) {
          fail('бэкап не начался: $stderrText');
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      process.kill(ProcessSignal.sigint);
      expect(await process.exitCode, ExitCode.cancelled, reason: '$stderrText');

      final (code, out) = await cli(['--json', 'backup', data.path]);
      expect(code, ExitCode.ok);
      final result = jsonDecode(out.lines.last) as Map<String, Object?>;
      expect(result['files'], 12);
    },
    testOn: '!windows',
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
