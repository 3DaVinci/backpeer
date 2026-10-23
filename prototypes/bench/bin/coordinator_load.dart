// Нагрузочный тест координатора (2.9.3): N узлов шлют heartbeat, M
// клиентов делают «бэкап» — размещение, подтверждение сегментов, индексы и
// снимок. Фрагменты не передаются: меряется координатор и его база.
//
//   FS_TEST_POSTGRES=postgres://… dart build cli -t bin/coordinator_load.dart
//   .../bundle/bin/coordinator_load [узлов] [клиентов] [сегментов на клиента]
//
// По умолчанию 1000 узлов, 200 клиентов, 20 сегментов. Координатор
// работает в отдельном isolate того же процесса (свой цикл событий),
// подписант — в третьем isolate за Unix-сокетом, как в бою (там это
// отдельный процесс). Для каждой фазы — время ответа по
// методам (p50, p95, p99, max), пропускная способность и счётчики базы
// (pg_stat_database), в конце — размеры таблиц и планы горячих запросов.

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:coordinator/coordinator.dart';
import 'package:core/core.dart';
import 'package:fixnum/fixnum.dart';
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:protocol/protocol.dart' as pb;

Future<void> main(List<String> args) async {
  final nodeCount = args.isNotEmpty ? int.parse(args[0]) : 1000;
  final clientCount = args.length > 1 ? int.parse(args[1]) : 200;
  final segmentsPerClient = args.length > 2 ? int.parse(args[2]) : 20;
  final url = Platform.environment['FS_TEST_POSTGRES'];
  if (url == null) {
    stderr.writeln('нужен FS_TEST_POSTGRES (пользователь с CREATEDB)');
    exit(64);
  }
  final (admin, database) = await _createDatabase(Uri.parse(url));
  final ready = ReceivePort();
  await Isolate.spawn(_serve, (ready.sendPort, database));
  final [port as int, stop as SendPort] = await ready.first as List<Object?>;
  final base = Uri.parse('http://127.0.0.1:$port');
  final crypto = await SodiumCryptoProvider.load();
  final stats = Connection.open(
    Endpoint(
      host: database.host,
      port: database.port,
      database: database.name,
      username: database.user,
      password: database.password,
    ),
    settings: const ConnectionSettings(sslMode: SslMode.disable),
  );
  final db = await stats;
  stdout.writeln(
    'узлов $nodeCount, клиентов $clientCount, сегментов на клиента '
    '$segmentsPerClient (n = 20); ${Platform.numberOfProcessors} ядер',
  );

  try {
    // --- Узлы: регистрация ---------------------------------------------------
    final latency = _Latency();
    final nodes = <DeviceKeys>[];
    var phase = await _Phase.start(db, 'регистрация узлов');
    await _pool(nodeCount, 50, (i) async {
      final client = CoordinatorClient(baseUri: base, crypto: crypto);
      final owner = await AccountKeys.fromMasterKey(
        SecretBytes(crypto.randomBytes(32)),
        crypto,
      );
      final ownerDevice = await DeviceKeys.generate(crypto);
      final node = await DeviceKeys.generate(crypto);
      await latency.time(
        'RegisterAccount',
        () async => await client.registerAccount(
          pb.RegisterAccountRequest(
            deviceCertificate: await DeviceCertificates.issue(
              crypto,
              owner,
              ownerDevice,
              issuedAt: DateTime.now(),
            ),
            login: 'owner$i',
          ),
          accountKey: owner.accountSign,
        ),
      );
      await latency.time(
        'RegisterNode',
        () async => await client.registerNode(
          pb.RegisterNodeRequest(
            nodeCertificate: await NodeCertificates.issue(
              crypto,
              owner,
              nodeId: node.sign.publicKey,
              nodeDh: node.dh.publicKey,
              issuedAt: DateTime.now(),
            ),
            capacityBytes: Int64(4 << 40),
            endpoints: ['10.${i >> 8}.${i & 255}.1:7000'],
            versions: [1],
            software: 'load',
          ),
          nodeKey: node.sign,
        ),
      );
      nodes.add(node);
      client.close();
    });
    await phase.finish(latency, nodeCount * 2);

    // --- Узлы: heartbeat всех подряд, с предельной скоростью ---------------
    latency.clear();
    final heartbeatClient = CoordinatorClient(baseUri: base, crypto: crypto);
    Future<void> heartbeat(DeviceKeys node, _Latency into) => into.time(
      'Heartbeat',
      () => heartbeatClient.heartbeat(
        pb.HeartbeatRequest(
          usedBytes: Int64(1 << 30),
          capacityBytes: Int64(4 << 40),
        ),
        nodeKey: node.sign,
      ),
    );
    phase = await _Phase.start(db, 'heartbeat ×3, 50 одновременно');
    await _pool(
      nodeCount * 3,
      50,
      (i) => heartbeat(nodes[i % nodeCount], latency),
    );
    await phase.finish(latency, nodeCount * 3);

    // --- Клиенты: бэкап на фоне heartbeat ------------------------------------
    // Фон: каждый узел раз в 30 с (в бою — раз в 5 минут), в 10 раз чаще
    // боевого.
    final background = _Latency();
    var stopBackground = false;
    final backgroundDone = () async {
      var i = 0;
      final interval = Duration(microseconds: 30000000 ~/ nodeCount);
      while (!stopBackground) {
        final started = DateTime.now();
        unawaited(heartbeat(nodes[i++ % nodeCount], background));
        final spent = DateTime.now().difference(started);
        if (spent < interval) await Future<void>.delayed(interval - spent);
      }
    }();

    latency.clear();
    phase = await _Phase.start(db, 'бэкап: $clientCount клиентов одновременно');
    var requests = 0;
    await _pool(clientCount, clientCount, (c) async {
      final keys = await AccountKeys.fromMasterKey(
        SecretBytes(crypto.randomBytes(32)),
        crypto,
      );
      final device = await DeviceKeys.generate(crypto);
      final client = CoordinatorClient(
        baseUri: base,
        crypto: crypto,
        deviceKey: device.sign,
      );
      await latency.time(
        'RegisterAccount',
        () async => await client.registerAccount(
          pb.RegisterAccountRequest(
            deviceCertificate: await DeviceCertificates.issue(
              crypto,
              keys,
              device,
              issuedAt: DateTime.now(),
            ),
            login: 'client$c',
          ),
          accountKey: keys.accountSign,
        ),
      );
      requests++;
      for (var s = 0; s < segmentsPerClient; s++) {
        final segmentId = crypto.randomBytes(32);
        final placed = await latency.time(
          'AllocateSegment',
          () => client.allocateSegment(
            pb.AllocateSegmentRequest(
              segmentId: segmentId,
              k: 10,
              n: 20,
              repairThreshold: 16,
              fragmentSize: (16 << 20) ~/ 10 + 96,
              fragmentIds: [
                for (var i = 0; i < 20; i++) crypto.randomBytes(32),
              ],
              bodyRoots: [for (var i = 0; i < 20; i++) crypto.randomBytes(32)],
            ),
          ),
        );
        if (placed.placements.length != 20) throw StateError('размещение');
        await latency.time(
          'CommitSegment',
          () => client.commitSegment(
            pb.CommitSegmentRequest(
              segmentId: segmentId,
              storedIndexes: [for (var i = 0; i < 20; i++) i],
            ),
          ),
        );
        requests += 2;
      }
      // Индекс: около 100 байт на сегмент и чанки — берём 64 КиБ.
      await latency.time(
        'PutObject',
        () => client.putObject(
          pb.PutObjectRequest(
            kind: pb.ObjectKind.OBJECT_KIND_INDEX,
            objectId: crypto.randomBytes(32),
            blob: crypto.randomBytes(64 << 10),
          ),
        ),
      );
      await latency.time(
        'PutObject',
        () => client.putObject(
          pb.PutObjectRequest(
            kind: pb.ObjectKind.OBJECT_KIND_SNAPSHOT,
            objectId: crypto.randomBytes(32),
            blob: crypto.randomBytes(4 << 10),
            sequence: Int64.ONE,
          ),
        ),
      );
      await latency.time(
        'ListObjects',
        () => client.listObjects(
          pb.ListObjectsRequest(kind: pb.ObjectKind.OBJECT_KIND_SNAPSHOT),
        ),
      );
      requests += 3;
      client.close();
    });
    stopBackground = true;
    await backgroundDone;
    await phase.finish(latency, requests);
    stdout.writeln('фоновый heartbeat во время бэкапа:');
    background.report();

    // --- Размеры и планы ----------------------------------------------------
    await _report(db);
    heartbeatClient.close();
  } finally {
    stop.send(null);
    await db.close();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await admin.execute(
      'DROP DATABASE IF EXISTS ${database.name} WITH (FORCE)',
    );
    await admin.close();
  }
}

