import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:coordinator/src/db/database.dart';
import 'package:coordinator/src/economy/economy_policy.dart';
import 'package:coordinator/src/nodes/uptime.dart';
import 'package:coordinator/src/rpc/call_context.dart';
import 'package:coordinator/src/rpc/errors.dart';
import 'package:core/core.dart';
import 'package:fixnum/fixnum.dart';
import 'package:postgres/postgres.dart';
import 'package:protocol/protocol.dart' as pb;

/// Состояние квоты учётной записи для API и проверок размещения.
final class EconomyQuota {
  const new({
    required this.dataBytes,
    required this.reservedBytes,
    required this.capacityBytes,
    required this.barterBytes,
    required this.balanceMicro,
    required this.maxBytes,
    required this.billableBytes,
    required this.monthlyCostMicro,
    required this.dailyCostMicro,
    required this.earnedMicro,
    required this.spentMicro,
    required this.entries,
    required this.negativeSince,
    required this.graceDays,
    required this.blocked,
    required this.repairBytes,
    required this.repairCostMicro,
    required this.repairWindowDays,
  });

  final int dataBytes;
  final int reservedBytes;
  final int capacityBytes;
  final int barterBytes;
  final int balanceMicro;
  final int maxBytes;
  final int billableBytes;
  final int monthlyCostMicro;
  final int dailyCostMicro;
  final int earnedMicro;
  final int spentMicro;
  final List<EconomyEntry> entries;

  /// С какого дня баланс непрерывно отрицательный; null — долга нет.
  final DateTime? negativeSince;
  final int graceDays;

  /// Новые размещения запрещены: долг длится дольше льготного периода.
  final bool blocked;

  /// Трафик ремонта на узлах учётной записи за [repairWindowDays] суток и
  /// его цена по тарифу хранителя — справочно: отдельно не списывается.
  final int repairBytes;
  final int repairCostMicro;
  final int repairWindowDays;
}

final class EconomyEntry {
  const new({
    required this.amountMicro,
    required this.kind,
    required this.at,
    required this.note,
  });

  final int amountMicro;
  final String kind;
  final DateTime at;
  final String note;
}

