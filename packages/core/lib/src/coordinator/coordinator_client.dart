import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:core/src/crypto/crypto_provider.dart';
import 'package:core/src/crypto/request_auth.dart';
import 'package:core/src/errors.dart';
import 'package:core/src/snapshot/manifest_objects.dart';
import 'package:protobuf/protobuf.dart';
import 'package:protocol/protocol.dart' as pb;

/// Повторы запросов к координатору.
final class RetryPolicy {
  const new({
    this.maxAttempts = 5,
    this.initialDelay = const Duration(milliseconds: 250),
    this.maxDelay = const Duration(seconds: 15),
  });

  /// Попыток всего, с первой.
  final int maxAttempts;

  /// Пауза перед второй попыткой; дальше удваивается до [maxDelay].
  final Duration initialDelay;
  final Duration maxDelay;

  /// Без повторов.
  static const none = RetryPolicy(maxAttempts: 1);

  /// Пауза перед попыткой номер [attempt] + 1 (с 1): экспоненциальная со
  /// случайной долей («полный разброс»), чтобы клиенты после сбоя не
  /// приходили одновременно; не меньше [retryAfter] координатора.
  Duration delay(int attempt, Duration? retryAfter, math.Random random) {
    final shift = math.min(attempt - 1, 20);
    final cap = math.min(
      initialDelay.inMicroseconds * (1 << shift),
      maxDelay.inMicroseconds,
    );
    final jittered = Duration(
      microseconds: cap ~/ 2 + random.nextInt(math.max(1, cap ~/ 2)),
    );
    if (retryAfter != null && retryAfter > jittered) return retryAfter;
    return jittered;
  }
}

/// HTTP-клиент API координатора (задача 2.8.1; protocol.md, раздел 4).
///
/// - Запросы подписываются заголовком `FS-Auth` ([RequestAuth]) ключом
///   устройства или ключом, переданным в вызов (учётной записи, узла);
///   каждая попытка подписывается заново с новым временем (раздел 4.2).
/// - Повторяются `UNAVAILABLE`, `RATE_LIMITED`, ответы прокси 502–504 без
///   тела `Error` и сбои связи — с экспоненциальной паузой и не раньше
///   `retry_after_ms`. Ошибки TLS не повторяются: это не сбой сети, а
///   неверный сертификат.
/// - Повтор после обрыва может прийти к координатору, уже выполнившему
///   запрос: `RegisterAccount` тогда ответит `ALREADY_EXISTS`,
///   `DeleteSegment` — `NOT_FOUND`; остальные методы повторы выдерживают.
/// - TLS: сертификат координатора проверяется по системным корневым
///   сертификатам или по `trustedCertificates` (тестовый стенд со своим
///   УЦ). Без TLS (`http`) — только к адресу на этой машине.
///
/// Ошибки — [CoordinatorException].
final class CoordinatorClient {
  new({
    required this.baseUri,
    required this.crypto,
    this.deviceKey,
    this.retry = const RetryPolicy(),
    this.requestTimeout = const Duration(seconds: 30),
    SecurityContext? trustedCertificates,
    String? userAgent,
    math.Random? random,
    Future<void> Function(Duration)? sleep,
  }) : _http = HttpClient(context: trustedCertificates)
         ..connectionTimeout = const Duration(seconds: 10)
         ..userAgent = userAgent,
       _random = random ?? math.Random(),
       _sleep = sleep ?? Future<void>.delayed {
    const local = {'localhost', '127.0.0.1', '::1', '[::1]'};
    if (baseUri.scheme != 'https' &&
        !(baseUri.scheme == 'http' && local.contains(baseUri.host))) {
      throw ArgumentError.value(
        baseUri,
        'baseUri',
        'нужен https (http — только к localhost)',
      );
    }
  }

  final Uri baseUri;
  final CryptoProvider crypto;

  /// Ключ устройства для методов, которые подписывает устройство.
  final Ed25519KeyPair? deviceKey;

  final RetryPolicy retry;
  final Duration requestTimeout;

  final HttpClient _http;
  final math.Random _random;
  final Future<void> Function(Duration) _sleep;

  static const _contentType = 'application/x-protobuf';