/// Подписант талонов на Unix-сокете в своём isolate.
Future<void> _signer((SendPort, String) args) async {
  final (reply, socket) = args;
  final crypto = await SodiumCryptoProvider.load();
  await SignerServer.bind(
    socket,
    TicketSigningService(
      crypto: crypto,
      key: await crypto.ed25519FromSeed(SecretBytes(crypto.randomBytes(32))),
      limiter: RateLimiter(perSecond: 1000000, burst: 1 << 20),
    ),
  );
  reply.send(null);
}

/// Координатор в своём isolate; отвечает портом и SendPort для остановки.
Future<void> _serve((SendPort, DatabaseConfig) args) async {
  final (reply, database) = args;
  JsonLogWriter(stderr).attach(Level.WARNING);
  final crypto = await SodiumCryptoProvider.load();
  final config = CoordinatorConfig(
    port: 0,
    database: database,
    limits: const RateLimits(
      ipPerSecond: 1000000,
      ipBurst: 1 << 20,
      keyPerSecond: 1000000,
      keyBurst: 1 << 20,
    ),
    nodes: const NodePolicy(minCapacityBytes: 0, maxPerAccount: 1000),
    // Все узлы приходят с 127.0.0.1: подсети не различаются.
    placement: const PlacementPolicy(
      probation: Duration.zero,
      distinctSubnets: false,
    ),
  );
  final socket =
      '${Directory.systemTemp.path}/fs-load-signer-${Random().nextInt(1 << 30)}';
  final signerReady = ReceivePort();
  await Isolate.spawn(_signer, (signerReady.sendPort, socket));
  await signerReady.first;
  final server = await CoordinatorServer.start(
    config,
    crypto: crypto,
    migrate: true,
    service: (db) => DatabaseCoordinatorService(
      db: db,
      crypto: crypto,
      config: config,
      signer: SocketTicketSigner(socket),
    ),
  );
  final stop = ReceivePort();
  reply.send([server.port, stop.sendPort]);
  await stop.first;
  await server.close();
  stop.close();
}

