// Алгоритм размещения (задача 2.7.1): ограничения на синтетическом реестре
// из 1000 узлов и распределение нагрузки по весам.

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
      final total = nodes.map(Placement.weight).reduce((a, b) => a + b);
      for (var i = 0; i < nodes.length; i++) {
        final expected = Placement.weight(nodes[i]) / total;
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
  });
}
