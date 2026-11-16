import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:admin/src/auth.dart';
import 'package:admin/src/config.dart';
import 'package:admin/src/postgres_read_model.dart';
import 'package:admin/src/read_model.dart';
import 'package:admin/src/reports.dart';
import 'package:coordinator/coordinator.dart'
    show
        AdminAccessException,
        AdminReadAccess,
        Database,
        JsonLogWriter,
        LogEvent;
import 'package:core/core.dart' show RateLimiter, appVersion;
import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_static/shelf_static.dart';

/// HTTP-панель оператора: API только на чтение, вход по паролю, приём
/// отчётов о сбоях и собранная статика `apps/admin/dist`.
///
/// Снаружи панель ставится за прокси с TLS; cookie сессии — `Secure`,
/// `HttpOnly`, `SameSite=Strict`. Все изменяющие действия (блокировка,
/// отзыв, исключение) по-прежнему только в `coordinator admin`.
final class AdminServer {
  new _({
    required HttpServer http,
    required this.config,
    required AdminReadModel readModel,
    required this._reports,
    required this._auth,
    required this._sessions,
    required this.startedAt,
    required this.logWriter,
    required this.loginLimiter,
    required this.reportLimiter,
    this._database,
    this._pruner,
  }) : _http = http,
       _read = readModel,
       _static = createStaticHandler(
         config.staticDir,
         defaultDocument: 'index.html',
       ) {
    shelf_io.serveRequests(http, call, poweredByHeader: null);
  }

  final HttpServer _http;

  /// Фактический порт (в тестах `listen.port: 0`).
  int get port => _http.port;
  final AdminConfig config;
  final DateTime startedAt;
  final JsonLogWriter logWriter;
  final RateLimiter loginLimiter;
  final RateLimiter reportLimiter;
  final AdminReadModel _read;
  final CrashReportStore _reports;
  final AdminAuthenticator _auth;
  final SessionStore _sessions;
  final Database? _database;
  final Handler _static;
  Timer? _pruner;

  static final _log = Logger('admin');

  /// Запускает панель. [readModel], [reports] и [hasher] можно подменить в
  /// тестах; иначе открывается база и папка отчётов.
  static Future<AdminServer> start(
    AdminConfig config, {
    AdminReadModel? readModel,
    CrashReportStore? reports,
    PasswordHasher? hasher,
    Database? database,
    DateTime Function()? clock,
  }) async {
    if (config.users.isEmpty) {
      throw const AdminConfigException('auth.users: не задан ни один оператор');
    }
    final staticDir = Directory(config.staticDir);
    if (!staticDir.existsSync()) {
      throw AdminConfigException(
        'static.dir не найдена: ${config.staticDir}. Соберите панель: '
        'cd apps/admin && npm ci && npm run build (docs/ops/admin.md)',
      );
    }
    final indexPath = '${config.staticDir}/index.html';
    if (!File(indexPath).existsSync()) {
      throw AdminConfigException(
        'static.dir: нет index.html в ${config.staticDir}; соберите apps/admin',
      );
    }
    var db = database;
    var ownsDb = false;
    try {
      var model = readModel;
      if (model == null) {
        db = Database.open(config.database);
        ownsDb = true;
        if (config.readOnlyRole.isNotEmpty) {
          await AdminReadAccess.check(db, config.readOnlyRole);
        }
        model = PostgresReadModel(
          db,
          onlineWindow: config.onlineWindow,
          probation: config.probation,
          economyPolicy: config.economy,
          readOnlyRole: config.readOnlyRole,
          clock: clock,
        );
      }
      final resolvedModel = model;
      final reportStore =
          reports ??
          await CrashReportStore.open(
            path: config.reportsDir,
            retentionDays: config.reportRetentionDays,
            maxEntries: config.reportMaxEntries,
            maxMemoryBytes: config.reportMaxMemoryBytes,
            clock: clock,
          );
      final passwordHasher = hasher ?? await PasswordHasher.load();
      final sessions = SessionStore(
        lifetime: config.sessionLifetime,
        clock: clock,
      );
      final auth = AdminAuthenticator(
        users: config.users,
        hasher: passwordHasher,
        sessions: sessions,
        maxFailedAttempts: config.maxFailedLogins,
        lockDuration: config.loginLock,
        clock: clock,
      );
      final http = await HttpServer.bind(config.host, config.port);
      http
        ..idleTimeout = const Duration(seconds: 60)
        ..autoCompress = false;
      final logWriter = JsonLogWriter(stdout)..attach(config.logLevel);
      final server = AdminServer._(
        http: http,
        config: config,
        readModel: resolvedModel,
        reports: reportStore,
        auth: auth,
        sessions: sessions,
        startedAt: DateTime.now().toUtc(),
        logWriter: logWriter,
        loginLimiter: RateLimiter(perSecond: 10 / 60, burst: 10, clock: clock),
        reportLimiter: RateLimiter(
          perSecond: config.reportPerHour / 3600,
          burst: config.reportPerHour,
          clock: clock,
        ),
        database: ownsDb ? db : null,
        pruner: Timer.periodic(const Duration(hours: 24), (_) {
          unawaited(reportStore.prune().catchError((Object _) {}));
        }),
      );
      _log.info(
        LogEvent('listening', {
          'port': http.port,
          'operators': config.users.length,
          'read_only_role': config.readOnlyRole,
          'reports_dir': config.reportsDir,
        }),
      );
      return server;
    } on Object {
      if (ownsDb) await db?.close();
      rethrow;
    }
  }

