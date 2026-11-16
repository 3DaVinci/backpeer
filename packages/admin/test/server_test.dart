import 'dart:convert';
import 'dart:io';

import 'package:admin/admin.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

class _ReadModel implements AdminReadModel {
  final Map<String, Object?> overviewData = {
    'generatedAt': '2026-11-16T12:00:00Z',
    'stats': {
      'accounts': 1,
      'accountsBlocked': 0,
      'devicesActive': 1,
      'nodes': 1,
      'nodesOnline': 1,
      'nodesExcluded': 0,
      'nodesOnProbation': 0,
      'capacityBytes': 1000,
      'objectBytes': 0,
      'fragmentBytes': 0,
      'segments': {'pending': 0, 'ok': 1, 'repair': 0},
      'segmentsByStoredFragments': {'10': 1},
    },
    'dataBytes': 1000,
    'objectsCount': 1,
    'storedFragments': 10,
    'damagedFragments': 0,
    'nodesFreeBytes': 1000,
    'nodesUsedBytes': 0,
    'nodesAssignedBytes': 0,
    'economy': {
      'balanceMc': 0,
      'negativeAccounts': 0,
      'blockedAccounts': 0,
      'earnedMc': 0,
      'spentMc': 0,
      'graceDays': 7,
    },
    'audits': {'passed24h': 1, 'failed24h': 0, 'latencyMs': 10, 'lastAt': null},
    'repair': {'running': 0, 'queue': 0, 'minLive': 10},
    'traffic': <String, Object?>{},
    'versions': <Object?>[],
    'countries': <Object?>[],
    'activity': {'accounts': <Object?>[], 'nodes': <Object?>[]},
    'journal': <Object?>[],
  };

  @override
  Future<Map<String, Object?>> overview() async => overviewData;

  @override
  Future<Map<String, Object?>> users({
    String query = '',
    String filter = 'all',
    String sort = 'created_desc',
    int page = 1,
    int limit = 25,
  }) async => {'items': <Object?>[], 'total': 0, 'page': page, 'limit': limit};

  @override
  Future<Map<String, Object?>?> user(String accountId) async => null;

  @override
  Future<Map<String, Object?>> nodes({
    String query = '',
    String filter = 'active',
    String sort = 'last_seen',
    String version = '',
    String country = '',
    int page = 1,
    int limit = 25,
  }) async => {'items': <Object?>[], 'total': 0, 'page': page, 'limit': limit};

  @override
  Future<Map<String, Object?>?> node(String nodeId) async => null;

  @override
  Future<Map<String, Object?>> segments({
    String query = '',
    String state = 'all',
    String sort = 'allocated_desc',
    int page = 1,
    int limit = 25,
  }) async => {'items': <Object?>[], 'total': 0, 'page': page, 'limit': limit};

  @override
  Future<Map<String, Object?>?> segment(String accountId, String segmentId) =>
      Future.value();

  @override
  Future<Map<String, Object?>> network({int hours = 24}) async => {
    'hours': hours,
    'stats': overviewData['stats'],
    'relay': <String, Object?>{},
    'repair': <String, Object?>{},
    'audits': <String, Object?>{},
  };

  @override
  Future<Map<String, Object?>> repairJobs({
    String state = 'open',
    String kind = 'all',
    int page = 1,
    int limit = 25,
  }) async => {'items': <Object?>[], 'total': 0, 'page': page, 'limit': limit};

  @override
  Future<Map<String, Object?>> audits({
    bool? passed,
    int page = 1,
    int limit = 25,
  }) async => {'items': <Object?>[], 'total': 0, 'page': page, 'limit': limit};

  @override
  Future<Map<String, Object?>> economy({int days = 30}) async => {
    'days': days,
    'policy': <String, Object?>{},
    'summary': <String, Object?>{},
    'topPositive': <Object?>[],
    'topNegative': <Object?>[],
    'ledger': <Object?>[],
    'daily': <Object?>[],
  };

  @override
  Future<Map<String, Object?>> journal({
    String query = '',
    int page = 1,
    int limit = 50,
  }) async => {'items': <Object?>[], 'total': 0, 'page': page, 'limit': limit};

  @override
  Future<Map<String, Object?>> system() async => {
    'database': {
      'user': 'fs_admin_web',
      'name': 'test',
      'version': 'PostgreSQL',
      'schema': 19,
      'readOnlyRole': 'fs_admin_web',
      'readOnly': true,
    },
    'config': <String, Object?>{},
    'counts': <String, Object?>{},
  };

  @override
  Future<List<Map<String, Object?>>> exportUsers({int limit = 10000}) async =>
      <Map<String, Object?>>[];

  @override
  Future<List<Map<String, Object?>>> exportNodes({int limit = 10000}) async =>
      <Map<String, Object?>>[];

  @override
  Future<bool> ping() async => true;
}

