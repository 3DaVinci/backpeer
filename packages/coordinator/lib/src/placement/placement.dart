import 'dart:math' as math;
import 'dart:typed_data';

import 'package:core/core.dart';

/// Узел-кандидат для размещения фрагмента.
final class NodeCandidate {
  const new({
    required this.nodeId,
    required this.ownerId,
    required this.subnet,
    required this.freeBytes,
    required this.availability,
    this.endpoints = const [],
    this.onProbation = false,
    this.reputation,
  });

  final Uint8List nodeId;

  /// Учётная запись владельца (`account_id` сертификата узла).
  final Uint8List ownerId;

  /// IPv4 /24 или IPv6 /48 (`NodeAddresses.subnetOf`).
  final String subnet;

  final int freeBytes;

  /// Доля интервалов в сети за 30 дней (`Uptime`).
  final double availability;

  /// Адреса `хост:порт`; пусто — узел за NAT.
  final List<String> endpoints;

  /// Узел зарегистрирован недавно (испытательный срок, модель угроз, С-6).
  final bool onProbation;

  /// Репутация (`Reputation.of`); `null` — по одной доступности, как у
  /// старого узла без провалов: A².
  final double? reputation;

  double get weight => reputation ?? availability * availability;
}

/// Подходящих узлов меньше n.
final class PlacementException implements Exception {
  const new({required this.needed, required this.found});

  final int needed;

  /// Сколько узлов удалось выбрать с соблюдением ограничений.
  final int found;

  @override
  String toString() =>
      'PlacementException: нужно $needed узлов, подходят $found';
}

/// Выбор n узлов для фрагментов сегмента (задачи 2.7.1, 4.2.2, 4.2.3;
/// protocol.md, раздел 5; durability.md, раздел 3).
///
/// Ограничения, которые не нарушаются никогда: узлы различны, их владельцы
/// различны, подсети различны, владелец сегмента своих фрагментов не
/// хранит, свободного места хватает на фрагмент, доступность не ниже
/// [minAvailability], репутация не ниже [minReputation], узлов на
/// испытательном сроке не больше заданного, и они получают только
/// фрагменты чётности (модель угроз, С-6: свежие подставные узлы не
/// соберут много фрагментов одного сегмента, а их уход не лишает сегмент
/// фрагментов данных). Среди подходящих узлов выбор случайный с весом —
/// репутацией ([NodeCandidate.weight], `docs/spec/reputation.md`): узлы с
/// высокой доступностью, без провалов аудитов, старые и быстрые получают
/// фрагменты чаще, а нагрузка расходится по всей сети, а не по нескольким
/// лучшим узлам.
///
/// Способ — последовательные взвешенные извлечения без возвращения: каждый
/// следующий узел выбирается среди ещё допустимых (владелец и подсеть не
/// заняты) с вероятностью, пропорциональной весу. Реализовано ключами
/// Эфраимидиса — Спиракиса: ключ узла `u^(1/w)`, `u` равномерно на (0, 1);
/// обход по убыванию ключа с пропуском конфликтующих узлов даёт то же
/// распределение за O(m log m).
final class Placement {
  new({
    this.minAvailability = defaultMinAvailability,
    this.minReputation = 0,
    math.Random? random,
  }) : _random = random ?? math.Random.secure();

  /// Порог доступности хранителя (`mvp-scope.md`).
  static const defaultMinAvailability = 0.6;

  final double minAvailability;
  final double minReputation;
  final math.Random _random;

  /// Узел подходит без учёта других выбранных узлов.
  bool eligible(
    NodeCandidate node, {
    required int fragmentSize,
    Uint8List? segmentOwner,
  }) =>
      node.availability >= minAvailability &&
      node.weight >= minReputation &&
      node.freeBytes >= fragmentSize &&
      (segmentOwner == null || !constantTimeEquals(node.ownerId, segmentOwner));

  /// [n] узлов из [candidates] по номерам фрагментов; узлов на
  /// испытательном сроке — не больше [maxProbation] (по умолчанию без
  /// предела), и при [parityFrom] они стоят на номерах не меньше его —
  /// фрагментах чётности (у Reed–Solomon первые k фрагментов — данные);
  /// без [distinctSubnets] подсети могут повторяться (только локальный
  /// стенд, `PlacementPolicy.distinctSubnets`). При ремонте (задача 4.3.4)
  /// часть фрагментов сегмента уже на узлах: [takenOwners] (hex) и
  /// [takenSubnets] заняты, узлы [excludedNodes] (hex) не выбираются. Не
  /// хватает подходящих — [PlacementException].
  List<NodeCandidate> choose(
    List<NodeCandidate> candidates, {
    required int n,
    required int fragmentSize,
    Uint8List? segmentOwner,
    int? maxProbation,
    int? parityFrom,
    bool distinctSubnets = true,
    Set<String> takenOwners = const {},
    Set<String> takenSubnets = const {},
    Set<String> excludedNodes = const {},
  }) {
    RangeError.checkValueInInterval(n, 1, 255, 'n');
    var probationLimit = maxProbation;
    if (parityFrom != null) {
      RangeError.checkValueInInterval(parityFrom, 0, n, 'parityFrom');
      final parity = n - parityFrom;
      if (probationLimit == null || probationLimit > parity) {
        probationLimit = parity;
      }
    }
    final keyed = <(double, NodeCandidate)>[];
    for (final node in candidates) {
      if (!eligible(
        node,
        fragmentSize: fragmentSize,
        segmentOwner: segmentOwner,
      )) {
        continue;
      }
      final w = node.weight;
      if (w <= 0) continue;
      // ln(u) / w — монотонно по u^(1/w), без потери точности при малых w.
      final u = 1 - _random.nextDouble(); // (0, 1]
      keyed.add((math.log(u) / w, node));
    }
    keyed.sort((a, b) => b.$1.compareTo(a.$1));
    final chosen = <NodeCandidate>[];
    final nodes = <String>{...excludedNodes};
    final owners = <String>{...takenOwners};
    final subnets = <String>{...takenSubnets};
    var probation = 0;
    for (final (_, node) in keyed) {
      if (!nodes.add(bytesToHex(node.nodeId))) continue;
      final owner = bytesToHex(node.ownerId);
      if (owners.contains(owner) ||
          (distinctSubnets && subnets.contains(node.subnet))) {
        continue;
      }
      if (node.onProbation) {
        if (probationLimit != null && probation >= probationLimit) continue;
        probation++;
      }
      owners.add(owner);
      subnets.add(node.subnet);
      chosen.add(node);
      if (chosen.length == n) {
        // Порядок выбора случаен; узлы на испытательном сроке — в конец,
        // на номера чётности.
        return [
          for (final c in chosen)
            if (!c.onProbation) c,
          for (final c in chosen)
            if (c.onProbation) c,
        ];
      }
    }
    throw PlacementException(needed: n, found: chosen.length);
  }
}
