// Экономика кредитов (этап 7): таблицы для docs/spec/economy.md.
//
//   dart run tool/economy.dart
//
// Модель, допущения и выводы — в docs/spec/economy.md. Все суммы в кредитах
// (CR) и рублях; 1 CR = 0,5 ₽, прайс — 1200 CR за ТБ·мес данных, 1 ТБ = 1000 ГБ.
// Плата за зарезервированное место не входит в модель: свободное место не оплачивается.
// Стоимость диска и электричества — допущения ноября 2026 года: HDD 40 000 ₽
// за 8 ТБ, аренда VPS — до 1000 ₽ за ТБ·мес (20 узлов по 1 ТБ на VPS).

// Длинные строки — это строки таблиц Markdown; переносить их нельзя.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';
import 'dart:math';

// --- Надёжность (docs/spec/durability.md) ---------------------------------

const k = 10;
const n = 20;

/// Перерасход места: n/k плюс 1,5 % на заголовки и выравнивание сегментов.
const double amplification = n / k * 1.015;

// --- Тарифы базового сценария ---------------------------------------------

/// Рублёвая опора кредита: 1 CR = 0,5 ₽ (1000 CR = 500 ₽).
const crRub = 0.5;

/// Цена хранения для клиента, CR за ТБ данных в месяц.
const pData = 1200.0;

/// Плата хранителю за занятое чужими фрагментами место, CR за ТБ·мес.
const pStore = 400.0;

// --- Себестоимость хранителя ---------------------------------------------

/// 8 ТБ за 40 000 ₽ — 5000 ₽ за ТБ.
const diskRubPerTb = 5000.0;
const diskLifeMonths = 60;
const double diskAmortization = diskRubPerTb / diskLifeMonths; // 83,3 ₽
const electricityRubPerKwh = 10.64;

/// 6,5 Вт на диск 8 ТБ — 0,81 Вт на ТБ.
const double diskWattPerTb = 6.5 / 8;
const hoursPerMonth = 730;
const double diskElectricity =
    diskWattPerTb * hoursPerMonth / 1000 * electricityRubPerKwh; // 6,3 ₽
const double replacementReserve = diskAmortization * 0.10; // 8,3 ₽
const double marginalCostPerTb =
    diskAmortization + diskElectricity + replacementReserve; // 98,0 ₽

/// Трафик ремонта: 12,8 объёма хранимого в год (стенд 4.6.4, уход 5 %/мес).
const repairTrafficPerYear = 12.8;

/// Доля трафика ремонта через relay и цена relay-трафика.
const relayShare = 0.10;
const relayRubPerTb = 300.0;

/// Платёжные издержки на покупку кредитов.
const paymentFee = 0.02;

/// Аренда ёмкости на зарубежном VPS: до 1000 ₽ за ТБ·мес.
const vpsRubPerTbMonth = 1000.0;

/// Один VPS — 20 узлов по 1 ТБ; аренда 20 000 ₽/мес.
const vpsNodes = 20;
const vpsNodeTb = 1.0;
const vpsAvailability = 0.99;
const double vpsRent = vpsRubPerTbMonth * vpsNodes * vpsNodeTb;

// --- Население сети --------------------------------------------------------

class Profile {
  const new(
    this.name,
    this.accounts,
    this.dataPerAccount,
    this.nodesPerAccount,
    this.capacityPerNode,
    this.availability,
    this.hostWatts,
  );

  final String name;
  final int accounts;
  final double dataPerAccount;
  final int nodesPerAccount;
  final double capacityPerNode;
  final double availability;
  final double hostWatts;

  double get hostCost =>
      hostWatts * hoursPerMonth / 1000 * electricityRubPerKwh;
}

const population = [
  Profile('Только клиент, дом', 480, 0.5, 0, 0, 0, 0),
  Profile('Только клиент, бизнес', 20, 2, 0, 0, 0, 0),
  Profile('Клиент и ПК-хранитель', 330, 0.3, 1, 2, 0.70, 40),
  Profile('Клиент и NAS-хранитель', 140, 1, 1, 8, 0.95, 25),
  Profile('Только хранитель (seed)', 30, 0, 2, 16, 0.99, 60),
];