/// Бартерная экономика (этап 7): бартерная квота по объявленной ёмкости,
/// кредиты за занятые фрагменты и ежедневное списание за хранение.
///
/// Правила (docs/spec/economy.md):
/// - бесплатная квота = объявленная ёмкость / 2,5;
/// - хранитель получает кредиты только за занятые фрагменты, с весом
///   доступности и доли пройденных аудитов;
/// - данные сверх бесплатной квоты списываются по 1200 CR за ТБ·мес;
/// - новых данных больше, чем покрывает квота и баланс, размещать нельзя
///   (`QUOTA_EXCEEDED`); уже сохранённые данные не удаляются;
/// - при отрицательном балансе действует льготный период: пока он идёт,
///   новые данные в пределах бесплатной квоты разрешены, после — запрещены
///   (задача 7.3.2).
final class EconomyService {
  new(
    this._db, {
    this.policy = const EconomyPolicy(),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Database _db;
  final EconomyPolicy policy;
  final DateTime Function() _clock;
  Timer? _timer;

  /// Ежедневный расчёт в 00:00 UTC; после простоя догоняет пропущенные дни.
  void start() {
    _schedule();
  }

  void _schedule() {
    final now = _clock().toUtc();
    final next = DateTime.utc(now.year, now.month, now.day + 1);
    _timer = Timer(next.difference(now), () async {
      try {
        await catchUp();
      } on Object {
        // Следующий запуск повторит: economy_runs не отметил день.
      }
      _schedule();
    });
  }

  Future<void> close() async {
    _timer?.cancel();
    _timer = null;
  }

  /// Квота учётной записи без HTTP-контекста (тесты и внутренние вызовы).
  Future<EconomyQuota> quota(Uint8List accountId) =>
      _db.transaction((tx) => _quotaInTx(tx, accountId));

  Future<pb.GetQuotaResponse> getQuota(
    CallContext context,
    pb.GetQuotaRequest request,
  ) async {
    // Догоняем пропущенные дни при первом обращении: координатор мог
    // простоять ночью.
    await catchUp();
    final accountId = _account(context);
    final quota = await _db.transaction((tx) => _quotaInTx(tx, accountId));
    return _response(quota);
  }

  /// Проверка перед новым размещением или объектом. Вызывается под
  /// блокировкой учётной записи, чтобы одновременные запросы не обошли
  /// квоту.
  Future<void> checkCanStore(
    TxSession tx,
    Uint8List accountId,
    int additionalBytes,
  ) async {
    if (additionalBytes <= 0) return;
    final quota = await _quotaInTx(tx, accountId);
    if (quota.blocked) {
      throw RpcException(
        pb.ErrorCode.ERROR_CODE_QUOTA_EXCEEDED,
        'баланс отрицательный дольше ${quota.graceDays} дн.: новые данные '
        'запрещены, сохранённые данные не удаляются; включите хранитель '
        'или освободите место',
      );
    }
    if (quota.reservedBytes + additionalBytes > quota.maxBytes) {
      throw RpcException(
        pb.ErrorCode.ERROR_CODE_QUOTA_EXCEEDED,
        'квота исчерпана: занято ${quota.reservedBytes} Б, '
        'доступно ${quota.maxBytes} Б',
      );
    }
  }

  /// Один день начислений и списаний. Идемпотентно: повторный вызов за
  /// тот же день ничего не меняет.
  Future<void> runDay(DateTime at) async {
    final day = DateTime.utc(at.year, at.month, at.day);
    await _db.transaction((tx) async {
      final started = await tx.execute(
        Sql.named(
          'INSERT INTO economy_runs (day) VALUES (@d:date) '
          'ON CONFLICT (day) DO NOTHING RETURNING day',
        ),
        parameters: {'d': day},
      );
      if (started.isEmpty) return;

      final accounts = await tx.execute('SELECT account_id FROM accounts');
      for (final row in accounts) {
        final accountId = Uint8List.fromList(row[0]! as List<int>);
        await _ensureAccount(tx, accountId);
        final before = await _usageInTx(tx, accountId);
        final billable = max(0, before.dataBytes - before.barterBytes);
        final charge =
            policy.dataCostMicro(billable) ~/ EconomyPolicy.daysPerMonth;
        if (charge > 0) {
          await _addEntry(
            tx,
            accountId,
            kind: 'storage_charge',
            amountMicro: -charge,
            day: day,
            ref: 'storage',
            note: 'хранение $billable Б сверх квоты',
          );
        }
      }

      // Кредиты хранителям — одним запросом по всем узлам. Доступность
      // считаем по heartbeat за 30 дней, а не по последнему значению в
      // nodes.availability: узел, который замолчал, не должен получать
      // полный кредит до истечения 72 часов. Нет строк uptime (тесты и
      // узел без единого heartbeat) — берём сохранённое значение.
      final now = _clock().toUtc();
      final uptimeRows = await tx.execute(
        Sql.named(
          'SELECT node_id, day, slots FROM node_uptime WHERE day >= @d:int4',
        ),
        parameters: {'d': Uptime.dayOf(Uptime.slotAt(now)) - Uptime.windowDays},
      );
      final uptime = <String, Map<int, Uint8List>>{};
      for (final row in uptimeRows) {
        final id = bytesToHex(Uint8List.fromList(row[0]! as List<int>));
        (uptime[id] ??= {})[row[1]! as int] = Uint8List.fromList(
          row[2]! as List<int>,
        );
      }

      final nodes = await tx.execute('''
        SELECT n.account_id, n.node_id, n.availability, n.registered_at,
               n.audits_passed, n.audits_failed, n.audit_window_failures,
               coalesce(sum(g.fragment_size), 0)::bigint AS bytes
          FROM nodes n
          JOIN fragments f ON f.node_id = n.node_id
            AND f.stored AND f.damaged_at IS NULL
          JOIN segments g ON g.account_id = f.account_id
            AND g.segment_id = f.segment_id AND g.state >= 1
         WHERE n.removed_at IS NULL
           AND n.excluded_at IS NULL
           AND n.lost_at IS NULL
         GROUP BY n.account_id, n.node_id, n.availability,
                  n.registered_at, n.audits_passed, n.audits_failed,
                  n.audit_window_failures
      ''');
      for (final row in nodes) {
        final accountId = Uint8List.fromList(row[0]! as List<int>);
        final nodeId = Uint8List.fromList(row[1]! as List<int>);
        final storedAvailability = (row[2]! as num).toDouble();
        final registeredAt = row[3]! as DateTime;
        final passed = row[4]! as int;
        final failed = row[5]! as int;
        final windowFailures = row[6]! as int;
        final bytes = row[7]! as int;
        final days = uptime[bytesToHex(nodeId)];
        final availability =
            (days == null
                    ? storedAvailability
                    : Uptime.availability(
                        days,
                        registeredAt: registeredAt,
                        now: now,
                      ))
                .clamp(0.0, 1.0);
        if (bytes == 0) continue;
        final audit = min(
          (passed + 10) / (passed + failed + 10),
          1 - windowFailures / 20,
        ).clamp(0.0, 1.0);
        final credit =
            (policy.storeCostMicro(bytes) *
                    availability *
                    audit /
                    EconomyPolicy.daysPerMonth)
                .round();
        if (credit <= 0) continue;
        await _addEntry(
          tx,
          accountId,
          kind: 'storage_credit',
          amountMicro: credit,
          day: day,
          ref: bytesToHex(nodeId),
          note:
              'фрагменты $bytes Б, доступность '
              '${availability.toStringAsFixed(2)}',
        );
      }

      // Льготный период при долге (задача 7.3.2): отметка ставится в день,
      // когда баланс стал отрицательным, и снимается, когда долг закрыт.
      // Считаем после всех проводок дня: кредит хранителя может закрыть долг.
      await tx.execute(
        Sql.named('''
          UPDATE credit_accounts
             SET negative_since = CASE
                   WHEN balance_mc < 0 THEN coalesce(negative_since, @d)
                   ELSE NULL
                 END,
                 updated_at = now()
           WHERE (balance_mc < 0 AND negative_since IS NULL)
              OR (balance_mc >= 0 AND negative_since IS NOT NULL)'''),
        parameters: {'d': day},
      );

      await tx.execute(
        Sql.named(
          'UPDATE economy_runs SET completed_at = now() WHERE day = @d:date',
        ),
        parameters: {'d': day},
      );
    });
  }

  /// Запускает расчёт за вчера и все пропущенные дни после последнего
  /// завершённого. Ошибки не валят координатор: следующий запуск повторит.
  Future<void> catchUp() async {
    final now = _clock().toUtc();
    final today = DateTime.utc(now.year, now.month, now.day);
    final rows = await _db.run(
      (s) => s.execute('SELECT max(day) FROM economy_runs'),
    );
    final last = rows.single.single as DateTime?;
    var day = last == null
        ? today.subtract(const Duration(days: 1))
        : DateTime.utc(
            last.year,
            last.month,
            last.day,
          ).add(const Duration(days: 1));
    while (day.isBefore(today)) {
      await runDay(day);
      day = day.add(const Duration(days: 1));
    }
  }

  pb.GetQuotaResponse _response(EconomyQuota q) => pb.GetQuotaResponse(
    dataBytes: Int64(q.dataBytes),
    capacityBytes: Int64(q.capacityBytes),
    barterBytes: Int64(q.barterBytes),
    balanceMc: Int64(q.balanceMicro),
    maxBytes: Int64(q.maxBytes),
    billableBytes: Int64(q.billableBytes),
    monthlyCostMc: Int64(q.monthlyCostMicro),
    dailyCostMc: Int64(q.dailyCostMicro),
    earnedMc: Int64(q.earnedMicro),
    spentMc: Int64(q.spentMicro),
    entries: [
      for (final e in q.entries)
        pb.QuotaEntry(
          amountMc: Int64(e.amountMicro),
          kind: e.kind,
          atUnixMs: Int64(e.at.millisecondsSinceEpoch),
          note: e.note,
        ),
    ],
    negativeSinceUnixMs: Int64(q.negativeSince?.millisecondsSinceEpoch ?? 0),
    graceDays: q.graceDays,
    blocked: q.blocked,
    repairBytes: Int64(q.repairBytes),
    repairCostMc: Int64(q.repairCostMicro),
    repairWindowDays: q.repairWindowDays,
  );

  Future<EconomyQuota> _quotaInTx(TxSession tx, Uint8List accountId) async {
    await _ensureAccount(tx, accountId);
    final usage = await _usageInTx(tx, accountId);
    final state = await _accountStateInTx(tx, accountId);
    final balance = state.balance;
    final totals = await tx.execute(
      Sql.named('''
        SELECT coalesce(sum(amount_mc) FILTER (WHERE amount_mc > 0), 0)::int8,
               coalesce(sum(-amount_mc) FILTER (WHERE amount_mc < 0), 0)::int8
          FROM credit_ledger WHERE account_id = @a:bytea'''),
      parameters: {'a': accountId},
    );
    final history = await tx.execute(
      Sql.named('''
        SELECT amount_mc, kind, day, note FROM credit_ledger
          WHERE account_id = @a:bytea ORDER BY id DESC LIMIT @n:int4'''),
      parameters: {'a': accountId, 'n': policy.historyLimit},
    );
    final repair = await _repairTrafficInTx(tx, accountId);
    final available = max(0, balance);
    final maxBytes = usage.barterBytes + policy.bytesForMicro(available);
    final billable = max(0, usage.dataBytes - usage.barterBytes);
    final monthly = policy.dataCostMicro(billable);
    final daily = monthly ~/ EconomyPolicy.daysPerMonth;
    return EconomyQuota(
      dataBytes: usage.dataBytes,
      reservedBytes: usage.reservedBytes,
      capacityBytes: usage.capacityBytes,
      barterBytes: usage.barterBytes,
      balanceMicro: balance,
      maxBytes: maxBytes,
      billableBytes: billable,
      monthlyCostMicro: monthly,
      dailyCostMicro: daily,
      earnedMicro: totals.single[0]! as int,
      spentMicro: totals.single[1]! as int,
      entries: [
        for (final row in history)
          EconomyEntry(
            amountMicro: row[0]! as int,
            kind: row[1]! as String,
            at: row[2]! as DateTime,
            note: (row[3] as String?) ?? '',
          ),
      ],
      negativeSince: state.negativeSince,
      graceDays: policy.graceDays,
      blocked: _isBlocked(balance, state.negativeSince),
      repairBytes: repair.bytes,
      repairCostMicro: policy.storeCostMicro(repair.bytes),
      repairWindowDays: policy.repairWindowDays,
    );
  }

  /// Долг дольше льготного периода: новые размещения запрещены.
  bool _isBlocked(int balance, DateTime? negativeSince) {
    if (balance >= 0 || negativeSince == null) return false;
    final until = negativeSince.toUtc().add(Duration(days: policy.graceDays));
    return !_clock().toUtc().isBefore(until);
  }

  /// Трафик ремонта на узлах учётной записи за окно (задача 7.4.3): он уже
  /// учтён в тарифе хранителя и отдельно не списывается, но виден в балансе.
  Future<({int bytes})> _repairTrafficInTx(
    TxSession tx,
    Uint8List accountId,
  ) async {
    final since = _clock().toUtc().subtract(
      Duration(days: policy.repairWindowDays),
    );
    final rows = await tx.execute(
      Sql.named('''
        SELECT coalesce(sum(j.bytes_downloaded + j.bytes_uploaded), 0)::int8
          FROM repair_jobs j
         WHERE j.executor IN (SELECT n.node_id FROM nodes n
                               WHERE n.account_id = @a:bytea)
           AND j.state IN (1, 2, 3)
           AND coalesce(j.finished_at, j.reported_at, j.created_at)
               >= @since:timestamptz'''),
      parameters: {'a': accountId, 'since': since},
    );
    return (bytes: rows.single.single! as int);
  }

  Future<_Usage> _usageInTx(TxSession tx, Uint8List accountId) async {
    final rows = await tx.execute(
      Sql.named('''
        SELECT
          coalesce((SELECT sum(s.k::bigint * s.fragment_size)
                      FROM segments s
                     WHERE s.account_id = @a:bytea AND s.state >= 1), 0)::int8,
          coalesce((SELECT sum(s.k::bigint * s.fragment_size)
                      FROM segments s
                     WHERE s.account_id = @a:bytea), 0)::int8,
          coalesce((SELECT a.object_bytes FROM accounts a
                     WHERE a.account_id = @a:bytea), 0)::int8,
          coalesce((SELECT sum(n.capacity_bytes) FROM nodes n
                     WHERE n.account_id = @a:bytea
                       AND n.removed_at IS NULL), 0)::int8'''),
      parameters: {'a': accountId},
    );
    final data = rows.single[0]! as int;
    final reserved = rows.single[1]! as int;
    final objects = rows.single[2]! as int;
    final capacity = rows.single[3]! as int;
    return _Usage(
      dataBytes: data + objects,
      reservedBytes: reserved + objects,
      capacityBytes: capacity,
      barterBytes: policy.barterBytes(capacity),
    );
  }

  Future<({int balance, DateTime? negativeSince})> _accountStateInTx(
    TxSession tx,
    Uint8List accountId,
  ) async {
    final rows = await tx.execute(
      Sql.named(
        'SELECT balance_mc, negative_since FROM credit_accounts '
        'WHERE account_id = @a:bytea',
      ),
      parameters: {'a': accountId},
    );
    if (rows.isEmpty) return (balance: 0, negativeSince: null);
    return (
      balance: rows.single[0]! as int,
      negativeSince: rows.single[1] as DateTime?,
    );
  }

  Future<void> _ensureAccount(TxSession tx, Uint8List accountId) async {
    final inserted = await tx.execute(
      Sql.named('''
        INSERT INTO credit_accounts (account_id, balance_mc)
        VALUES (@a:bytea, 0)
        ON CONFLICT (account_id) DO NOTHING
        RETURNING account_id'''),
      parameters: {'a': accountId},
    );
    if (inserted.isEmpty) return;
    final day = _date(_clock());
    await _addEntry(
      tx,
      accountId,
      kind: 'starter',
      amountMicro: policy.toMicro(policy.starterCredits),
      day: day,
      ref: 'starter',
      note: 'стартовый грант ${policy.starterCredits} CR',
    );
  }

  Future<void> _addEntry(
    TxSession tx,
    Uint8List accountId, {
    required String kind,
    required int amountMicro,
    required DateTime day,
    required String ref,
    required String note,
  }) async {
    if (amountMicro == 0) return;
    final inserted = await tx.execute(
      Sql.named('''
        INSERT INTO credit_ledger
          (account_id, kind, amount_mc, day, ref, note)
        VALUES (@a:bytea, @k:text, @m:int8, @d:date, @r:text, @n:text)
        ON CONFLICT (account_id, kind, day, ref) DO NOTHING
        RETURNING id'''),
      parameters: {
        'a': accountId,
        'k': kind,
        'm': amountMicro,
        'd': day,
        'r': ref,
        'n': note,
      },
    );
    if (inserted.isEmpty) return;
    await tx.execute(
      Sql.named('''
        UPDATE credit_accounts
          SET balance_mc = balance_mc + @m:int8, updated_at = now()
          WHERE account_id = @a:bytea'''),
      parameters: {'a': accountId, 'm': amountMicro},
    );
  }

  static DateTime _date(DateTime at) => DateTime.utc(at.year, at.month, at.day);

  static Uint8List _account(CallContext context) =>
      context.caller!.info!.accountId;
}

final class _Usage {
  const new({
    required this.dataBytes,
    required this.reservedBytes,
    required this.capacityBytes,
    required this.barterBytes,
  });

  final int dataBytes;
  final int reservedBytes;
  final int capacityBytes;
  final int barterBytes;
}
