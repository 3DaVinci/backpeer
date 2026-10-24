import 'dart:typed_data';

import 'package:core/src/crypto/crypto_provider.dart';
import 'package:core/src/crypto/secret_bytes.dart';
import 'package:core/src/errors.dart';
import 'package:meta/meta.dart';

/// `Noise_XX_25519_ChaChaPoly_BLAKE2b` (Noise Protocol Framework, ревизия
/// 34) на примитивах [CryptoProvider]: protocol.md, раздел 3.1. Проверяется
/// официальными векторами cacophony (`test-vectors/protocol/
/// noise-cacophony.json`).
///
/// Готового пакета Noise для Dart с подходящей лицензией нет (задача
/// 3.3.1), поэтому реализован только нужный шаблон XX без PSK.
abstract final class Noise {
  static const String protocolName = 'Noise_XX_25519_ChaChaPoly_BLAKE2b';

  /// Пролог протокола версии 1.
  static final Uint8List prologue = Uint8List.fromList('fs/v1/noise'.codeUnits);

  /// Наибольшее сообщение Noise (спецификация Noise, раздел 3).
  static const int maxMessageLength = 65535;

  static const int tagLength = CryptoProvider.aeadTagLength;
  static const int dhLength = 32;
  static const int hashLength = CryptoProvider.blake2b512Length;
  static const _blockLength = 128;

  /// HMAC-BLAKE2b (RFC 2104 с длиной блока 128 байт).
  static Uint8List _hmac(CryptoProvider crypto, Uint8List key, Uint8List data) {
    assert(key.length <= _blockLength, 'ключ HMAC длиннее блока');
    final inner = Uint8List(_blockLength + data.length)..setAll(0, key);
    for (var i = 0; i < _blockLength; i++) {
      inner[i] ^= 0x36;
    }
    inner.setAll(_blockLength, data);
    final innerHash = crypto.blake2b512(inner);
    final outer = Uint8List(_blockLength + hashLength)..setAll(0, key);
    for (var i = 0; i < _blockLength; i++) {
      outer[i] ^= 0x5c;
    }
    outer.setAll(_blockLength, innerHash);
    inner.fillRange(0, _blockLength, 0);
    final out = crypto.blake2b512(outer);
    outer.fillRange(0, outer.length, 0);
    return out;
  }

  /// `HKDF(chaining_key, input_key_material, 2)` из спецификации Noise.
  static (Uint8List, Uint8List) _hkdf2(
    CryptoProvider crypto,
    Uint8List chainingKey,
    Uint8List ikm,
  ) {
    final temp = _hmac(crypto, chainingKey, ikm);
    final out1 = _hmac(crypto, temp, Uint8List.fromList(const [1]));
    final out2 = _hmac(crypto, temp, Uint8List.fromList([...out1, 2]));
    temp.fillRange(0, temp.length, 0);
    return (out1, out2);
  }
}

/// `CipherState` Noise: ключ ChaCha20-Poly1305 и счётчик nonce.
final class NoiseCipherState {
  new(this._crypto, [this._key]);

  final CryptoProvider _crypto;
  SecretBytes? _key;
  int _nonce = 0;

  /// nonce 2^64 − 1 зарезервирован для [rekey]. До 2^63 − 1 счётчик не
  /// дойдёт: смена ключей и кадры ограничивают его гораздо раньше.
  static const _maxNonce = 0x7FFFFFFFFFFFFFFF;

  bool get hasKey => _key != null;

  /// Номер следующего сообщения.
  int get nonce => _nonce;

  /// `EncryptWithAd`. Без ключа возвращает открытый текст.
  Uint8List encrypt(Uint8List ad, Uint8List plaintext) {
    final key = _key;
    if (key == null) return Uint8List.fromList(plaintext);
    final out = _crypto.chacha20Poly1305Encrypt(
      key: key,
      nonce: _nonceBytes(_next()),
      plaintext: plaintext,
      aad: ad,
    );
    return out;
  }

  /// `DecryptWithAd`. Неверный тег — `null`; nonce при этом не меняется.
  Uint8List? decrypt(Uint8List ad, Uint8List ciphertext) {
    final key = _key;
    if (key == null) return Uint8List.fromList(ciphertext);
    if (_nonce >= _maxNonce) throw StateError('nonce Noise исчерпан');
    final out = _crypto.chacha20Poly1305Decrypt(
      key: key,
      nonce: _nonceBytes(_nonce),
      ciphertext: ciphertext,
      aad: ad,
    );
    if (out != null) _nonce++;
    return out;
  }