  /// Вызов метода [method] (`PutObject`). [key] — ключ подписи; `null` —
  /// [deviceKey]; [unsigned] — без подписи (`GetLoginParams`,
  /// `GetKeyBundle`).
  Future<R> call<R extends GeneratedMessage>(
    String method,
    GeneratedMessage request,
    R Function(List<int>) parse, {
    Ed25519KeyPair? key,
    bool unsigned = false,
  }) async {
    final signer = unsigned ? null : (key ?? deviceKey);
    if (!unsigned && signer == null) {
      throw StateError('нет ключа для подписи $method');
    }
    final path = '${_basePath()}/api/v1/$method';
    final body = request.writeToBuffer();
    for (var attempt = 1; ; attempt++) {
      try {
        final bytes = await _attempt(path, body, signer);
        try {
          final response = ManifestObjects.parseMessage<R>(
            method,
            () => parse(bytes),
          );
          return response;
        } on DataFormatException {
          throw CoordinatorException(
            pb.ErrorCode.ERROR_CODE_INTERNAL,
            'ответ $method не разбирается',
            httpStatus: 200,
          );
        }
      } on CoordinatorException catch (e) {
        if (!_retryable(e) || attempt >= retry.maxAttempts) rethrow;
        await _sleep(retry.delay(attempt, e.retryAfter, _random));
      }
    }
  }

  /// Путь канала команд узла (protocol.md, раздел 4.10).
  static const nodeChannelPath = '/api/v1/NodeChannel';

  /// Открывает канал команд узла: WebSocket к [nodeChannelPath] с
  /// подписью `FS-Auth` ключом [nodeKey] над путём и пустым телом. Тот же
  /// TLS, что у запросов; сжатие выключено. Отказ координатора (ошибка
  /// подписи, перегрузка, старый координатор без канала) и сбой связи —
  /// [CoordinatorException] с кодом `UNAVAILABLE`: причину отказа узел
  /// узнаёт из обычного heartbeat по HTTP.
  Future<WebSocket> openNodeChannel({required Ed25519KeyPair nodeKey}) async {
    final path = '${_basePath()}$nodeChannelPath';
    final auth = await RequestAuth.sign(
      crypto,
      nodeKey,
      path: path,
      body: const [],
    );
    final url = baseUri.replace(
      scheme: baseUri.scheme == 'https' ? 'wss' : 'ws',
      path: path,
    );
    try {
      return await WebSocket.connect(
        url.toString(),
        headers: {RequestAuth.headerName: auth.toHeader()},
        compression: CompressionOptions.compressionOff,
        customClient: _http,
      ).timeout(requestTimeout);
    } on TlsException catch (e) {
      throw CoordinatorException(
        pb.ErrorCode.ERROR_CODE_UNAUTHENTICATED,
        'TLS: ${e.message}',
      );
    } on IOException catch (e) {
      // WebSocketException и HttpException — тоже IOException.
      throw CoordinatorException(
        pb.ErrorCode.ERROR_CODE_UNAVAILABLE,
        'канал не открыт: ${e.runtimeType}',
      );
    } on TimeoutException {
      throw const CoordinatorException(
        pb.ErrorCode.ERROR_CODE_UNAVAILABLE,
        'канал не открыт: нет ответа',
      );
    }
  }

  void close({bool force = false}) => _http.close(force: force);

  String _basePath() {
    final p = baseUri.path;
    return p.endsWith('/') ? p.substring(0, p.length - 1) : p;
  }

  Future<Uint8List> _attempt(
    String path,
    Uint8List body,
    Ed25519KeyPair? signer,
  ) async {
    final auth = signer == null
        ? null
        : await RequestAuth.sign(crypto, signer, path: path, body: body);
    final HttpClientResponse response;
    final Uint8List bytes;
    try {
      final request = await _http
          .postUrl(baseUri.replace(path: path))
          .timeout(requestTimeout);
      request.headers
        ..set(HttpHeaders.contentTypeHeader, _contentType)
        ..contentLength = body.length;
      if (auth != null) request.headers.set('FS-Auth', auth.toHeader());
      request.add(body);
      response = await request.close().timeout(requestTimeout);
      bytes = await _read(response).timeout(requestTimeout);
    } on TlsException catch (e) {
      throw CoordinatorException(
        pb.ErrorCode.ERROR_CODE_UNAUTHENTICATED,
        'TLS: ${e.message}',
      );
    } on IOException catch (e) {
      throw CoordinatorException(
        pb.ErrorCode.ERROR_CODE_UNAVAILABLE,
        'нет связи: ${e.runtimeType}',
      );
    } on TimeoutException {
      throw const CoordinatorException(
        pb.ErrorCode.ERROR_CODE_UNAVAILABLE,
        'нет ответа',
      );
    }
    if (response.statusCode == 200) return bytes;
    throw _error(response, bytes);
  }

