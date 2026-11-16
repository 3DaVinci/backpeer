// Крайние случаи бартерной экономики (этап 7, задачи 7.3.2, 7.4.1–7.4.3):
// льготный период при долге, штрафы за аудиты и простои, защита от накрутки,
// трафик ремонта. Нужен FS_TEST_POSTGRES.
import 'dart:typed_data';

import 'package:coordinator/coordinator.dart';
import 'package:postgres/postgres.dart';
import 'package:protocol/protocol.dart' as pb;
import 'package:test/test.dart';

import 'support/postgres.dart';

void main() {
  test('долг: льготный период, затем запрет новых данных', () async {
    final testDb = await TestDatabase.create();
    addTearDown(testDb.drop);
    final db = Database.open(testDb.config);
    addTearDown(db.close);
    await Migrator(db).migrate();

    // Должник без своих узлов: 1 ГБ данных, бесплатной квоты нет, списание
    // 0,04 CR в день сразу уводит баланс в минус.
    final debtor = _id(1);
    await _account(db, debtor);
    await _segment(db, debtor, _id(10), k: 10, fragmentSize: 100000000);
    // Хранитель с 25 ГБ ёмкости (квота 10 ГБ) и 20 ГБ данных: 10 ГБ сверх
    // квоты, 0,4 CR в день. Позже он освобождает место и проверяет льготу.
    final keeper = _id(2);
    await _account(db, keeper);
    await _node(db, keeper, _id(20), capacity: 25000000000, availability: 0);
    final keeperSegment = _id(11);
    await _segment(db, keeper, keeperSegment, k: 10, fragmentSize: 2000000000);

    final economy = EconomyService(
      db,
      policy: const EconomyPolicy(starterCredits: 0),
      clock: () => DateTime.utc(2026, 11, 1, 12),
    );
    await economy.runDay(DateTime.utc(2026, 11));
    final first = await economy.quota(debtor);
    expect(first.balanceMicro, -40000);
    expect(first.negativeSince, DateTime.utc(2026, 11));
    expect(first.blocked, isFalse);

    final keeperFirst = await economy.quota(keeper);
    expect(keeperFirst.balanceMicro, -400000);
    expect(keeperFirst.negativeSince, DateTime.utc(2026, 11));

    // Хранитель освобождает место: долг остаётся, данные других не тронуты.
    await db.run(
      (s) => s.execute(
        Sql.named('''
          DELETE FROM segments
           WHERE account_id = @a:bytea AND segment_id = @g:bytea'''),
        parameters: {'a': keeper, 'g': keeperSegment},
      ),
    );

    // День 3: отметка остаётся днём начала долга, а не сдвигается.
    await economy.runDay(DateTime.utc(2026, 11, 2));
    await economy.runDay(DateTime.utc(2026, 11, 3));
    final third = await economy.quota(debtor);
    expect(third.negativeSince, DateTime.utc(2026, 11));
    expect(third.balanceMicro, -120000);
    expect(third.dataBytes, 1000000000);

    // В льготный период новые данные в пределах бесплатной квоты проходят.
    await db.transaction((tx) => economy.checkCanStore(tx, keeper, 1000000000));

    // Через 7 дней долга (день 8) новые размещения запрещены.
    final blocked = EconomyService(
      db,
      policy: const EconomyPolicy(starterCredits: 0),
      clock: () => DateTime.utc(2026, 11, 8, 12),
    );
    final afterGrace = await blocked.quota(debtor);
    expect(afterGrace.blocked, isTrue);
    expect(afterGrace.dataBytes, 1000000000, reason: 'данные не удаляются');
    await expectLater(
      db.transaction((tx) => blocked.checkCanStore(tx, debtor, 1)),
      throwsA(
        isA<RpcException>().having(
          (e) => e.message,
          'message',
          contains('новые данные запрещены'),
        ),
      ),
    );

    // Последний день льготы (день 7) ещё разрешает данные в пределах квоты.
    final lastGrace = EconomyService(
      db,
      policy: const EconomyPolicy(starterCredits: 0),
      clock: () => DateTime.utc(2026, 11, 7, 12),
    );
    expect((await lastGrace.quota(keeper)).blocked, isFalse);
    await db.transaction((tx) => lastGrace.checkCanStore(tx, keeper, 1));

    // GetQuota отдаёт то же состояние.
    final api = await blocked.getQuota(
      CallContext(
        method: 'GetQuota',
        requestId: 'test',
        caller: Caller(
          publicKey: _id(1),
          info: KeyInfo(kind: KeyKind.account, accountId: debtor),
        ),
      ),
      pb.GetQuotaRequest(),
    );
    expect(api.blocked, isTrue);
    expect(api.graceDays, 7);
    expect(
      api.negativeSinceUnixMs.toInt(),
      DateTime.utc(2026, 11).millisecondsSinceEpoch,
    );
  }, skip: skipWithoutPostgres);

  test('аудиты и простои: кредит падает и возвращается', () async {
    final testDb = await TestDatabase.create();
    addTearDown(testDb.drop);
    final db = Database.open(testDb.config);
    addTearDown(db.close);
    await Migrator(db).migrate();

    final account = _id(1);
    await _account(db, account);
    // У хранителя три узла; у каждого свой клиент с одинаковым сегментом,
    // поэтому разница в кредите — только доступность и аудиты.
    final reliable = _id(20);
    final poor = _id(21);
    final excluded = _id(22);
    await _node(db, account, reliable, capacity: 2500000000, availability: 1);
    await _node(db, account, poor, capacity: 2500000000, availability: 0.5);
    await _node(db, account, excluded, capacity: 2500000000, availability: 1);
    await db.run(
      (s) => s.execute(
        Sql.named(
          'UPDATE nodes SET excluded_at = now(), excluded_reason = @r:text '
          'WHERE node_id = @n:bytea',
        ),
        parameters: {'n': excluded, 'r': 'тест'},
      ),
    );
    final placements = {reliable: 2, poor: 3, excluded: 4};
    for (final entry in placements.entries) {
      final client = _id(entry.value);
      await _account(db, client);
      final segment = _id(10 + entry.value);
      await _segment(db, client, segment, k: 10, fragmentSize: 100000000);
      await _fragments(db, client, segment, entry.key);
    }

    final economy = EconomyService(db);
    await economy.runDay(DateTime.utc(2026, 11));
    final credit = await _credit(db, account, reliable, DateTime.utc(2026, 11));
    final half = await _credit(db, account, poor, DateTime.utc(2026, 11));
    expect(credit, greaterThan(0));
    expect(half, lessThan(credit));
    expect(half, closeTo((credit * 0.5).round(), 1));
    expect(
      await _credit(db, account, excluded, DateTime.utc(2026, 11)),
      0,
      reason: 'исключённый узел не зарабатывает',
    );

    // Провалы аудитов в окне снижают кредит: 4 из 20 — множитель 0,8.
    await db.run(
      (s) => s.execute(
        Sql.named(
          'UPDATE nodes SET audit_window_failures = 4 WHERE node_id = @n:bytea',
        ),
        parameters: {'n': reliable},
      ),
    );
    await economy.runDay(DateTime.utc(2026, 11, 2));
    final penalized = await _credit(
      db,
      account,
      reliable,
      DateTime.utc(2026, 11, 2),
    );
    expect(penalized, lessThan(credit));
    expect(penalized, closeTo((credit * 0.8).round(), 1));

    // Восстановление: провалы ушли, доступность выросла — кредит вернулся.
    await db.run(
      (s) => s.execute(
        Sql.named('''
          UPDATE nodes SET audit_window_failures = 0, availability = 1
           WHERE node_id = @n:bytea'''),
        parameters: {'n': poor},
      ),
    );
    await economy.runDay(DateTime.utc(2026, 11, 3));
    expect(await _credit(db, account, poor, DateTime.utc(2026, 11, 3)), credit);
  }, skip: skipWithoutPostgres);

  test('накрутка: ёмкость без фрагментов не даёт кредитов', () async {
    final testDb = await TestDatabase.create();
    addTearDown(testDb.drop);
    final db = Database.open(testDb.config);
    addTearDown(db.close);
    await Migrator(db).migrate();

    final account = _id(1);
    await _account(db, account);
    // Огромная ёмкость и пустой узел: кредит только стартовый, не за место.
    await _node(db, account, _id(20), capacity: 1000000000000, availability: 1);
    // Размещённый, но не подтверждённый сегмент тоже не считается занятым.
    await _segment(
      db,
      account,
      _id(10),
      k: 10,
      fragmentSize: 100000000,
      state: 0,
    );

    final economy = EconomyService(db);
    await economy.runDay(DateTime.utc(2026, 11));
    final q = await economy.quota(account);
    expect(q.dataBytes, 0);
    expect(q.barterBytes, 400000000000);
    expect(q.balanceMicro, 600000000);
    expect(q.entries.map((e) => e.kind), ['starter']);
    expect(q.entries.single.note, contains('стартовый грант'));
  }, skip: skipWithoutPostgres);

  test(
    'простой снижает кредит по heartbeat, а не по последнему значению',
    () async {
      final testDb = await TestDatabase.create();
      addTearDown(testDb.drop);
      final db = Database.open(testDb.config);
      addTearDown(db.close);
      await Migrator(db).migrate();

      final account = _id(1);
      await _account(db, account);
      final busy = _id(20);
      final idle = _id(21);
      await _node(db, account, busy, capacity: 2500000000, availability: 1);
      await _node(db, account, idle, capacity: 2500000000, availability: 1);
      // Оба узла «в сети» по последнему значению, но у busy heartbeat только
      // половину окна.
      final now = DateTime.utc(2026, 11, 1, 12);
      await db.run(
        (s) => s.execute(
          Sql.named(
            'UPDATE nodes SET registered_at = @t:timestamptz '
            'WHERE node_id = @n:bytea',
          ),
          parameters: {'n': busy, 't': DateTime.utc(2026, 11)},
        ),
      );
      final slots = Uint8List(12);
      for (var i = 0; i < 24; i++) {
        slots[i >> 3] |= 1 << (i & 7);
      }
      await db.run(
        (s) => s.execute(
          Sql.named('''
          INSERT INTO node_uptime (node_id, day, slots)
          VALUES (@n:bytea, @d:int4, @s:bytea)'''),
          parameters: {
            'n': busy,
            'd': Uptime.dayOf(Uptime.slotAt(now)),
            's': slots,
          },
        ),
      );
      for (final entry in {busy: 2, idle: 3}.entries) {
        final client = _id(entry.value);
        await _account(db, client);
        final segment = _id(10 + entry.value);
        await _segment(db, client, segment, k: 10, fragmentSize: 100000000);
        await _fragments(db, client, segment, entry.key);
      }

      final economy = EconomyService(db, clock: () => now);
      await economy.runDay(DateTime.utc(2026, 11));
      final busyCredit = await _credit(
        db,
        account,
        busy,
        DateTime.utc(2026, 11),
      );
      final idleCredit = await _credit(
        db,
        account,
        idle,
        DateTime.utc(2026, 11),
      );
      expect(busyCredit, greaterThan(0));
      // Окно от регистрации 00:00 до 12:00 — 49 интервалов, взведены 24:
      // доступность 24/49 ≈ 0,49, а не последнее значение 1,0.
      expect(busyCredit, lessThan(idleCredit));
      expect(busyCredit, closeTo(idleCredit * 0.49, idleCredit * 0.02));
    },
    skip: skipWithoutPostgres,
  );

  test('узел выключен навсегда: квота падает, данные остаются', () async {
    final testDb = await TestDatabase.create();
    addTearDown(testDb.drop);
    final db = Database.open(testDb.config);
    addTearDown(db.close);
    await Migrator(db).migrate();

    final account = _id(1);
    await _account(db, account);
    final node = _id(20);
    await _node(db, account, node, capacity: 25000000000, availability: 1);
    await _segment(db, account, _id(10), k: 10, fragmentSize: 100000000);

    final economy = EconomyService(
      db,
      policy: const EconomyPolicy(starterCredits: 0),
      clock: () => DateTime.utc(2026, 11, 1, 12),
    );
    // Пока узел есть, 1 ГБ данных покрывает квота 10 ГБ: списания нет.
    await economy.runDay(DateTime.utc(2026, 11));
    expect((await economy.quota(account)).balanceMicro, 0);

    // Узел ушёл навсегда: ёмкость и квота обнуляются, данные остаются.
    await db.run(
      (s) => s.execute(
        Sql.named(
          'UPDATE nodes SET removed_at = now() WHERE node_id = @n:bytea',
        ),
        parameters: {'n': node},
      ),
    );
    final afterLeave = await economy.quota(account);
    expect(afterLeave.capacityBytes, 0);
    expect(afterLeave.barterBytes, 0);
    expect(afterLeave.dataBytes, 1000000000);
    expect(afterLeave.maxBytes, 0);

    // День без узла: данные сверх квоты уводят баланс в минус.
    await economy.runDay(DateTime.utc(2026, 11, 2));
    final debt = await economy.quota(account);
    expect(debt.balanceMicro, -40000);
    expect(debt.negativeSince, DateTime.utc(2026, 11, 2));
    expect(debt.dataBytes, 1000000000);

    // Через 7 дней долга новые бэкапы запрещены, данные целы.
    final blocked = EconomyService(
      db,
      policy: const EconomyPolicy(starterCredits: 0),
      clock: () => DateTime.utc(2026, 11, 9, 12),
    );
    final q = await blocked.quota(account);
    expect(q.blocked, isTrue);
    expect(q.dataBytes, 1000000000);
    await expectLater(
      db.transaction((tx) => blocked.checkCanStore(tx, account, 1)),
      throwsA(isA<RpcException>()),
    );
  }, skip: skipWithoutPostgres);

  test('трафик ремонта виден в балансе, но отдельно не списывается', () async {
    final testDb = await TestDatabase.create();
    addTearDown(testDb.drop);
    final db = Database.open(testDb.config);
    addTearDown(db.close);
    await Migrator(db).migrate();

    final account = _id(1);
    await _account(db, account);
    final segment = _id(10);
    await _segment(
      db,
      account,
      segment,
      k: 10,
      fragmentSize: 100000000,
      state: 0,
    );
    final node = _id(20);
    await _node(db, account, node, capacity: 2500000000, availability: 1);
    await db.run(
      (s) => s.execute(
        Sql.named('''
          INSERT INTO repair_jobs
            (job_id, account_id, segment_id, executor, live, planned_bytes,
             state, created_at, deadline, reported_at, finished_at,
             bytes_downloaded, bytes_uploaded)
          VALUES (@j:bytea, @a:bytea, @g:bytea, @n:bytea, 16, 2000000000,
                  2, now(), now(), now(), now(), 1000000000, 500000000)'''),
        parameters: {'j': Uint8List(16), 'a': account, 'g': segment, 'n': node},
      ),
    );

    final economy = EconomyService(db);
    final q = await economy.quota(account);
    expect(q.repairBytes, 1500000000);
    expect(q.repairCostMicro, const EconomyPolicy().storeCostMicro(1500000000));
    expect(
      q.balanceMicro,
      600000000,
      reason: 'ремонт отдельно не оплачивается',
    );
  }, skip: skipWithoutPostgres);
}