  /// Останавливает приём, уборку и (если открывали) соединение с базой.
  Future<void> close() async {
    _pruner?.cancel();
    _pruner = null;
    await _http.close(force: true);
    await logWriter.detach();
    await _database?.close();
  }

  Future<Response> call(Request request) async {
    try {
      return _secure(await _dispatch(request));
    } on ApiError catch (e) {
      return _secure(_json(e.status, {'error': e.message}));
    } on CrashReportException catch (e) {
      return _secure(_json(400, {'error': e.message}));
    } on _PayloadTooLarge {
      return _secure(_json(413, {'error': 'тело запроса слишком велико'}));
    } on AdminAccessException catch (e) {
      _log.severe(LogEvent('admin_access', {'message': e.message}));
      return _secure(_json(503, {'error': 'нет прав только для чтения'}));
    } on Object catch (e, stack) {
      _log.severe(
        LogEvent('request_failed', {'path': '/${request.url.path}'}),
        e,
        stack,
      );
      return _secure(_json(500, {'error': 'внутренняя ошибка'}));
    }
  }

  Future<Response> _dispatch(Request request) async {
    final path = '/${request.url.path}';
    if (path == '/health') return await _health();
    if (path == '/api/v1/crash-reports') {
      if (request.method != 'POST') return _methodNotAllowed('POST');
      return await _ingestReport(request);
    }
    if (path == '/api/login') {
      if (request.method != 'POST') return _methodNotAllowed('POST');
      return await _login(request);
    }
    if (path == '/api/logout') {
      if (request.method != 'POST') return _methodNotAllowed('POST');
      return await _logout(request);
    }
    if (path == '/api/session') return await _sessionRoute(request);
    if (path == '/api' || path.startsWith('/api/')) {
      return await _api(request, path);
    }
    return await _staticRoute(request);
  }

  // --- вход и сессии --------------------------------------------------------

