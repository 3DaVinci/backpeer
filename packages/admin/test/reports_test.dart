import 'dart:io';

import 'package:admin/src/reports.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;
  late CrashReportStore store;
  var now = DateTime.utc(2026, 11, 16, 12);

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('fs-admin-reports-');
    now = DateTime.utc(2026, 11, 16, 12);
    store = await CrashReportStore.open(
      path: dir.path,
      retentionDays: 30,
      maxEntries: 100,
      clock: () => now,
    );
  });

  tearDown(() => dir.deleteSync(recursive: true));

  Map<String, Object?> report({
    String version = '0.0.7',
    String os = 'linux',
    String error = 'Bad state: boom',
    String at = '2026-11-16T10:00:00Z',
  }) => {
    'version': version,
    'os': os,
    'error': error,
    'stack': '#0 main (/home/user/app.dart:1)',
    'at': at,
  };

  test('отчёт очищается и сохраняется в файл', () async {
    final saved = await store.add(
      report(error: 'сбой /home/user/file 0123456789abcdef0123456789abcdef'),
      source: 'app',
    );
    expect(saved.error, contains('<path>'));
    expect(saved.error, contains('<secret>'));
    expect(saved.source, 'app');
    final files = dir.listSync().whereType<File>().toList();
    expect(files, hasLength(1));
    expect(files.single.path, endsWith('2026-11-16.jsonl'));
    final reloaded = await CrashReportStore.open(
      path: dir.path,
      retentionDays: 30,
      maxEntries: 100,
      clock: () => now,
    );
    expect(reloaded.reports, hasLength(1));
    expect(reloaded.get(saved.id)?.version, '0.0.7');
  });

  test('выборка, поиск и сводка', () async {
    await store.add(report(version: '0.0.6', os: 'windows'));
    await store.add(report(error: 'другая'));
    await store.add(report());
    final page = store.list(query: 'другая');
    expect(page.total, 1);
    expect(page.items.single.error, 'другая');
    expect(store.list(version: '0.0.7').total, 2);
    expect(store.list(os: 'windows').total, 1);
    expect(store.list(days: 1).total, 3);
    final summary = store.summary();
    expect(summary.total, 3);
    expect(summary.last24h, 3);
    expect(summary.byVersion.first['name'], '0.0.7');
    expect(summary.byVersion.first['count'], 2);
    expect(summary.byOs, hasLength(2));
    expect(summary.top, isNotEmpty);
  });

  test('плохие отчёты отклоняются', () async {
    await expectLater(
      store.add(report(version: '')),
      throwsA(isA<CrashReportException>()),
    );
    await expectLater(
      store.add(report(at: 'не время')),
      throwsA(isA<CrashReportException>()),
    );
    await expectLater(
      store.add(report(at: '2030-01-01T00:00:00Z')),
      throwsA(isA<CrashReportException>()),
    );
    await expectLater(
      store.add({'version': '1', 'os': 'x', 'error': '', 'stack': ''}),
      throwsA(isA<CrashReportException>()),
    );
  });

  test('память под отчёты ограничена', () async {
    final sub = Directory('${dir.path}/small')..createSync();
    final small = await CrashReportStore.open(
      path: sub.path,
      retentionDays: 30,
      maxEntries: 100,
      maxMemoryBytes: 600,
      clock: () => now,
    );
    await small.add(report(error: 'а' * 400));
    await small.add(report(error: 'б' * 400));
    expect(small.reports.length, lessThanOrEqualTo(1));
    expect(small.reports, isNotEmpty);
  });

  test('срок хранения удаляет старые файлы', () async {
    await store.add(report(at: '2026-09-01T00:00:00Z'));
    expect(store.reports, hasLength(1));
    await store.prune();
    // Отчёт получен сегодня, поэтому остаётся; старым считается файл по
    // дате получения, а не по at.
    expect(store.reports, hasLength(1));
    final old = File('${dir.path}/2026-01-01.jsonl');
    final _ = old..writeAsStringSync('{}\n');
    await store.prune();
    expect(old.existsSync(), isFalse);
  });
}
