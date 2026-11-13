import 'dart:convert';
import 'dart:typed_data';

import 'package:core/src/crypto/crypto_provider.dart';
import 'package:core/src/crypto/signing.dart';
import 'package:core/src/errors.dart';
import 'package:core/src/updates/product_version.dart';
import 'package:core/src/util/bytes.dart';
import 'package:meta/meta.dart';

/// Канал обновлений (docs/spec/updates.md, раздел 3).
enum UpdateChannel {
  stable('stable'),
  beta('beta');

  new(this.name);

  final String name;

  static UpdateChannel parse(String text) => switch (text) {
    'stable' => UpdateChannel.stable,
    'beta' => UpdateChannel.beta,
    _ => throw DataFormatException(
      object: 'updates',
      problem: FormatProblem.invalidField,
      detail: 'channel $text',
    ),
  };
}

/// Платформа сборки в манифесте.
enum UpdatePlatform {
  linux('linux'),
  macos('macos'),
  windows('windows');

  new(this.name);

  final String name;

  static UpdatePlatform parse(String text) => switch (text) {
    'linux' => UpdatePlatform.linux,
    'macos' => UpdatePlatform.macos,
    'windows' => UpdatePlatform.windows,
    _ => throw DataFormatException(
      object: 'updates',
      problem: FormatProblem.invalidField,
      detail: 'platform $text',
    ),
  };
}

/// Сборка под платформу (docs/spec/updates.md, раздел 4).
@immutable
final class UpdatePackage {
  const new({
    required this.platform,
    required this.arch,
    required this.url,
    required this.sha256,
    required this.size,
  });

  final UpdatePlatform platform;

  /// `x64`, `arm64` или `null` — любая.
  final String? arch;

  /// HTTPS-адрес пакета.
  final Uri url;

  /// BLAKE2b-256 пакета, 32 байта.
  final Uint8List sha256;

  /// Размер пакета в байтах.
  final int size;

  /// Вид сборки по расширению файла в [url] — `appimage`, `deb`, `rpm`,
  /// `exe` или `dmg`; `null` — не распознан. По нему клиент отличает сборки
  /// одной платформы: установленное из `.deb` приложение обновляется
  /// пакетом, а не образом AppImage (docs/spec/updates.md, раздел 4).
  String? get kind {
    final name = url.pathSegments.isEmpty
        ? ''
        : url.pathSegments.last.toLowerCase();
    for (final kind in _kinds) {
      if (name.endsWith('.$kind')) return kind;
    }
    return null;
  }

  static const _kinds = ['appimage', 'deb', 'rpm', 'exe', 'dmg'];
}

/// Манифест версий (docs/spec/updates.md, раздел 3). Подпись — отсоединённая,
/// над точными байтами файла `updates.json`; её проверяет [verifySignature].
/// Разбор строгий: неизвестные поля и `format` ≠ 1 — [DataFormatException]
/// (`object`: `updates`).
@immutable
final class UpdateManifest {
  const new({
    required this.format,
    required this.channel,
    required this.version,
    required this.minVersion,
    required this.releasedAt,
    required this.rollout,
    required this.packages,
    required this.signer,
    this.nextUpdatePublicKey,
  });