  /// Тело ответа целиком; больше 9 МиБ — сбой (блоб до 8 МиБ и поля).
  static Future<Uint8List> _read(HttpClientResponse response) async {
    const limit = 9 * 1024 * 1024;
    final out = BytesBuilder(copy: false);
    await for (final chunk in response) {
      out.add(chunk);
      if (out.length > limit) {
        throw const CoordinatorException(
          pb.ErrorCode.ERROR_CODE_INTERNAL,
          'ответ больше 9 МиБ',
        );
      }
    }
    return out.takeBytes();
  }

  static CoordinatorException _error(
    HttpClientResponse response,
    Uint8List bytes,
  ) {
    final status = response.statusCode;
    final isProtobuf = response.headers.contentType?.mimeType == _contentType;
    if (isProtobuf) {
      try {
        final error = ManifestObjects.parseMessage(
          'Error',
          () => pb.Error.fromBuffer(bytes),
        );
        if (error.code != pb.ErrorCode.ERROR_CODE_UNSPECIFIED) {
          return CoordinatorException(
            error.code,
            error.message,
            retryAfter: error.retryAfterMs == 0
                ? null
                : Duration(milliseconds: error.retryAfterMs),
            httpStatus: status,
          );
        }
      } on DataFormatException {
        // Битый ответ ошибки — по статусу, как ниже.
      }
    }
    // Ответ без тела Error: прокси, балансировщик.
    final retryAfter = int.tryParse(
      response.headers.value(HttpHeaders.retryAfterHeader) ?? '',
    );
    return CoordinatorException(
      switch (status) {
        429 => pb.ErrorCode.ERROR_CODE_RATE_LIMITED,
        502 || 503 || 504 => pb.ErrorCode.ERROR_CODE_UNAVAILABLE,
        _ => pb.ErrorCode.ERROR_CODE_INTERNAL,
      },
      'HTTP $status',
      retryAfter: retryAfter == null ? null : Duration(seconds: retryAfter),
      httpStatus: status,
    );
  }

  static bool _retryable(CoordinatorException e) =>
      e.code == pb.ErrorCode.ERROR_CODE_UNAVAILABLE ||
      e.code == pb.ErrorCode.ERROR_CODE_RATE_LIMITED;

  // --- Методы (coordinator.proto) -------------------------------------------

  Future<pb.RegisterAccountResponse> registerAccount(
    pb.RegisterAccountRequest request, {
    required Ed25519KeyPair accountKey,
  }) => call(
    'RegisterAccount',
    request,
    pb.RegisterAccountResponse.fromBuffer,
    key: accountKey,
  );

  Future<pb.AddDeviceResponse> addDevice(
    pb.AddDeviceRequest request, {
    required Ed25519KeyPair accountKey,
  }) => call(
    'AddDevice',
    request,
    pb.AddDeviceResponse.fromBuffer,
    key: accountKey,
  );

  Future<pb.ListDevicesResponse> listDevices({
    required Ed25519KeyPair accountKey,
  }) => call(
    'ListDevices',
    pb.ListDevicesRequest(),
    pb.ListDevicesResponse.fromBuffer,
    key: accountKey,
  );

  Future<pb.RevokeDeviceResponse> revokeDevice(
    pb.RevokeDeviceRequest request, {
    required Ed25519KeyPair accountKey,
  }) => call(
    'RevokeDevice',
    request,
    pb.RevokeDeviceResponse.fromBuffer,
    key: accountKey,
  );

  Future<pb.SetKeyBundleResponse> setKeyBundle(
    pb.SetKeyBundleRequest request, {
    required Ed25519KeyPair accountKey,
  }) => call(
    'SetKeyBundle',
    request,
    pb.SetKeyBundleResponse.fromBuffer,
    key: accountKey,
  );

  Future<pb.GetLoginParamsResponse> getLoginParams(
    pb.GetLoginParamsRequest request,
  ) => call(
    'GetLoginParams',
    request,
    pb.GetLoginParamsResponse.fromBuffer,
    unsigned: true,
  );

