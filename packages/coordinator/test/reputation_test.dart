// Формула репутации (задача 4.2.1; docs/spec/reputation.md): множители и
// поведение на синтетических историях узлов.

import 'dart:math';

import 'package:coordinator/coordinator.dart';
import 'package:test/test.dart';

const _day = Duration(days: 1);

/// История узла по дням: доступность, аудитов в сутки (новые узлы — 24,
/// старые — 4, как в `AuditPolicy`), доля провалов, время ответа.
final class _History {
  new({
    required this.availability,
    this.failureRate = 0,
    this.latency = const Duration(milliseconds: 300),
    this.failFrom = 0,
  });

  final double availability;

  /// Доля проваленных аудитов, начиная с дня [failFrom].
  final double failureRate;
  final int failFrom;
  final Duration latency;

  /// Репутация на конец дня [days] от регистрации.
  double after(int days, {Random? random}) {
    final r = random ?? Random(1);
    var passed = 0;
    var failed = 0;
    final recent = <bool>[];
    for (var d = 0; d < days; d++) {
      final audits = d < 7 ? 24 : 4;
      for (var i = 0; i < audits; i++) {
        final ok = d < failFrom || r.nextDouble() >= failureRate;
        ok ? passed++ : failed++;
        recent.add(ok);
        if (recent.length > 20) recent.removeAt(0);
      }
    }
    return Reputation.of(
      ReputationInput(
        availability: availability,
        age: _day * days,
        auditsPassed: passed,
        auditsFailed: failed,
        recentFailures: recent.where((ok) => !ok).length,
        auditLatency: latency,
      ),
    );
  }
}

void main() {
  group('множители', () {
    test('старый узел без провалов и с быстрыми ответами — A²', () {
      for (final a in [0.6, 0.8, 0.99, 1.0]) {
        final r = Reputation.of(
          ReputationInput(
            availability: a,
            age: const Duration(days: 90),
            auditsPassed: 500,
            auditLatency: const Duration(milliseconds: 200),
          ),
        );
        expect(r, closeTo(a * a, 1e-12));
      }
    });

    test('аудиты: сглаживание и степень', () {
      double p(int passed, int failed) => Reputation.auditFactor(
        ReputationInput(
          availability: 1,
          age: Duration.zero,
          auditsPassed: passed,
          auditsFailed: failed,
        ),
      );
      expect(p(0, 0), 1);
      // Один провал у нового узла: (10/11)^4.
      expect(p(0, 1), closeTo(pow(10 / 11, 4), 1e-12));
      expect(p(90, 10), closeTo(pow(100 / 110, 4), 1e-12));
      expect(p(1000, 0), 1);
    });

    test('свежие провалы старого узла не тонут в истории', () {
      double p(int recent) => Reputation.auditFactor(
        ReputationInput(
          availability: 1,
          age: Duration.zero,
          auditsPassed: 1000,
          auditsFailed: recent,
          recentFailures: recent,
        ),
      );
      expect(p(0), 1);
      expect(p(1), closeTo(pow(0.95, 4), 1e-12));
      expect(p(3), closeTo(pow(0.85, 4), 1e-12));
      expect(p(20), 0);
      expect(p(25), 0, reason: 'окно аудитов шире 20 — не меньше нуля');
    });

    test('возраст: от 0,25 до 1 за 30 дней', () {
      double g(Duration age) =>
          Reputation.ageFactor(ReputationInput(availability: 1, age: age));
      expect(g(Duration.zero), 0.25);
      expect(g(const Duration(days: 3)), closeTo(0.325, 1e-12));
      expect(g(const Duration(days: 15)), closeTo(0.625, 1e-12));
      expect(g(const Duration(days: 30)), 1);
      expect(g(const Duration(days: 400)), 1);
      // Часы координатора отстали от регистрации — не меньше минимума.
      expect(g(const Duration(days: -1)), 0.25);
    });

    test('скорость: 1 до 2 с, дальше 2 с / t, не ниже 0,25', () {
      double l(Duration? t) => Reputation.latencyFactor(
        ReputationInput(availability: 1, age: Duration.zero, auditLatency: t),
      );
      expect(l(null), 1);
      expect(l(const Duration(milliseconds: 50)), 1);
      expect(l(const Duration(seconds: 2)), 1);
      expect(l(const Duration(seconds: 4)), 0.5);
      expect(l(const Duration(seconds: 8)), 0.25);
      expect(l(const Duration(seconds: 10)), 0.25);
    });

    test('доступность вне 0–1 ограничивается', () {
      expect(
        Reputation.availabilityFactor(
          const ReputationInput(availability: 1.2, age: Duration.zero),
        ),
        1,
      );
      expect(
        Reputation.availabilityFactor(
          const ReputationInput(availability: -0.1, age: Duration.zero),
        ),
        0,
      );
    });
  });

  group('синтетические истории', () {
    final nas = _History(availability: 0.99);
    final homePc = _History(availability: 0.7);
    final slow = _History(
      availability: 0.99,
      latency: const Duration(seconds: 6),
    );
    final flaky = _History(availability: 0.99, failureRate: 0.03);
    final cheater = _History(
      availability: 0.99,
      failureRate: 0.5,
      failFrom: 30,
    );

    test('NAS через 60 дней — около 0,98, домашний ПК — около 0,49', () {
      expect(nas.after(60), closeTo(0.98, 0.01));
      expect(homePc.after(60), closeTo(0.49, 0.01));
    });

    test('новый узел набирает вес за 30 дней', () {
      final weights = [
        for (final d in [1, 3, 7, 15, 30, 60]) nas.after(d),
      ];
      for (var i = 1; i < weights.length; i++) {
        expect(weights[i], greaterThanOrEqualTo(weights[i - 1]));
      }
      expect(weights.first, lessThan(0.3));
      // После испытательного срока (3 дня) новый NAS всё ещё легче
      // старого домашнего ПК: проверенные узлы получают больше.
      expect(nas.after(3), lessThan(homePc.after(60)));
      expect(nas.after(30), closeTo(nas.after(60), 1e-9));
    });

    test('медленный, нестабильный и обманщик ниже честного NAS', () {
      final honest = nas.after(60);
      expect(slow.after(60), closeTo(honest / 3, 0.01));
      expect(flaky.after(60), allOf(lessThan(honest), greaterThan(0.85)));
      // Удалил половину фрагментов на 30-й день: к 35-му (20 аудитов
      // после удаления) вес заметно ниже, а исключение по окну аудитов
      // (4 из 20) наступает ещё раньше.
      expect(cheater.after(30), closeTo(honest, 1e-9));
      expect(cheater.after(35), lessThan(honest * 0.8));
      expect(cheater.after(60), lessThan(honest * 0.6));
    });

    test('новый узел на пороге доступности проходит порог репутации', () {
      final threshold = _History(availability: 0.6).after(0);
      expect(
        threshold,
        greaterThanOrEqualTo(const PlacementPolicy().minReputation),
      );
      // Новый узел, отвечающий за 8 с, — нет.
      final slowNew = _History(
        availability: 0.6,
        latency: const Duration(seconds: 8),
      ).after(0);
      expect(slowNew, lessThan(const PlacementPolicy().minReputation));
    });
  });
}