class Node {
  new(this.profile, this.capacity);

  final Profile profile;
  double capacity;
  double used = 0;

  double get weight => profile.availability * profile.availability * capacity;
}

class Network {
  new(this.dataTb, this.nodes, this.accountScale);

  final double dataTb;
  final List<Node> nodes;
  final double accountScale;

  double get fragments => dataTb * amplification;
  double get capacity => nodes.fold<double>(0, (s, x) => s + x.capacity);
  double get utilization => fragments / capacity;

  double payoutPerNode(Node node) {
    return node.profile.availability * pStore * node.used;
  }

  double get charges => dataTb * pData;
  double get payouts => nodes.fold<double>(0, (s, x) => s + payoutPerNode(x));

  /// Раскладывает фрагменты по узлам пропорционально A²·ёмкости, не больше
  /// ёмкости; остаток от переполненных узлов достаётся остальным.
  void place() {
    for (final node in nodes) {
      node.used = 0;
    }
    var remaining = fragments;
    for (var round = 0; round < 20 && remaining > 1e-9; round++) {
      final free = nodes.where((x) => x.used < x.capacity - 1e-9).toList();
      if (free.isEmpty) break;
      final totalWeight = free.fold<double>(0, (s, x) => s + x.weight);
      if (totalWeight <= 0) break;
      for (final node in free) {
        final share = remaining * node.weight / totalWeight;
        node.used = min(node.capacity, node.used + share);
      }
      remaining = fragments - nodes.fold<double>(0, (s, x) => s + x.used);
    }
  }
}

Network buildNetwork({double capacityScale = 1.0, double accountScale = 1.0}) {
  final data = population.fold<double>(
    0,
    (s, p) => s + p.accounts * accountScale * p.dataPerAccount,
  );
  final nodes = <Node>[];
  for (final p in population) {
    final count = (p.accounts * accountScale).round();
    for (var i = 0; i < count * p.nodesPerAccount; i++) {
      nodes.add(Node(p, p.capacityPerNode * capacityScale));
    }
  }
  final network = Network(data, nodes, accountScale)..place();
  return network;
}

// --- Печать -----------------------------------------------------------------

String num2(double x, {int digits = 0}) {
  final s = x.toStringAsFixed(digits).replaceAll('.', ',');
  final parts = s.split(',');
  final sign = parts.first.startsWith('-') ? '-' : '';
  final intPart = parts.first.replaceFirst('-', '');
  final grouped = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) grouped.write(' ');
    grouped.write(intPart[i]);
  }
  return '$sign$grouped${parts.length > 1 ? ',${parts[1]}' : ''}';
}

String rub(double credits) => num2(credits * crRub);

void main() {
  final base = buildNetwork();
  _costs();
  _tariffs(base);
  _keepers(base);
  _clients();
  _network(base);
  _operator(base);
  _sensitivity();
  _withdrawals(base);
  _breakEven(base);
  _beta();
  _vps();
}

void _costs() {
  stdout
    ..writeln('## Себестоимость хранения у хранителя')
    ..writeln()
    ..writeln(
      '| Занято на узле, ТБ | Диск | Электричество диска | Износ | Хост 40 Вт | Полная, ₽/ТБ·мес | Приростная, ₽/ТБ·мес |',
    )
    ..writeln('|---|---|---|---|---|---|---|');
  for (final used in [1.0, 2.0, 4.0, 8.0, 16.0]) {
    const host = 40 * hoursPerMonth / 1000 * electricityRubPerKwh;
    final full = marginalCostPerTb + host / used;
    stdout.writeln(
      '| ${num2(used)} | ${num2(diskAmortization, digits: 1)} | '
      '${num2(diskElectricity, digits: 1)} | ${num2(replacementReserve, digits: 1)} | '
      '${num2(host / used, digits: 1)} | ${num2(full)} | ${num2(marginalCostPerTb)} |',
    );
  }
  stdout
    ..writeln()
    ..writeln(
      'Трафик ремонта: ${num2(repairTrafficPerYear, digits: 1)} объёма данных в год — '
      '${num2(repairTrafficPerYear / 12, digits: 2)} ТБ на ТБ данных в месяц '
      '(${num2(repairTrafficPerYear / 12 / amplification, digits: 2)} ТБ на ТБ фрагментов). '
      'Домашний безлимитный канал — 0 ₽; relay — ${num2(relayRubPerTb)} ₽/ТБ '
      'при доле ${num2(relayShare * 100)} %.',
    )
    ..writeln();
}