  Future<Response> _login(Request request) async {
    final ip = _clientAddress(request);
    final retry = loginLimiter.take(ip);
    if (retry != null) return _tooMany(retry);
    _checkCsrfHeader(request);
    _checkOrigin(request);
    final body = await _readJson(request, 8 * 1024);
    final user = body['user'];
    final password = body['password'];
    if (user is! String ||
        password is! String ||
        user.isEmpty ||
        user.length > 64 ||
        password.isEmpty ||
        password.length > 1024) {
      throw const ApiError(400, 'нужны имя и пароль');
    }
    final result = await _auth.login(user, password);
    if (!result.ok) {
      final until = result.lockedUntil;
      if (until != null) {
        final wait = until.difference(DateTime.now());
        _log.warning(LogEvent('login_locked', {'user': user}));
        return _json(
          429,
          {'error': 'слишком много неудачных попыток, попробуйте позже'},
          headers: {'retry-after': '${max(1, wait.inSeconds)}'},
        );
      }
      _log.warning(LogEvent('login_failed', {'user': user}));
      return _json(401, {'error': 'неверное имя или пароль'});
    }
    final session = result.session!;
    _log.info(LogEvent('login', {'user': session.user}));
    return _json(
      200,
      {
        'user': session.user,
        'expiresAt': session.expiresAt.toUtc().toIso8601String(),
      },
      headers: {'set-cookie': _cookie(session)},
    );
  }

  Future<Response> _logout(Request request) async {
    _checkCsrfHeader(request);
    _sessions.destroy(_sessionToken(request));
    return _json(200, {'ok': true}, headers: {'set-cookie': _clearCookie()});
  }

  Future<Response> _sessionRoute(Request request) async {
    if (request.method != 'GET') return _methodNotAllowed('GET');
    final session = _sessions.lookup(_sessionToken(request));
    if (session == null) throw const ApiError(401, 'нужен вход');
    return _json(200, {
      'user': session.user,
      'expiresAt': session.expiresAt.toUtc().toIso8601String(),
    });
  }

  // --- API ------------------------------------------------------------------

