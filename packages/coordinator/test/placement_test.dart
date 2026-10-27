// Алгоритм размещения (задачи 2.7.1, 4.2.2, 4.2.3): ограничения на
// синтетическом реестре из 1000 узлов, распределение нагрузки по весам,
// испытательный срок и репутация.

import 'dart:math';
import 'dart:typed_data';

import 'package:coordinator/coordinator.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

Uint8List _id(int i, [int tag = 0]) => Uint8List(32)
  ..[0] = tag
  ..buffer.asByteData().setUint32(1, i);

/// Реестр, похожий на настоящий: у части владельцев несколько узлов,
/// часть узлов делит подсеть (провайдер, общежитие), доступность от 0,3
/// до 1, у некоторых узлов мало места.
List<NodeCandidate> _registry(Random r, int size) => [
  for (var i = 0; i < size; i++)
    NodeCandidate(
      nodeId: _id(i),
      ownerId: _id(r.nextInt(size * 2 ~/ 3), 1),
      subnet: '10.${r.nextInt(4)}.${r.nextInt(150)}.0/24',
      freeBytes: r.nextInt(10) == 0 ? 1000 : 1 << 40,
      availability: 0.3 + 0.7 * r.nextDouble(),
    ),
];

void main() {
  group('Placement', () {
    test('на реестре из 1000 узлов ограничения не нарушаются', () {
      final r = Random(1);
      final registry = _registry(r, 1000);
      final placement = Placement(random: Random(2));
      const fragmentSize = 1 << 20;
      final used = <String, int>{};
      for (var s = 0; s < 2000; s++) {
        final owner = registry[r.nextInt(registry.length)].ownerId;
        final chosen = placement.choose(
          registry,
          n: 20,
          fragmentSize: fragmentSize,
          segmentOwner: owner,
        );
        expect(chosen, hasLength(20));
        expect(chosen.map((c) => bytesToHex(c.nodeId)).toSet(), hasLength(20));
        expect(
          chosen.map((c) => bytesToHex(c.ownerId)).toSet(),
          hasLength(20),
          reason: 'владельцы различны',
        );
        expect(
          chosen.map((c) => c.subnet).toSet(),
          hasLength(20),
          reason: 'подсети различны',
        );
        for (final c in chosen) {
          expect(constantTimeEquals(c.ownerId, owner), isFalse);
          expect(c.availability, greaterThanOrEqualTo(0.6));
          expect(c.freeBytes, greaterThanOrEqualTo(fragmentSize));
          used.update(bytesToHex(c.nodeId), (v) => v + 1, ifAbsent: () => 1);
        }
      }
      final eligible = registry.where(
        (c) => c.availability >= 0.6 && c.freeBytes >= fragmentSize,
      );
      expect(
        used.length,
        greaterThan(eligible.length * 0.95),
        reason: 'нагрузка расходится по всем подходящим узлам',
      );
    });

    test('доля выбора пропорциональна весу', () {
      // n = 1: узел выбирается с вероятностью w / Σw.
      final nodes = [
        for (var i = 0; i < 4; i++)
          NodeCandidate(
            nodeId: _id(i),
            ownerId: _id(i, 1),
            subnet: '10.0.$i.0/24',
            freeBytes: 1 << 30,
            availability: [0.6, 0.7, 0.85, 1.0][i],
          ),
      ];
      final placement = Placement(random: Random(3));
      final counts = List.filled(nodes.length, 0);
      const draws = 40000;
      for (var d = 0; d < draws; d++) {
        final c = placement.choose(nodes, n: 1, fragmentSize: 1).single;
        counts[c.nodeId.buffer.asByteData().getUint32(1)]++;
      }
      final total = nodes.map((c) => c.weight).reduce((a, b) => a + b);
      for (var i = 0; i < nodes.length; i++) {
        final expected = nodes[i].weight / total;
        expect(counts[i] / draws, closeTo(expected, 0.01), reason: 'узел $i');
      }
    });

    test('узлы с высокой доступностью получают фрагменты чаще', () {
      final nodes = [
        for (var i = 0; i < 200; i++)
          NodeCandidate(
            nodeId: _id(i),
            ownerId: _id(i, 1),
            subnet: '10.0.$i.0/24',
            freeBytes: 1 << 30,
            availability: i < 100 ? 0.65 : 0.99,
          ),
      ];
      final placement = Placement(random: Random(5));
      var low = 0;
      var high = 0;
      for (var s = 0; s < 3000; s++) {
        for (final c in placement.choose(nodes, n: 20, fragmentSize: 1)) {
          c.availability < 0.9 ? low++ : high++;
        }
      }
      // Без возвращения перекос меньше отношения весов (2,3), но заметен.
      expect(high / low, inInclusiveRange(1.8, 2.4));
    });

    test('подходящих узлов меньше n — PlacementException', () {
      final nodes = [
        for (var i = 0; i < 25; i++)
          NodeCandidate(
            nodeId: _id(i),
            ownerId: _id(i % 15, 1),
            subnet: '10.0.$i.0/24',
            freeBytes: 1 << 30,
            availability: 1,
          ),
      ];
      expect(
        () => Placement().choose(nodes, n: 20, fragmentSize: 1),
        throwsA(isA<PlacementException>().having((e) => e.found, 'found', 15)),
        reason: 'владельцев всего 15',
      );
      expect(
        () => Placement().choose(nodes, n: 10, fragmentSize: 1 << 31),
        throwsA(isA<PlacementException>()),
        reason: 'места не хватает',
      );
    });

    test('без distinctSubnets подсеть может повторяться', () {
      final nodes = [
        for (var i = 0; i < 20; i++)
          NodeCandidate(
            nodeId: _id(i),
            ownerId: _id(i, 1),
            subnet: '127.0.0.0/24',
            freeBytes: 1 << 30,
            availability: 1,
          ),
      ];
      expect(
        () => Placement().choose(nodes, n: 20, fragmentSize: 1),
        throwsA(isA<PlacementException>().having((e) => e.found, 'found', 1)),
      );
      expect(
        Placement().choose(
          nodes,
          n: 20,
          fragmentSize: 1,
          distinctSubnets: false,
        ),
        hasLength(20),
      );
    });
  });

  group('репутация и испытательный срок', () {
    /// Реестр с историями: возраст до 90 дней (каждый пятый узел — на
    /// испытательном сроке), у части узлов провалы аудитов и медленные
    /// ответы; вес — `Reputation.of`.
    List<NodeCandidate> registry(Random r, int size) => [
      for (var i = 0; i < size; i++)
        () {
          final probation = i % 5 == 0;
          final age = probation
              ? Duration(hours: r.nextInt(72))
              : Duration(days: 3 + r.nextInt(87));
          final audits = age.inHours ~/ 6;
          final failed = r.nextInt(10) == 0 ? r.nextInt(audits ~/ 4 + 1) : 0;
          final input = ReputationInput(
            availability: 0.6 + 0.4 * r.nextDouble(),
            age: age,
            auditsPassed: audits - failed,
            auditsFailed: failed,
            recentFailures: min(failed, 3),
            auditLatency: Duration(
              milliseconds: 100 + r.nextInt(r.nextInt(4) == 0 ? 9000 : 1000),
            ),
          );
          return NodeCandidate(
            nodeId: _id(i),
            ownerId: _id(i, 1),
            subnet: '10.${i ~/ 250}.${i % 250}.0/24',
            freeBytes: 1 << 40,
            availability: input.availability,
            onProbation: probation,
            reputation: Reputation.of(input),
          );
        }(),
    ];

    test('новые узлы — не больше доли сегмента и только на чётности', () {
      final r = Random(11);
      final nodes = registry(r, 1000);
      const policy = PlacementPolicy();
      final placement = Placement(
        minReputation: policy.minReputation,
        random: Random(12),
      );
      final counts = <String, int>{};
      for (var s = 0; s < 2000; s++) {
        final chosen = placement.choose(
          nodes,
          n: 20,
          fragmentSize: 1,
          maxProbation: policy.maxProbation(20, 10),
          parityFrom: 10,
        );
        expect(chosen, hasLength(20));
        final probation = [
          for (var i = 0; i < 20; i++)
            if (chosen[i].onProbation) i,
        ];
        expect(probation.length, lessThanOrEqualTo(5));
        expect(probation.every((i) => i >= 10), isTrue, reason: '$probation');
        for (final c in chosen) {
          expect(c.weight, greaterThanOrEqualTo(policy.minReputation));
          counts.update(bytesToHex(c.nodeId), (v) => v + 1, ifAbsent: () => 1);
        }
      }
      // Вес — репутация: верхняя четверть узлов по репутации получает
      // фрагменты заметно чаще нижней.
      final eligible =
          nodes.where((c) => c.weight >= policy.minReputation).toList()
            ..sort((a, b) => a.weight.compareTo(b.weight));
      int share(Iterable<NodeCandidate> part) =>
          part.fold(0, (sum, c) => sum + (counts[bytesToHex(c.nodeId)] ?? 0));
      final quarter = eligible.length ~/ 4;
      final low = share(eligible.take(quarter));
      final high = share(eligible.skip(eligible.length - quarter));
      expect(high, greaterThan(low * 3));
      expect(
        nodes.where((c) => c.weight < policy.minReputation),
        isNotEmpty,
        reason: 'в реестре есть узлы ниже порога',
      );
    });

    test('новых узлов не больше числа фрагментов чётности', () {
      final nodes = [
        for (var i = 0; i < 40; i++)
          NodeCandidate(
            nodeId: _id(i),
            ownerId: _id(i, 1),
            subnet: '10.0.$i.0/24',
            freeBytes: 1 << 30,
            availability: 1,
            onProbation: i >= 18,
            reputation: i >= 18 ? 1 : 0.01,
          ),
      ];
      final placement = Placement(random: Random(13));
      for (var s = 0; s < 200; s++) {
        final chosen = placement.choose(
          nodes,
          n: 20,
          fragmentSize: 1,
          maxProbation: 5,
          parityFrom: 18,
        );
        expect(chosen.take(18).any((c) => c.onProbation), isFalse);
        expect(chosen.where((c) => c.onProbation), hasLength(2));
      }
      expect(const PlacementPolicy().maxProbation(20, 18), 2);
      expect(const PlacementPolicy().maxProbation(20, 10), 5);
    });

    test('узел ниже порога репутации не выбирается', () {
      final nodes = [
        for (var i = 0; i < 21; i++)
          NodeCandidate(
            nodeId: _id(i),
            ownerId: _id(i, 1),
            subnet: '10.0.$i.0/24',
            freeBytes: 1 << 30,
            availability: 1,
            reputation: i == 0 ? 0.04 : 0.5,
          ),
      ];
      final placement = Placement(minReputation: 0.05, random: Random(14));
      for (var s = 0; s < 100; s++) {
        final chosen = placement.choose(nodes, n: 20, fragmentSize: 1);
        expect(chosen.map((c) => c.nodeId[4]), isNot(contains(0)));
      }
      expect(
        () => placement.choose(nodes.take(20).toList(), n: 20, fragmentSize: 1),
        throwsA(isA<PlacementException>()),
      );
    });

    test('Sybil (С-6): 20 узлов одного владельца — один фрагмент сегмента', () {
      // Предел узлов на учётную запись — nodes.max_per_account (20): больше
      // одна учётная запись не зарегистрирует. Узлы атакующего — лучшие в
      // сети, в разных подсетях.
      final nodes = [
        for (var i = 0; i < 200; i++)
          NodeCandidate(
            nodeId: _id(i),
            ownerId: _id(i, 1),
            subnet: '10.0.$i.0/24',
            freeBytes: 1 << 30,
            availability: 0.8,
            reputation: Reputation.of(
              ReputationInput(
                availability: 0.8,
                age: Duration(days: 3 + i % 60),
              ),
            ),
          ),
        for (var i = 0; i < const NodePolicy().maxPerAccount; i++)
          NodeCandidate(
            nodeId: _id(i, 2),
            ownerId: _id(0, 3),
            subnet: '10.1.$i.0/24',
            freeBytes: 1 << 30,
            availability: 1,
            reputation: 1,
          ),
      ];
      final placement = Placement(random: Random(15));
      var withAttacker = 0;
      for (var s = 0; s < 2000; s++) {
        final chosen = placement.choose(nodes, n: 20, fragmentSize: 1);
        final attacker = chosen.where((c) => c.ownerId[0] == 3).length;
        expect(attacker, lessThanOrEqualTo(1));
        withAttacker += attacker;
      }
      // Один фрагмент из 20 — меньше k = 10 при любом числе сегментов.
      expect(withAttacker, greaterThan(0));
    });
  });
}
