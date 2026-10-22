import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:coordinator/src/auth/request_verifier.dart';
import 'package:coordinator/src/limits/rate_limiter.dart';
import 'package:coordinator/src/log.dart';
import 'package:coordinator/src/rpc/call_context.dart';
import 'package:coordinator/src/rpc/errors.dart';
import 'package:coordinator/src/rpc/methods.dart';
import 'package:core/core.dart';
import 'package:logging/logging.dart';
import 'package:protocol/protocol.dart' as pb;
import 'package:shelf/shelf.dart';

const _protobufType = 'application/x-protobuf';
const _apiPrefix = '/api/v1/';

/// HTTP-обработчик координатора (protocol.md, раздел 4): `POST
/// /api/v1/<Метод>` и `GET /health`.
final class ApiHandler {
  new({
    required List<RpcMethod> methods,
    required this.verifier,
    required this.ipLimiter,
    required this.keyLimiter,
    required this.healthCheck,
    this.trustForwardedFor = false,
  }) : _methods = {for (final m in methods) m.path: m};

  final Map<String, RpcMethod> _methods;
  final RequestVerifier verifier;
  final RateLimiter ipLimiter;
  final RateLimiter keyLimiter;

  /// `true` — база данных отвечает.
  final Future<bool> Function() healthCheck;

  /// Брать адрес клиента из последнего значения `X-Forwarded-For`
  /// (координатор за обратным прокси).
  final bool trustForwardedFor;

  static final _log = Logger('coordinator.api');
  final _random = Random.secure();

  Future<Response> call(Request request) async {
    final path = '/${request.url.path}';
    if (path == '/health') return await _health(request);
    if (!path.startsWith(_apiPrefix)) {
      return _plainNotFound();
    }

    final started = DateTime.now();
    final requestId = _newRequestId();
    final method = _methods[path];
    var bytesIn = 0;
    var code = 'OK';
    Response response;
    try {
      if (method == null) {
        throw const RpcException(
          pb.ErrorCode.ERROR_CODE_NOT_FOUND,
          'неизвестный метод',
        );
      }
      if (request.method != 'POST') {
        throw const RpcException(
          pb.ErrorCode.ERROR_CODE_BAD_REQUEST,
          'нужен метод POST',
          httpStatus: 405,
        );
      }
      if (request.url.hasQuery) {
        throw const RpcException(
          pb.ErrorCode.ERROR_CODE_BAD_REQUEST,
          'строка запроса не поддерживается',
        );
      }
      _limit(ipLimiter, _clientAddress(request), 'IP');
      _checkContentType(request);
      final body = await _readBody(request, method.maxBodyBytes);
      bytesIn = body.length;
      final caller = await verifier.verify(
        requirement: method.auth,
        path: path,
        header: request.headers[RequestAuth.headerName],
        body: body,
      );
      if (caller != null) {
        _limit(keyLimiter, String.fromCharCodes(caller.publicKey), 'ключ');
      }
      final context = CallContext(
        method: method.name,
        requestId: requestId,
        caller: caller,
      );
      response = _protobuf(200, await method.call(context, body), requestId);
    } on RpcException catch (e) {
      code = errorCodeName(e.code);
      response = _error(e, requestId);
    } on Object catch (e, stack) {
      _log.severe(
        LogEvent('unhandled', {'rid': requestId, 'method': method?.name}),
        e,
        stack,
      );
      code = 'INTERNAL';
      response = _error(
        const RpcException(
          pb.ErrorCode.ERROR_CODE_INTERNAL,
          'внутренняя ошибка',
        ),
        requestId,
      );
    }
    _logRequest(method?.name, code, response, started, requestId, bytesIn);
    return response;
  }

  void _limit(RateLimiter limiter, String key, String what) {
    final wait = limiter.take(key);
    if (wait != null) {
      throw RpcException(
        pb.ErrorCode.ERROR_CODE_RATE_LIMITED,
        'превышена частота запросов ($what)',
        retryAfter: wait,
      );
    }
  }

  static void _checkContentType(Request request) {
    final type = request.headers[HttpHeaders.contentTypeHeader];
    final mime = type?.split(';').first.trim().toLowerCase();
    if (mime != _protobufType) {
      throw const RpcException(
        pb.ErrorCode.ERROR_CODE_BAD_REQUEST,
        'Content-Type должен быть $_protobufType',
        httpStatus: 415,
      );
    }
  }

  static Future<Uint8List> _readBody(Request request, int limit) async {
    const tooLarge = RpcException(
      pb.ErrorCode.ERROR_CODE_BAD_REQUEST,
      'тело запроса больше предела',
      httpStatus: 413,
    );
    final declared = request.contentLength;
    if (declared != null && declared > limit) throw tooLarge;
    final builder = BytesBuilder(copy: false);
    await for (final chunk in request.read()) {
      if (builder.length + chunk.length > limit) throw tooLarge;
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  String _clientAddress(Request request) {
    if (trustForwardedFor) {
      final forwarded = request.headers['x-forwarded-for'];
      if (forwarded != null && forwarded.isNotEmpty) {
        return forwarded.split(',').last.trim();
      }
    }
    final info = request.context['shelf.io.connection_info'];
    return info is HttpConnectionInfo ? info.remoteAddress.address : '';
  }

  Future<Response> _health(Request request) async {
    if (request.method != 'GET' && request.method != 'HEAD') {
      return Response(405, headers: {'allow': 'GET, HEAD'});
    }
    var ok = false;
    try {
      ok = await healthCheck().timeout(const Duration(seconds: 2));
    } on Object catch (e) {
      _log.warning(const LogEvent('health-check-failed'), e);
    }
    return Response(
      ok ? 200 : 503,
      body: ok ? '{"status":"ok"}' : '{"status":"unavailable"}',
      headers: {
        HttpHeaders.contentTypeHeader: 'application/json',
        HttpHeaders.cacheControlHeader: 'no-store',
      },
    );
  }

  static Response _plainNotFound() => Response.notFound(
    null,
    headers: {HttpHeaders.cacheControlHeader: 'no-store'},
  );

  static Response _protobuf(int status, List<int> body, String requestId) =>
      Response(
        status,
        body: body,
        headers: {
          HttpHeaders.contentTypeHeader: _protobufType,
          HttpHeaders.cacheControlHeader: 'no-store',
          'fs-request-id': requestId,
        },
      );

  static Response _error(RpcException e, String requestId) {
    final response = _protobuf(
      e.status,
      e.toProto().writeToBuffer(),
      requestId,
    );
    final retry = e.retryAfter;
    final allow = e.httpStatus == 405 ? {'allow': 'POST'} : null;
    if (retry == null && allow == null) return response;
    return response.change(
      headers: {
        if (retry != null)
          HttpHeaders.retryAfterHeader:
              '${(retry.inMilliseconds / 1000).ceil()}',
        ...?allow,
      },
    );
  }

  void _logRequest(
    String? method,
    String code,
    Response response,
    DateTime started,
    String requestId,
    int bytesIn,
  ) {
    _log.info(
      LogEvent('request', {
        'rid': requestId,
        'method': method,
        'status': response.statusCode,
        'code': code,
        'ms': DateTime.now().difference(started).inMilliseconds,
        'in': bytesIn,
        'out': response.contentLength,
      }),
    );
  }

  String _newRequestId() =>
      bytesToHex(List<int>.generate(8, (_) => _random.nextInt(256)));
}