  Future<Response> _api(Request request, String path) async {
    if (request.method != 'GET') return _methodNotAllowed('GET');
    if (_sessions.lookup(_sessionToken(request)) == null) {
      throw const ApiError(401, 'нужен вход');
    }
    if (path == '/api/overview') {
      final overview = await _read.overview();
      overview['reports'] = _reports.summary().toJson();
      overview['recentReports'] = [
        for (final report in _reports.list(limit: 5).items) report.toJson(),
      ];
      return _json(200, overview);
    }
    if (path == '/api/users') {
      return _json(
        200,
        await _read.users(
          query: _textParam(request, 'query', 200),
          filter: _enumParam(request, 'filter', {
            'all',
            'blocked',
            'debt',
            'keepers',
            'clients',
            'inactive',
            'active',
          }),
          sort: _enumParam(request, 'sort', {
            'created_desc',
            'created_asc',
            'login',
            'storage',
            'balance',
            'balance_desc',
            'activity',
            'nodes',
          }),
          page: _intParam(request, 'page', 1, 100000, 1),
          limit: _intParam(request, 'limit', 1, 200, 25),
        ),
      );
    }
    if (path.startsWith('/api/users/')) {
      final id = path.substring('/api/users/'.length);
      final user = await _read.user(id);
      if (user == null) throw const ApiError(404, 'учётная запись не найдена');
      return _json(200, user);
    }
    if (path == '/api/nodes') {
      return _json(
        200,
        await _read.nodes(
          query: _textParam(request, 'query', 200),
          filter: _enumParam(request, 'filter', {
            'active',
            'all',
            'online',
            'offline',
            'lost',
            'excluded',
            'leaving',
            'probation',
          }),
          sort: _enumParam(request, 'sort', {
            'last_seen',
            'registered_desc',
            'capacity',
            'used',
            'availability',
            'audits',
          }),
          version: _textParam(request, 'version', 64),
          country: _textParam(request, 'country', 2),
          page: _intParam(request, 'page', 1, 100000, 1),
          limit: _intParam(request, 'limit', 1, 200, 25),
        ),
      );
    }
    if (path.startsWith('/api/nodes/')) {
      final id = path.substring('/api/nodes/'.length);
      final node = await _read.node(id);
      if (node == null) throw const ApiError(404, 'узел не найден');
      return _json(200, node);
    }
    if (path == '/api/segments') {
      return _json(
        200,
        await _read.segments(
          query: _textParam(request, 'query', 200),
          state: _enumParam(request, 'state', {
            'all',
            'pending',
            'ok',
            'repair',
            'lost',
            'stored',
          }),
          sort: _enumParam(request, 'sort', {
            'allocated_desc',
            'allocated_asc',
            'live',
            'size',
          }),
          page: _intParam(request, 'page', 1, 100000, 1),
          limit: _intParam(request, 'limit', 1, 200, 25),
        ),
      );
    }
    if (path.startsWith('/api/segments/')) {
      final rest = path.substring('/api/segments/'.length).split('/');
      if (rest.length != 2) throw const ApiError(400, 'нужны две части ключа');
      final segment = await _read.segment(rest[0], rest[1]);
      if (segment == null) throw const ApiError(404, 'сегмент не найден');
      return _json(200, segment);
    }
    if (path == '/api/network') {
      return _json(
        200,
        await _read.network(hours: _intParam(request, 'hours', 1, 24 * 90, 24)),
      );
    }
    if (path == '/api/repair-jobs') {
      return _json(
        200,
        await _read.repairJobs(
          state: _enumParam(request, 'state', {
            'open',
            'done',
            'failed',
            'all',
          }),
          kind: _enumParam(request, 'kind', {'all', 'repair', 'relocate'}),
          page: _intParam(request, 'page', 1, 100000, 1),
          limit: _intParam(request, 'limit', 1, 200, 25),
        ),
      );
    }
    if (path == '/api/audits') {
      final passed = request.url.queryParameters['passed'];
      return _json(
        200,
        await _read.audits(
          passed: passed == null
              ? null
              : passed == 'true' ||
                    (passed == 'false'
                        ? false
                        : throw const ApiError(400, 'passed: true или false')),
          page: _intParam(request, 'page', 1, 100000, 1),
          limit: _intParam(request, 'limit', 1, 200, 25),
        ),
      );
    }
    if (path == '/api/economy') {
      return _json(
        200,
        await _read.economy(days: _intParam(request, 'days', 1, 365, 30)),
      );
    }
    if (path == '/api/journal') {
      return _json(
        200,
        await _read.journal(
          query: _textParam(request, 'query', 200),
          page: _intParam(request, 'page', 1, 100000, 1),
          limit: _intParam(request, 'limit', 1, 200, 50),
        ),
      );
    }
    if (path == '/api/reports') {
      final page = _reports.list(
        query: _textParam(request, 'query', 200),
        version: _textParam(request, 'version', 64),
        os: _textParam(request, 'os', 200),
        days: _intParam(request, 'days', 0, 3650, 0),
        limit: _intParam(request, 'limit', 1, 200, 50),
        offset: _intParam(request, 'offset', 0, 1000000, 0),
      );
      return _json(200, {
        ...page.toJson(),
        'summary': _reports.summary().toJson(),
      });
    }
    if (path == '/api/reports/summary') {
      return _json(200, _reports.summary().toJson());
    }
    if (path.startsWith('/api/reports/')) {
      final report = _reports.get(path.substring('/api/reports/'.length));
      if (report == null) throw const ApiError(404, 'отчёт не найден');
      return _json(200, report.toJson());
    }
    if (path == '/api/system') {
      final system = await _read.system();
      system['service'] = {
        'version': appVersion,
        'startedAt': startedAt.toIso8601String(),
        'uptimeSeconds': DateTime.now().toUtc().difference(startedAt).inSeconds,
        'sessions': _sessions.activeCount,
        'operators': config.users.length,
        'reports': _reports.summary().toJson(),
      };
      system['config'] = {
        'host': config.host,
        'port': config.port,
        'publicUrl': config.publicUrl,
        'staticDir': config.staticDir,
        'reportsDir': config.reportsDir,
        'reportRetentionDays': config.reportRetentionDays,
        'reportPerHour': config.reportPerHour,
        'sessionHours': config.sessionLifetime.inHours,
        'onlineWindowMinutes': config.onlineWindow.inMinutes,
        'probationHours': config.probation.inHours,
        'cookieSecure': config.cookieSecure,
        'trustForwardedFor': config.trustForwardedFor,
        'readOnlyRole': config.readOnlyRole,
        'economy': {
          'dataCreditsPerTbMonth': config.economy.dataCreditsPerTbMonth,
          'storeCreditsPerTbMonth': config.economy.storeCreditsPerTbMonth,
          'barterRatio': config.economy.barterRatio,
          'starterCredits': config.economy.starterCredits,
          'graceDays': config.economy.graceDays,
        },
      };
      return _json(200, system);
    }
    if (path == '/api/export/users.csv') {
      return _csv('users.csv', await _read.exportUsers(), const [
        ('account_id', 'accountId'),
        ('login', 'login'),
        ('created_at', 'createdAt'),
        ('blocked_at', 'blockedAt'),
        ('blocked_reason', 'blockedReason'),
        ('devices', 'devicesActive'),
        ('nodes', 'nodesActive'),
        ('nodes_online', 'nodesOnline'),
        ('objects_bytes', 'objectBytes'),
        ('fragments_bytes', 'fragmentBytes'),
        ('balance_mc', 'balanceMc'),
        ('negative_since', 'negativeSince'),
        ('last_activity_at', 'lastActivityAt'),
      ]);
    }
    if (path == '/api/export/nodes.csv') {
      return _csv('nodes.csv', await _read.exportNodes(), const [
        ('node_id', 'nodeId'),
        ('owner_login', 'ownerLogin'),
        ('status', 'status'),
        ('country', 'country'),
        ('city', 'city'),
        ('registered_at', 'registeredAt'),
        ('last_heartbeat_at', 'lastHeartbeatAt'),
        ('capacity_bytes', 'capacityBytes'),
        ('used_bytes', 'usedBytes'),
        ('assigned_bytes', 'assignedBytes'),
        ('availability', 'availability'),
        ('software', 'software'),
        ('audits_passed', 'auditsPassed'),
        ('audits_failed', 'auditsFailed'),
        ('reputation', 'reputation'),
        ('relay', 'relay'),
      ]);
    }
    if (path == '/api/export/reports.csv') {
      final all = <Map<String, Object?>>[];
      var offset = 0;
      while (true) {
        final next = _reports.list(limit: 200, offset: offset);
        all.addAll([for (final report in next.items) report.toJson()]);
        if (all.length >= next.total || next.items.isEmpty) break;
        offset += next.items.length;
      }
      return _csv('crash-reports.csv', all, const [
        ('id', 'id'),
        ('at', 'at'),
        ('received_at', 'receivedAt'),
        ('version', 'version'),
        ('os', 'os'),
        ('source', 'source'),
        ('error', 'error'),
        ('stack', 'stack'),
      ]);
    }
    throw const ApiError(404, 'неизвестный метод');
  }

