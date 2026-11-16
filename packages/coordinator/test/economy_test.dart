// Бартерная экономика: квота, стартовый грант, ежедневное списание и
// кредиты за занятые фрагменты. Нужен FS_TEST_POSTGRES.
import 'dart:typed_data';

import 'package:coordinator/coordinator.dart';
import 'package:postgres/postgres.dart';
import 'package:protocol/protocol.dart' as pb;
import 'package:test/test.dart';

import 'support/postgres.dart';

void main() {
  test('тарифы: 1 ТБ данных = 1200 CR, фрагменты = 400 CR', () {
    const p = EconomyPolicy(starterCredits: 0);
    expect(
      p.dataCostMicro(EconomyPolicy.tbBytes),
      1200 * EconomyPolicy.microPerCredit,
    );
    expect(
      p.storeCostMicro(EconomyPolicy.tbBytes),
      400 * EconomyPolicy.microPerCredit,
    );
    expect(p.barterBytes(1000), 400);
    expect(
      p.bytesForMicro(1200 * EconomyPolicy.microPerCredit),
      EconomyPolicy.tbBytes,
    );
  });

  test('квота, списание и кредиты', () async {
    final testDb = await TestDatabase.create();
    addTearDown(testDb.drop);
    final db = Database.open(testDb.config);
    addTearDown(db.close);
    expect(await Migrator(db).migrate(), 19);

    final client = _id(1);
    final keeper = _id(2);
    for (final a in [client, keeper]) {
      await db.run(
        (s) => s.execute(
          Sql.named('INSERT INTO accounts (account_id) VALUES (@a:bytea)'),
          parameters: {'a': a},
        ),
      );
    }
    // Клиент: 1 ГБ данных, без своих узлов.
    final segment = _id(10);
    await db.run(
      (s) => s.execute(
        Sql.named('''
          INSERT INTO segments
            (account_id, segment_id, k, n, repair_threshold, fragment_size,
             state, allocated_at, committed_at)
          VALUES (@a:bytea, @g:bytea, 10, 20, 16, 100000000, 1,
                  now(), now())'''),
        parameters: {'a': client, 'g': segment},
      ),
    );
    // Хранитель: узел на 2,5 ГБ ёмкости, на нём 20 фрагментов по 100 МБ.
    final node = _id(20);
    await db.run(
      (s) => s.execute(
        Sql.named('''
          INSERT INTO nodes (node_id, account_id, certificate, capacity_bytes,
                             availability)
          VALUES (@n:bytea, @a:bytea, @c:bytea, 2500000000, 0.99)'''),
        parameters: {'n': node, 'a': keeper, 'c': Uint8List(0)},
      ),
    );
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
            'a': client,
            'g': segment,
            'i': i,
            'f': _id(100 + i),
            'r': _id(200 + i),
            'n': node,
          },
        ),
      );
    }
    final economy = EconomyService(db);
    await economy.runDay(DateTime.utc(2026, 11, 15));

    final cq = await economy.quota(client);
    expect(cq.dataBytes, 1000000000);
    expect(cq.barterBytes, 0);
    expect(cq.balanceMicro, 600000000 - 40000);
    expect(cq.dailyCostMicro, 40000);
    expect(cq.billableBytes, 1000000000);
    expect(
      cq.entries.map((e) => e.kind),
      containsAll(['starter', 'storage_charge']),
    );

    final kq = await economy.quota(keeper);
    expect(kq.capacityBytes, 2500000000);
    expect(kq.barterBytes, 1000000000);
    expect(kq.balanceMicro, 600000000 + 26400);
    expect(kq.entries.map((e) => e.kind), contains('storage_credit'));

    // Идемпотентность: повторный день не меняет баланс.
    await economy.runDay(DateTime.utc(2026, 11, 15));
    expect((await economy.quota(client)).balanceMicro, 600000000 - 40000);
    expect((await economy.quota(keeper)).balanceMicro, 600000000 + 26400);

    final inspect = EconomyService(
      db,
      clock: () => DateTime.utc(2026, 11, 15, 12),
    );
    final api = await inspect.getQuota(
      CallContext(
        method: 'GetQuota',
        requestId: 'test',
        caller: Caller(
          publicKey: _id(1),
          info: KeyInfo(kind: KeyKind.account, accountId: client),
        ),
      ),
      pb.GetQuotaRequest(),
    );
    expect(api.dataBytes.toInt(), 1000000000);
    expect(api.barterBytes.toInt(), 0);
    expect(api.entries.map((e) => e.kind), contains('storage_charge'));

    // Новая квота: 0,5 ТБ покрывает 0,1 ТБ и не покрывает 1 ТБ.
    await db.transaction(
      (tx) => economy.checkCanStore(tx, client, 100000000000),
    );
    await expectLater(
      db.transaction((tx) => economy.checkCanStore(tx, client, 1000000000000)),
      throwsA(isA<RpcException>()),
    );
  }, skip: skipWithoutPostgres);
}

Uint8List _id(int n) {
  final b = Uint8List(32);
  b[0] = n & 0xff;
  b[1] = (n >> 8) & 0xff;
  return b;
}
