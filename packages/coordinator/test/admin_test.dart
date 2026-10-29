// Административный CLI координатора (задачи 2.10.1–2.10.4): права роли
// администратора, журнал только на добавление, блокировка, отзыв,
// исключение узла. Нужен FS_TEST_POSTGRES с правом CREATEROLE.

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:coordinator/coordinator.dart';
import 'package:core/core.dart';
import 'package:postgres/postgres.dart';
import 'package:protocol/protocol.dart' as pb;
import 'package:test/test.dart';

import 'support/db_harness.dart';
import 'support/postgres.dart';

const pb.ErrorCode _denied = pb.ErrorCode.ERROR_CODE_PERMISSION_DENIED;

final class _Console implements AdminConsole {
  new([this.answer]);

  final String? answer;
  final List<String> lines = [];
  final List<String> errors = [];

  @override
  void out(String line) => lines.add(line);

  @override
  void err(String line) => errors.add(line);

  @override
  String? ask(String prompt) => answer;
}

void main() {
  if (testPostgresUrl == null) {
    test('администрирование', () {}, skip: skipWithoutPostgres);
    return;
  }
  late DbHarness h;
  late Database adminDb;
  late String role;
  late AdminService admin;
  late AccountKeys alice;
  late Ed25519KeyPair aliceDevice;
  final nodes = <Ed25519KeyPair>[];
  final journal = <AuditRecord>[];
  const password = 'admin-test-password';

  // Пользователю тестов нужно право CREATEROLE: без него тесты
  // пропускаются.
  var canCreateRoles = true;
  setUpAll(() async {
    final probe = await TestDatabase.create();
    try {
      await probe.createRole(
        'fs_probe_${Random().nextInt(1 << 32).toRadixString(16)}',
        password,
      );
    } on ServerException catch (e) {
      if (e.code != '42501') rethrow;
      canCreateRoles = false;
    } finally {
      await probe.drop();
    }
  });

  void adminTest(String name, Future<void> Function() body) => test(name, () {
    if (!canCreateRoles) {
      markTestSkipped('пользователю тестов нужно право CREATEROLE');
      return Future<void>.value();
    }
    return body();
  });

  setUp(() async {
    if (!canCreateRoles) return;
    h = await DbHarness.create();
    final suffix = Random().nextInt(1 << 32).toRadixString(16);
    role = 'fs_admin_$suffix';
    await h.testDb.createRole(role, password);
    expect(await AdminAccess.grant(h.db, role), isTrue);
    adminDb = Database.open(h.testDb.as(role, password));
    journal.clear();
    admin = AdminService(
      adminDb,
      onlineWindow: const Duration(minutes: 15),
      probation: Duration.zero,
      clock: h.clock.call,
      journal: journal.add,
    );
    alice = await h.newAccount();
    aliceDevice = await h.newKey();
    await h.register(alice, aliceDevice, login: 'alice', password: 'пароль');
    nodes.clear();
    for (var i = 0; i < 3; i++) {
      final owner = await h.newAccount();
      await h.register(owner, await h.newKey(), login: 'keeper$i');
      final node = await h.newKey();
      await h.registerNode(owner, node, ip: '198.51.$i.10');
      nodes.add(node);
    }
  });
  tearDown(() async {
    if (!canCreateRoles) return;
    await adminDb.close();
    await h.close();
  });

  AdminActor actor([String reason = 'жалоба №1']) =>
      AdminActor(osUser: 'operator', reason: reason);

  Future<void> putObject(Ed25519KeyPair device) => h.call(
    'PutObject',
    pb.PutObjectRequest(
      kind: pb.ObjectKind.OBJECT_KIND_INDEX,
      objectId: Uint8List(32)..[0] = 1,
      blob: [1, 2, 3],
    ),
    pb.PutObjectResponse.fromBuffer,
    key: device,
  );

  Future<pb.AllocateSegmentResponse> allocate(int n, int tag) => h.call(
    'AllocateSegment',
    pb.AllocateSegmentRequest(
      segmentId: Uint8List(32)..[0] = tag,
      k: 1,
      n: n,
      repairThreshold: 1,
      fragmentSize: 1000,
      fragmentIds: [for (var i = 0; i < n; i++) Uint8List(32)..[0] = i],
      bodyRoots: [for (var i = 0; i < n; i++) Uint8List(32)..[1] = i],
    ),
    pb.AllocateSegmentResponse.fromBuffer,
    key: aliceDevice,
  );

  adminTest('права: роль администратора и посторонняя роль', () async {
    await AdminAccess.check(adminDb, role);
    final other = 'fs_other_${Random().nextInt(1 << 32).toRadixString(16)}';
    await h.testDb.createRole(other, password);
    final otherDb = Database.open(h.testDb.as(other, password));
    addTearDown(otherDb.close);
    await expectLater(
      AdminAccess.check(otherDb, role),
      throwsA(isA<AdminAccessException>()),
    );
    // Без проверки — отказ базы и понятная ошибка CLI.
    final console = _Console();
    final code = await runAdmin(
      ['stats'],
      service: AdminService(
        otherDb,
        onlineWindow: const Duration(minutes: 15),
        probation: Duration.zero,
      ),
      osUser: 'intruder',
      console: console,
    );
    expect(code, AdminExit.noPermission);
    expect(console.errors.join(), contains('Нет прав'));
    // Секретов учётной записи роль администратора не читает (К-2).
    await expectLater(
      adminDb.run((s) => s.execute('SELECT key_bundle FROM accounts')),
      throwsA(isA<ServerException>().having((e) => e.code, 'code', '42501')),
    );
    await expectLater(
      adminDb.run((s) => s.execute('SELECT blob FROM objects')),
      throwsA(isA<ServerException>().having((e) => e.code, 'code', '42501')),
    );
    expect(await AdminAccess.grant(h.db, 'fs_no_such_role'), isFalse);
  });

  adminTest('метрики ремонта читаются ролью администратора (4.3.6)', () async {
    final stats = await admin.repairStats(hours: 6);
    expect(stats['hours'], 6);
    expect(stats['segments'], 0);
    expect(stats['minLive'], isNull);
    expect(stats['nodesLost'], 0);
    expect((stats['traffic']! as Map)['bytesPerTbPerDay'], isNull);
  });

  adminTest('поиск и сводка учётной записи', () async {
    final byLogin = await admin.findAccounts('Alice');
    expect(byLogin.single['accountId'], bytesToHex(alice.accountId));
    final byDevice = await admin.findAccounts(
      bytesToHex(aliceDevice.publicKey),
    );
    expect(byDevice.single['matchedBy'], 'device');
    final byNode = await admin.findAccounts(bytesToHex(nodes[0].publicKey));
    expect(byNode.single['login'], 'keeper0');
    expect(await admin.findAccounts('nobody'), isEmpty);

    await putObject(aliceDevice);
    final show = await admin.showAccount('alice');
    expect(show['keyCopy'], isTrue);
    expect(show['objectBytes'], 3);
    expect(show['devices'], hasLength(1));
    expect(show['lastActivityAt'], isNotNull);
    expect((await admin.showAccount('keeper1'))['nodes'], hasLength(1));
  });

  adminTest('блокировка и разблокировка', () async {
    final result = await admin.setBlocked(
      'alice',
      blocked: true,
      actor: actor(),
    );
    expect(result['changed'], isTrue);
    await expectLater(putObject(aliceDevice), failsWith(_denied));
    await expectLater(
      h.call(
        'ListDevices',
        pb.ListDevicesRequest(),
        pb.ListDevicesResponse.fromBuffer,
        key: alice.accountSign,
      ),
      failsWith(_denied),
    );
    // Повторная блокировка — без изменений, но с записью в журнале.
    expect(
      (await admin.setBlocked(
        'alice',
        blocked: true,
        actor: actor(),
      ))['changed'],
      isFalse,
    );
    await admin.setBlocked('alice', blocked: false, actor: actor('ошибка'));
    await putObject(aliceDevice);

    // Узлы заблокированного владельца не получают фрагментов и не
    // регистрируются заново.
    final keeper = await admin.resolveAccount(bytesToHex(nodes[0].publicKey));
    await admin.setBlocked(bytesToHex(keeper), blocked: true, actor: actor());
    await expectLater(
      allocate(3, 1),
      failsWith(pb.ErrorCode.ERROR_CODE_UNAVAILABLE),
    );
    await expectLater(
      h.heartbeat(nodes[0], ip: '198.51.0.10'),
      failsWith(_denied),
    );
    final records = await admin.audit();
    expect(records.map((r) => r['command']), [
      'account block',
      'account unblock',
      'account block',
      'account block',
    ]);
    expect(records[2]['result'], 'unchanged');
    expect(records.first['osUser'], 'operator');
    expect(records.first['dbUser'], role);
    expect(journal, hasLength(4));
  });

  adminTest('административный отзыв устройства', () async {
    final prefix = bytesToHex(aliceDevice.publicKey).substring(0, 12);
    final result = await admin.revokeDevice(prefix, actor: actor());
    expect(result['changed'], isTrue);
    await expectLater(
      putObject(aliceDevice),
      failsWith(pb.ErrorCode.ERROR_CODE_UNAUTHENTICATED),
    );
    // Отзыв без подписи учётной записи узлам не отдаётся…
    final node = nodes[0];
    Future<int> revocations() async => (await h.call(
      'ListRevocations',
      pb.ListRevocationsRequest(),
      pb.ListRevocationsResponse.fromBuffer,
      key: node,
      ip: '198.51.0.10',
    )).revocations.length;
    expect(await revocations(), 0);
    // …а подписанный пользователем отзыв дополняет его.
    await h.call(
      'RevokeDevice',
      pb.RevokeDeviceRequest(
        revocation: await h.revocation(alice, aliceDevice),
      ),
      pb.RevokeDeviceResponse.fromBuffer,
      key: alice.accountSign,
    );
    expect(await revocations(), 1);
    final show = await admin.showAccount('alice');
    expect(((show['devices']! as List).single as Map)['revokedBy'], 'account');
    await expectLater(
      admin.revokeDevice('00', actor: actor()),
      throwsA(isA<AdminException>()),
    );
    expect((await admin.audit()).first['result'], startsWith('error:'));
  });

  adminTest('исключение узла из размещения', () async {
    for (final (i, node) in nodes.indexed) {
      await h.heartbeat(node, ip: '198.51.$i.10');
    }
    expect((await allocate(3, 1)).placements, hasLength(3));
    final excluded = bytesToHex(nodes[1].publicKey);
    await admin.setExcluded(
      excluded.substring(0, 10),
      excluded: true,
      actor: actor('диск сбоит'),
    );
    await expectLater(
      allocate(3, 2),
      failsWith(pb.ErrorCode.ERROR_CODE_UNAVAILABLE),
    );
    final two = await allocate(2, 3);
    expect(
      two.placements.map((p) => bytesToHex(p.node.nodeId)),
      isNot(contains(excluded)),
    );
    final show = await admin.showNode(excluded);
    expect(show['excludedReason'], 'диск сбоит');
    expect(show['online'], isTrue);
    // Новый узел без аудитов: A² · G, G = 0,25 (docs/spec/reputation.md).
    expect(
      show['reputation'],
      closeTo(0.25 * pow(show['availability']! as double, 2), 1e-9),
    );
    expect(show['auditLatencyMs'], isNull);
    await admin.setExcluded(excluded, excluded: false, actor: actor());
    expect((await allocate(3, 4)).placements, hasLength(3));
    expect(await admin.listNodes(), hasLength(3));
    expect(await admin.listNodes(account: 'keeper2'), hasLength(1));

    final stats = await admin.stats();
    expect(stats['nodes'], 3);
    expect(stats['nodesOnline'], 3);
    expect(stats['accounts'], 4);
    expect((stats['segments']! as Map)['allocated'], 3);
  });

  adminTest('журнал только на добавление', () async {
    await admin.setBlocked('alice', blocked: true, actor: actor());
    for (final sql in [
      "UPDATE admin_audit SET reason = 'подмена'",
      'DELETE FROM admin_audit',
      'TRUNCATE admin_audit',
    ]) {
      await expectLater(
        adminDb.run((s) => s.execute(sql)),
        throwsA(isA<ServerException>().having((e) => e.code, 'code', '42501')),
        reason: sql,
      );
      // Владелец схемы упирается в триггер.
      await expectLater(
        h.db.run((s) => s.execute(sql)),
        throwsA(isA<ServerException>()),
        reason: '$sql от владельца',
      );
    }
    expect(await admin.audit(), hasLength(1));
  });

  adminTest('runAdmin: причина, подтверждение, JSON', () async {
    Future<(int, _Console)> run(List<String> args, {String? answer}) async {
      final console = _Console(answer);
      final code = await runAdmin(
        args,
        service: admin,
        osUser: 'operator',
        console: console,
      );
      return (code, console);
    }

    expect((await run(['account', 'block', 'alice'])).$1, AdminExit.usage);
    expect(
      (await run(['account', 'block', 'alice', '--reason', 'спам'])).$1,
      AdminExit.usage,
      reason: 'нет терминала и нет --yes',
    );
    expect(
      (await run([
        'account',
        'block',
        'alice',
        '--reason',
        'спам',
      ], answer: 'нет')).$1,
      AdminExit.error,
    );
    var (code, console) = await run([
      'account',
      'block',
      'alice',
      '--reason',
      'спам',
    ], answer: 'да');
    expect(code, AdminExit.ok);
    (code, console) = await run(['--json', 'account', 'show', 'alice']);
    expect(code, AdminExit.ok);
    final show = jsonDecode(console.lines.single) as Map<String, Object?>;
    expect(show['blockedReason'], 'спам');
    (code, console) = await run(['stats']);
    expect(code, AdminExit.ok);
    expect(console.lines.join('\n'), contains('accountsBlocked: 1'));
    (code, console) = await run(['account', 'show', 'nobody']);
    expect(code, AdminExit.error);
    expect((await run(['nonsense'])).$1, AdminExit.usage);
    (code, console) = await run(['--json', 'audit', '--limit', '1']);
    expect(
      (jsonDecode(console.lines.single) as List).single,
      containsPair('reason', 'спам'),
    );
  });
}
