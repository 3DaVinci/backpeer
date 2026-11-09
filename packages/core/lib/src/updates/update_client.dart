import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:core/src/crypto/crypto_provider.dart';
import 'package:core/src/errors.dart';
import 'package:core/src/updates/product_version.dart';
import 'package:core/src/updates/update_manifest.dart';
import 'package:core/src/util/bytes.dart';
import 'package:protocol/protocol.dart' as pb;

/// Загрузка байтов по адресу. В тестах — подделка; по умолчанию — HTTP
/// ([UpdateClient] создаёт её сам).
typedef UpdateFetch = Future<Uint8List> Function(Uri url);

/// Клиент обновлений (docs/spec/updates.md): загружает и проверяет манифест
/// и пакет. Чистый Dart, без Flutter; установка — на стороне приложения.
///
/// Только HTTPS; `http` — только к адресу на этой машине (как у
/// `CoordinatorClient`).
final class UpdateClient {
  new({
    required this.crypto,
    required this.acceptedKeys,
    UpdateFetch? fetch,
    this.requestTimeout = const Duration(seconds: 30),
  }) : _fetch = fetch {
    if (fetch == null) {
      _http = HttpClient()
        ..connectionTimeout = const Duration(seconds: 10)
        ..userAgent = 'backpeer-update';
    }
  }

  /// Основной криптопровайдер (libsodium): Ed25519 и BLAKE2b-256.
  final CryptoProvider crypto;

  /// Допустимые открытые ключи обновлений (текущий и следующий при
  /// ротации; docs/spec/updates.md, раздел 2).
  final List<Uint8List> acceptedKeys;

  final Duration requestTimeout;

  /// Подделка в тестах; `null` — свой [HttpClient].
  final UpdateFetch? _fetch;
  HttpClient? _http;

  Future<Uint8List> _get(Uri url) =>
      _fetch != null ? _fetch(url) : defaultFetch(url, http: _http);

  /// Загрузка GET с пределом размера; битые ответы и сбои связи —
  /// [CoordinatorException] `UNAVAILABLE`. [http] — общий клиент, если
  /// скачиваний несколько; `null` — создаётся и закрывается на вызов.
  static Future<Uint8List> defaultFetch(
    Uri url, {
    int maxBytes = 512 * 1024 * 1024,
    HttpClient? http,
  }) async {
    final own =
        http ??
        (HttpClient()
          ..connectionTimeout = const Duration(seconds: 10)
          ..userAgent = 'backpeer-update');
    try {
      if (!_httpsAllowed(url)) {
        throw const CoordinatorException(
          pb.ErrorCode.ERROR_CODE_UNAVAILABLE,
          'адрес обновлений должен быть https',
        );
      }
      final request = await own
          .getUrl(url)
          .timeout(const Duration(seconds: 30));
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if (response.statusCode != 200) {
        throw CoordinatorException(
          pb.ErrorCode.ERROR_CODE_UNAVAILABLE,
          'HTTP ${response.statusCode}',
          httpStatus: response.statusCode,
        );
      }
      final out = BytesBuilder(copy: false);
      await for (final chunk in response) {
        out.add(chunk);
        if (out.length > maxBytes) {
          throw const CoordinatorException(
            pb.ErrorCode.ERROR_CODE_INTERNAL,
            'ответ больше предела',
          );
        }
      }
      return out.takeBytes();
    } on CoordinatorException {
      rethrow;
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
    } finally {
      if (http == null) own.close(force: true);
    }
  }

  static bool _httpsAllowed(Uri url) {
    const local = {'localhost', '127.0.0.1', '::1', '[::1]'};
    return url.scheme == 'https' ||
        (url.scheme == 'http' && local.contains(url.host));
  }

  /// Загружает манифест по адресу [manifestUri] (файл `updates.json`),
  /// отсоединённую подпись — по `manifestUri.sig`, проверяет её и сверяет
  /// канал. Неприменимость к текущей версии здесь не проверяется — её
  /// решает вызывающий через [UpdateManifest.checkApplicable].
  Future<UpdateManifest> fetchManifest(
    Uri manifestUri, {
    required UpdateChannel channel,
  }) async {
    final bytes = await _get(manifestUri);
    final signature = await _get(Uri.parse('$manifestUri.sig'));
    await UpdateManifest.verifySignature(
      crypto,
      bytes: bytes,
      signature: signature,
      acceptedKeys: acceptedKeys,
    );
    final manifest = UpdateManifest.parse(utf8.decode(bytes));
    if (manifest.channel != channel) {
      throw PreconditionException(
        'манифест канала ${manifest.channel.name}, запрошен ${channel.name}',
      );
    }
    return manifest;
  }

  /// Загружает [package] и проверяет размер и BLAKE2b-256; расхождение —
  /// [IntegrityException] (`check`: `hash`). Размер сверяется с полем
  /// манифеста, поэтому подмена размера требует подписи манифеста.
  Future<Uint8List> download(UpdatePackage package) async {
    final bytes = await _get(package.url);
    if (bytes.length != package.size) {
      throw const IntegrityException(
        object: 'update package',
        check: IntegrityCheck.hash,
      );
    }
    if (!constantTimeEquals(crypto.blake2b256(bytes), package.sha256)) {
      throw const IntegrityException(
        object: 'update package',
        check: IntegrityCheck.hash,
      );
    }
    return bytes;
  }

  /// Полная проверка «есть ли для меня обновление»: манифест по адресу
  /// [baseUri]`{channel}.json`, затем применимость к [currentVersion] и
  /// раскатка по [installId]. Нет обновления или не в доле — `null` (не
  /// ошибка); подмена — [IntegrityException] / [DataFormatException].
  ///
  /// База для GitHub Releases — `https://github.com/OWNER/REPO/releases/latest/download`:
  /// в релизе лежат `stable.json` и `stable.json.sig` рядом с пакетами
  /// (`docs/spec/updates.md`, раздел 8).
  Future<UpdateManifest?> check({
    required Uri baseUri,
    required UpdateChannel channel,
    required ProductVersion currentVersion,
    required Uint8List installId,
  }) async {
    final manifest = await fetchManifest(
      baseUri.replace(path: '${_trimSlash(baseUri.path)}/${channel.name}.json'),
      channel: channel,
    );
    try {
      manifest.checkApplicable(currentVersion);
    } on PreconditionException {
      return null;
    }
    if (!manifest.rolloutAllows(crypto, installId)) return null;
    return manifest;
  }

  static String _trimSlash(String path) =>
      path.endsWith('/') ? path.substring(0, path.length - 1) : path;

  /// Закрывает HTTP-клиент, если он был создан здесь.
  void close() => _http?.close(force: true);
}
