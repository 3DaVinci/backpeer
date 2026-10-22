import 'dart:typed_data';

import 'package:coordinator/src/auth/key_directory.dart';
import 'package:coordinator/src/auth/replay_cache.dart';
import 'package:coordinator/src/rpc/errors.dart';
import 'package:core/core.dart';
import 'package:protocol/protocol.dart' as pb;

/// Какой ключ должен подписать запрос (protocol.md, раздел 4.3).
enum AuthRequirement {
  /// Без подписи (`GetKeyBundle`).
  none,

  /// Ключ ещё может быть неизвестен: запрос его регистрирует
  /// (`RegisterAccount`, `RegisterNode`). Совпадение ключа с сертификатом
  /// проверяет обработчик.
  registering,

  account,
  device,
  node,
}

/// Кто подписал запрос.
final class Caller {
  const new({required this.publicKey, this.info});

  final Uint8List publicKey;

  /// `null` — ключ ещё не зарегистрирован ([AuthRequirement.registering]).
  final KeyInfo? info;
}

/// Проверка заголовка `FS-Auth` (protocol.md, раздел 4.2).
final class RequestVerifier {
  new({
    required this.crypto,
    required this.keys,
    DateTime Function()? clock,
    int replayCapacity = 1 << 20,
  }) : _clock = clock ?? DateTime.now,
       _replay = ReplayCache(capacity: replayCapacity);

  final CryptoProvider crypto;
  final KeyDirectory keys;
  final DateTime Function() _clock;
  final ReplayCache _replay;

  static final int _skewMs = RequestAuth.maxClockSkew.inMilliseconds;

  /// Проверяет подпись запроса к [path] с телом [body]. `null` — метод без
  /// подписи. Любая ошибка — [RpcException].
  Future<Caller?> verify({
    required AuthRequirement requirement,
    required String path,
    required String? header,
    required List<int> body,
  }) async {
    if (requirement == AuthRequirement.none) return null;
    if (header == null) throw _unauthenticated('нет заголовка FS-Auth');

    final RequestAuth auth;
    try {
      auth = RequestAuth.parse(header);
    } on DataFormatException {
      throw _unauthenticated('заголовок FS-Auth не разбирается');
    }

    final nowMs = _clock().millisecondsSinceEpoch;
    if ((auth.timeMs - nowMs).abs() > _skewMs) {
      throw _unauthenticated('время подписи вне окна ±5 минут');
    }

    final info = await keys.lookup(auth.signer);
    _checkKey(requirement, info);

    if (!await auth.verify(crypto, path: path, body: body)) {
      throw _unauthenticated('подпись неверна');
    }

    try {
      final fresh = _replay.remember(
        auth.signature,
        expiresAtMs: auth.timeMs + _skewMs,
        nowMs: nowMs,
      );
      if (!fresh) throw _unauthenticated('повтор запроса');
    } on ReplayCacheFullException {
      throw const RpcException(
        pb.ErrorCode.ERROR_CODE_UNAVAILABLE,
        'координатор перегружен',
        retryAfter: Duration(seconds: 1),
      );
    }
    return Caller(publicKey: auth.signer, info: info);
  }

  static void _checkKey(AuthRequirement requirement, KeyInfo? info) {
    if (info != null && info.revoked) throw _unauthenticated('ключ отозван');
    final expected = switch (requirement) {
      AuthRequirement.account => KeyKind.account,
      AuthRequirement.device => KeyKind.device,
      AuthRequirement.node => KeyKind.node,
      AuthRequirement.none || AuthRequirement.registering => null,
    };
    if (expected == null) return;
    if (info == null) throw _unauthenticated('ключ неизвестен');
    if (info.kind != expected) {
      throw RpcException(
        pb.ErrorCode.ERROR_CODE_PERMISSION_DENIED,
        'метод требует ключ вида ${expected.name}',
      );
    }
  }

  static RpcException _unauthenticated(String message) =>
      RpcException(pb.ErrorCode.ERROR_CODE_UNAUTHENTICATED, message);
}
