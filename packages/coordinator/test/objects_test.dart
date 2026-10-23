// Снимки и индексы на координаторе (задачи 2.5.1, 2.5.2; protocol.md,
// раздел 4.8). Нужен FS_TEST_POSTGRES.

import 'dart:typed_data';

import 'package:coordinator/coordinator.dart';
import 'package:core/core.dart';
import 'package:fixnum/fixnum.dart';
import 'package:postgres/postgres.dart';
import 'package:protocol/protocol.dart' as pb;
import 'package:test/test.dart';

// Тот же контракт, что у LocalObjectStore в core: клиентская реализация
// поверх координатора (2.8.2) обязана его выполнять.
import '../../core/test/support/object_store_contract.dart';
import 'support/db_harness.dart';
import 'support/postgres.dart';

const pb.ErrorCode _badRequest = pb.ErrorCode.ERROR_CODE_BAD_REQUEST;
const pb.ErrorCode _notFound = pb.ErrorCode.ERROR_CODE_NOT_FOUND;

/// [ObjectStore] поверх обработчика API без HTTP — для тестов с подменой
/// содержимого базы. Клиент по HTTP — `CoordinatorObjectStore` в core
/// (`storage_test.dart`).
final class _ApiObjects implements ObjectStore {
  new(this.h, this.device, {this.pageSize = 0});

  final DbHarness h;
  final Ed25519KeyPair device;
  final int pageSize;

  static pb.ObjectKind _kind(ObjectKind kind) => switch (kind) {
    ObjectKind.snapshot => pb.ObjectKind.OBJECT_KIND_SNAPSHOT,
    ObjectKind.indexObject => pb.ObjectKind.OBJECT_KIND_INDEX,
  };

  @override
  Future<void> put(
    ObjectKind kind,
    Uint8List id,
    Uint8List blob, {
    int sequence = 0,
  }) async {
    await h.call(
      'PutObject',
      pb.PutObjectRequest(
        kind: _kind(kind),
        objectId: id,
        blob: blob,
        sequence: Int64(sequence),
      ),
      pb.PutObjectResponse.fromBuffer,
      key: device,
    );
  }

  @override
  Future<List<ObjectInfo>> list(ObjectKind kind) async {
    final out = <ObjectInfo>[];
    var after = Uint8List(0);
    for (;;) {
      final page = await h.call(
        'ListObjects',
        pb.ListObjectsRequest(
          kind: _kind(kind),
          afterObjectId: after,
          limit: pageSize,
        ),
        pb.ListObjectsResponse.fromBuffer,
        key: device,
      );
      for (final o in page.objects) {
        out.add(
          ObjectInfo(
            id: Uint8List.fromList(o.objectId),
            size: o.size,
            storedAtMs: o.storedAtUnixMs.toInt(),
            sequence: o.sequence.toInt(),
          ),
        );
      }
      if (!page.more) return out;
      after = out.last.id;
    }
  }

  @override
  Future<Uint8List> get(ObjectKind kind, Uint8List id) async {
    try {
      final r = await h.call(
        'GetObject',
        pb.GetObjectRequest(kind: _kind(kind), objectId: id),
        pb.GetObjectResponse.fromBuffer,
        key: device,
      );
      return Uint8List.fromList(r.blob);
    } on RpcFailure catch (f) {
      if (f.code != _notFound) rethrow;
      throw const StorageException(
        location: 'coordinator',
        problem: StorageProblem.notFound,
        operation: 'get',
      );
    }
  }

  @override
  Future<void> delete(ObjectKind kind, Uint8List id) async {
    await h.call(
      'DeleteObject',
      pb.DeleteObjectRequest(kind: _kind(kind), objectId: id),
      pb.DeleteObjectResponse.fromBuffer,
      key: device,
    );
  }
}