  Future<pb.GetKeyBundleResponse> getKeyBundle(
    pb.GetKeyBundleRequest request,
  ) => call(
    'GetKeyBundle',
    request,
    pb.GetKeyBundleResponse.fromBuffer,
    unsigned: true,
  );

  Future<pb.PutObjectResponse> putObject(pb.PutObjectRequest request) =>
      call('PutObject', request, pb.PutObjectResponse.fromBuffer);

  Future<pb.ListObjectsResponse> listObjects(pb.ListObjectsRequest request) =>
      call('ListObjects', request, pb.ListObjectsResponse.fromBuffer);

  Future<pb.GetObjectResponse> getObject(pb.GetObjectRequest request) =>
      call('GetObject', request, pb.GetObjectResponse.fromBuffer);

  Future<pb.DeleteObjectResponse> deleteObject(
    pb.DeleteObjectRequest request,
  ) => call('DeleteObject', request, pb.DeleteObjectResponse.fromBuffer);

  Future<pb.AllocateSegmentResponse> allocateSegment(
    pb.AllocateSegmentRequest request,
  ) => call('AllocateSegment', request, pb.AllocateSegmentResponse.fromBuffer);

  Future<pb.CommitSegmentResponse> commitSegment(
    pb.CommitSegmentRequest request,
  ) => call('CommitSegment', request, pb.CommitSegmentResponse.fromBuffer);

  Future<pb.LocateSegmentResponse> locateSegment(
    pb.LocateSegmentRequest request,
  ) => call('LocateSegment', request, pb.LocateSegmentResponse.fromBuffer);

  Future<pb.DeleteSegmentResponse> deleteSegment(
    pb.DeleteSegmentRequest request,
  ) => call('DeleteSegment', request, pb.DeleteSegmentResponse.fromBuffer);

  Future<pb.RegisterNodeResponse> registerNode(
    pb.RegisterNodeRequest request, {
    required Ed25519KeyPair nodeKey,
  }) => call(
    'RegisterNode',
    request,
    pb.RegisterNodeResponse.fromBuffer,
    key: nodeKey,
  );

  Future<pb.HeartbeatResponse> heartbeat(
    pb.HeartbeatRequest request, {
    required Ed25519KeyPair nodeKey,
  }) =>
      call('Heartbeat', request, pb.HeartbeatResponse.fromBuffer, key: nodeKey);

  Future<pb.ReportDamagedFragmentsResponse> reportDamagedFragments(
    pb.ReportDamagedFragmentsRequest request, {
    required Ed25519KeyPair nodeKey,
  }) => call(
    'ReportDamagedFragments',
    request,
    pb.ReportDamagedFragmentsResponse.fromBuffer,
    key: nodeKey,
  );

  /// Отчёт исполнителя ремонта (protocol.md, раздел 4.14).
  Future<pb.ReportRepairResponse> reportRepair(
    pb.ReportRepairRequest request, {
    required Ed25519KeyPair nodeKey,
  }) => call(
    'ReportRepair',
    request,
    pb.ReportRepairResponse.fromBuffer,
    key: nodeKey,
  );

  /// Выход узла из сети или ход переноса (protocol.md, раздел 4.15).
  Future<pb.LeaveNetworkResponse> leaveNetwork(
    pb.LeaveNetworkRequest request, {
    required Ed25519KeyPair nodeKey,
  }) => call(
    'LeaveNetwork',
    request,
    pb.LeaveNetworkResponse.fromBuffer,
    key: nodeKey,
  );

  /// Сверка фрагментов узла (protocol.md, раздел 4.15).
  Future<pb.ReconcileFragmentsResponse> reconcileFragments(
    pb.ReconcileFragmentsRequest request, {
    required Ed25519KeyPair nodeKey,
  }) => call(
    'ReconcileFragments',
    request,
    pb.ReconcileFragmentsResponse.fromBuffer,
    key: nodeKey,
  );

  /// Здоровье бэкапа учётной записи (protocol.md, раздел 4.16).
  Future<pb.GetBackupHealthResponse> getBackupHealth(
    pb.GetBackupHealthRequest request,
  ) => call('GetBackupHealth', request, pb.GetBackupHealthResponse.fromBuffer);

