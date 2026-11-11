import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:agent/src/secrets/secret_store.dart';
import 'package:ffi/ffi.dart';

/// Связка ключей macOS (Keychain) через Security.framework по FFI
/// (задача 5.1.5, ADR-010).
///
/// Запись — `kSecClassGenericPassword` со службой [service]; счёт
/// (`kSecAttrAccount`) — ключ записи, то есть путь каталога программы, как
/// атрибут `key` у libsecret. Секрет — та же короткая строка (ключ агента
/// в base64), что и на Linux.
///
/// В связке ключей запись видна в «Связке ключей» как `service` со счётом —
/// путём каталога программы. Доступ к ней система даёт приложению с той же
/// подписью (Developer ID), поэтому после обновления по сети ключ читается
/// без запроса пароля.
///
/// Вызовы `SecItem*` синхронные и могут ждать ответа пользователя
/// (разрешение доступа к записи), — поэтому каждый идёт в отдельном
/// isolate, как у `LibsecretStore` на Linux. Указатели CF-объектов между
/// isolate не передаются: библиотека загружается в каждом заново.
final class KeychainStore implements SecretStore {
  new _();

  /// Служба записей: по ней они видны в «Связке ключей».
  static const service = 'org.backpeer.agent';

  /// Security.framework и CoreFoundation загружаются; нет — `null`.
  static KeychainStore? open() {
    try {
      _Lib.load();
      return KeychainStore._();
      // Нет библиотеки: FFI бросает ArgumentError.
      // ignore: avoid_catching_errors
    } on ArgumentError {
      return null;
    }
  }

  @override
  String get name => 'keychain';

  @override
  Future<String?> read(String key) =>
      Isolate.run(() => _Lib.load().read(service, key));

  @override
  Future<void> write(String key, String label, String secret) =>
      Isolate.run(() => _Lib.load().write(service, key, label, secret));

  @override
  Future<void> delete(String key) =>
      Isolate.run(() => _Lib.load().delete(service, key));
}

/// `kCFStringEncodingUTF8`.
const _encodingUtf8 = 0x08000100;

/// `errSecSuccess`.
const _statusOk = 0;

/// `errSecItemNotFound` — записи нет (для удаления и чтения это не ошибка).
const _statusNotFound = -25300;

/// Функции Security.framework и CoreFoundation. Загружается в каждом
/// isolate заново: указатели функций нельзя передать между isolate.
final class _Lib {
  factory load() => _instance ??= _Lib._(
    DynamicLibrary.open(
      '/System/Library/Frameworks/Security.framework/Security',
    ),
    DynamicLibrary.open(
      '/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation',
    ),
  );

  new _(DynamicLibrary security, DynamicLibrary coreFoundation)
    : _stringCreate = coreFoundation
          .lookupFunction<_StringCreateC, _StringCreate>(
            'CFStringCreateWithCString',
          ),
      _dataCreate = coreFoundation.lookupFunction<_DataCreateC, _DataCreate>(
        'CFDataCreate',
      ),
      _dataLength = coreFoundation.lookupFunction<_DataLengthC, _DataLength>(
        'CFDataGetLength',
      ),
      _dataBytes = coreFoundation.lookupFunction<_DataBytesC, _DataBytes>(
        'CFDataGetBytePtr',
      ),
      _getTypeId = coreFoundation.lookupFunction<_TypeIdC, _TypeId>(
        'CFGetTypeID',
      ),
      _dataGetTypeId = coreFoundation.lookupFunction<_TypeIdGetC, _TypeIdGet>(
        'CFDataGetTypeID',
      ),
      _dictionaryCreate = coreFoundation
          .lookupFunction<_DictionaryCreateC, _DictionaryCreate>(
            'CFDictionaryCreateMutable',
          ),
      _dictionaryAdd = coreFoundation
          .lookupFunction<_DictionaryAddC, _DictionaryAdd>(
            'CFDictionaryAddValue',
          ),
      _release = coreFoundation.lookupFunction<_ReleaseC, _Release>(
        'CFRelease',
      ),
      _itemAdd = security.lookupFunction<_ItemAddC, _ItemAdd>('SecItemAdd'),
      _itemCopy = security.lookupFunction<_ItemCopyC, _ItemCopy>(
        'SecItemCopyMatching',
      ),
      _itemUpdate = security.lookupFunction<_ItemUpdateC, _ItemUpdate>(
        'SecItemUpdate',
      ),
      _itemDelete = security.lookupFunction<_ItemDeleteC, _ItemDelete>(
        'SecItemDelete',
      ),
      _keyCallbacks = coreFoundation.lookup<Void>(
        'kCFTypeDictionaryKeyCallBacks',
      ),
      _valueCallbacks = coreFoundation.lookup<Void>(
        'kCFTypeDictionaryValueCallBacks',
      ),
      _booleanTrue = coreFoundation
          .lookup<Pointer<Void>>('kCFBooleanTrue')
          .value,
      _class = security.lookup<Pointer<Void>>('kSecClass').value,
      _classGenericPassword = security
          .lookup<Pointer<Void>>('kSecClassGenericPassword')
          .value,
      _attrService = security.lookup<Pointer<Void>>('kSecAttrService').value,
      _attrAccount = security.lookup<Pointer<Void>>('kSecAttrAccount').value,
      _attrLabel = security.lookup<Pointer<Void>>('kSecAttrLabel').value,
      _valueData = security.lookup<Pointer<Void>>('kSecValueData').value,
      _returnData = security.lookup<Pointer<Void>>('kSecReturnData').value,
      _matchLimit = security.lookup<Pointer<Void>>('kSecMatchLimit').value,
      _matchLimitOne = security
          .lookup<Pointer<Void>>('kSecMatchLimitOne')
          .value;