  // --- приём отчётов --------------------------------------------------------

  Future<Response> _ingestReport(Request request) async {
    _checkJson(request);
    final ip = _clientAddress(request);
    final retry = reportLimiter.take(ip);
    if (retry != null) return _tooMany(retry);
    final body = await _readJson(request, config.reportMaxBodyBytes);
    final source = _component(request);
    final report = await _reports.add(body, source: source);
    _log.info(
      LogEvent('crash_report', {
        'source': report.source,
        'version': report.version,
      }),
    );
    return _json(202, {
      'id': report.id,
      'receivedAt': report.receivedAt.toUtc().toIso8601String(),
    });
  }

  static String _component(Request request) {
    final header = request.headers['x-backpeer-component'];
    if (header != null && header.isNotEmpty) return header;
    final agent = request.headers['user-agent'] ?? '';
    if (agent.startsWith('backpeer-app')) return 'app';
    if (agent.startsWith('backpeer-node')) return 'node';
    if (agent.startsWith('backpeer-agent')) return 'agent';
    return 'unknown';
  }

  // --- здоровье и статика ---------------------------------------------------

  Future<Response> _health() async {
    var ok = false;
    try {
      ok = await _read.ping();
    } on Object {
      ok = false;
    }
    return _json(ok ? 200 : 503, {
      'status': ok ? 'ok' : 'unavailable',
      'version': appVersion,
    });
  }

