import 'dart:convert';
import 'dart:typed_data';

import 'package:core/src/crypto/bip39_english.dart';
import 'package:core/src/crypto/crypto_provider.dart';
import 'package:core/src/crypto/secret_bytes.dart';
import 'package:core/src/errors.dart';
import 'package:hashlib/hashlib.dart' as hashlib;

/// Фраза восстановления: 24 слова BIP39 из 32 байт энтропии
/// (docs/spec/crypto.md, раздел 3.1). Корень всех ключей учётной записи.
///
/// Хранится только энтропия в [SecretBytes]; слова строятся по запросу
/// ([words]), потому что строки Dart нельзя затереть. [toString] фразу не
/// показывает.
final class RecoveryPhrase {
  new _(this._entropy);

  /// Новая фраза из ГПСЧ операционной системы.
  factory generate(CryptoProvider crypto) =>
      RecoveryPhrase._(SecretBytes.adopt(crypto.randomBytes(entropyLength)));

  /// Фраза из 32 байт энтропии (копируются).
  factory fromEntropy(Uint8List entropy) {
    if (entropy.length != entropyLength) {
      throw ArgumentError(
        'Нужно $entropyLength байт энтропии, получено ${entropy.length}',
      );
    }
    return RecoveryPhrase._(SecretBytes(entropy));
  }

  /// Разбор фразы, введённой пользователем: регистр и пробельные символы
  /// между словами не важны. Неизвестное слово или не 24 слова —
  /// [DataFormatException], неверная контрольная сумма —
  /// [IntegrityException]. Сами слова в ошибку не попадают, только номер.
  factory parse(String text) {
    final words = text.trim().toLowerCase().split(RegExp(r'\s+'));
    if (words.length == 1 && words.single.isEmpty) words.clear();
    if (words.length != wordCount) {
      throw DataFormatException(
        object: _object,
        problem: FormatProblem.invalidField,
        detail: 'слов ${words.length}, нужно $wordCount',
      );
    }
    return RecoveryPhrase._(SecretBytes.adopt(mnemonicToEntropy(words)));
  }

  static const int wordCount = 24;
  static const int entropyLength = 32;
  static const int seedLength = 64;

  final SecretBytes _entropy;

  /// Энтропия; ссылку не хранить.
  SecretBytes get entropy => _entropy;

  /// Слова фразы для показа пользователю.
  List<String> get words => entropyToMnemonic(_entropy.bytes);

  /// Фраза в канонической записи: слова через один пробел, нижний регистр.
  String get phrase => words.join(' ');

  /// seed BIP39 (64 байта); passphrase в MVP всегда пустая.
  Future<SecretBytes> seed(CryptoProvider crypto) =>
      bip39Seed(crypto, phrase, passphrase: '');

  void dispose() => _entropy.dispose();

  @override
  String toString() => 'RecoveryPhrase($wordCount слов)';
}

const _object = 'recovery-phrase';

/// Энтропия 16–32 байт (кратно 4) → слова BIP39. Общая функция для любой
/// длины нужна тестам на официальных векторах; фраза продукта — только 24
/// слова.
List<String> entropyToMnemonic(Uint8List entropy) {
  final bits = entropy.length * 8;
  if (entropy.length < 16 || entropy.length > 32 || entropy.length % 4 != 0) {
    throw ArgumentError('Длина энтропии BIP39: 16–32 байта, кратно 4');
  }
  final checksumBits = bits ~/ 32;
  final checksum = hashlib.sha256.convert(entropy).bytes[0];
  final count = (bits + checksumBits) ~/ 11;
  int bit(int i) => i < bits
      ? (entropy[i >> 3] >> (7 - (i & 7))) & 1
      : (checksum >> (7 - (i - bits))) & 1;
  return [for (var w = 0; w < count; w++) bip39English[_index(w, bit)]];
}

int _index(int word, int Function(int) bit) {
  var index = 0;
  for (var b = 0; b < 11; b++) {
    index = (index << 1) | bit(word * 11 + b);
  }
  return index;
}

/// Слова BIP39 (12–24, кратно 3, нижний регистр) → энтропия с проверкой
/// контрольной суммы.
Uint8List mnemonicToEntropy(List<String> words) {
  if (words.length < 12 || words.length > 24 || words.length % 3 != 0) {
    throw DataFormatException(
      object: _object,
      problem: FormatProblem.invalidField,
      detail: 'слов ${words.length}',
    );
  }
  final totalBits = words.length * 11;
  final checksumBits = totalBits ~/ 33;
  final entropyBits = totalBits - checksumBits;
  final entropy = Uint8List(entropyBits ~/ 8);
  var checksum = 0;
  for (var w = 0; w < words.length; w++) {
    final index = _wordIndex[words[w]];
    if (index == null) {
      entropy.fillRange(0, entropy.length, 0);
      throw DataFormatException(
        object: _object,
        problem: FormatProblem.invalidField,
        detail: 'слово №${w + 1} не из словаря BIP39',
      );
    }
    for (var b = 0; b < 11; b++) {
      final i = w * 11 + b;
      final value = (index >> (10 - b)) & 1;
      if (i < entropyBits) {
        entropy[i >> 3] |= value << (7 - (i & 7));
      } else {
        checksum = (checksum << 1) | value;
      }
    }
  }
  final expected =
      hashlib.sha256.convert(entropy).bytes[0] >> (8 - checksumBits);
  if (checksum != expected) {
    entropy.fillRange(0, entropy.length, 0);
    throw const IntegrityException(
      object: _object,
      check: IntegrityCheck.checksum,
    );
  }
  return entropy;
}

/// seed BIP39: PBKDF2-HMAC-SHA512(NFKD(фраза), "mnemonic" || NFKD(passphrase),
/// 2048, 64). Для английских слов и ASCII-passphrase NFKD ничего не
/// меняет; другие passphrase в MVP не используются.
Future<SecretBytes> bip39Seed(
  CryptoProvider crypto,
  String phrase, {
  required String passphrase,
}) {
  if (!_isAscii(phrase) || !_isAscii(passphrase)) {
    throw ArgumentError('Поддерживаются только ASCII-фраза и passphrase');
  }
  return crypto.pbkdf2HmacSha512(
    password: ascii.encode(phrase),
    salt: ascii.encode('mnemonic$passphrase'),
    iterations: 2048,
    length: RecoveryPhrase.seedLength,
  );
}

bool _isAscii(String s) => s.codeUnits.every((c) => c < 0x80);

final Map<String, int> _wordIndex = {
  for (var i = 0; i < bip39English.length; i++) bip39English[i]: i,
};
