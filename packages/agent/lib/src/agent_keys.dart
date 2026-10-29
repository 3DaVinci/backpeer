import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:agent/src/secrets/secret_store.dart';
import 'package:core/core.dart';

/// Ключи учётной записи и устройства в памяти агента: мастер-ключ и
/// секрет ключей устройства. [open] каждый раз выводит свежие объекты —
/// задание освобождает их само, а материал остаётся до [dispose].
final class KeyMaterial {
  new _(this.accountId, this._master, this._device);

  /// Копия ключей [keys] и [device].
  factory of(AccountKeys keys, DeviceKeys? device) => KeyMaterial._(
    Uint8List.fromList(keys.accountId),
    SecretBytes(keys.masterKey.bytes),
    device?.toSecret(),
  );

  final Uint8List accountId;
  final SecretBytes _master;
  final SecretBytes? _device;

  bool get hasDevice => _device != null;

  Future<(AccountKeys, DeviceKeys?)> open(CryptoProvider crypto) async {
    final keys = await AccountKeys.fromMasterKey(
      SecretBytes(_master.bytes),
      crypto,
    );
    if (_device case final secret?) {
      try {
        return (keys, await DeviceKeys.fromSecret(crypto, secret));
      } on Object {
        keys.dispose();
        rethrow;
      }
    }
    return (keys, null);
  }

  void dispose() {
    _master.dispose();
    _device?.dispose();
  }
}

/// Ключи для фоновой работы (задача 5.1.4, ADR-010): копия мастер-ключа и
/// ключей устройства в файле [file] (блоб типа 7, `crypto.md`, раздел 4.5)
/// под случайным ключом агента `K_agent`, а `K_agent` — в хранилище
/// секретов ОС ([SecretStore]) под ключом записи [entry].
///
/// Пароль при этом не хранится нигде. Удаление записи из хранилища ОС
/// ([forget]) или смена `K_agent` ([remember]) делает старый файл
/// бесполезным.
final class AgentKeyVault {
  new({
    required this.file,
    required this.crypto,
    required this.secrets,
    required this.entry,
  });

  /// Подпись записи в хранилище ОС.
  static const label = 'Ключ агента бэкапа (Backpeer)';

  final File file;
  final CryptoProvider crypto;
  final SecretStore secrets;

  /// Ключ записи в хранилище ОС: свой у каждого каталога программы.
  final String entry;

  bool get exists => file.existsSync();

  /// Сохраняет ключи для работы без пароля: новый `K_agent` в хранилище
  /// ОС, затем файл. Хранилище недоступно — [SecretStoreException], файл
  /// не меняется.
  Future<void> remember(AccountKeys keys, DeviceKeys? device) async {
    final agentKey = SecretBytes(crypto.randomBytes(CryptoProvider.keyLength));
    final deviceSecret = device?.toSecret();
    final plaintext = Uint8List(
      CryptoProvider.keyLength +
          (deviceSecret == null ? 0 : DeviceKeys.secretLength),
    )..setAll(0, keys.masterKey.bytes);
    if (deviceSecret != null) {
      plaintext.setAll(CryptoProvider.keyLength, deviceSecret.bytes);
    }
    deviceSecret?.dispose();
    try {
      final blob = EncryptedBlob.seal(
        crypto,
        type: BlobType.localAgentKeys,
        objectId: keys.accountId,
        key: agentKey,
        plaintext: plaintext,
      );
      await secrets.write(entry, label, base64.encode(agentKey.bytes));
      writePrivateFileAtomic(file, blob);
    } finally {
      plaintext.fillRange(0, plaintext.length, 0);
      agentKey.dispose();
    }
  }

  /// Ключи без пароля; нет файла или записи в хранилище — `null`.
  /// Хранилище недоступно или закрыто — [SecretStoreException]. Файл не
  /// подходит к ключу (запись в хранилище заменена) — тоже `null`.
  Future<KeyMaterial?> open() async {
    final Uint8List blob;
    try {
      blob = file.readAsBytesSync();
    } on PathNotFoundException {
      return null;
    }
    final encoded = await secrets.read(entry);
    if (encoded == null) return null;
    final Uint8List raw;
    try {
      raw = base64.decode(encoded);
    } on FormatException {
      return null;
    }
    final agentKey = SecretBytes.adopt(raw);
    try {
      if (agentKey.length != CryptoProvider.keyLength) return null;
      final header = BlobHeader.parse(blob);
      final plaintext = EncryptedBlob.open(
        crypto,
        blob,
        key: agentKey,
        expectedType: BlobType.localAgentKeys,
      );
      try {
        final withDevice =
            plaintext.length ==
            CryptoProvider.keyLength + DeviceKeys.secretLength;
        if (plaintext.length != CryptoProvider.keyLength && !withDevice) {
          return null;
        }
        final material = KeyMaterial._(
          Uint8List.fromList(header.objectId),
          SecretBytes(Uint8List.sublistView(plaintext, 0, 32)),
          withDevice ? SecretBytes(Uint8List.sublistView(plaintext, 32)) : null,
        );
        // Мастер-ключ должен давать ту же учётную запись, что в заголовке.
        final (keys, device) = await material.open(crypto);
        final same = constantTimeEquals(keys.accountId, material.accountId);
        keys.dispose();
        device?.dispose();
        if (!same) {
          material.dispose();
          return null;
        }
        return material;
      } finally {
        plaintext.fillRange(0, plaintext.length, 0);
      }
    } on CoreException {
      return null;
    } finally {
      agentKey.dispose();
    }
  }

  /// Удаляет ключи для работы без пароля: запись в хранилище ОС и файл.
  Future<void> forget() async {
    try {
      await secrets.delete(entry);
    } finally {
      if (file.existsSync()) file.deleteSync();
    }
  }
}