  /// Разбирает JSON-манифест. Строгий к типам полей.
  factory parse(String json) {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException catch (e) {
      throw DataFormatException(
        object: 'updates',
        problem: FormatProblem.invalidField,
        detail: 'не JSON: ${e.message}',
      );
    }
    if (decoded is! Map<String, Object?>) {
      throw const DataFormatException(
        object: 'updates',
        problem: FormatProblem.invalidField,
        detail: 'не объект',
      );
    }
    final format = _intField(decoded, 'format');
    if (format != 1) {
      throw DataFormatException(
        object: 'updates',
        problem: FormatProblem.unsupportedVersion,
        detail: 'format $format',
      );
    }
    final channel = UpdateChannel.parse(_stringField(decoded, 'channel'));
    final version = ProductVersion.parse(_stringField(decoded, 'version'));
    final minVersion = ProductVersion.parse(
      _stringField(decoded, 'minVersion'),
    );
    final releasedAt = DateTime.tryParse(_stringField(decoded, 'releasedAt'));
    if (releasedAt == null) {
      throw const DataFormatException(
        object: 'updates',
        problem: FormatProblem.invalidField,
        detail: 'releasedAt',
      );
    }
    final rollout = _numberField(decoded, 'rollout');
    if (rollout < 0 || rollout > 1) {
      throw DataFormatException(
        object: 'updates',
        problem: FormatProblem.invalidField,
        detail: 'rollout $rollout',
      );
    }
    final packages = _packages(decoded['packages']);
    if (packages.isEmpty) {
      throw const DataFormatException(
        object: 'updates',
        problem: FormatProblem.invalidField,
        detail: 'packages пусто',
      );
    }
    final signer = _base64Key(decoded['signer'], 'signer');
    final next = decoded['nextUpdatePublicKey'];
    final nextKey = next == null
        ? null
        : _base64Key(next, 'nextUpdatePublicKey');
    if (minVersion > version) {
      throw DataFormatException(
        object: 'updates',
        problem: FormatProblem.invalidField,
        detail: 'minVersion $minVersion новее version $version',
      );
    }
    return UpdateManifest(
      format: format,
      channel: channel,
      version: version,
      minVersion: minVersion,
      releasedAt: releasedAt,
      rollout: rollout,
      packages: packages,
      signer: signer,
      nextUpdatePublicKey: nextKey,
    );
  }

  final int format;

  final UpdateChannel channel;

  /// Версия, на которую обновляет.
  final ProductVersion version;

  /// Минимальная версия, с которой можно обновиться напрямую.
  final ProductVersion minVersion;

  final DateTime releasedAt;

  /// Доля пользователей канала, 0…1.
  final double rollout;

  final List<UpdatePackage> packages;

  /// Открытый ключ, которым подписан манифест (32 байта).
  final Uint8List signer;

  /// Следующий ключ обновлений для ротации; `null` — нет.
  final Uint8List? nextUpdatePublicKey;

  /// Проверяет отсоединённую подпись [signature] над точными [bytes]
  /// манифеста. Допустимые ключи — [acceptedKeys] (текущий и следующий при
  /// ротации). Подпись от другого ключа или неверная — [IntegrityException]
  /// (`check`: `signature`).
  static Future<void> verifySignature(
    CryptoProvider crypto, {
    required Uint8List bytes,
    required Uint8List signature,
    required List<Uint8List> acceptedKeys,
  }) async {
    if (signature.length != CryptoProvider.ed25519SignatureLength) {
      throw const DataFormatException(
        object: 'updates',
        problem: FormatProblem.invalidField,
        detail: 'подпись неверной длины',
      );
    }
    final message = signingInput('updates', bytes);
    for (final key in acceptedKeys) {
      if (await crypto.ed25519Verify(
        publicKey: key,
        message: message,
        signature: signature,
      )) {
        return;
      }
    }
    throw const IntegrityException(
      object: 'updates',
      check: IntegrityCheck.signature,
    );
  }

  /// Сборка для [platform] и [arch] (при прочих равных — точное совпадение
  /// архитектуры предпочтительнее `arch == null`); нет — `null`.
  ///
  /// [kind] — вид сборки (`deb`, `appimage`, `exe`, `dmg`, см.
  /// [UpdatePackage.kind]): с ним берётся только сборка своего вида, а
  /// сборки другой платформы или вида не подставляются — иначе клиент с
  /// `.deb` скачал бы образ AppImage.
  UpdatePackage? packageFor(
    UpdatePlatform platform,
    String? arch, {
    String? kind,
  }) {
    UpdatePackage? any;
    for (final p in packages) {
      if (p.platform != platform) continue;
      if (kind != null && p.kind != kind) continue;
      if (p.arch == arch) return p;
      if (p.arch == null) any ??= p;
    }
    return any;
  }

