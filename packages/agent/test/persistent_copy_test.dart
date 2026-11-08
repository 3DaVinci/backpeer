// Постоянная копия программ: обновляется не только по версии продукта.
// Версия одна и та же у разных сборок (а при запуске из исходников —
// `dev`), поэтому в отпечаток входят размер и время изменения каждой
// программы: новая сборка — новая копия, службы перезапускаются.

import 'dart:io';

import 'package:agent/agent.dart';
import 'package:core/core.dart' show setUnixFileMode;
import 'package:test/test.dart';

void main() {
  late Directory dir;
  late DaemonBundle source;
  late PersistentDaemons copy;

  void writeProgram(String program, String content) {
    final file = File('${dir.path}/src/$program/bin/$program')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(content);
    if (!Platform.isWindows) setUnixFileMode(file.path, 0x1ED); // 0755
  }

  setUp(() {
    dir = Directory.systemTemp.createTempSync('fs-persist-');
    source = DaemonBundle('${dir.path}/src');
    copy = PersistentDaemons(target: Directory('${dir.path}/target'));
    writeProgram('agent', 'agent v1');
    writeProgram('node', 'node v1');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('первая копия создаётся, повторная — нет', () {
    expect(copy.sync(source, '0.0.3'), isTrue);
    expect(DaemonBundle(copy.target.path).executable('agent'), isNotNull);
    expect(
      File('${copy.target.path}/VERSION').readAsStringSync(),
      contains('0.0.3'),
    );
    expect(copy.sync(source, '0.0.3'), isFalse);
  });

  test('изменилась программа той же версии — копия обновляется', () {
    expect(copy.sync(source, 'dev'), isTrue);
    expect(copy.sync(source, 'dev'), isFalse);

    File('${dir.path}/src/agent/bin/agent')
        .writeAsStringSync('agent v2 — другая сборка');
    // Размер другой — отпечаток изменился.
    expect(copy.sync(source, 'dev'), isTrue);
    expect(
      File('${copy.target.path}/agent/bin/agent').readAsStringSync(),
      'agent v2 — другая сборка',
    );
  });

  test('новая версия — копия обновляется', () {
    expect(copy.sync(source, '0.0.3'), isTrue);
    expect(copy.sync(source, '0.0.4'), isTrue);
    expect(
      File('${copy.target.path}/VERSION').readAsStringSync(),
      contains('0.0.4'),
    );
  });

  test('исходной программы нет — отпечаток не падает', () {
    File('${dir.path}/src/node/bin/node').deleteSync();
    expect(PersistentDaemons.fingerprint(source), contains('agent:'));
    expect(PersistentDaemons.fingerprint(source), isNot(contains('node:')));
  });
}
