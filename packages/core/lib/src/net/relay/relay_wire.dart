import 'dart:typed_data';

import 'package:core/src/crypto/crypto_provider.dart';
import 'package:core/src/crypto/signed_message.dart';
import 'package:core/src/crypto/signing.dart';
import 'package:core/src/errors.dart';
import 'package:core/src/format/coordinator_keys.dart';
import 'package:core/src/snapshot/manifest_objects.dart';
import 'package:core/src/util/bytes.dart';
import 'package:protobuf/protobuf.dart';
import 'package:protocol/protocol.dart' as pb;

/// Постоянные протокола relay (protocol.md, раздел 4.12).
abstract final class RelayWire {
  static const version = 1;

  /// Кадр до начала ретрансляции: `u16be длина || сообщение`; длина 0 —
  /// сообщение со всеми полями по умолчанию (`RelayOpened` без ошибки).
  static const maxFrameLength = 4096;

  static const nonceLength = 32;
  static const passIdLength = 16;
  static const sessionIdLength = 16;
  static const keyLength = 32;

  /// Имя relay: 1–64 символа `a–z`, `0–9`, `.`, `-`.
  static final relayName = RegExp(r'^[a-z0-9][a-z0-9.-]{0,63}$');

  /// Контекст доказательства владения ключом пропуска (protocol.md,
  /// раздел 6).
  static const openContext = 'relay-open';

  /// Кадр с [message].
  static Uint8List frame(GeneratedMessage message) {
    final body = message.writeToBuffer();
    if (body.length > maxFrameLength) {
      throw ArgumentError('кадр relay: ${body.length} байт');
    }
    return Uint8List(2 + body.length)
      ..[0] = body.length >> 8
      ..[1] = body.length & 0xFF
      ..setAll(2, body);
  }

  /// Что подписывает владелец пропуска: `nonce || BLAKE2b-256(pass.body)
  /// || accept` в контексте [openContext].
  static Uint8List proofInput(
    CryptoProvider crypto,
    List<int> nonce,
    List<int> passBody,
    List<int> accept,
  ) => signingInput(openContext, [
    ...nonce,
    ...crypto.blake2b256(Uint8List.fromList(passBody)),
    ...accept,
  ]);

  /// Подпись [key] для `RelayOpen` на вызов [nonce].
  static Future<Uint8List> prove(
    CryptoProvider crypto,
    Ed25519KeyPair key,
    List<int> nonce,
    pb.Signed pass, {
    List<int> accept = const [],
  }) => crypto.ed25519Sign(key, proofInput(crypto, nonce, pass.body, accept));
}

/// Собирает кадры relay из кусков потока; после рукопожатия остаток
/// ([takeRest]) — уже байты собеседника.
final class RelayFrameReader {
  Uint8List _pending = Uint8List(0);

  void add(Uint8List chunk) {
    _pending = _pending.isEmpty
        ? Uint8List.fromList(chunk)
        : (BytesBuilder(copy: false)
                ..add(_pending)
                ..add(chunk))
              .takeBytes();
  }

  /// Следующий целый кадр или `null`. Длина больше
  /// [RelayWire.maxFrameLength] — [FormatException].
  Uint8List? next() {
    if (_pending.length < 2) return null;
    final length = (_pending[0] << 8) | _pending[1];
    if (length > RelayWire.maxFrameLength) {
      throw const FormatException('длина кадра relay');
    }
    if (_pending.length < 2 + length) return null;
    final frame = Uint8List.sublistView(_pending, 2, 2 + length);
    _pending = Uint8List.sublistView(_pending, 2 + length);
    return frame;
  }

  /// Непрочитанные байты; читатель после этого пуст.
  Uint8List takeRest() {
    final rest = _pending;
    _pending = Uint8List(0);
    return rest;
  }
}

/// Почему relay не принимает пропуск.
enum RelayPassRejection {
  /// Подписавший не входит в список ключей пропусков.
  untrusted,
  signature,
  format,
  expired,
  tooLong,

  /// Пропуск другого relay.
  otherRelay,
}

final class RelayPassRejectedException implements Exception {
  const new(this.reason, [this.detail]);

  final RelayPassRejection reason;
  final String? detail;

  @override
  String toString() =>
      'RelayPassRejectedException(${reason.name}'
      '${detail == null ? '' : ': $detail'})';
}

/// Правила пропуска `RelayPass` (protocol.md, раздел 4.12): общие для
/// координатора, который его выдаёт, и relay, который его проверяет.
abstract final class RelayPasses {
  /// Контекст подписи пропуска (protocol.md, раздел 6).
  static const signingContext = 'relay-pass';

