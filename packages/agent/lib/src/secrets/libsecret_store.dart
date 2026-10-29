import 'dart:ffi';
import 'dart:isolate';

import 'package:agent/src/secrets/secret_store.dart';
import 'package:ffi/ffi.dart';

/// Secret Service (GNOME Keyring, KWallet 5.97+, KeePassXC) через
/// libsecret по FFI (ADR-010). Библиотека системная, в сборку не входит;
/// пакет D-Bus для Dart не подошёл по лицензии (MPL-2.0).
///
/// Вызовы `*_sync` блокируют поток, а при закрытой связке ключей ждут,
/// пока пользователь ответит на запрос пароля, — поэтому каждый вызов
/// идёт в отдельном isolate ([Isolate.run]).
///
/// Схема записи — [schema], атрибут `key` — ключ записи. Секрет проходит
/// через строки Dart и glib и не затирается — так у любого клиента
/// Secret Service.
final class LibsecretStore implements SecretStore {
  new _();

  /// Имя схемы: по нему записи видны в «Паролях и ключах».
  static const schema = 'org.backpeer.agent';

  /// libsecret и glib загружаются; нет — `null`.
  static LibsecretStore? open() {
    try {
      _Lib.load();
      return LibsecretStore._();
      // Нет библиотеки: FFI бросает ArgumentError.
      // ignore: avoid_catching_errors
    } on ArgumentError {
      return null;
    }
  }

  @override
  String get name => 'secret-service';

  @override
  Future<String?> read(String key) =>
      Isolate.run(() => _Lib.load().lookup(key));

  @override
  Future<void> write(String key, String label, String secret) =>
      Isolate.run(() => _Lib.load().store(key, label, secret));

  @override
  Future<void> delete(String key) => Isolate.run(() => _Lib.load().clear(key));
}

final class _GError extends Struct {
  @Uint32()
  external int domain;

  @Int32()
  external int code;

  external Pointer<Utf8> message;
}

typedef _HashTableNewC = Pointer<Void> Function(Pointer<Void>, Pointer<Void>);
typedef _HashTableInsertC = Int32 Function(
  Pointer<Void>,
  Pointer<Void>,
  Pointer<Void>,
);
typedef _HashTableInsert = int Function(
  Pointer<Void>,
  Pointer<Void>,
  Pointer<Void>,
);
typedef _UnrefC = Void Function(Pointer<Void>);
typedef _Unref = void Function(Pointer<Void>);
typedef _SchemaNewvC = Pointer<Void> Function(
  Pointer<Utf8>,
  Int32,
  Pointer<Void>,
);
typedef _SchemaNewv = Pointer<Void> Function(Pointer<Utf8>, int, Pointer<Void>);
typedef _StorevC = Int32 Function(
  Pointer<Void>,
  Pointer<Void>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Void>,
  Pointer<Pointer<_GError>>,
);
typedef _Storev = int Function(
  Pointer<Void>,
  Pointer<Void>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Void>,
  Pointer<Pointer<_GError>>,
);
typedef _LookupvC = Pointer<Utf8> Function(
  Pointer<Void>,
  Pointer<Void>,
  Pointer<Void>,
  Pointer<Pointer<_GError>>,
);
typedef _ClearvC = Int32 Function(
  Pointer<Void>,
  Pointer<Void>,
  Pointer<Void>,
  Pointer<Pointer<_GError>>,
);
typedef _Clearv = int Function(
  Pointer<Void>,
  Pointer<Void>,
  Pointer<Void>,
  Pointer<Pointer<_GError>>,
);
typedef _PasswordFreeC = Void Function(Pointer<Utf8>);
typedef _PasswordFree = void Function(Pointer<Utf8>);
typedef _ErrorFreeC = Void Function(Pointer<_GError>);
typedef _ErrorFree = void Function(Pointer<_GError>);

/// Функции libsecret и glib. Загружается в каждом isolate заново: указатели
/// функций нельзя передать между isolate.
final class _Lib {
  factory load() => _instance ??= _Lib._(
    DynamicLibrary.open('libsecret-1.so.0'),
    DynamicLibrary.open('libglib-2.0.so.0'),
  );

