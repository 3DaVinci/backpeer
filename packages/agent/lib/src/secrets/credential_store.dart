import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';

import 'package:agent/src/secrets/secret_store.dart';
import 'package:ffi/ffi.dart';

/// Диспетчер учётных данных Windows (Credential Manager) через advapi32 по
/// FFI (задача 5.1.5, ADR-010).
///
/// Запись — обычная учётная запись (`CRED_TYPE_GENERIC`) с именем
/// [target]; секрет — та же короткая строка (ключ агента в base64), что и
/// на Linux и macOS. Диспетчер шифрует секрет ключом входа пользователя
/// (DPAPI), поэтому в файле на диске его нет.
///
/// Запись видна в «Панели управления» → «Диспетчер учётных данных» →
/// «Учётные данные Windows» с именем `target`. Она сохраняется на этом
/// компьютере (`CRED_PERSIST_LOCAL_MACHINE`) и доступна процессам этого же
/// пользователя — как и запись Secret Service на Linux.
///
/// Вызовы `Cred*W` синхронные; они идут в отдельном isolate, как у
/// `LibsecretStore`, чтобы не задерживать события агента. Указатели между
/// isolate не передаются: библиотека загружается в каждом заново.
final class CredentialStore implements SecretStore {
  new _();

  /// Начало имени записи: по нему записи агента видно в диспетчере.
  static const targetPrefix = 'Backpeer';

  /// advapi32 загружается; нет (не Windows) — `null`.
  static CredentialStore? open() {
    try {
      _Lib.load();
      return CredentialStore._();
      // Нет библиотеки: FFI бросает ArgumentError.
      // ignore: avoid_catching_errors
    } on ArgumentError {
      return null;
    }
  }

  @override
  String get name => 'credential-manager';

  /// Имя записи для ключа [key] — пути каталога программы (как атрибут
  /// `key` у libsecret): `Backpeer: C:\Users\…\backpeer`.
  static String target(String key) => '$targetPrefix: $key';

  @override
  Future<String?> read(String key) =>
      Isolate.run(() => _Lib.load().read(target(key)));

  @override
  Future<void> write(String key, String label, String secret) =>
      Isolate.run(() => _Lib.load().write(target(key), label, secret));

  @override
  Future<void> delete(String key) =>
      Isolate.run(() => _Lib.load().delete(target(key)));
}

/// `CRED_TYPE_GENERIC`.
const _typeGeneric = 1;

/// `CRED_PERSIST_LOCAL_MACHINE` — переживает перезагрузку.
const _persistLocalMachine = 2;

/// `ERROR_NOT_FOUND`: записи нет — для чтения и удаления не ошибка.
const _errorNotFound = 1168;

/// Функции advapi32 и kernel32. Загружается в каждом isolate заново.
final class _Lib {
  factory load() => _instance ??= _Lib._(
    DynamicLibrary.open('advapi32.dll'),
    DynamicLibrary.open('kernel32.dll'),
  );

  new _(DynamicLibrary advapi, DynamicLibrary kernel)
    : _read = advapi.lookupFunction<_CredReadC, _CredRead>('CredReadW'),
      _write = advapi.lookupFunction<_CredWriteC, _CredWrite>('CredWriteW'),
      _delete = advapi.lookupFunction<_CredDeleteC, _CredDelete>('CredDeleteW'),
      _free = advapi.lookupFunction<_CredFreeC, _CredFree>('CredFree'),
      _lastError = kernel.lookupFunction<_LastErrorC, _LastError>(
        'GetLastError',
      );

  static _Lib? _instance;

  final _CredRead _read;
  final _CredWrite _write;
  final _CredDelete _delete;
  final _CredFree _free;
  final _LastError _lastError;