void _tariffs(Network network) {
  stdout
    ..writeln('## Тарифы базового сценария')
    ..writeln()
    ..writeln('| Параметр | Значение | В рублях |')
    ..writeln('|---|---|---|')
    ..writeln(
      '| Клиент: хранение данных | ${num2(pData)} CR/ТБ·мес | ${num2(pData * crRub)} ₽ |',
    )
    ..writeln(
      '| Хранитель: занятые фрагменты | ${num2(pStore)} CR/ТБ·мес | ${num2(pStore * crRub)} ₽ |',
    )
    ..writeln('| Плата за ёмкость | 0 CR/ТБ·мес | 0 ₽ |')
    ..writeln('| Перерасход места | ${num2(amplification, digits: 2)} | — |')
    ..writeln('| Опора кредита | 1 CR | ${num2(crRub, digits: 2)} ₽ |')
    ..writeln(
      '| Занятость сети | ${num2(network.utilization * 100, digits: 1)} % | — |',
    )
    ..writeln();
}

void _keepers(Network network) {
  final byProfile = <String, List<Node>>{};
  for (final node in network.nodes) {
    byProfile.putIfAbsent(node.profile.name, () => []).add(node);
  }
  stdout
    ..writeln('## Заработок хранителя')
    ..writeln()
    ..writeln(
      '| Профиль | Ёмкость, ТБ | Занято, ТБ | Занятость | Доступность | Кредит/мес | ₽/мес | Полная себестоимость | Приростная | Итог, полная | Итог, приростная |',
    )
    ..writeln('|---|---|---|---|---|---|---|---|---|---|---|');
  for (final p in population.where((p) => p.nodesPerAccount > 0)) {
    final nodes = byProfile[p.name]!;
    final used = nodes.fold<double>(0, (s, x) => s + x.used) / nodes.length;
    final payout =
        nodes.fold<double>(0, (s, x) => s + network.payoutPerNode(x)) /
        nodes.length;
    final full = used * marginalCostPerTb + p.hostCost;
    final marginal = used * marginalCostPerTb;
    stdout.writeln(
      '| ${p.name} | ${num2(p.capacityPerNode)} | ${num2(used, digits: 2)} | '
      '${num2(used / p.capacityPerNode * 100)} % | ${num2(p.availability, digits: 2)} | '
      '${num2(payout)} | ${num2(payout * crRub)} | ${num2(full)} | ${num2(marginal)} | '
      '${num2(payout * crRub - full)} | ${num2(payout * crRub - marginal)} |',
    );
  }
  stdout.writeln();
}

void _clients() {
  stdout
    ..writeln('## Счёт клиента')
    ..writeln()
    ..writeln('| Данные, ТБ | CR/мес | ₽/мес | ₽/год | ₽/ТБ·мес |')
    ..writeln('|---|---|---|---|---|');
  for (final tb in [0.1, 0.5, 1.0, 2.0, 5.0]) {
    final credits = tb * pData;
    stdout.writeln(
      '| ${num2(tb, digits: 1)} | ${num2(credits)} | ${num2(credits * crRub)} | '
      '${num2(credits * crRub * 12)} | ${num2(pData * crRub)} |',
    );
  }
  stdout.writeln();
}

