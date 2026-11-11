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

  group('часы и проверка', () {
    test('разрешённые часы: внутри — как есть, вне — начало окна', () {
      const night = BackupHours(22, 7);
      expect(night.contains(23), isTrue);
      expect(night.contains(3), isTrue);
      expect(night.contains(7), isFalse);
      expect(night.contains(12), isFalse);
      const day = BackupHours(9, 18);
      expect(day.contains(9), isTrue);
      expect(day.contains(18), isFalse);

      final noon = DateTime(2026, 10, 27, 12);
      // Пора было час назад, сейчас полдень: ждать 22:00.
      expect(
        fitHours(noon.subtract(const Duration(hours: 1)), night, noon),
        DateTime(2026, 10, 27, 22),
      );
      // Пора в 3 ночи завтра — в окне.
      final early = DateTime(2026, 10, 28, 3);
      expect(fitHours(early, night, noon), early);
      // Пора в 19:00, окно 9–18: завтра в 9.
      expect(
        fitHours(DateTime(2026, 10, 27, 19), day, noon),
        DateTime(2026, 10, 28, 9),
      );
      // Пора в 7:30, окно 9–18: сегодня в 9.
      expect(
        fitHours(DateTime(2026, 10, 27, 7, 30), day, DateTime(2026, 10, 27, 6)),
        DateTime(2026, 10, 27, 9),
      );
      expect(fitHours(early, null, noon), early);
      final past = DateTime(2026, 10, 27, 10);
      expect(fitHours(past, day, noon), past, reason: 'пора и окно открыто');
    });

    test('бэкап по расписанию — в разрешённые часы', () {
      final noon = DateTime(2026, 10, 27, 12);
      final s = AgentSettings(paths: ['/d'], hours: const BackupHours(1, 5));
      expect(
        nextScheduledBackup(s, AgentState(), now: noon),
        DateTime(2026, 10, 28, 1),
      );
      // Незаконченный бэкап тоже ждёт окна.
      expect(
        nextScheduledBackup(s, AgentState(interrupted: noon), now: noon),
        DateTime(2026, 10, 28, 1),
      );
    });

    test('проверка: через интервал после удачного бэкапа и проверки', () {
      final settings = AgentSettings(paths: ['/d']);
      expect(nextScheduledVerify(settings, AgentState()), isNull);
      final state = AgentState(lastOkBackupAt: t0);
      expect(
        nextScheduledVerify(settings, state),
        t0.add(const Duration(hours: 24)),
      );
      state.record('verify', record(JobOutcome.ok));
      expect(
        nextScheduledVerify(settings, state),
        t0.add(const Duration(hours: 24)),
      );
      expect(
        nextScheduledVerify(
          AgentSettings(paths: ['/d'], verifyIntervalHours: null),
          state,
        ),
        isNull,
      );
      state.interrupted = t0;
      expect(nextScheduledVerify(settings, state), isNull);
    });

    test('история: последние 100, удачный бэкап запоминается', () {
      final state = AgentState();
      for (var i = 0; i < 120; i++) {
        state.record(
          'backup',
          record(i.isEven ? JobOutcome.ok : JobOutcome.failed),
        );
      }
      expect(state.history, hasLength(AgentState.historyLimit));
      expect(state.lastBackup!.outcome, JobOutcome.failed);
      expect(state.lastOkBackupAt, t0.add(const Duration(minutes: 5)));
    });
  });

  group('здоровье', () {
    final settings = AgentSettings(paths: ['/d']);
    final now = t0.add(const Duration(hours: 1));

    HealthReport health(AgentState state) =>
        assessHealth(settings, state, now: now);

    JobRecord verify(Map<String, Object?> result) => JobRecord(
      startedAt: t0,
      finishedAt: t0,
      outcome: JobOutcome.ok,
      result: result,
    );

    test('нет бэкапа — неизвестно; удачный — в порядке', () {
      expect(health(AgentState()).state, HealthState.unknown);
      final ok = AgentState()..record('backup', record(JobOutcome.ok));
      final report = health(ok);
      expect(report.state, HealthState.ok);
      expect(report.reasons.single.code, 'never_verified');
    });

    test('требует внимания: бэкап не удался, давно не было, риск', () {
      final failed = AgentState()
        ..record('backup', record(JobOutcome.ok))
        ..record('backup', record(JobOutcome.failed));
      expect(health(failed).state, HealthState.attention);
      expect(health(failed).reasons.first.code, 'backup_failed');

      final stale = AgentState()..record('backup', record(JobOutcome.ok));
      final later = assessHealth(
        settings,
        stale,
        now: t0.add(const Duration(days: 3)),
      );
      expect(later.state, HealthState.attention);
      expect(later.reasons.first.code, 'backup_stale');

      for (final (result, code, state) in [
        ({'unrecoverable': 2}, 'unrecoverable', HealthState.attention),
        ({'atRisk': 1}, 'at_risk', HealthState.attention),
        // Не удалось связаться с узлами: проверка неполная, но это не
        // потеря данных и не повод для тревоги.
        ({'unchecked': 4}, 'verify_failed', HealthState.ok),
        ({'problems': 3}, 'fragments_missing', HealthState.ok),
      ]) {
        final s = AgentState()
          ..record('backup', record(JobOutcome.ok))
          ..record('verify', verify(result));
        expect(health(s).state, state, reason: code);
        expect(health(s).reasons.single.code, code);
      }
      final a = AgentState()
        ..record('backup', record(JobOutcome.ok))
        ..record('verify', verify({'atRisk': 1}));
      final b = AgentState()
        ..record('backup', record(JobOutcome.ok))
        ..record('verify', verify({'unrecoverable': 1}));
      expect(health(a).signature, isNot(health(b).signature));
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
      expect(defaults.excludePresets, ExcludePreset.defaults);
      expect(defaults.hours, isNull);
      expect(defaults.onlyOnAcPower, isFalse);
      final next = defaults.merge({
        'paths': ['/a', '/b'],
        'intervalMinutes': null,
        'excludePresets': ['development'],
        'hours': {'from': 22, 'to': 6},
        'onlyOnAcPower': true,
      })..save(file);
      final loaded = AgentSettings.load(file);
      expect(loaded.paths, ['/a', '/b']);
      expect(loaded.intervalMinutes, isNull);
      expect(loaded.excludePresets, [ExcludePreset.development]);
      expect(loaded.hours!.from, 22);
      expect(loaded.onlyOnAcPower, isTrue);
      expect(loaded.excludeRulesList, contains('node_modules/'));
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
        {
          'excludePresets': ['нет такого'],
        },
        {
          'hours': {'from': 5, 'to': 5},
        },
        {
          'hours': {'from': 24, 'to': 5},
        },
        {'onlyOnAcPower': 'да'},
        {'verifyIntervalHours': 0},
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