Future<(Connection, DatabaseConfig)> _createDatabase(Uri url) async {
  final user = url.userInfo.split(':');
  final admin = await Connection.open(
    Endpoint(
      host: url.host,
      port: url.hasPort ? url.port : 5432,
      database: url.pathSegments.isEmpty ? 'postgres' : url.pathSegments.first,
      username: Uri.decodeComponent(user.first),
      password: user.length > 1 ? Uri.decodeComponent(user[1]) : null,
    ),
    settings: const ConnectionSettings(sslMode: SslMode.disable),
  );
  final name = 'fs_load_${Random().nextInt(1 << 32).toRadixString(16)}';
  await admin.execute('CREATE DATABASE $name');
  return (
    admin,
    DatabaseConfig(
      host: url.host,
      port: url.hasPort ? url.port : 5432,
      name: name,
      user: Uri.decodeComponent(user.first),
      password: user.length > 1 ? Uri.decodeComponent(user[1]) : null,
      maxConnections: 20,
    ),
  );
}

/// [count] заданий, не больше [parallel] одновременно.
Future<void> _pool(
  int count,
  int parallel,
  Future<void> Function(int i) task,
) async {
  var next = 0;
  Future<void> worker() async {
    while (next < count) {
      await task(next++);
    }
  }

  await Future.wait([for (var w = 0; w < min(parallel, count); w++) worker()]);
}

/// Время ответа по методам.
final class _Latency {
  final Map<String, List<int>> _us = {};

  Future<T> time<T>(String method, Future<T> Function() call) async {
    final watch = Stopwatch()..start();
    try {
      return await call();
    } finally {
      (_us[method] ??= []).add(watch.elapsedMicroseconds);
    }
  }

  void clear() => _us.clear();

  void report() {
    for (final MapEntry(key: method, value: list) in _us.entries) {
      list.sort();
      String p(double q) =>
          (list[min(list.length - 1, (list.length * q).floor())] / 1000)
              .toStringAsFixed(1);
      stdout.writeln(
        '  ${method.padRight(16)} ${list.length.toString().padLeft(6)}  '
        'p50 ${p(0.5)}  p95 ${p(0.95)}  p99 ${p(0.99)}  '
        'max ${(list.last / 1000).toStringAsFixed(1)} мс',
      );
    }
  }
}