  /// Наибольший срок жизни пропуска.
  static const maxLifetime = Duration(hours: 2);

  /// Допуск на расхождение часов relay и координатора.
  static const clockSkew = Duration(minutes: 5);

  static const maxEncodedLength = 512;

  /// Подписывает [pass] ключом пропусков [key] (координатор).
  static Future<pb.Signed> issue(
    CryptoProvider crypto,
    Ed25519KeyPair key,
    pb.RelayPass pass,
  ) {
    check(pass);
    return SignedMessages.sign(crypto, key, signingContext, pass);
  }

  /// Разбирает тело и проверяет поля и каноничность. Ошибка —
  /// [DataFormatException] (`object: relay-pass`).
  static pb.RelayPass parse(Uint8List body) {
    if (body.length > maxEncodedLength) {
      throw _error(FormatProblem.tooLarge, '${body.length} байт');
    }
    final pass = ManifestObjects.parseMessage(
      'relay-pass',
      () => pb.RelayPass.fromBuffer(body),
    );
    if (pass.unknownFields.isNotEmpty ||
        !constantTimeEquals(pass.writeToBuffer(), body)) {
      throw _error(FormatProblem.invalidField, 'неканоническая сериализация');
    }
    check(pass);
    return pass;
  }

  /// Поля пропуска.
  static void check(pb.RelayPass pass) {
    if (pass.role == pb.RelayRole.RELAY_ROLE_UNSPECIFIED) {
      throw _error(FormatProblem.invalidField, 'role не задана');
    }
    _length('holder', pass.holder, RelayWire.keyLength);
    _length('node_id', pass.nodeId, RelayWire.keyLength);
    _length('account_id', pass.accountId, RelayWire.keyLength);
    _length('pass_id', pass.passId, RelayWire.passIdLength);
    if (!RelayWire.relayName.hasMatch(pass.relay)) {
      throw _error(FormatProblem.invalidField, 'relay: имя');
    }
    if (pass.expiresAtUnixMs <= 0) {
      throw _error(FormatProblem.invalidField, 'expires_at_unix_ms не задан');
    }
    final listen = pass.role == pb.RelayRole.RELAY_ROLE_LISTEN;
    if (listen != constantTimeEquals(pass.holder, pass.nodeId)) {
      // LISTEN — только для самого узла; CONNECT к себе не нужен.
      throw _error(FormatProblem.invalidField, 'holder и node_id');
    }
  }

  /// Полная проверка relay [relay] на момент [now]: подписавший — из
  /// [trusted], подпись, поля, имя relay, срок. Отказ —
  /// [RelayPassRejectedException].
  static Future<pb.RelayPass> verify(
    CryptoProvider crypto,
    pb.Signed signed,
    CoordinatorKeySet trusted, {
    required String relay,
    required DateTime now,
  }) async {
    if (!trusted.trusts(signed.signer)) {
      throw const RelayPassRejectedException(RelayPassRejection.untrusted);
    }
    final pb.RelayPass pass;
    try {
      pass = await SignedMessages.open(
        crypto,
        signed,
        context: signingContext,
        object: 'relay-pass',
        parse: (body) => parse(Uint8List.fromList(body)),
      );
    } on IntegrityException {
      throw const RelayPassRejectedException(RelayPassRejection.signature);
    } on DataFormatException catch (e) {
      throw RelayPassRejectedException(RelayPassRejection.format, e.detail);
    }
    if (pass.relay != relay) {
      throw RelayPassRejectedException(
        RelayPassRejection.otherRelay,
        pass.relay,
      );
    }
    final expires = pass.expiresAtUnixMs.toInt();
    final nowMs = now.millisecondsSinceEpoch;
    if (expires + clockSkew.inMilliseconds <= nowMs) {
      throw const RelayPassRejectedException(RelayPassRejection.expired);
    }
    if (expires >
        nowMs + maxLifetime.inMilliseconds + clockSkew.inMilliseconds) {
      throw const RelayPassRejectedException(RelayPassRejection.tooLong);
    }
    return pass;
  }

  /// Пропуск без проверки подписи — для того, кто его получил от
  /// координатора (срок, имя relay). Битый — [DataFormatException].
  static pb.RelayPass read(pb.Signed signed) =>
      parse(Uint8List.fromList(signed.body));

  static void _length(String field, List<int> value, int expected) {
    if (value.length != expected) {
      throw _error(
        FormatProblem.invalidField,
        '$field: ${value.length} байт, нужно $expected',
      );
    }
  }

  static DataFormatException _error(FormatProblem problem, String detail) =>
      DataFormatException(
        object: 'relay-pass',
        problem: problem,
        detail: detail,
      );
}
