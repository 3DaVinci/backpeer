import 'dart:convert';
import 'dart:typed_data';

import 'package:core/core.dart';

/// Открытый ключ обновлений, вшитый в приложение при сборке
/// (`--dart-define=UPDATE_PUBLIC_KEY=...`; docs/spec/updates.md, раздел 2).
/// Пусто — сборка без обновлений (запуск из исходников, локальная сборка).
const String updatePublicKeyBase64 = String.fromEnvironment(
  'UPDATE_PUBLIC_KEY',
);

/// База адресов обновлений (`--dart-define=UPDATE_BASE_URL=...`). Для
/// GitHub Releases — `https://github.com/OWNER/REPO/releases/latest/download`;
/// клиент запрашивает `{channel}.json` и `{channel}.json.sig` рядом с
/// пакетами. Пусто — обновления не проверяются.
const String updateBaseUrl = String.fromEnvironment('UPDATE_BASE_URL');

/// Настройки обновлений из сборки: адрес, допустимые ключи и текущая
/// версия. `null` — обновления не настроены или версия не стабильная
/// (`dev`, `X.Y.Z-dev.N`).
final class UpdateConfig {
  const new({
    required this.baseUri,
    required this.acceptedKeys,
    required this.currentVersion,
  });

  final Uri baseUri;
  final List<Uint8List> acceptedKeys;
  final ProductVersion currentVersion;

  /// Для текущей сборки; [version] — для тестов.
  static UpdateConfig? resolve({String version = appVersion}) {
    if (updatePublicKeyBase64.isEmpty || updateBaseUrl.isEmpty) return null;
    final base = Uri.tryParse(updateBaseUrl);
    if (base == null || !base.hasScheme) return null;
    final key = _publicKey();
    if (key == null) return null;
    final current = _stableVersion(version);
    if (current == null) return null;
    return UpdateConfig(
      baseUri: base,
      acceptedKeys: [key],
      currentVersion: current,
    );
  }

  static Uint8List? _publicKey() {
    try {
      final bytes = base64Decode(updatePublicKeyBase64);
      if (bytes.length != CryptoProvider.keyLength) return null;
      return Uint8List.fromList(bytes);
    } on FormatException {
      return null;
    }
  }

  static ProductVersion? _stableVersion(String text) {
    try {
      return ProductVersion.parse(text);
    } on Object {
      return null;
    }
  }
}