  /// `Rekey()`: новый ключ — первые 32 байта шифротекста 32 нулей с
  /// nonce 2^64 − 1 (спецификация Noise, раздел 11.3). Счётчик не
  /// сбрасывается.
  void rekey() {
    final key = _key;
    if (key == null) throw StateError('Rekey без ключа');
    final out = _crypto.chacha20Poly1305Encrypt(
      key: key,
      nonce: Uint8List(12)..fillRange(4, 12, 0xFF),
      plaintext: Uint8List(32),
      aad: Uint8List(0),
    );
    key.dispose();
    _key = SecretBytes.adopt(Uint8List.sublistView(out, 0, 32));
  }

  /// Копия состояния с тем же ключом и nonce: для фаззинга.
  @visibleForTesting
  NoiseCipherState copy() =>
      NoiseCipherState(_crypto, _key == null ? null : SecretBytes(_key!.bytes))
        .._nonce = _nonce;

  /// Затирает ключ.
  void dispose() {
    _key?.dispose();
    _key = null;
  }

  int _next() {
    if (_nonce >= _maxNonce) throw StateError('nonce Noise исчерпан');
    return _nonce++;
  }

  static Uint8List _nonceBytes(int n) =>
      Uint8List(12)..buffer.asByteData().setUint64(4, n, Endian.little);
}

/// `SymmetricState` Noise: `ck`, `h` и текущий [NoiseCipherState].
final class NoiseSymmetricState {
  new(this._crypto) {
    final name = Noise.protocolName.codeUnits;
    // Имя протокола короче HASHLEN: h = имя, дополненное нулями.
    _h = Uint8List(Noise.hashLength)..setAll(0, name);
    _ck = Uint8List.fromList(_h);
    _cipher = NoiseCipherState(_crypto);
  }

  final CryptoProvider _crypto;
  late Uint8List _ck;
  late Uint8List _h;
  late NoiseCipherState _cipher;

  Uint8List get handshakeHash => Uint8List.fromList(_h);

  void mixHash(Uint8List data) {
    _h = _crypto.blake2b512(Uint8List.fromList([..._h, ...data]));
  }

  void mixKey(Uint8List ikm) {
    final (ck, temp) = Noise._hkdf2(_crypto, _ck, ikm);
    _ck.fillRange(0, _ck.length, 0);
    _ck = ck;
    _cipher.dispose();
    _cipher = NoiseCipherState(
      _crypto,
      SecretBytes(Uint8List.sublistView(temp, 0, CryptoProvider.keyLength)),
    );
    temp.fillRange(0, temp.length, 0);
  }

  Uint8List encryptAndHash(Uint8List plaintext) {
    final out = _cipher.encrypt(_h, plaintext);
    mixHash(out);
    return out;
  }

  /// Неверный тег — [IntegrityException].
  Uint8List decryptAndHash(Uint8List ciphertext) {
    final out = _cipher.decrypt(_h, ciphertext);
    if (out == null) {
      throw const IntegrityException(
        object: 'noise-handshake',
        check: IntegrityCheck.aeadTag,
      );
    }
    mixHash(ciphertext);
    return out;
  }

  /// `Split()`: шифры инициатор → отвечающий и обратно.
  (NoiseCipherState, NoiseCipherState) split() {
    final (k1, k2) = Noise._hkdf2(_crypto, _ck, Uint8List(0));
    NoiseCipherState cipher(Uint8List k) {
      final state = NoiseCipherState(
        _crypto,
        SecretBytes(Uint8List.sublistView(k, 0, CryptoProvider.keyLength)),
      );
      k.fillRange(0, k.length, 0);
      return state;
    }

    return (cipher(k1), cipher(k2));
  }

  void dispose() {
    _ck.fillRange(0, _ck.length, 0);
    _cipher.dispose();
  }
}

/// Шифры канала после рукопожатия.
final class NoiseTransportKeys {
  new({
    required this.send,
    required this.receive,
    required this.handshakeHash,
    required this.remoteStatic,
  });

  final NoiseCipherState send;
  final NoiseCipherState receive;

  /// `h` после рукопожатия (64 байта): общий для обеих сторон
  /// идентификатор сеанса.
  final Uint8List handshakeHash;

  /// Статический ключ X25519 собеседника.
  final Uint8List remoteStatic;

  void dispose() {
    send.dispose();
    receive.dispose();
  }
}

/// Рукопожатие XX:
///
/// ```text
/// -> e
/// <- e, ee, s, es
/// -> s, se
/// ```
///
/// Инициатор пишет сообщения 1 и 3 и читает 2; отвечающий наоборот. После
/// третьего сообщения [finish] отдаёт шифры канала.
final class NoiseHandshake {
  new _(this._crypto, this.initiator, this._s, this._e, Uint8List prologue)
    : _state = NoiseSymmetricState(_crypto) {
    _state.mixHash(prologue);
  }

