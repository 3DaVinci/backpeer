// Модель надёжности (задача 0.3.6): таблицы для docs/spec/durability.md.
//
//   dart run tool/durability.dart
//
// Модель и допущения описаны в docs/spec/durability.md. Узлы считаются
// независимыми; коррелированные отказы ограничиваются правилами размещения.

import 'dart:io';
import 'dart:math';

const configs = [(10, 16), (10, 20), (10, 24), (10, 30), (20, 40)];
const availabilities = [0.5, 0.6, 0.7, 0.8, 0.9, 0.95];
const churnPerMonth = [0.03, 0.05, 0.10, 0.20];
const repairWindowDays =
    4.0; // 72 ч до признания фрагмента потерянным + сутки на ремонт
const segmentsPerTerabyte = 65536; // 1 ТБ / 16 МиБ

void main() {
  stdout
    ..writeln('## Доступность: P(в сети не меньше k из n)')
    ..writeln()
    ..writeln(
      '| k из n | n/k | ${availabilities.map((p) => 'p = $p').join(' | ')} |',
    )
    ..writeln('|---|---|${'---|' * availabilities.length}');
  for (final (k, n) in configs) {
    final cells = availabilities.map((p) => _fmt(_tail(n, p, k)));
    stdout.writeln('| $k из $n | ${_dec(n / k)} | ${cells.join(' | ')} |');
  }

  stdout
    ..writeln()
    ..writeln(
      '## Сохранность: ожидаемое число потерянных сегментов на 1 ТБ в год',
    )
    ..writeln()
    ..writeln('Окно ремонта ${_dec(repairWindowDays)} сут. t — порог ремонта.')
    ..writeln()
    ..writeln('| k из n | t | ${churnPerMonth.map(_churnHeader).join(' | ')} |')
    ..writeln('|---|---|${'---|' * churnPerMonth.length}');
  for (final (k, n) in configs) {
    for (var t = k + 2; t < n; t += 2) {
      if (t > k + 8) break;
      final cells = churnPerMonth.map(
        (c) => _sci(_annualLoss(k, n, t, c) * segmentsPerTerabyte),
      );
      stdout.writeln('| $k из $n | $t | ${cells.join(' | ')} |');
    }
  }

  stdout
    ..writeln()
    ..writeln('## Трафик ремонта: объём данных, перекачиваемый за год')
    ..writeln()
    ..writeln(
      'В объёмах хранимых данных (1,0 — столько же, сколько хранится). '
      'Один ремонт скачивает k фрагментов (сегмент целиком) и загружает n − t.',
    )
    ..writeln()
    ..writeln('| k из n | t | ${churnPerMonth.map(_churnHeader).join(' | ')} |')
    ..writeln('|---|---|${'---|' * churnPerMonth.length}');
  for (final (k, n) in configs.where((c) => c.$1 == 10)) {
    for (final t in [k + 4, k + 5, k + 6]) {
      if (t >= n) continue;
      final cells = churnPerMonth.map((c) {
        final perRepair = 1 + (n - t) / k;
        return _dec(_repairsPerYear(n, t, c) * perRepair);
      });
      stdout.writeln('| $k из $n | $t | ${cells.join(' | ')} |');
    }
  }
}

/// P(Bin(n, p) ≥ k).
double _tail(int n, double p, int k) {
  var sum = 0.0;
  for (var i = k; i <= n; i++) {
    sum += _choose(n, i) * pow(p, i) * pow(1 - p, n - i);
  }
  return sum;
}

double _choose(int n, int k) {
  var r = 1.0;
  for (var i = 1; i <= k; i++) {
    r = r * (n - k + i) / i;
  }
  return r;
}

/// Интенсивность ухода узла в сутки при доле ухода за месяц.
double _dailyRate(double monthly) => -log(1 - monthly) / 30;

/// Ремонтов сегмента в год: фрагменты теряются с суммарной интенсивностью
/// ≈ n·λ, ремонт запускается после каждых n − t потерь.
double _repairsPerYear(int n, int t, double monthly) =>
    n * _dailyRate(monthly) * 365 / (n - t);

/// Ожидаемое число потерь сегмента в год: ремонтов в год × вероятность, что
/// за окно ремонта из t оставшихся фрагментов уйдёт больше t − k.
double _annualLoss(int k, int n, int t, double monthly) {
  final q = 1 - exp(-_dailyRate(monthly) * repairWindowDays);
  return _repairsPerYear(n, t, monthly) * _tail(t, q, t - k + 1);
}

String _churnHeader(double c) => 'уход ${(c * 100).round()}%/мес';

String _dec(double x) => x.toStringAsFixed(1).replaceAll('.', ',');

String _fmt(double p) =>
    p > 0.999999 ? '> 0,999999' : p.toStringAsFixed(6).replaceAll('.', ',');

String _sci(double x) {
  if (x == 0) return '0';
  final e = (log(x) / ln10).floor();
  final m = x / pow(10, e);
  return '${m.toStringAsFixed(1).replaceAll('.', ',')}·10^$e';
}