Future<void> _account(Database db, Uint8List account) => db.run(
  (s) => s.execute(
    Sql.named('INSERT INTO accounts (account_id) VALUES (@a:bytea)'),
    parameters: {'a': account},
  ),
);

Future<void> _segment(
  Database db,
  Uint8List account,
  Uint8List segment, {
  required int k,
  required int fragmentSize,
  int state = 1,
}) => db.run(
  (s) => s.execute(
    Sql.named('''
      INSERT INTO segments
        (account_id, segment_id, k, n, repair_threshold, fragment_size,
         state, allocated_at, committed_at)
      VALUES (@a:bytea, @g:bytea, @k:int2, 20, 16, @s:int4, @st:int2,
              now(), now())'''),
    parameters: {
      'a': account,
      'g': segment,
      'k': k,
      's': fragmentSize,
      'st': state,
    },
  ),
);

Future<void> _node(
  Database db,
  Uint8List account,
  Uint8List node, {
  required int capacity,
  required double availability,
}) => db.run(
  (s) => s.execute(
    Sql.named('''
      INSERT INTO nodes (node_id, account_id, certificate, capacity_bytes,
                         availability)
      VALUES (@n:bytea, @a:bytea, @c:bytea, @cap:int8, @av:real)'''),
    parameters: {
      'n': node,
      'a': account,
      'c': Uint8List(0),
      'cap': capacity,
      'av': availability,
    },
  ),
);