void _network(Network network) {
  final byProfile = <String, List<Node>>{};
  for (final node in network.nodes) {
    byProfile.putIfAbsent(node.profile.name, () => []).add(node);
  }
  stdout
    ..writeln('## Баланс сети (1000 учётных записей)')
    ..writeln()
    ..writeln(
      '| Профиль | Учётных записей | Данные, ТБ | Списание, CR/мес | Начисление, CR/мес | Итог, CR/мес | Итог, ₽/мес |',
    )
    ..writeln('|---|---|---|---|---|---|---|');
  var charges = 0.0;
  var payouts = 0.0;
  for (final p in population) {
    final charge = p.accounts * p.dataPerAccount * pData;
    final nodes = byProfile[p.name] ?? const <Node>[];
    final payout = nodes.isEmpty
        ? 0.0
        : nodes.fold<double>(0, (s, x) => s + network.payoutPerNode(x)) /
              nodes.length *
              p.accounts *
              p.nodesPerAccount;
    charges += charge;
    payouts += payout;
    stdout.writeln(
      '| ${p.name} | ${p.accounts} | ${num2(p.accounts * p.dataPerAccount, digits: 1)} | '
      '${num2(charge)} | ${num2(payout)} | ${num2(payout - charge)} | '
      '${num2((payout - charge) * crRub)} |',
    );
  }
  final gross = charges - payouts;
  stdout
    ..writeln(
      '| **Итого** | **1000** | **${num2(network.dataTb, digits: 1)}** | '
      '**${num2(charges)}** | **${num2(payouts)}** | **${num2(gross)}** | '
      '**${num2(gross * crRub)}** |',
    )
    ..writeln()
    ..writeln(
      'Фрагментов: ${num2(network.fragments)} ТБ; ёмкость: '
      '${num2(network.capacity)} ТБ; занятость: '
      '${num2(network.utilization * 100, digits: 1)} %.',
    )
    ..writeln(
      'Валовая маржа: ${num2(gross)} CR (${num2(gross * crRub)} ₽), '
      '${num2(gross / charges * 100, digits: 1)} % выручки.',
    )
    ..writeln();
}

/// Чистый поток по профилю: начислено минус списано, CR/мес.
Map<String, double> profileNet(Network network) {
  final byName = <String, List<Node>>{};
  for (final node in network.nodes) {
    byName.putIfAbsent(node.profile.name, () => []).add(node);
  }
  final result = <String, double>{};
  for (final p in population) {
    final accounts = p.accounts * network.accountScale;
    final nodes = byName[p.name] ?? const <Node>[];
    final payout = nodes.isEmpty
        ? 0.0
        : nodes.fold<double>(0, (s, x) => s + network.payoutPerNode(x)) /
              nodes.length *
              accounts *
              p.nodesPerAccount;
    result[p.name] = payout - accounts * p.dataPerAccount * pData;
  }
  return result;
}