void main() {
  late Directory root;
  late Directory reports;
  late AdminServer server;
  late PasswordHasher hasher;
  late String hash;
  late HttpClient client;

  setUpAll(() async {
    hasher = PasswordHasher(
      DartCryptoProvider(),
      params: const Argon2Params(memoryKiB: 8 * 1024, iterations: 1),
    );
    hash = await hasher.hashPassword('operator-password-123');
  });

  setUp(() async {
    root = Directory.systemTemp.createTempSync('fs-admin-web-');
    reports = Directory.systemTemp.createTempSync('fs-admin-reports-');
    File('${root.path}/index.html').writeAsStringSync(
      '<!doctype html><title>admin</title><div id="root"></div>',
    );
    final store = await CrashReportStore.open(
      path: reports.path,
      retentionDays: 30,
      maxEntries: 100,
    );
    server = await AdminServer.start(
      AdminConfig(
        port: 0,
        cookieSecure: false,
        readOnlyRole: '',
        staticDir: root.path,
        reportsDir: reports.path,
        users: {'operator': hash},
      ),
      readModel: _ReadModel(),
      reports: store,
      hasher: hasher,
    );
    client = HttpClient();
  });

  tearDown(() async {
    client.close(force: true);
    await server.close();
    root.deleteSync(recursive: true);
    reports.deleteSync(recursive: true);
  });

  Future<({int status, Map<String, String> headers, String body})> send(
    String method,
    String path, {
    Map<String, String> headers = const {},
    String? body,
    String? cookie,
  }) async {
    final request = await client.openUrl(
      method,
      Uri.parse('http://127.0.0.1:${server.port}$path'),
    );
    headers.forEach(request.headers.set);
    if (cookie != null) request.headers.set('cookie', cookie);
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(body);
    }
    final response = await request.close();
    final text = await utf8.decoder.bind(response).join();
    final map = <String, String>{};
    response.headers.forEach((name, values) => map[name] = values.join(', '));
    return (status: response.statusCode, headers: map, body: text);
  }

  Future<String> login() async {
    final response = await send(
      'POST',
      '/api/login',
      headers: {'x-requested-with': 'BackpeerAdmin'},
      body: jsonEncode({
        'user': 'operator',
        'password': 'operator-password-123',
      }),
    );
    expect(response.status, 200);
    final setCookie = response.headers['set-cookie']!;
    return setCookie.split(';').first;
  }

  test('без входа API отвечает 401, статика открыта', () async {
    final api = await send('GET', '/api/overview');
    expect(api.status, 401);
    final index = await send('GET', '/');
    expect(index.status, 200);
    expect(index.body, contains('id="root"'));
    final spa = await send('GET', '/users/abc');
    expect(spa.status, 200);
    expect(spa.body, contains('id="root"'));
    final missing = await send('GET', '/assets/nope.js');
    expect(missing.status, 404);
    expect(
      index.headers['content-security-policy'],
      contains("default-src 'self'"),
    );
    expect(index.headers['x-frame-options'], 'DENY');
  });

  test('вход: CSRF-заголовок, неверный пароль, cookie', () async {
    final noHeader = await send(
      'POST',
      '/api/login',
      body: jsonEncode({'user': 'operator', 'password': 'x'}),
    );
    expect(noHeader.status, 403);
    final wrong = await send(
      'POST',
      '/api/login',
      headers: {'x-requested-with': 'BackpeerAdmin'},
      body: jsonEncode({'user': 'operator', 'password': 'wrong'}),
    );
    expect(wrong.status, 401);
    final cookie = await login();
    expect(cookie, startsWith('backpeer_admin='));
    final session = await send('GET', '/api/session', cookie: cookie);
    expect(session.status, 200);
    expect(
      (jsonDecode(session.body) as Map<String, Object?>)['user'],
      'operator',
    );
    final overview = await send('GET', '/api/overview', cookie: cookie);
    expect(overview.status, 200);
    expect(
      (jsonDecode(overview.body) as Map<String, Object?>)['reports'],
      isNotNull,
    );
  });

  test('приём отчётов, список, деталь и CSV', () async {
    final cookie = await login();
    final report = jsonEncode({
      'version': '0.0.7',
      'os': 'linux',
      'error': 'сбой /home/user/file',
      'stack': '#0 main',
      'at': '2026-11-16T10:00:00Z',
    });
    final ingest = await send(
      'POST',
      '/api/v1/crash-reports',
      headers: {'x-backpeer-component': 'app'},
      body: report,
    );
    expect(ingest.status, 202);
    final id =
        (jsonDecode(ingest.body) as Map<String, Object?>)['id']! as String;
    final list = await send('GET', '/api/reports', cookie: cookie);
    expect(list.status, 200);
    final page = jsonDecode(list.body) as Map<String, Object?>;
    expect(page['total'], 1);
    final items = page['items']! as List<Object?>;
    expect(
      (items.single! as Map<String, Object?>)['error'],
      contains('<path>'),
    );
    final detail = await send('GET', '/api/reports/$id', cookie: cookie);
    expect(detail.status, 200);
    final csv = await send('GET', '/api/export/reports.csv', cookie: cookie);
    expect(csv.status, 200);
    expect(csv.headers['content-type'], startsWith('text/csv'));
    expect(csv.body, contains('<path>'));
    final bad = await send(
      'POST',
      '/api/v1/crash-reports',
      body: jsonEncode({'version': '1', 'at': 'bad'}),
    );
    expect(bad.status, 400);
  });

  test('выход завершает сессию', () async {
    final cookie = await login();
    final out = await send(
      'POST',
      '/api/logout',
      headers: {'x-requested-with': 'BackpeerAdmin'},
      cookie: cookie,
    );
    expect(out.status, 200);
    final after = await send('GET', '/api/overview', cookie: cookie);
    expect(after.status, 401);
    expect(out.headers['set-cookie'], contains('Max-Age=0'));
  });
}