Future<void> _fragments(
  Database db,
  Uint8List account,
  Uint8List segment,
  Uint8List node,
) async {
  for (var i = 0; i < 20; i++) {
    await db.run(
      (s) => s.execute(
        Sql.named('''
          INSERT INTO fragments
            (account_id, segment_id, idx, fragment_id, body_root, node_id,
             stored)
          VALUES (@a:bytea, @g:bytea, @i:int2, @f:bytea, @r:bytea,
                  @n:bytea, true)'''),
        parameters: {
          'a': account,
          'g': segment,
          'i': i,
          'f': _id(100 + i + node[0]),
          'r': _id(200 + i + node[0]),
          'n': node,
        },
      ),
    );
  }
}

Future<int> _credit(
  Database db,
  Uint8List account,
  Uint8List node,
  DateTime day,
) async {
  final rows = await db.run(
    (s) => s.execute(
      Sql.named('''
        SELECT coalesce(sum(amount_mc), 0)::int8 FROM credit_ledger
         WHERE account_id = @a:bytea AND kind = 'storage_credit'
           AND day = @d:date AND ref = @r:text'''),
      parameters: {'a': account, 'd': day, 'r': _hex(node)},
    ),
  );
  return rows.single.single! as int;
}

String _hex(Uint8List bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Uint8List _id(int n) {
  final b = Uint8List(32);
  b[0] = n & 0xff;
  b[1] = (n >> 8) & 0xff;
  return b;
}