void _operator(Network network) {
  final net = profileNet(network);
  final purchases = net.values
      .where((x) => x < 0)
      .fold<double>(0, (s, x) => s - x);
  final withdrawalsThirdParty = net.entries
      .where((e) => e.value > 0 && e.key != 'Только хранитель (seed)')
      .fold<double>(0, (s, e) => s + e.value);
  final seedPayout = net['Только хранитель (seed)']!;
  final seedCapacity = network.nodes
      .where((x) => x.profile.name == 'Только хранитель (seed)')
      .fold<double>(0, (s, x) => s + x.capacity);
  final seedHosting = network.nodes
      .where((x) => x.profile.name == 'Только хранитель (seed)')
      .fold<double>(
        0,
        (s, x) => s + x.capacity * marginalCostPerTb + x.profile.hostCost,
      );
  final fees = network.charges * paymentFee;
  final relay =
      network.dataTb *
      repairTrafficPerYear /
      12 *
      relayShare *
      relayRubPerTb /
      crRub;
  final ownSeeds =
      (purchases - withdrawalsThirdParty - fees - relay) * crRub - seedHosting;
  final foreignSeeds =
      (purchases - withdrawalsThirdParty - seedPayout - fees - relay) * crRub;

  stdout
    ..writeln('## Деньги оператора')
    ..writeln()
    ..writeln('| Поток | CR/мес | ₽/мес |')
    ..writeln('|---|---|---|')
    ..writeln(
      '| Покупка кредитов клиентами (отрицательный баланс) | ${num2(purchases)} | ${num2(purchases * crRub)} |',
    )
    ..writeln(
      '| Вывод заработанных кредитов сторонними хранителями | ${num2(withdrawalsThirdParty)} | ${num2(withdrawalsThirdParty * crRub)} |',
    )
    ..writeln(
      '| Платёжные издержки, 2 % | ${num2(fees)} | ${num2(fees * crRub)} |',
    )
    ..writeln(
      '| Relay-трафик ремонта | ${num2(relay)} | ${num2(relay * crRub)} |',
    )
    ..writeln()
    ..writeln(
      '| Итог до постоянных затрат | seed-узлы свои | seed-узлы чужие |',
    )
    ..writeln('|---|---|---|')
    ..writeln(
      '| Выплаты seed-узлам | 0 (внутренние) | ${num2(seedPayout * crRub)} ₽ |',
    )
    ..writeln('| Хостинг seed-узлов | ${num2(seedHosting)} ₽ | 0 |')
    ..writeln(
      '| **Маржа** | **${num2(ownSeeds)} ₽** | **${num2(foreignSeeds)} ₽** |',
    )
    ..writeln()
    ..writeln(
      'Кредиты seed-узлов (${num2(seedPayout)} CR) оператор не выкупает у себя; '
      'ёмкость seed-узлов ${num2(seedCapacity)} ТБ, '
      'их хостинг ${num2(seedHosting)} ₽/мес. Разница двух колонок '
      '(${num2(ownSeeds - foreignSeeds)} ₽) — вклад seed-узлов сверх их хостинга.',
    )
    ..writeln();
}

void _sensitivity() {
  const relayPerTbData =
      repairTrafficPerYear / 12 * relayShare * relayRubPerTb / crRub;
  stdout
    ..writeln('## Чувствительность')
    ..writeln()
    ..writeln(
      'Выплата хранителям и маржа на 1 ТБ данных, ₽; доступность — средняя по занятому месту.',
    )
    ..writeln()
    ..writeln(
      '| pStore, CR | Доступность 0,70 | 0,85 | 0,95 | Маржа при 0,85, % |',
    )
    ..writeln('|---|---|---|---|---|');
  for (final store in [300.0, 400.0, 500.0]) {
    final cells = <String>[];
    for (final a in [0.70, 0.85, 0.95]) {
      final payout = amplification * store * a;
      cells.add(num2(payout * crRub));
    }
    final payout = amplification * store * 0.85;
    final margin = (pData - payout) / pData * 100;
    stdout.writeln(
      '| ${num2(store)} | ${cells.join(' | ')} | ${num2(margin, digits: 1)} % |',
    );
  }
  stdout
    ..writeln()
    ..writeln('Валовая маржа при разной цене для клиента и плате хранителю, %:')
    ..writeln()
    ..writeln('| Цена, CR/ТБ | ₽/ТБ | pStore 300 | pStore 400 |')
    ..writeln('|---|---|---|---|');
  for (final price in [900.0, 1000.0, 1200.0]) {
    final cells = <String>[];
    for (final store in [300.0, 400.0]) {
      final payout = amplification * store * 0.85;
      final margin =
          (price - payout - relayPerTbData - price * paymentFee) / price * 100;
      cells.add('${num2(margin, digits: 1)} %');
    }
    stdout.writeln(
      '| ${num2(price)} | ${num2(price * crRub)} | ${cells.join(' | ')} |',
    );
  }
  stdout
    ..writeln()
    ..writeln(
      '| Занятость | Нужно ёмкости на 1 ТБ данных, ТБ | Отношение «ёмкость : данные» |',
    )
    ..writeln('|---|---|---|');
  for (final u in [0.4, 0.6, 0.8, 1.0]) {
    final capacityPerTb = amplification / u;
    stdout.writeln(
      '| ${num2(u * 100)} % | ${num2(capacityPerTb, digits: 2)} | '
      '${num2(capacityPerTb, digits: 1)} : 1 |',
    );
  }
  stdout.writeln();
}

