import 'dart:io';

import 'package:agent/agent.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  final t0 = DateTime.utc(2026, 10, 27, 12);

  JobRecord record(JobOutcome outcome, {int minutes = 5}) => JobRecord(
    startedAt: t0,
    finishedAt: t0.add(Duration(minutes: minutes)),
    outcome: outcome,
  );

  group('расписание', () {
    final settings = AgentSettings(paths: ['/data']);

    test('нет папок или только вручную — не по расписанию', () {
      expect(nextScheduledBackup(AgentSettings(), AgentState()), isNull);
      expect(
        nextScheduledBackup(
          AgentSettings(paths: ['/data'], intervalMinutes: null),
          AgentState(lastBackup: record(JobOutcome.ok)),
        ),
        isNull,
      );
    });

    test('первый бэкап — сразу', () {
      final next = nextScheduledBackup(settings, AgentState())!;
      expect(next.isBefore(DateTime.now()), isTrue);
    });

    test('после удачного — интервал от начала', () {
      for (final outcome in [JobOutcome.ok, JobOutcome.partial]) {
        expect(
          nextScheduledBackup(
            settings,
            AgentState(lastBackup: record(outcome)),
          ),
          t0.add(const Duration(minutes: 60)),
        );
      }
    });

    test(
      'после неудачного — повтор через retryMinutes, не позже интервала',
      () {
        expect(
          nextScheduledBackup(
            settings,
            AgentState(lastBackup: record(JobOutcome.failed)),
          ),
          t0.add(const Duration(minutes: 15)),
        );
        expect(
          nextScheduledBackup(
            AgentSettings(paths: ['/d'], intervalMinutes: 3),
            AgentState(lastBackup: record(JobOutcome.failed)),
          ),
          t0.add(const Duration(minutes: 8)),
        );
      },
    );

    test('незаконченный бэкап — сразу, даже при ручном режиме', () {
      final started = t0.add(const Duration(hours: 1));
      expect(
        nextScheduledBackup(
          AgentSettings(paths: ['/d'], intervalMinutes: null),
          AgentState(lastBackup: record(JobOutcome.ok), interrupted: started),
        ),
        started,
      );
    });
  });

  group('настройки и состояние', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('fs-agent-set-'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('по умолчанию, слияние, сохранение', () {
      final file = File('${dir.path}/settings.json');
      final defaults = AgentSettings.load(file);
      expect(defaults.paths, isEmpty);
      expect(defaults.intervalMinutes, 60);
      final next = defaults.merge({
        'paths': ['/a', '/b'],
        'intervalMinutes': null,
      })..save(file);
      final loaded = AgentSettings.load(file);
      expect(loaded.paths, ['/a', '/b']);
      expect(loaded.intervalMinutes, isNull);
      expect(next.toJson(), loaded.toJson());
    });

    test('неверные значения — ConfigException', () {
      for (final bad in [
        {'paths': '/a'},
        {
          'paths': [1],
        },
        {'intervalMinutes': 0},
        {'intervalMinutes': 'час'},
      ]) {
        expect(
          () => AgentSettings().merge(bad),
          throwsA(isA<ConfigException>()),
          reason: '$bad',
        );
      }
    });

    test('состояние переживает перезапуск; испорченный файл — пустое', () {
      final file = File('${dir.path}/state.json');
      AgentState(
        lastBackup: JobRecord(
          startedAt: t0,
          finishedAt: t0,
          outcome: JobOutcome.partial,
          result: const {'files': 3},
        ),
        interrupted: t0,
      ).save(file);
      final state = AgentState.load(file);
      expect(state.lastBackup!.outcome, JobOutcome.partial);
      expect(state.lastBackup!.result, {'files': 3});
      expect(state.interrupted, t0);
      file.writeAsStringSync('{"lastBackup": {"startedAt": 1}}');
      expect(AgentState.load(file).lastBackup, isNull);
      file.writeAsStringSync('не json');
      expect(AgentState.load(file).interrupted, isNull);
    });
  });
}
