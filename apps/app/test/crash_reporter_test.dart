// Отчёты о сбоях (задача 5.9.3): очистка от путей и ключей, согласие.

import 'dart:convert';
import 'dart:io';

import 'package:app/src/services/crash_reporter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('redact убирает пути, ключи и строки с секретами', () {
    const key =
        '1731fb20d6f98866ced74d2f7fbac311723c99e20aea990ab281a0d33482bb29';
    const blobs = 'zLxiViV3qqs870oI1CqKSbYLMDWMzRxpuaXqc0Gemgs=';
    const input =
        'ошибка в /home/user/data/file.txt и C:\\Users\\user\\x\n'
        'ключ $key и блоб $blobs\n'
        'строка с password не должна попасть';
    final out = CrashReporter.redact(input);
    expect(out, isNot(contains('/home/user')));
    expect(out, isNot(contains(r'C:\Users')));
    expect(out, isNot(contains(key)));
    expect(out, isNot(contains(blobs)));
    expect(out, isNot(contains('password')));
    expect(out, contains('<path>'));
    expect(out, contains('<secret>'));
  });

  test('capture сохраняет обезличенный отчёт и отправляет', () async {
    final dir = Directory.systemTemp.createTempSync('fs-crash-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/crash-reports.jsonl');
    Map<String, Object?>? uploaded;
    final reporter = CrashReporter(
      file: file,
      upload: (report) async => uploaded = report,
    );
    await reporter.capture(
      StateError('нет ключа /home/user/secret/key.bin'),
      StackTrace.current,
    );

    final lines = file.readAsLinesSync();
    expect(lines, hasLength(1));
    final report = jsonDecode(lines.single) as Map<String, Object?>;
    expect(report['version'], isNotEmpty);
    expect(report['error'], contains('<path>'));
    expect(report['error'], isNot(contains('/home/user')));
    expect(report['stack'], isNot(contains('/home/')));
    expect(uploaded, isNotNull);
  });

  test('без file и upload capture не падает', () async {
    await CrashReporter().capture(StateError('x'), StackTrace.current);
  });
}
