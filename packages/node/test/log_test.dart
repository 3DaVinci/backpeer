import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:node/node.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('fs-node-log-'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('ротация по размеру: не больше files файлов, старые сдвигаются', () {
    final path = '${dir.path}/logs/node.log';
    final log = RotatingLogFile(path, maxBytes: 100, files: 3);
    for (var i = 0; i < 20; i++) {
      log.writeln('строка $i ${'x' * 30}');
    }
    log.close();
    final names =
        dir
            .listSync(recursive: true)
            .whereType<File>()
            .map((f) => f.uri.pathSegments.last)
            .toList()
          ..sort();
    expect(names, ['node.log', 'node.log.1', 'node.log.2']);
    for (final name in names) {
      expect(File('${dir.path}/logs/$name').lengthSync(), lessThan(100));
    }
    // Последняя запись — в текущем файле, предыдущие — в .1.
    expect(File(path).readAsStringSync(), contains('строка 19'));
    expect(File('$path.1').readAsStringSync(), contains('строка 17'));
  });

  test('дописывает в существующий файл после перезапуска', () {
    final path = '${dir.path}/node.log';
    RotatingLogFile(path, maxBytes: 1000, files: 2)
      ..writeln('первый')
      ..close();
    RotatingLogFile(path, maxBytes: 1000, files: 2)
      ..writeln('второй')
      ..close();
    expect(File(path).readAsLinesSync(), ['первый', 'второй']);
  });

  test('JSON Lines: поля события, у исключения только тип', () {
    final out = StringBuffer();
    final writer = JsonLogWriter(out)
      ..write(
        LogRecord(
          Level.WARNING,
          'x',
          'node',
          const FormatException('секрет'),
          null,
          null,
          const LogEvent('bad', {'n': 1}),
        ),
      );
    final line = jsonDecode(out.toString()) as Map<String, Object?>;
    expect(line['event'], 'bad');
    expect(line['n'], 1);
    expect(line['level'], 'warning');
    expect(line['error'], 'FormatException');
    expect(out.toString(), isNot(contains('секрет')));
    expect(writer, isNotNull);
  });
}
