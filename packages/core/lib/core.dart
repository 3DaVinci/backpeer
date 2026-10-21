/// Ядро (шифрование, erasure coding, чанкинг, форматы данных). Без Flutter.
///
/// Публичный API — только этот файл. Устройство `lib/src/`:
///
/// - `util/` — общие утилиты: целые little/big-endian, varint, hex;
/// - `crypto/` — `CryptoProvider`, ключи, зашифрованный блоб, KeyBundle;
/// - `chunking/` — FastCDC и идентификаторы чанков;
/// - `erasure/` — `ErasureCoder` и Reed–Solomon;
/// - `format/` — сегменты, фрагменты, дерево Меркла;
/// - `snapshot/` — обход папок, деревья, снимки и индексы;
/// - `storage/` — хранилища фрагментов и объектов, локальный индекс;
/// - `pipeline/` — конвейеры бэкапа и восстановления.
library;

export 'src/build_info.dart';
export 'src/chunking/chunk_id.dart';
export 'src/chunking/fastcdc.dart';
export 'src/chunking/file_chunker.dart';
export 'src/crypto/account_keys.dart';
export 'src/crypto/crypto_provider.dart';
export 'src/crypto/dart_crypto_provider.dart';
export 'src/crypto/encrypted_blob.dart';
export 'src/crypto/key_bundle.dart';
export 'src/crypto/recovery_phrase.dart' show RecoveryPhrase;
export 'src/crypto/secret_bytes.dart';
export 'src/crypto/sodium_crypto_provider.dart';
export 'src/erasure/erasure_coder.dart';
export 'src/erasure/reed_solomon.dart';
export 'src/errors.dart';
export 'src/storage/device_key_store.dart';
export 'src/storage/local_index.dart';
export 'src/util/bytes.dart';
