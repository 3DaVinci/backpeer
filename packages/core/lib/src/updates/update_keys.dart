import 'dart:convert';
import 'dart:typed_data';

/// Ключи обновлений (docs/spec/updates.md, раздел 2).
///
/// В релизной сборке открытый ключ боевой пары подставляется при сборке,
/// как `appVersion` (`tool/build_exe.dart`); до этого действует ключ
/// разработки ниже. Закрытый ключ — только на машине подписи (П-3), в код
/// и репозиторий не попадает.
abstract final class UpdateKeys {
  /// Открытый ключ разработки (base64), общий с генератором векторов
  /// `tool/updates/vectors.dart` и инструментом `tool/updates/sign.dart`.
  static const String devPublicKeyBase64 =
      'FzH7INb5iGbO100vf7rDEXI8meIK6pkKsoGg0zSCuyk=';

  /// Открытый ключ разработки, 32 байта.
  static Uint8List devPublicKey() =>
      Uint8List.fromList(base64Decode(devPublicKeyBase64));
}