  static _Lib? _instance;

  final _StringCreate _stringCreate;
  final _DataCreate _dataCreate;
  final _DataLength _dataLength;
  final _DataBytes _dataBytes;
  final _TypeId _getTypeId;
  final _TypeIdGet _dataGetTypeId;
  final _DictionaryCreate _dictionaryCreate;
  final _DictionaryAdd _dictionaryAdd;
  final _Release _release;
  final _ItemAdd _itemAdd;
  final _ItemCopy _itemCopy;
  final _ItemUpdate _itemUpdate;
  final _ItemDelete _itemDelete;
  final Pointer<Void> _keyCallbacks;
  final Pointer<Void> _valueCallbacks;
  final Pointer<Void> _booleanTrue;
  final Pointer<Void> _class;
  final Pointer<Void> _classGenericPassword;
  final Pointer<Void> _attrService;
  final Pointer<Void> _attrAccount;
  final Pointer<Void> _attrLabel;
  final Pointer<Void> _valueData;
  final Pointer<Void> _returnData;
  final Pointer<Void> _matchLimit;
  final Pointer<Void> _matchLimitOne;

  String? read(String service, String account) {
    final use = _Refs(this);
    final out = calloc<Pointer<Void>>();
    try {
      final query = use.dictionary();
      use
        ..add(query, _class, _classGenericPassword)
        ..add(query, _attrService, use.string(service))
        ..add(query, _attrAccount, use.string(account))
        ..add(query, _returnData, _booleanTrue)
        ..add(query, _matchLimit, _matchLimitOne);
      final status = _itemCopy(query, out);
      if (status == _statusNotFound) return null;
      if (status != _statusOk) throw _error(status, 'чтение');
      final result = out.value;
      if (result == nullptr) return null;
      try {
        if (_getTypeId(result) != _dataGetTypeId()) {
          throw const SecretStoreException('связка ключей вернула не данные');
        }
        final length = _dataLength(result);
        if (length == 0) return null;
        final bytes = Uint8List.fromList(
          _dataBytes(result).asTypedList(length),
        );
        return utf8.decode(bytes);
      } finally {
        _release(result);
      }
    } finally {
      use.dispose();
      calloc.free(out);
    }
  }

  void write(String service, String account, String label, String secret) {
    final use = _Refs(this);
    try {
      final query = use.dictionary();
      use
        ..add(query, _class, _classGenericPassword)
        ..add(query, _attrService, use.string(service))
        ..add(query, _attrAccount, use.string(account));
      // В обновлении — только секрет: метка не меняется, а лишние
      // атрибуты в запросе `SecItemUpdate` старый Keychain не принимает.
      final update = use.dictionary();
      use.add(update, _valueData, use.data(utf8.encode(secret)));
      // Сначала обновление: если запись есть, она не пропадает ни на
      // мгновение (удаление + добавление оставили бы окно без ключа).
      final status = _itemUpdate(query, update);
      if (status != _statusNotFound) {
        if (status != _statusOk) throw _error(status, 'запись');
        return;
      }
      final attributes = use.dictionary();
      use
        ..add(attributes, _class, _classGenericPassword)
        ..add(attributes, _attrService, use.string(service))
        ..add(attributes, _attrAccount, use.string(account))
        ..add(attributes, _attrLabel, use.string(label))
        ..add(attributes, _valueData, use.data(utf8.encode(secret)));
      final out = calloc<Pointer<Void>>();
      try {
        final added = _itemAdd(attributes, out);
        if (added != _statusOk) throw _error(added, 'запись');
      } finally {
        calloc.free(out);
      }
    } finally {
      use.dispose();
    }
  }

  void delete(String service, String account) {
    final use = _Refs(this);
    try {
      final query = use.dictionary();
      use
        ..add(query, _class, _classGenericPassword)
        ..add(query, _attrService, use.string(service))
        ..add(query, _attrAccount, use.string(account));
      final status = _itemDelete(query);
      if (status != _statusOk && status != _statusNotFound) {
        throw _error(status, 'удаление');
      }
    } finally {
      use.dispose();
    }
  }