void _withdrawals(Network network) {
  final net = profileNet(network);
  final monthly = net.entries
      .where((e) => e.value > 0 && e.key != 'Только хранитель (seed)')
      .fold<double>(0, (s, e) => s + e.value * crRub);
  stdout
    ..writeln('## Вывод кредитов и обеспечение')
    ..writeln()
    ..writeln('| Показатель | Значение |')
    ..writeln('|---|---|')
    ..writeln('| Выплаты сторонним хранителям за месяц | ${num2(monthly)} ₽ |')
    ..writeln('| Срок удержания заработанных кредитов | 30 дней |')
    ..writeln(
      '| Максимальный вывод за месяц (одна месячная выплата) | ${num2(monthly)} ₽ |',
    )
    ..writeln(
      '| Денежный запас на два месяца выплат | ${num2(monthly * 2)} ₽ |',
    )
    ..writeln(
      '| «Набег»: одновременный вывод 20 % накопленного за 3 месяца | ${num2(monthly * 3 * 0.2)} ₽ |',
    )
    ..writeln();
}

void _breakEven(Network network) {
  const payoutPerTbData = amplification * pStore * 0.85;
  const relayPerTbData =
      repairTrafficPerYear / 12 * relayShare * relayRubPerTb / crRub;
  const feePerTbData = pData * paymentFee;
  const contribution =
      (pData - payoutPerTbData - relayPerTbData - feePerTbData) * crRub;
  stdout
    ..writeln('## Точка безубыточности')
    ..writeln()
    ..writeln('| Слагаемое | ₽ на 1 ТБ данных в месяц |')
    ..writeln('|---|---|')
    ..writeln('| Выручка | ${num2(pData * crRub)} |')
    ..writeln('| Выплаты хранителям | ${num2(payoutPerTbData * crRub)} |')
    ..writeln('| Relay-трафик | ${num2(relayPerTbData * crRub)} |')
    ..writeln('| Платёжные издержки | ${num2(feePerTbData * crRub)} |')
    ..writeln('| **Вклад на покрытие** | **${num2(contribution)}** |')
    ..writeln()
    ..writeln(
      '| Постоянные затраты, ₽/мес | Нужно данных, ТБ | Нужно учётных записей |',
    )
    ..writeln('|---|---|---|');
  for (final fixed in [30000.0, 90000.0]) {
    stdout.writeln(
      '| ${num2(fixed)} | ${num2(fixed / contribution)} | '
      '${num2(fixed / contribution / (network.dataTb / 1000))} |',
    );
  }
  stdout.writeln();
}

void _beta() {
  final beta = buildNetwork(accountScale: 0.2);
  final gross = beta.charges - beta.payouts;
  final byName = <String, List<Node>>{};
  for (final node in beta.nodes) {
    byName.putIfAbsent(node.profile.name, () => []).add(node);
  }
  final home = byName['Клиент и ПК-хранитель']!;
  final homePayout =
      home.fold<double>(0, (s, x) => s + beta.payoutPerNode(x)) / home.length;
  stdout
    ..writeln('## Бета: 200 учётных записей')
    ..writeln()
    ..writeln('| Показатель | Значение |')
    ..writeln('|---|---|')
    ..writeln('| Данных | ${num2(beta.dataTb, digits: 1)} ТБ |')
    ..writeln('| Ёмкость | ${num2(beta.capacity)} ТБ |')
    ..writeln('| Занятость | ${num2(beta.utilization * 100, digits: 1)} % |')
    ..writeln(
      '| Списано | ${num2(beta.charges)} CR (${num2(beta.charges * crRub)} ₽) |',
    )
    ..writeln(
      '| Начислено | ${num2(beta.payouts)} CR (${num2(beta.payouts * crRub)} ₽) |',
    )
    ..writeln(
      '| Валовая маржа | ${num2(gross)} CR (${num2(gross * crRub)} ₽) |',
    )
    ..writeln(
      '| Средний ПК-хранитель | ${num2(homePayout)} CR (${num2(homePayout * crRub)} ₽) |',
    )
    ..writeln();
}