void main() {
  if (testPostgresUrl == null) {
    test('объекты', () {}, skip: skipWithoutPostgres);
    return;
  }
  late DbHarness h;
  late AccountKeys account;
  late Ed25519KeyPair device;

  Future<void> start({CoordinatorConfig config = DbHarness.testConfig}) async {
    h = await DbHarness.create(config: config);
    account = await h.newAccount();
    device = await h.newKey();
    await h.register(account, device, login: 'alice');
  }

  tearDown(() => h.close());

  Uint8List id(int b) => Uint8List(32)..[0] = b;

  Future<int> usage(AccountKeys a) async {
    final rows = await h.db.run(
      (s) => s.execute(
        Sql.named(
          'SELECT object_bytes FROM accounts WHERE account_id = @a:bytea',
        ),
        parameters: {'a': a.accountId},
      ),
    );
    return rows.single.single! as int;
  }

  group('контракт ObjectStore', () {
    objectStoreContract(() async {
      await start();
      return _ApiObjects(h, device);
    });
  });

  group('контракт ObjectStore, постранично', () {
    objectStoreContract(() async {
      await start();
      return _ApiObjects(h, device, pageSize: 1);
    });
  });

  group('объекты', () {
    setUp(start);

    test('объекты другой учётной записи недоступны', () async {
      final bob = await h.newAccount();
      final bobDevice = await h.newKey();
      await h.register(bob, bobDevice, login: 'bob');
      final alice = _ApiObjects(h, device);
      final other = _ApiObjects(h, bobDevice);
      await alice.put(ObjectKind.snapshot, id(1), Uint8List(10), sequence: 1);

      await expectLater(
        other.get(ObjectKind.snapshot, id(1)),
        throwsA(isA<StorageException>()),
        reason: 'чужой объект — NOT_FOUND, его существование не выдаётся',
      );
      expect(await other.list(ObjectKind.snapshot), isEmpty);
      await other.delete(ObjectKind.snapshot, id(1));
      expect(await alice.get(ObjectKind.snapshot, id(1)), Uint8List(10));

      // Тот же идентификатор у другой учётной записи — свой объект.
      await other.put(ObjectKind.snapshot, id(1), Uint8List(3), sequence: 7);
      expect(await alice.get(ObjectKind.snapshot, id(1)), Uint8List(10));
      expect((await other.list(ObjectKind.snapshot)).single.sequence, 7);
    });

    test('учёт объёма: запись, замена, удаление', () async {
      final store = _ApiObjects(h, device);
      await store.put(ObjectKind.snapshot, id(1), Uint8List(100), sequence: 1);
      await store.put(ObjectKind.indexObject, id(1), Uint8List(1000));
      expect(await usage(account), 1100);
      await store.put(ObjectKind.indexObject, id(1), Uint8List(400));
      expect(await usage(account), 500);
      await store.delete(ObjectKind.snapshot, id(1));
      await store.delete(ObjectKind.snapshot, id(1));
      expect(await usage(account), 400);
    });

    test('пределы и поля запроса', () async {
      Future<void> put(pb.PutObjectRequest r) =>
          h.call('PutObject', r, pb.PutObjectResponse.fromBuffer, key: device);
      const snapshot = pb.ObjectKind.OBJECT_KIND_SNAPSHOT;
      const index = pb.ObjectKind.OBJECT_KIND_INDEX;

      // Ровно 8 МиБ — можно, на байт больше — BAD_REQUEST.
      await put(
        pb.PutObjectRequest(
          kind: index,
          objectId: id(1),
          blob: Uint8List(ObjectService.maxBlobBytes),
        ),
      );
      await expectLater(
        () => put(
          pb.PutObjectRequest(
            kind: index,
            objectId: id(2),
            blob: Uint8List(ObjectService.maxBlobBytes + 1),
          ),
        ),
        failsWith(_badRequest),
      );
      for (final bad in [
        pb.PutObjectRequest(kind: index, objectId: id(3)),
        pb.PutObjectRequest(objectId: id(3), blob: [1]),
        pb.PutObjectRequest(kind: snapshot, objectId: [1, 2], blob: [1]),
        pb.PutObjectRequest(
          kind: index,
          objectId: id(3),
          blob: [1],
          sequence: Int64(5),
        ),
        pb.PutObjectRequest(
          kind: snapshot,
          objectId: id(3),
          blob: [1],
          sequence: Int64.MIN_VALUE,
        ),
      ]) {
        await expectLater(() => put(bad), failsWith(_badRequest));
      }
      await expectLater(
        () => h.call(
          'ListObjects',
          pb.ListObjectsRequest(kind: snapshot, afterObjectId: [1]),
          pb.ListObjectsResponse.fromBuffer,
          key: device,
        ),
        failsWith(_badRequest),
      );
      await expectLater(
        () => h.call(
          'GetObject',
          pb.GetObjectRequest(kind: snapshot, objectId: id(9)),
          pb.GetObjectResponse.fromBuffer,
          key: device,
        ),
        failsWith(_notFound),
      );
    });

    test('страница ListObjects: limit и more', () async {
      final store = _ApiObjects(h, device);
      for (var i = 1; i <= 5; i++) {
        await store.put(ObjectKind.indexObject, id(i), Uint8List(1));
      }
      final page = await h.call(
        'ListObjects',
        pb.ListObjectsRequest(
          kind: pb.ObjectKind.OBJECT_KIND_INDEX,
          afterObjectId: id(1),
          limit: 3,
        ),
        pb.ListObjectsResponse.fromBuffer,
        key: device,
      );
      expect(page.objects.map((o) => o.objectId[0]), [2, 3, 4]);
      expect(page.more, isTrue);
    });

    test('ключ узла — PERMISSION_DENIED', () async {
      final node = await h.newKey();
      await h.registerNode(account, node);
      await expectLater(
        () => h.call(
          'ListObjects',
          pb.ListObjectsRequest(kind: pb.ObjectKind.OBJECT_KIND_SNAPSHOT),
          pb.ListObjectsResponse.fromBuffer,
          key: node,
        ),
        failsWith(pb.ErrorCode.ERROR_CODE_PERMISSION_DENIED),
      );
    });
  });

  test('предел объёма учётной записи — QUOTA_EXCEEDED', () async {
    await start(
      config: const CoordinatorConfig(maxObjectBytesPerAccount: 1000),
    );
    final store = _ApiObjects(h, device);
    await store.put(ObjectKind.indexObject, id(1), Uint8List(600));
    await expectLater(
      () => store.put(ObjectKind.indexObject, id(2), Uint8List(600)),
      failsWith(pb.ErrorCode.ERROR_CODE_QUOTA_EXCEEDED),
    );
    // Замена не считает старый объект дважды.
    await store.put(ObjectKind.indexObject, id(1), Uint8List(1000));
    expect(await usage(account), 1000);
  });

  group('обнаружение отката (manifest.md, раздел 6)', () {
    late LocalIndex index;
    late SnapshotCatalog catalog;
    final manifestKey = SecretBytes(Uint8List(32)..[0] = 7);

    setUp(() async {
      await start();
      index = LocalIndex.inMemory();
      catalog = SnapshotCatalog(
        crypto: h.crypto,
        manifestKey: manifestKey,
        store: _ApiObjects(h, device),
        index: index,
      );
    });
    tearDown(() => index.close());

    pb.Snapshot snapshot(int b, int sequence, [int? parent]) => pb.Snapshot(
      formatVersion: 1,
      snapshotId: id(b),
      sequence: Int64(sequence),
      parentSnapshotId: parent == null ? null : id(parent),
      deviceId: device.publicKey,
      paths: ['/data'],
      rootTree: [Uint8List(32)],
    );

    Future<void> hide(int b) => h.db.run(
      (s) => s.execute(
        Sql.named('DELETE FROM objects WHERE object_id = @o:bytea'),
        parameters: {'o': id(b)},
      ),
    );

    test(
      'координатор отдаёт sequence; без сокрытия — без предупреждений',
      () async {
        await catalog.save(snapshot(0xA1, 1));
        await catalog.save(snapshot(0xB2, 2, 0xA1));
        final listing = await catalog.list();
        expect(listing.snapshots.map((s) => s.sequence.toInt()), [1, 2]);
        expect(listing.warnings, isEmpty);
      },
    );

    test('скрытый последний снимок — предупреждение у клиента', () async {
      await catalog.save(snapshot(0xA1, 1));
      await catalog.save(snapshot(0xB2, 2, 0xA1));
      await catalog.save(snapshot(0xC3, 3, 0xB2));
      await hide(0xC3);
      final listing = await catalog.list();
      expect(listing.snapshots.map((s) => s.sequence.toInt()), [1, 2]);
      expect(
        listing.warnings,
        containsAll([
          RollbackWarning.sequenceRegressed,
          RollbackWarning.lastSnapshotMissing,
        ]),
      );
    });

    test('скрытый чужой новый снимок — предупреждение по sequence', () async {
      // Снимок другого устройства той же учётной записи: клиент его видел,
      // потом координатор его спрятал.
      final other = await h.newKey();
      await h.call(
        'AddDevice',
        pb.AddDeviceRequest(
          deviceCertificate: await h.deviceCert(account, other),
        ),
        pb.AddDeviceResponse.fromBuffer,
        key: account.accountSign,
      );
      await catalog.save(snapshot(0xA1, 1));
      final otherCatalog = SnapshotCatalog(
        crypto: h.crypto,
        manifestKey: manifestKey,
        store: _ApiObjects(h, other),
        index: LocalIndex.inMemory(),
      );
      await otherCatalog.save(snapshot(0xD4, 2));
      expect((await catalog.list()).warnings, isEmpty);
      await hide(0xD4);
      expect((await catalog.list()).warnings, [
        RollbackWarning.sequenceRegressed,
      ]);
      otherCatalog.index.close();
    });
  });
}