  Future<Response> _staticRoute(Request request) async {
    if (request.method != 'GET' && request.method != 'HEAD') {
      return _methodNotAllowed('GET');
    }
    final path = request.url.path;
    if (path.startsWith('assets/') ||
        path == 'favicon.svg' ||
        path == 'robots.txt') {
      final response = await _static(request);
      if (response.statusCode == 200) {
        return response.change(
          headers: {
            'cache-control': path.startsWith('assets/')
                ? 'public, max-age=31536000, immutable'
                : 'no-cache',
          },
        );
      }
      return _json(404, {'error': 'файл не найден'});
    }
    return await _index();
  }

  Future<Response> _index() async {
    final file = File('${config.staticDir}/index.html');
    if (!file.existsSync()) {
      return _json(503, {'error': 'панель не собрана: нет index.html'});
    }
    return Response.ok(
      await file.readAsBytes(),
      headers: {
        'content-type': 'text/html; charset=utf-8',
        'cache-control': 'no-store',
      },
    );
  }

  // --- общие помощники ------------------------------------------------------

  Response _secure(Response response) {
    final headers = <String, String>{
      ...response.headers,
      'x-content-type-options': 'nosniff',
      'x-frame-options': 'DENY',
      'referrer-policy': 'no-referrer',
      'x-robots-tag': 'noindex, nofollow',
      'permissions-policy': 'geolocation=(), microphone=(), camera=()',
      'cross-origin-opener-policy': 'same-origin',
      'content-security-policy':
          "default-src 'self'; script-src 'self'; style-src 'self'; "
          "img-src 'self' data:; font-src 'self'; connect-src 'self'; "
          "base-uri 'none'; form-action 'self'; frame-ancestors 'none'",
    };
    if (config.cookieSecure) {
      headers['strict-transport-security'] =
          'max-age=31536000; includeSubDomains';
    }
    return response.change(headers: headers);
  }

  Response _json(int status, Object body, {Map<String, String>? headers}) {
    return Response(
      status,
      body: jsonEncode(body),
      headers: {
        'content-type': 'application/json; charset=utf-8',
        'cache-control': 'no-store',
        ...?headers,
      },
    );
  }

  Response _csv(
    String name,
    List<Map<String, Object?>> rows,
    List<(String, String)> columns,
  ) {
    final buffer = StringBuffer('\uFEFF')
      ..writeln(columns.map((c) => _csvCell(c.$1)).join(','));
    for (final row in rows) {
      buffer.writeln(
        columns.map((c) => _csvCell('${row[c.$2] ?? ''}')).join(','),
      );
    }
    return Response.ok(
      utf8.encode(buffer.toString()),
      headers: {
        'content-type': 'text/csv; charset=utf-8',
        'content-disposition': 'attachment; filename="$name"',
        'cache-control': 'no-store',
      },
    );
  }