void _vps() {
  const relayPerTbData =
      repairTrafficPerYear / 12 * relayShare * relayRubPerTb / crRub;
  const pStoreBreakEven =
      vpsRent / crRub / (vpsNodes * vpsAvailability * vpsNodeTb);
  const pDataBreakEven =
      (amplification * pStoreBreakEven * vpsAvailability + relayPerTbData) /
      (1 - paymentFee);
  const hddFull8 =
      marginalCostPerTb + 40 * hoursPerMonth / 1000 * electricityRubPerKwh / 8;

  stdout
    ..writeln('## Аренда ёмкости на VPS')
    ..writeln()
    ..writeln(
      'Один VPS: $vpsNodes узлов по ${num2(vpsNodeTb)} ТБ, доступность '
      '${num2(vpsAvailability, digits: 2)}, аренда ${num2(vpsRent)} ₽/мес '
      '(${num2(vpsRubPerTbMonth)} ₽ за ТБ·мес).',
    )
    ..writeln()
    ..writeln(
      '| Занятость узла | Доход узла, CR/мес | Доход VPS, ₽/мес | Аренда, ₽/мес | Итог, ₽/мес |',
    )
    ..writeln('|---|---|---|---|---|');
  for (final u in [0.4, 0.6, 0.8, 1.0]) {
    final payoutNode = vpsAvailability * pStore * u;
    final payoutVps = vpsNodes * payoutNode * crRub;
    stdout.writeln(
      '| ${num2(u * 100)} % | ${num2(payoutNode)} | ${num2(payoutVps)} | '
      '${num2(vpsRent)} | ${num2(payoutVps - vpsRent)} |',
    );
  }
  stdout
    ..writeln()
    ..writeln('| Чтобы VPS окупился | Значение |')
    ..writeln('|---|---|')
    ..writeln(
      '| Плата за занятые фрагменты | ${num2(pStoreBreakEven)} CR/ТБ·мес '
      '(${num2(pStoreBreakEven * crRub)} ₽) |',
    )
    ..writeln(
      '| Цена хранения для клиента | ${num2(pDataBreakEven)} CR/ТБ·мес '
      '(${num2(pDataBreakEven * crRub)} ₽) |',
    )
    ..writeln(
      '| Во сколько раз дороже текущей цены | '
      '${num2(pDataBreakEven / pData, digits: 1)}× |',
    )
    ..writeln()
    ..writeln('| Вариант ёмкости | ₽/ТБ·мес | Что входит |')
    ..writeln('|---|---|---|')
    ..writeln(
      '| HDD 8 ТБ за 40 000 ₽, 60 мес | ${num2(diskAmortization, digits: 1)} | только диск |',
    )
    ..writeln(
      '| HDD, приростная себестоимость | ${num2(marginalCostPerTb, digits: 1)} | диск, электричество, износ |',
    )
    ..writeln(
      '| HDD, полная при 8 ТБ занятости | ${num2(hddFull8, digits: 1)} | плюс хост 40 Вт |',
    )
    ..writeln(
      '| VPS, аренда | ${num2(vpsRubPerTbMonth)} | без своего диска и хоста |',
    )
    ..writeln(
      '| VPS / HDD, приростная | ${num2(vpsRubPerTbMonth / marginalCostPerTb, digits: 1)}× | — |',
    )
    ..writeln();
}