  /// Ошибка связки ключей словами: коды `SecBase.h`.
  SecretStoreException _error(int status, String what) =>
      SecretStoreException(switch (status) {
        // errSecInteractionNotAllowed — связка закрыта, а спросить
        // пользователя негде: агент работает без окна.
        -25308 => 'связка ключей закрыта: её нужно разблокировать в сеансе',
        // errSecAuthFailed, errSecNotAvailable, errSecNoAccessForItem.
        -25293 => 'связка ключей не приняла пароль сеанса',
        -25291 => 'связка ключей недоступна',
        -25243 => 'нет доступа к записи в связке ключей',
        // errSecDuplicateItem — гонка двух записей: повтор не поможет.
        -25299 => 'запись в связке ключей уже есть',
        _ => 'связка ключей: ошибка при $what, код $status',
      });
}

/// CF-объекты, созданные для одного вызова: освобождаются все разом.
///
/// Словарь сохраняет (retain) ключи и значения, поэтому свои ссылки на них
/// можно отпускать сразу после `CFDictionaryAddValue`; здесь они живут до
/// конца вызова — так проще и безопаснее.
final class _Refs {
  new(this._lib);

  final _Lib _lib;
  final List<Pointer<Void>> _made = [];

  Pointer<Void> string(String value) {
    final c = value.toNativeUtf8();
    try {
      final cf = _lib._stringCreate(nullptr, c, _encodingUtf8);
      if (cf == nullptr) {
        throw const SecretStoreException('связка ключей: не хватило памяти');
      }
      _made.add(cf);
      return cf;
    } finally {
      malloc.free(c);
    }
  }

  Pointer<Void> data(List<int> bytes) {
    final raw = malloc<Uint8>(bytes.length);
    try {
      raw.asTypedList(bytes.length).setAll(0, bytes);
      final cf = _lib._dataCreate(nullptr, raw, bytes.length);
      if (cf == nullptr) {
        throw const SecretStoreException('связка ключей: не хватило памяти');
      }
      _made.add(cf);
      return cf;
    } finally {
      malloc.free(raw);
    }
  }

  Pointer<Void> dictionary() {
    final dict = _lib._dictionaryCreate(
      nullptr,
      0,
      _lib._keyCallbacks,
      _lib._valueCallbacks,
    );
    if (dict == nullptr) {
      throw const SecretStoreException('связка ключей: не хватило памяти');
    }
    _made.add(dict);
    return dict;
  }

  void add(Pointer<Void> dictionary, Pointer<Void> key, Pointer<Void> value) =>
      _lib._dictionaryAdd(dictionary, key, value);

  void dispose() {
    _made.forEach(_lib._release);
    _made.clear();
  }
}

typedef _StringCreateC = Pointer<Void> Function(
  Pointer<Void>,
  Pointer<Utf8>,
  Uint32,
);
typedef _StringCreate = Pointer<Void> Function(
  Pointer<Void>,
  Pointer<Utf8>,
  int,
);
typedef _DataCreateC = Pointer<Void> Function(
  Pointer<Void>,
  Pointer<Uint8>,
  IntPtr,
);
typedef _DataCreate = Pointer<Void> Function(
  Pointer<Void>,
  Pointer<Uint8>,
  int,
);
typedef _DataLengthC = IntPtr Function(Pointer<Void>);
typedef _DataLength = int Function(Pointer<Void>);
typedef _DataBytesC = Pointer<Uint8> Function(Pointer<Void>);
typedef _DataBytes = Pointer<Uint8> Function(Pointer<Void>);
typedef _TypeIdC = UintPtr Function(Pointer<Void>);
typedef _TypeId = int Function(Pointer<Void>);
typedef _TypeIdGetC = UintPtr Function();
typedef _TypeIdGet = int Function();
typedef _DictionaryCreateC = Pointer<Void> Function(
  Pointer<Void>,
  IntPtr,
  Pointer<Void>,
  Pointer<Void>,
);
typedef _DictionaryCreate = Pointer<Void> Function(
  Pointer<Void>,
  int,
  Pointer<Void>,
  Pointer<Void>,
);
typedef _DictionaryAddC = Void Function(
  Pointer<Void>,
  Pointer<Void>,
  Pointer<Void>,
);
typedef _DictionaryAdd = void Function(
  Pointer<Void>,
  Pointer<Void>,
  Pointer<Void>,
);
typedef _ReleaseC = Void Function(Pointer<Void>);
typedef _Release = void Function(Pointer<Void>);
typedef _ItemAddC = Int32 Function(Pointer<Void>, Pointer<Pointer<Void>>);
typedef _ItemAdd = int Function(Pointer<Void>, Pointer<Pointer<Void>>);
typedef _ItemCopyC = Int32 Function(Pointer<Void>, Pointer<Pointer<Void>>);
typedef _ItemCopy = int Function(Pointer<Void>, Pointer<Pointer<Void>>);
typedef _ItemUpdateC = Int32 Function(Pointer<Void>, Pointer<Void>);
typedef _ItemUpdate = int Function(Pointer<Void>, Pointer<Void>);
typedef _ItemDeleteC = Int32 Function(Pointer<Void>);
typedef _ItemDelete = int Function(Pointer<Void>);