  static String _csvCell(String value) {
    if (value.contains(',') ||
        value.contains('"') ||
        value.contains('\n') ||
        value.contains('\r')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  Future<Map<String, Object?>> _readJson(Request request, int maxBytes) async {
    _checkJson(request);
    final bytes = await _readBody(request, maxBytes);
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      throw const ApiError(400, 'тело не JSON');
    }
    if (decoded is! Map) {
      throw const ApiError(400, 'нужен объект JSON');
    }
    return Map<String, Object?>.from(decoded);
  }

  Future<Uint8List> _readBody(Request request, int maxBytes) async {
    final declared = request.contentLength;
    if (declared != null && declared > maxBytes) throw const _PayloadTooLarge();
    final builder = BytesBuilder(copy: false);
    var total = 0;
    await for (final chunk in request.read()) {
      total += chunk.length;
      if (total > maxBytes) throw const _PayloadTooLarge();
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  static void _checkJson(Request request) {
    final type = request.headers['content-type'] ?? '';
    if (!type.toLowerCase().startsWith('application/json')) {
      throw const ApiError(415, 'нужен content-type: application/json');
    }
  }

  static void _checkCsrfHeader(Request request) {
    if (request.headers['x-requested-with'] != 'BackpeerAdmin') {
      throw const ApiError(403, 'нет заголовка X-Requested-With');
    }
  }

  void _checkOrigin(Request request) {
    final publicUrl = config.publicUrl;
    final origin = request.headers['origin'];
    if (publicUrl == null || origin == null || origin.isEmpty) return;
    if (origin.replaceAll(RegExp(r'/+$'), '') !=
        publicUrl.replaceAll(RegExp(r'/+$'), '')) {
      throw const ApiError(403, 'чужой origin');
    }
  }

  String _sessionToken(Request request) {
    final cookie = request.headers['cookie'];
    if (cookie == null) return '';
    final name = _cookieName;
    for (final part in cookie.split(';')) {
      final trimmed = part.trim();
      if (trimmed.startsWith('$name=')) {
        return trimmed.substring(name.length + 1);
      }
    }
    return '';
  }

  String _cookie(AdminSession session) {
    final age = session.expiresAt.difference(DateTime.now()).inSeconds;
    return '$_cookieName=${session.token}; Path=/; HttpOnly; '
        'SameSite=Strict; Max-Age=$age'
        '${config.cookieSecure ? '; Secure' : ''}';
  }

  String _clearCookie() =>
      '$_cookieName=; Path=/; HttpOnly; SameSite=Strict; Max-Age=0'
      '${config.cookieSecure ? '; Secure' : ''}';

  String get _cookieName =>
      config.cookieSecure ? '__Host-backpeer_admin' : 'backpeer_admin';

  String _clientAddress(Request request) {
    if (config.trustForwardedFor) {
      final forwarded = request.headers['x-forwarded-for'];
      if (forwarded != null && forwarded.isNotEmpty) {
        final last = forwarded.split(',').last.trim();
        if (last.isNotEmpty) return last;
      }
    }
    final info = request.context['shelf.io.connection_info'];
    return info is HttpConnectionInfo ? info.remoteAddress.address : '';
  }

  static Response _methodNotAllowed(String allow) => Response(
    405,
    body: jsonEncode({'error': 'метод не поддерживается'}),
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'allow': allow,
      'cache-control': 'no-store',
    },
  );

  static Response _tooMany(Duration retry) => Response(
    429,
    body: jsonEncode({'error': 'слишком часто, попробуйте позже'}),
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'retry-after': '${max(1, retry.inSeconds)}',
      'cache-control': 'no-store',
    },
  );

  static String _textParam(Request request, String name, int max) {
    final value = request.url.queryParameters[name] ?? '';
    if (value.length > max) throw ApiError(400, '$name: слишком длинно');
    return value;
  }

  static int _intParam(
    Request request,
    String name,
    int min,
    int max,
    int fallback,
  ) {
    final raw = request.url.queryParameters[name];
    if (raw == null || raw.isEmpty) return fallback;
    final value = int.tryParse(raw);
    if (value == null || value < min || value > max) {
      throw ApiError(400, '$name: число от $min до $max');
    }
    return value;
  }

  static String _enumParam(Request request, String name, Set<String> allowed) {
    final value = request.url.queryParameters[name] ?? '';
    if (value.isEmpty) return '';
    if (!allowed.contains(value)) {
      throw ApiError(400, '$name: одно из ${allowed.join(', ')}');
    }
    return value;
  }
}

final class ApiError implements Exception {
  const new(this.status, this.message);

  final int status;
  final String message;
}

final class _PayloadTooLarge implements Exception {
  const new();
}
