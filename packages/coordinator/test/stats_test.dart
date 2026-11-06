// Публичная сводка о сети для сайта (задача С.3.5): числа, CORS, кеш,
// места узлов по geoip. Нужен FS_TEST_POSTGRES.

import 'dart:convert';
import 'dart:io';

import 'package:coordinator/coordinator.dart';
import 'package:core/core.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'support/db_harness.dart';
import 'support/harness.dart';
import 'support/postgres.dart';

const _geo = '''
1.0.0.0,1.0.0.255,AU,Australia,Queensland,Brisbane,-27.4679,153.0281
2.0.0.0,2.0.0.255,DE,Germany,Berlin,Berlin,52.5244,13.4105
''';

const _site = 'https://backpeer.test';

void main() {
  if (testPostgresUrl == null) {
    test('сводка о сети', () {}, skip: skipWithoutPostgres);
    return;
  }

  late Directory dir;
  late GeoDatabase geo;
  late DbHarness h;
  late AccountKeys owner;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('stats-geoip');
    File('${dir.path}/dbip-city-lite.csv').writeAsStringSync(_geo);
    geo = (await GeoDatabase.open(dir.path))!;
    h = await DbHarness.create(
      geo: geo,
      stats: true,
      statsPolicy: const StatsPolicy(
        allowedOrigins: [_site],
        maxAge: Duration.zero,
        perMinute: 1000,
      ),
    );
    owner = await h.newAccount();
    await h.register(owner, await h.newKey(), login: 'owner');
  });

  tearDown(() async {
    await h.close();
    dir.deleteSync(recursive: true);
  });

  Future<Response> get({String? origin, String method = 'GET'}) =>
      h.handler.call(
        Request(
          method,
          Uri.parse('http://coordinator.test/api/v1/NetworkStats'),
          headers: {'origin': ?origin},
        ),
      );

  Future<Map<String, Object?>> json(Response response) async =>
      jsonDecode(utf8.decode(await bodyOf(response))) as Map<String, Object?>;

  Future<Ed25519KeyPair> node(
    String ip, {
    int capacity = 1000,
    int used = 0,
  }) async {
    final node = await h.newKey();
    await h.registerNode(owner, node, ip: ip, capacity: capacity);
    await h.heartbeat(
      node,
      ip: ip,
      used: used,
      capacity: capacity,
      free: capacity - used,
    );
    return node;
  }

  test('узлы, место, объём и города', () async {
    await node('1.0.0.7', used: 100);
    await node('2.0.0.9', capacity: 2000, used: 200);
    // Узел с частного адреса: в числах есть, на карте — нет.
    await h.registerNode(
      owner,
      await h.newKey(),
      ip: '10.0.0.5',
      capacity: 500,
    );

    final response = await get(origin: _site);
    expect(response.statusCode, 200);
    expect(response.headers['access-control-allow-origin'], _site);
    expect(response.headers['vary'], contains('Origin'));
    expect(response.headers['cache-control'], contains('max-age=0'));

    final body = await json(response);
    expect(body['schema'], 1);
    expect(body['hosts'], {'available': 3, 'known': 3});
    expect(body['space'], {
      'freeBytes': 900 + 1800 + 500,
      'capacityBytes': 3500,
    });
    expect(body['data'], {'storedBytes': 0, 'fragmentBytes': 300});
    expect(body['countries'], [
      {'code': 'AU', 'hosts': 1},
      {'code': 'DE', 'hosts': 1},
    ]);
    expect(body['cities'], [
      {
        'country': 'AU',
        'city': 'Brisbane',
        'latitude': -27.47,
        'longitude': 153.03,
        'hosts': 1,
      },
      {
        'country': 'DE',
        'city': 'Berlin',
        'latitude': 52.52,
        'longitude': 13.41,
        'hosts': 1,
      },
    ]);
  });

  test('чужой источник не получает CORS, но данные отдаются', () async {
    await node('1.0.0.7');
    final response = await get(origin: 'https://evil.test');
    expect(response.statusCode, 200);
    expect(response.headers['access-control-allow-origin'], isNull);
  });

  test('OPTIONS разрешён только своему источнику', () async {
    final ok = await get(origin: _site, method: 'OPTIONS');
    expect(ok.statusCode, 204);
    expect(ok.headers['access-control-allow-origin'], _site);
    expect(ok.headers['access-control-allow-methods'], contains('GET'));
    final bad = await get(origin: 'https://evil.test', method: 'OPTIONS');
    expect(bad.statusCode, 403);
  });

  test('только GET и HEAD', () async {
    final response = await get(method: 'POST');
    expect(response.statusCode, 405);
    expect(response.headers['allow'], contains('GET'));
  });

  test('ушедший узел пропадает из сводки', () async {
    await node('1.0.0.7');
    expect((await json(await get()))['hosts'], {'available': 1, 'known': 1});
    h.clock.advance(const Duration(minutes: 16));
    final body = await json(await get());
    expect(body['hosts'], {'available': 0, 'known': 1});
    expect(body['countries'], isEmpty);
  });

  test('heartbeat с другого адреса переносит узел на карте', () async {
    final mover = await node('1.0.0.7');
    final first = await json(await get());
    expect((first['countries']! as List).single, {'code': 'AU', 'hosts': 1});
    await h.heartbeat(mover, ip: '2.0.0.9', capacity: 1000, free: 1000);
    final second = await json(await get());
    expect((second['countries']! as List).single, {'code': 'DE', 'hosts': 1});
  });

  test('без настройки сводка закрыта', () async {
    final closed = await DbHarness.create();
    try {
      final response = await closed.handler.call(
        Request(
          'GET',
          Uri.parse('http://coordinator.test/api/v1/NetworkStats'),
        ),
      );
      expect(response.statusCode, 404);
    } finally {
      await closed.close();
    }
  });

  test('города с числом узлов меньше порога скрыты', () async {
    final hidden = await DbHarness.create(
      geo: geo,
      stats: true,
      statsPolicy: const StatsPolicy(
        allowedOrigins: [_site],
        maxAge: Duration.zero,
        minCityHosts: 2,
      ),
    );
    try {
      final account = await hidden.newAccount();
      await hidden.register(account, await hidden.newKey(), login: 'other');
      final single = await hidden.newKey();
      await hidden.registerNode(account, single, ip: '1.0.0.7');
      final response = await hidden.handler.call(
        Request(
          'GET',
          Uri.parse('http://coordinator.test/api/v1/NetworkStats'),
          headers: {'origin': _site},
        ),
      );
      expect(response.statusCode, 200);
      final body = jsonDecode(
        utf8.decode(await bodyOf(response)),
      ) as Map<String, Object?>;
      expect(body['cities'], isEmpty);
    } finally {
      await hidden.close();
    }
  });
}
