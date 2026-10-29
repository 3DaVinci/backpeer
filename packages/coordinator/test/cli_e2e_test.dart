// Сквозной сценарий CLI через настоящий координатор (задача 2.8.3):
// регистрация на одном «устройстве», вход по паролю и восстановление по
// фразе на других, устройства и отзыв, смена пароля, копия ключа, состояние
// бэкапа и проверки (4.5). Фрагменты
// — в папках узлов-заглушек (node stub). Нужен FS_TEST_POSTGRES.

import 'dart:convert';
import 'dart:io';

import 'package:cli/cli.dart';
import 'package:node/node.dart';
import 'package:test/test.dart';

import 'support/live.dart';
import 'support/postgres.dart';

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

void main() {
  if (testPostgresUrl == null) {
    test('CLI через координатор', () {}, skip: skipWithoutPostgres);
    return;
  }
  late LiveCoordinator live;
  late Directory dir;
  const password = 'correct horse battery staple';

  setUp(() async {
    live = await LiveCoordinator.start();
    dir = Directory.systemTemp.createTempSync('fs-cli-coord-');
    final client = live.client();
    await StubNodes(
      root: Directory('${dir.path}/nodes'),
      client: client,
      crypto: live.crypto,
    ).create(5);
    client.close();
  });
  tearDown(() async {
    await live.close();
    dir.deleteSync(recursive: true);
  });

  Map<String, String> env(String device, {String pw = password}) => {
    'FS_HOME': '${dir.path}/$device',
    'FS_PASSWORD': pw,
    'FS_ARGON2_FAST': '1',
  };

  /// Запуск с `--json`; результат — последняя строка (result или error).
  Future<(int, Map<String, Object?>, _Console)> cli(
    List<String> args,
    Map<String, String> environment, {
    String? Function(String, List<String>)? answer,
  }) async {
    final console = _Console(answer);
    final code = await runCli(
      ['--json', ...args],
      console: console,
      environment: environment,
    );
    final last = console.lines.isEmpty
        ? const <String, Object?>{}
        : jsonDecode(console.lines.last) as Map<String, Object?>;
    return (code, last, console);
  }

  List<String> storage() => [
    '--coordinator',
    live.url,
    '--nodes',
    '${dir.path}/nodes',
    '--k',
    '2',
    '--n',
    '4',
    '--repair-threshold',
    '3',
  ];

  /// Ответы на проверку слов фразы — из события `phrase`.
  String? words(String prompt, List<String> out) {
    final m = RegExp(r'Слово №(\d+)').firstMatch(prompt);
    if (m == null) return null;
    final phrase = out
        .map((l) => jsonDecode(l) as Map<String, Object?>)
        .firstWhere((e) => e['type'] == 'phrase');
    return (phrase['words']! as List<Object?>)[int.parse(m[1]!) - 1]! as String;
  }

  test('регистрация, бэкап, вход по паролю и по фразе, отзыв', () async {
    final a = env('a');
    var (code, result, console) = await cli(
      ['register', ...storage(), '--login', 'Alice'],
      a,
      answer: words,
    );
    expect(code, ExitCode.ok, reason: console.lines.join('\n'));
    expect(result['login'], 'alice');
    expect(result['keyCopy'], isTrue);
    final phrase = (jsonDecode(console.lines.first) as Map)['words'] as List;

    // Занятое имя.
    (code, result, _) = await cli(
      ['register', ...storage(), '--login', 'alice'],
      env('x'),
      answer: words,
    );
    expect(code, ExitCode.error);
    expect(result['message'], contains('занято'));
    expect(File('${dir.path}/x/keys.bundle').existsSync(), isFalse);

    final source = Directory('${dir.path}/src')..createSync();
    File('${source.path}/doc.txt').writeAsStringSync('документ ' * 1000);
    (code, result, console) = await cli(['backup', source.path], a);
    expect(code, ExitCode.ok, reason: console.lines.join('\n'));
    final snapshot = result['snapshotId']! as String;

    // Второе устройство: вход по имени и паролю.
    final b = env('b');
    (code, result, console) = await cli([
      'login',
      ...storage(),
      '--login',
      'alice',
    ], b);
    expect(code, ExitCode.ok, reason: console.lines.join('\n'));
    expect(result['indexes'], greaterThan(0));
    (code, result, _) = await cli([
      'restore',
      snapshot.substring(0, 8),
      '--to',
      '${dir.path}/out-b',
    ], b);
    expect(code, ExitCode.ok);
    expect(
      File('${dir.path}/out-b${source.path}/doc.txt').readAsStringSync(),
      'документ ' * 1000,
    );

    // Неверный пароль.
    (code, result, _) = await cli([
      'login',
      ...storage(),
      '--login',
      'alice',
    ], env('y', pw: 'wrong password here'));
    expect(code, ExitCode.error);
    expect(result['message'], contains('Неверное имя или пароль'));

    // Третье устройство: по фразе.
    final c = {...env('c'), 'FS_PHRASE': phrase.join(' ')};
    (code, result, console) = await cli(['recover', ...storage()], c);
    expect(code, ExitCode.ok, reason: console.lines.join('\n'));
    (code, result, _) = await cli(['snapshots'], c);
    expect(code, ExitCode.ok);
    expect(result['snapshots'], hasLength(1));

    // Устройства и отзыв третьего с первого.
    (code, result, _) = await cli(['devices'], a);
    expect(code, ExitCode.ok);
    final devices = (result['devices']! as List).cast<Map<String, Object?>>();
    expect(devices, hasLength(3));
    expect(devices.where((d) => d['current'] == true), hasLength(1));
    final cId = jsonDecode(
      File('${dir.path}/c/config.json').readAsStringSync(),
    ) as Map<String, Object?>;
    (code, result, _) = await cli([
      'revoke',
      (cId['deviceId']! as String).substring(0, 12),
    ], a);
    expect(code, ExitCode.ok);
    (code, result, _) = await cli(['snapshots'], c);
    expect(code, ExitCode.error, reason: 'отозванное устройство');
    expect(result['message'], contains('UNAUTHENTICATED'));
    // Себя отозвать нельзя.
    (code, _, _) = await cli([
      'revoke',
      (devices.firstWhere((d) => d['current'] == true)['deviceId']! as String)
          .substring(0, 12),
    ], a);
    expect(code, ExitCode.usage);
  });

  test('смена пароля и копия ключа на координаторе', () async {
    final a = env('a');
    var (code, _, console) = await cli(
      ['register', ...storage(), '--login', 'bob', '--no-key-copy'],
      a,
      answer: words,
    );
    expect(code, ExitCode.ok, reason: console.lines.join('\n'));
    Future<int> login(String device, String pw) async => (await cli([
      'login',
      ...storage(),
      '--login',
      'bob',
    ], env(device, pw: pw))).$1;

    expect(await login('b', password), ExitCode.error, reason: 'копии нет');
    (code, _, _) = await cli(['key-copy', 'on'], a);
    expect(code, ExitCode.ok);
    expect(await login('c', password), ExitCode.ok);

    const fresh = 'another long passphrase 2026';
    (code, _, console) = await cli(
      ['passwd'],
      {...a, 'FS_NEW_PASSWORD': fresh},
    );
    expect(code, ExitCode.ok, reason: console.lines.join('\n'));
    expect((jsonDecode(console.lines.last) as Map)['keyCopyUpdated'], isTrue);
    expect(await login('d', password), ExitCode.error, reason: 'старый');
    expect(await login('e', fresh), ExitCode.ok);
    (code, _, _) = await cli(['devices'], a);
    expect(code, ExitCode.error, reason: 'локально тоже новый пароль');
    final a2 = env('a', pw: fresh);
    (code, _, _) = await cli(['devices'], a2);
    expect(code, ExitCode.ok);

    (code, _, _) = await cli(['key-copy', 'off'], a2);
    expect(code, ExitCode.ok);
    expect(await login('f', fresh), ExitCode.error);
    final config = jsonDecode(
      File('${dir.path}/a/config.json').readAsStringSync(),
    ) as Map<String, Object?>;
    expect(config['keyCopy'], isFalse);
  });

  test('состояние бэкапа от координатора (4.5.1)', () async {
    final a = env('a');
    var (code, result, console) = await cli(
      ['register', ...storage(), '--login', 'carol'],
      a,
      answer: words,
    );
    expect(code, ExitCode.ok, reason: console.lines.join('\n'));
    (code, result, console) = await cli(['status'], a);
    expect(code, ExitCode.ok, reason: console.lines.join('\n'));
    expect(result['localSegments'], 0);
    expect((result['health']! as Map)['segments'], 0);

    final source = Directory('${dir.path}/src')..createSync();
    File('${source.path}/doc.txt').writeAsStringSync('данные ' * 5000);
    (code, _, _) = await cli(['backup', source.path], a);
    expect(code, ExitCode.ok);
    (code, result, console) = await cli(['status'], a);
    expect(code, ExitCode.ok, reason: console.lines.join('\n'));
    final local = result['localSegments']! as int;
    expect(local, greaterThan(0));
    final health = result['health']! as Map<String, Object?>;
    expect(health['segments'], local);
    expect(health['healthy'], local, reason: 'все 4 фрагмента из 4');
    expect(health['atRisk'], 0);
    expect(health['lost'], 0);
    expect(health['liveFragments'], local * 4);
    expect(health['fragmentBytes'], greaterThan(0));
    expect(health['lastAudit'], isNull);

    // Текст для человека.
    final human = _Console();
    expect(
      await runCli(['status'], console: human, environment: a),
      ExitCode.ok,
    );
    expect(human.lines.join('\n'), contains('полностью здоровы: $local'));
  });
}