  Future<pb.CheckReachabilityResponse> checkReachability(
    pb.CheckReachabilityRequest request, {
    required Ed25519KeyPair nodeKey,
  }) => call(
    'CheckReachability',
    request,
    pb.CheckReachabilityResponse.fromBuffer,
    key: nodeKey,
  );

  /// Адреса сводника (protocol.md, раздел 4.11). [key] — ключ узла;
  /// `null` — ключ устройства.
  Future<pb.GetRendezvousInfoResponse> getRendezvousInfo({
    Ed25519KeyPair? key,
  }) => call(
    'GetRendezvousInfo',
    pb.GetRendezvousInfoRequest(),
    pb.GetRendezvousInfoResponse.fromBuffer,
    key: key,
  );

  /// Сведение с узлом; [key] — ключ узла при ремонте, `null` — ключ
  /// устройства.
  Future<pb.RendezvousResponse> rendezvous(
    pb.RendezvousRequest request, {
    Ed25519KeyPair? key,
  }) => call('Rendezvous', request, pb.RendezvousResponse.fromBuffer, key: key);

  /// Пропуск к relay (protocol.md, раздел 4.12): узлу — LISTEN к себе
  /// ([key] — ключ узла, `node_id` — свой), инициатору — CONNECT к узлу.
  /// [key] `null` — ключ устройства.
  Future<pb.GetRelayPassResponse> getRelayPass(
    pb.GetRelayPassRequest request, {
    Ed25519KeyPair? key,
  }) => call(
    'GetRelayPass',
    request,
    pb.GetRelayPassResponse.fromBuffer,
    key: key,
  );

  /// Отчёт relay о трафике; подписан ключом relay.
  Future<pb.ReportRelayUsageResponse> reportRelayUsage(
    pb.ReportRelayUsageRequest request, {
    required Ed25519KeyPair relayKey,
  }) => call(
    'ReportRelayUsage',
    request,
    pb.ReportRelayUsageResponse.fromBuffer,
    key: relayKey,
  );

  /// Отчёт о трафике фрагментов по способам подключения; [key] — ключ
  /// узла, `null` — ключ устройства.
  Future<pb.ReportTrafficResponse> reportTraffic(
    pb.ReportTrafficRequest request, {
    Ed25519KeyPair? key,
  }) => call(
    'ReportTraffic',
    request,
    pb.ReportTrafficResponse.fromBuffer,
    key: key,
  );

  Future<pb.ListRevocationsResponse> listRevocations(
    pb.ListRevocationsRequest request, {
    required Ed25519KeyPair nodeKey,
  }) => call(
    'ListRevocations',
    request,
    pb.ListRevocationsResponse.fromBuffer,
    key: nodeKey,
  );

  /// Узел начинает привязку к учётной записи (protocol.md, раздел 4.17);
  /// [nodeKey] — ключ узла, ещё без сертификата.
  Future<pb.NodePairStartResponse> nodePairStart(
    pb.NodePairStartRequest request, {
    required Ed25519KeyPair nodeKey,
  }) => call(
    'NodePairStart',
    request,
    pb.NodePairStartResponse.fromBuffer,
    key: nodeKey,
  );

  /// Узел спрашивает, подписан ли его сертификат (protocol.md, раздел 4.17).
  Future<pb.NodePairStatusResponse> nodePairStatus(
    pb.NodePairStatusRequest request, {
    required Ed25519KeyPair nodeKey,
  }) => call(
    'NodePairStatus',
    request,
    pb.NodePairStatusResponse.fromBuffer,
    key: nodeKey,
  );

  /// Владелец по коду узнаёт ключи узла (protocol.md, раздел 4.17).
  Future<pb.NodePairLookupResponse> nodePairLookup(
    pb.NodePairLookupRequest request, {
    required Ed25519KeyPair accountKey,
  }) => call(
    'NodePairLookup',
    request,
    pb.NodePairLookupResponse.fromBuffer,
    key: accountKey,
  );

  /// Владелец передаёт подписанный сертификат узла (protocol.md, раздел 4.17).
  Future<pb.NodePairSignResponse> nodePairSign(
    pb.NodePairSignRequest request, {
    required Ed25519KeyPair accountKey,
  }) => call(
    'NodePairSign',
    request,
    pb.NodePairSignResponse.fromBuffer,
    key: accountKey,
  );
}