  /// Применим ли манифест к [currentVersion]: версия строго новее (запрет
  /// отката) и [currentVersion] не старше [minVersion]. Неприменим —
  /// [PreconditionException].
  void checkApplicable(ProductVersion currentVersion) {
    if (!(version > currentVersion)) {
      throw PreconditionException('уже установлена версия $currentVersion');
    }
    if (currentVersion < minVersion) {
      throw PreconditionException(
        'обновление только с версии $minVersion и новее '
        '(сейчас $currentVersion)',
      );
    }
  }

  /// Номер бакета раскатки, 0…99, детерминированный по [installId]
  /// (docs/spec/updates.md, раздел 3).
  int rolloutBucket(CryptoProvider crypto, Uint8List installId) {
    final digest = crypto.blake2b256(
      Uint8List.fromList([
        ...installId,
        ...utf8.encode(channel.name),
        ...utf8.encode(version.toString()),
      ]),
    );
    var value = 0;
    for (var i = 0; i < 8; i++) {
      value |= digest[i] << (8 * i);
    }
    return value % 100;
  }

  /// Входит ли [installId] в долю [rollout].
  bool rolloutAllows(CryptoProvider crypto, Uint8List installId) =>
      rolloutBucket(crypto, installId) < (rollout * 100).floor();

  static int _intField(Map<String, Object?> m, String name) {
    final v = m[name];
    if (v is int) return v;
    throw DataFormatException(
      object: 'updates',
      problem: FormatProblem.invalidField,
      detail: name,
    );
  }

  static String _stringField(Map<String, Object?> m, String name) {
    final v = m[name];
    if (v is String && v.isNotEmpty) return v;
    throw DataFormatException(
      object: 'updates',
      problem: FormatProblem.invalidField,
      detail: name,
    );
  }

  static double _numberField(Map<String, Object?> m, String name) {
    final v = m[name];
    if (v is num) return v.toDouble();
    throw DataFormatException(
      object: 'updates',
      problem: FormatProblem.invalidField,
      detail: name,
    );
  }

  static Uint8List _base64Key(Object? v, String name) {
    if (v is! String) {
      throw DataFormatException(
        object: 'updates',
        problem: FormatProblem.invalidField,
        detail: name,
      );
    }
    try {
      final bytes = base64Decode(v);
      if (bytes.length != CryptoProvider.keyLength) {
        throw const FormatException('длина');
      }
      return Uint8List.fromList(bytes);
    } on FormatException {
      throw DataFormatException(
        object: 'updates',
        problem: FormatProblem.invalidField,
        detail: name,
      );
    }
  }

  static List<UpdatePackage> _packages(Object? v) {
    if (v is! List<Object?>) {
      throw const DataFormatException(
        object: 'updates',
        problem: FormatProblem.invalidField,
        detail: 'packages',
      );
    }
    return [
      for (final item in v)
        if (item is Map<String, Object?>)
          UpdatePackage(
            platform: UpdatePlatform.parse(_stringField(item, 'platform')),
            arch: switch (item['arch']) {
              final String a => a,
              _ => null,
            },
            url: _url(item),
            sha256: _hex32(item),
            size: _intField(item, 'size'),
          ),
    ];
  }

  static Uri _url(Map<String, Object?> item) {
    final text = _stringField(item, 'url');
    final uri = Uri.tryParse(text);
    if (uri == null || !uri.hasScheme) {
      throw DataFormatException(
        object: 'updates',
        problem: FormatProblem.invalidField,
        detail: 'url $text',
      );
    }
    return uri;
  }

  static Uint8List _hex32(Map<String, Object?> item) {
    final text = _stringField(item, 'sha256');
    if (text.length != 64) {
      throw const DataFormatException(
        object: 'updates',
        problem: FormatProblem.invalidField,
        detail: 'sha256',
      );
    }
    try {
      return hexToBytes(text);
    } on FormatException {
      throw const DataFormatException(
        object: 'updates',
        problem: FormatProblem.invalidField,
        detail: 'sha256',
      );
    }
  }
}