  /// Начинает рукопожатие со статическим ключом [staticKey]. Эфемерный
  /// ключ создаётся из ГПСЧ; [ephemeral] — только для векторов.
  static Future<NoiseHandshake> start(
    CryptoProvider crypto, {
    required bool initiator,
    required X25519KeyPair staticKey,
    Uint8List? prologue,
    X25519KeyPair? ephemeral,
  }) async {
    final e =
        ephemeral ??
        await crypto.x25519FromSecret(
          SecretBytes.adopt(crypto.randomBytes(Noise.dhLength)),
        );
    return NoiseHandshake._(
      crypto,
      initiator,
      staticKey,
      e,
      prologue ?? Noise.prologue,
    );
  }

  final CryptoProvider _crypto;
  final bool initiator;
  final X25519KeyPair _s;
  final X25519KeyPair _e;
  final NoiseSymmetricState _state;
  late Uint8List _re;
  Uint8List? _rs;
  int _step = 0;
  bool _finished = false;

  /// Все три сообщения переданы.
  bool get isComplete => _step == 3;

  /// Чья очередь писать: инициатор пишет сообщения 0 и 2.
  bool get isMyTurn => !isComplete && (_step.isEven == initiator);

  /// Статический ключ собеседника: у инициатора — после сообщения 2, у
  /// отвечающего — после сообщения 3.
  Uint8List? get remoteStatic => _rs;

  /// Следующее сообщение с полезной нагрузкой [payload].
  Future<Uint8List> writeMessage(Uint8List payload) async {
    if (!isMyTurn) throw StateError('сейчас очередь собеседника');
    final out = BytesBuilder(copy: false);
    switch (_step) {
      case 0:
        out.add(_e.publicKey);
        _state.mixHash(_e.publicKey);
      case 1:
        out.add(_e.publicKey);
        _state.mixHash(_e.publicKey);
        await _mixDh(_e, _re);
        out.add(_state.encryptAndHash(_s.publicKey));
        await _mixDh(_s, _re);
      default:
        out.add(_state.encryptAndHash(_s.publicKey));
        await _mixDh(_s, _re);
    }
    out.add(_state.encryptAndHash(payload));
    _step++;
    final message = out.takeBytes();
    if (message.length > Noise.maxMessageLength) {
      throw ArgumentError('сообщение рукопожатия длиннее 65 535 байт');
    }
    return message;
  }

  /// Читает сообщение собеседника и возвращает его полезную нагрузку.
  /// Короткое сообщение — [DataFormatException], неверный тег —
  /// [IntegrityException], ключ малого порядка — [DataFormatException].
  Future<Uint8List> readMessage(Uint8List message) async {
    if (isComplete || isMyTurn) throw StateError('сейчас наша очередь');
    var offset = 0;
    Uint8List take(int length) {
      if (message.length - offset < length) {
        throw DataFormatException(
          object: 'noise-handshake',
          problem: FormatProblem.truncated,
          detail: 'сообщение ${_step + 1}: ${message.length} байт',
        );
      }
      final out = Uint8List.sublistView(message, offset, offset + length);
      offset += length;
      return out;
    }

    const sealedKey = Noise.dhLength + Noise.tagLength;
    switch (_step) {
      case 0:
        final re = _re = Uint8List.fromList(take(Noise.dhLength));
        _state.mixHash(re);
      case 1:
        final re = _re = Uint8List.fromList(take(Noise.dhLength));
        _state.mixHash(re);
        await _mixDh(_e, re);
        final rs = _rs = _state.decryptAndHash(take(sealedKey));
        await _mixDh(_e, rs);
      default:
        final rs = _rs = _state.decryptAndHash(take(sealedKey));
        await _mixDh(_e, rs);
    }
    final payload = _state.decryptAndHash(
      Uint8List.sublistView(message, offset),
    );
    _step++;
    return payload;
  }

  /// Шифры канала: у инициатора отправка — первый шифр `Split()`, у
  /// отвечающего — второй. Затирает состояние рукопожатия.
  NoiseTransportKeys finish() {
    if (!isComplete || _finished) throw StateError('рукопожатие не завершено');
    _finished = true;
    final (c1, c2) = _state.split();
    final keys = NoiseTransportKeys(
      send: initiator ? c1 : c2,
      receive: initiator ? c2 : c1,
      handshakeHash: _state.handshakeHash,
      remoteStatic: _rs!,
    );
    dispose();
    return keys;
  }

  /// Затирает состояние рукопожатия и эфемерный ключ.
  void dispose() {
    _state.dispose();
    _e.secretKey.dispose();
  }

  Future<void> _mixDh(X25519KeyPair local, Uint8List remote) async {
    final shared = await _crypto.x25519(
      secretKey: local.secretKey,
      publicKey: remote,
    );
    try {
      _state.mixKey(shared.bytes);
    } finally {
      shared.dispose();
    }
  }
}