/// Фаза замера: время и счётчики pg_stat_database.
final class _Phase {
  new _(this.db, this.name, this.before, this.watch);

  static Future<_Phase> start(Connection db, String name) async =>
      _Phase._(db, name, await _counters(db), Stopwatch()..start());

  final Connection db;
  final String name;
  final Map<String, int> before;
  final Stopwatch watch;

  Future<void> finish(_Latency latency, int requests) async {
    final seconds = watch.elapsedMicroseconds / 1000000;
    final after = await _counters(db);
    stdout.writeln(
      '$name: ${seconds.toStringAsFixed(1)} с, запросов $requests, '
      '${(requests / seconds).toStringAsFixed(0)} в секунду',
    );
    latency.report();
    final delta = {for (final k in after.keys) k: after[k]! - before[k]!};
    stdout.writeln(
      '  база: транзакций ${delta['xact_commit']} '
      '(${(delta['xact_commit']! / seconds).toStringAsFixed(0)}/с), откатов '
      '${delta['xact_rollback']}, строк вставлено ${delta['tup_inserted']}, '
      'изменено ${delta['tup_updated']}, удалено ${delta['tup_deleted']}, '
      'прочитано ${delta['tup_fetched']}; '
      'блоков с диска ${delta['blks_read']}, '
      'из кеша ${delta['blks_hit']}',
    );
  }

  static Future<Map<String, int>> _counters(Connection db) async {
    // Статистика обновляется с задержкой; принудительно сбросить её в
    // общий доступ нельзя, поэтому небольшая пауза.
    await Future<void>.delayed(const Duration(milliseconds: 600));
    final rows = await db.execute('''
      SELECT xact_commit, xact_rollback, tup_inserted, tup_updated,
             tup_deleted, tup_fetched, blks_read, blks_hit
        FROM pg_stat_database WHERE datname = current_database()''');
    final [a, b, c, d, e, f, g, h] = rows.single;
    return {
      'xact_commit': a! as int,
      'xact_rollback': b! as int,
      'tup_inserted': c! as int,
      'tup_updated': d! as int,
      'tup_deleted': e! as int,
      'tup_fetched': f! as int,
      'blks_read': g! as int,
      'blks_hit': h! as int,
    };
  }
}

Future<void> _report(Connection db) async {
  stdout.writeln('таблицы (строк, размер с индексами):');
  final sizes = await db.execute('''
    SELECT relname, n_live_tup, pg_total_relation_size(relid)
      FROM pg_stat_user_tables ORDER BY pg_total_relation_size(relid) DESC
      LIMIT 8''');
  for (final [name, rows, bytes] in sizes) {
    stdout.writeln(
      '  ${(name! as String).padRight(16)} ${rows.toString().padLeft(8)}  '
      '${((bytes! as int) / (1 << 20)).toStringAsFixed(1)} МиБ',
    );
  }
  final usage = await db.execute('''
    SELECT relname, seq_scan, seq_tup_read, idx_scan
      FROM pg_stat_user_tables WHERE seq_scan > 0
      ORDER BY seq_tup_read DESC LIMIT 5''');
  stdout.writeln(
    'последовательные чтения (таблица: сканов, строк; по индексу):',
  );
  for (final [name, scans, tuples, idx] in usage) {
    stdout.writeln('  $name: $scans, $tuples; $idx');
  }
  // План выбора кандидатов размещения — самый тяжёлый запрос.
  final plan = await db.execute(r'''
    EXPLAIN (ANALYZE, BUFFERS, TIMING OFF)
    SELECT node_id, account_id, subnet,
           capacity_bytes - greatest(used_bytes, assigned_bytes),
           availability, endpoints, registered_at > now()
      FROM nodes
      WHERE removed_at IS NULL AND excluded_at IS NULL
        AND account_id NOT IN (
          SELECT account_id FROM accounts WHERE blocked_at IS NOT NULL)
        AND last_heartbeat_at >= now() - interval '15 minutes'
        AND subnet IS NOT NULL
        AND capacity_bytes - greatest(used_bytes, assigned_bytes) >= 1000
        AND availability >= 0.6
        AND account_id <> '\x00'::bytea''');
  stdout.writeln('план выбора кандидатов:');
  for (final row in plan) {
    stdout.writeln('  ${row.single}');
  }
}