  String? read(String target) {
    final name = target.toNativeUtf16();
    final out = calloc<Pointer<_Credential>>();
    try {
      if (_read(name, _typeGeneric, 0, out) == 0) {
        final error = _lastError();
        if (error == _errorNotFound) return null;
        throw _error(error, 'чтение');
      }
      final credential = out.value;
      if (credential == nullptr) return null;
      try {
        final size = credential.ref.credentialBlobSize;
        if (size == 0) return null;
        final bytes = credential.ref.credentialBlob.asTypedList(size);
        return utf8.decode(bytes);
      } finally {
        // Буфер учётной записи освобождает только CredFree.
        _free(credential.cast());
      }
    } finally {
      malloc.free(name);
      calloc.free(out);
    }
  }

  void write(String target, String label, String secret) {
    final name = target.toNativeUtf16();
    final userName = label.toNativeUtf16();
    final bytes = utf8.encode(secret);
    final blob = malloc<Uint8>(bytes.length);
    final credential = calloc<_Credential>();
    try {
      blob.asTypedList(bytes.length).setAll(0, bytes);
      credential.ref
        ..type = _typeGeneric
        ..targetName = name
        ..comment = userName
        ..credentialBlobSize = bytes.length
        ..credentialBlob = blob
        ..persist = _persistLocalMachine
        ..userName = userName;
      if (_write(credential, 0) == 0) {
        throw _error(_lastError(), 'запись');
      }
    } finally {
      malloc
        ..free(name)
        ..free(userName)
        ..free(blob);
      calloc.free(credential);
    }
  }

  void delete(String target) {
    final name = target.toNativeUtf16();
    try {
      if (_delete(name, _typeGeneric, 0) == 0) {
        final error = _lastError();
        if (error != _errorNotFound) throw _error(error, 'удаление');
      }
    } finally {
      malloc.free(name);
    }
  }

  /// Ошибка диспетчера словами: коды WinError.
  SecretStoreException _error(int code, String what) =>
      SecretStoreException(switch (code) {
        // ERROR_ACCESS_DENIED, ERROR_NO_SUCH_LOGON_SESSION,
        // ERROR_NOT_FOUND.
        5 => 'диспетчер учётных данных не даёт доступа',
        1312 => 'у диспетчера учётных данных нет сеанса входа пользователя',
        1168 => 'учётной записи нет в диспетчере',
        _ => 'диспетчер учётных данных: ошибка при $what, код $code',
      });
}

/// `CREDENTIALW` (wincred.h). Раскладку полей считает сам Dart FFI.
final class _Credential extends Struct {
  @Uint32()
  external int flags;

  @Uint32()
  external int type;

  external Pointer<Utf16> targetName;

  external Pointer<Utf16> comment;

  external _FileTime lastWritten;

  @Uint32()
  external int credentialBlobSize;

  external Pointer<Uint8> credentialBlob;

  @Uint32()
  external int persist;

  @Uint32()
  external int attributeCount;

  external Pointer<Void> attributes;

  external Pointer<Utf16> targetAlias;

  external Pointer<Utf16> userName;
}

/// `FILETIME` (minwinbase.h).
final class _FileTime extends Struct {
  @Uint32()
  external int lowDateTime;

  @Uint32()
  external int highDateTime;
}

typedef _CredReadC = Int32 Function(
  Pointer<Utf16>,
  Uint32,
  Uint32,
  Pointer<Pointer<_Credential>>,
);
typedef _CredRead = int Function(
  Pointer<Utf16>,
  int,
  int,
  Pointer<Pointer<_Credential>>,
);
typedef _CredWriteC = Int32 Function(Pointer<_Credential>, Uint32);
typedef _CredWrite = int Function(Pointer<_Credential>, int);
typedef _CredDeleteC = Int32 Function(Pointer<Utf16>, Uint32, Uint32);
typedef _CredDelete = int Function(Pointer<Utf16>, int, int);
typedef _CredFreeC = Void Function(Pointer<Void>);
typedef _CredFree = void Function(Pointer<Void>);
typedef _LastErrorC = Uint32 Function();
typedef _LastError = int Function();