  new _(DynamicLibrary secret, DynamicLibrary glib)
    : _hashTableNew = glib.lookupFunction<_HashTableNewC, _HashTableNewC>(
        'g_hash_table_new',
      ),
      _hashTableInsert = glib
          .lookupFunction<_HashTableInsertC, _HashTableInsert>(
            'g_hash_table_insert',
          ),
      _hashTableUnref = glib.lookupFunction<_UnrefC, _Unref>(
        'g_hash_table_unref',
      ),
      _strHash = glib.lookup<Void>('g_str_hash'),
      _strEqual = glib.lookup<Void>('g_str_equal'),
      _errorFree = glib.lookupFunction<_ErrorFreeC, _ErrorFree>('g_error_free'),
      _schemaNewv = secret.lookupFunction<_SchemaNewvC, _SchemaNewv>(
        'secret_schema_newv',
      ),
      _schemaUnref = secret.lookupFunction<_UnrefC, _Unref>(
        'secret_schema_unref',
      ),
      _storev = secret.lookupFunction<_StorevC, _Storev>(
        'secret_password_storev_sync',
      ),
      _lookupv = secret.lookupFunction<_LookupvC, _LookupvC>(
        'secret_password_lookupv_sync',
      ),
      _clearv = secret.lookupFunction<_ClearvC, _Clearv>(
        'secret_password_clearv_sync',
      ),
      _passwordFree = secret.lookupFunction<_PasswordFreeC, _PasswordFree>(
        'secret_password_free',
      );

  static _Lib? _instance;

  final Pointer<Void> Function(Pointer<Void>, Pointer<Void>) _hashTableNew;
  final _HashTableInsert _hashTableInsert;
  final _Unref _hashTableUnref;
  final Pointer<Void> _strHash;
  final Pointer<Void> _strEqual;
  final _ErrorFree _errorFree;
  final _SchemaNewv _schemaNewv;
  final _Unref _schemaUnref;
  final _Storev _storev;
  final Pointer<Utf8> Function(
    Pointer<Void>,
    Pointer<Void>,
    Pointer<Void>,
    Pointer<Pointer<_GError>>,
  )
  _lookupv;
  final _Clearv _clearv;
  final _PasswordFree _passwordFree;

  /// `SECRET_SCHEMA_ATTRIBUTE_STRING`.
  static const _attributeString = 0;

  /// `SECRET_SCHEMA_NONE`.
  static const _schemaFlags = 0;

  String? lookup(String key) => _call(key, (schema, attributes, error) {
    final value = _lookupv(schema, attributes, nullptr, error);
    if (value == nullptr) return null;
    try {
      return value.toDartString();
    } finally {
      _passwordFree(value);
    }
  });

  void store(String key, String label, String secret) =>
      _call(key, (schema, attributes, error) {
        final l = label.toNativeUtf8();
        final s = secret.toNativeUtf8();
        try {
          _storev(schema, attributes, nullptr, l, s, nullptr, error);
        } finally {
          s.cast<Uint8>().asTypedList(s.length).fillRange(0, s.length, 0);
          malloc
            ..free(l)
            ..free(s);
        }
      });

  void clear(String key) => _call(key, (schema, attributes, error) {
    _clearv(schema, attributes, nullptr, error);
  });

  /// Схема и атрибуты `{key}` на время [body]; GError — исключение.
  T _call<T>(
    String key,
    T Function(
      Pointer<Void> schema,
      Pointer<Void> attributes,
      Pointer<Pointer<_GError>> error,
    )
    body,
  ) {
    final name = LibsecretStore.schema.toNativeUtf8();
    final attr = 'key'.toNativeUtf8();
    final value = key.toNativeUtf8();
    final error = calloc<Pointer<_GError>>();
    final types = _hashTableNew(_strHash, _strEqual);
    final attributes = _hashTableNew(_strHash, _strEqual);
    Pointer<Void> schema = nullptr;
    try {
      _hashTableInsert(
        types,
        attr.cast(),
        Pointer.fromAddress(_attributeString),
      );
      schema = _schemaNewv(name, _schemaFlags, types);
      _hashTableInsert(attributes, attr.cast(), value.cast());
      final result = body(schema, attributes, error);
      final e = error.value;
      if (e != nullptr) {
        final message = e.ref.message.toDartString();
        _errorFree(e);
        throw SecretStoreException(message);
      }
      return result;
    } finally {
      if (schema != nullptr) _schemaUnref(schema);
      _hashTableUnref(attributes);
      _hashTableUnref(types);
      calloc.free(error);
      malloc
        ..free(name)
        ..free(attr)
        ..free(value);
    }
  }
}
