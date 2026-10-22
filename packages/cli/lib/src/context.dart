import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:args/command_runner.dart';
import 'package:cli/src/app_config.dart';
import 'package:cli/src/console.dart';
import 'package:cli/src/password.dart';
import 'package:core/core.dart';

/// Коды возврата CLI.
abstract final class ExitCode {
  static const int ok = 0;

  /// Ошибка: операция не выполнена.
  static const int error = 1;

  /// Неверный вызов: команда, флаги, аргументы.
  static const int usage = 2;

  /// Частичный успех: выполнено, но часть файлов пропущена или не
  /// восстановлена, есть предупреждения о снимках или фрагментах.
  static const int partial = 3;

  /// Прервано пользователем (Ctrl+C), как принято в Unix: 128 + SIGINT.
  static const int cancelled = 130;
}

/// Вывод команд: текст для человека или JSON Lines (`--json`): каждая
/// строка — объект с полем `type` (`progress`, `warning`, `phrase`,
/// `result`, `error`); последняя — `result` или `error`.
final class Reporter {
  new(this.console, {required this.json});

  final Console console;
  final bool json;

  /// Текст только для человека.
  void info(String text) {
    if (!json) console.out(text);
  }

  /// Предупреждение: текст в stderr или событие `warning`.
  void warn(String text, [Map<String, Object?> data = const {}]) {
    if (json) {
      _emit({'type': 'warning', 'message': text, ...data});
    } else {
      console.err(text);
    }
  }

  void progress(Map<String, Object?> data, String human) {
    if (json) {
      _emit({'type': 'progress', ...data});
    } else {
      console.progress(human);
    }
  }

  /// Произвольное событие JSON (например, `phrase`); в тексте не выводится.
  void event(String type, Map<String, Object?> data) {
    if (json) _emit({'type': type, ...data});
  }

  void result(Map<String, Object?> data, {int exitCode = ExitCode.ok}) {
    if (json) _emit({'type': 'result', 'exitCode': exitCode, ...data});
  }

  void error(String message, int exitCode) {
    if (json) {
      _emit({'type': 'error', 'exitCode': exitCode, 'message': message});
    } else {
      console.err('Ошибка: $message');
    }
  }

  void _emit(Map<String, Object?> event) => console.out(jsonEncode(event));
}

/// Ошибка, понятная пользователю, с кодом возврата.
final class CliException implements Exception {
  const new(this.message, [this.exitCode = ExitCode.error]);

  final String message;
  final int exitCode;
}

/// Общее для команд: ввод-вывод, каталог программы, криптография,
/// разблокировка ключей.
final class CliContext {
  new({
    required this.console,
    required this.env,
    required this.home,
    this.json = false,
  }) : report = Reporter(console, json: json);

  final Console console;
  final bool json;
  final Reporter report;
  final Map<String, String> env;
  final AppHome home;

  Future<CryptoProvider>? _crypto;

  /// libsodium; если не загрузилась — запасная реализация на Dart. Один
  /// раз на запуск, даже при одновременных вызовах.
  Future<CryptoProvider> crypto() => _crypto ??= _loadCrypto();

  Future<CryptoProvider> _loadCrypto() async {
    try {
      return await SodiumCryptoProvider.load();
    } on Object catch (e) {
      report.warn(
        'libsodium недоступна, работаю медленнее, на Dart: '
        '${_nativeHint('$e')}',
      );
      return DartCryptoProvider();
    }
  }

  /// Параметры Argon2id; `FS_ARGON2_FAST=1` — малые, только для тестов.
  Argon2Params get argon2 => env['FS_ARGON2_FAST'] == '1'
      ? const Argon2Params(memoryKiB: 1024, iterations: 1)
      : const Argon2Params();

  Future<DeviceKeyStore> keyStore() async =>
      DeviceKeyStore(home.keysFile, await crypto(), params: argon2);

  AppConfig config() => AppConfig.load(home);

  /// Пароль: `FS_PASSWORD` (для скриптов) или ввод без эха.
  String password([String prompt = 'Пароль: ']) {
    if (env['FS_PASSWORD'] case final String p) return p;
    final value = console.askSecret(prompt);
    if (value == null) throw const CliException('Пароль не введён');
    return value;
  }

  /// Новый пароль: дважды, не короче [minPasswordLength], с оценкой
  /// стойкости и подтверждением слабого (модель угроз, К-3).
  String newPassword() {
    if (env['FS_PASSWORD'] case final String p) {
      if (p.runes.length < minPasswordLength) {
        throw const CliException(
          'FS_PASSWORD короче $minPasswordLength символов',
        );
      }
      return p;
    }
    for (;;) {
      final first = password(
        'Новый пароль (не короче $minPasswordLength символов): ',
      );
      if (first.runes.length < minPasswordLength) {
        console.err('Слишком короткий пароль.');
        continue;
      }
      final bits = estimatePasswordBits(first);
      console.err(
        'Оценка стойкости: ${passwordRating(bits)} (≈ ${bits.round()} бит).',
      );
      if (bits < 50) {
        console.err(
          'Слабый пароль можно подобрать, если копия ключа попадёт к '
          'злоумышленнику. Лучше 4–5 случайных слов.',
        );
        final answer = console.ask('Оставить этот пароль? (да/нет): ');
        if (answer?.trim().toLowerCase() != 'да') continue;
      }
      if (password('Повторите пароль: ') != first) {
        console.err('Пароли не совпадают.');
        continue;
      }
      return first;
    }
  }

  /// Ключи учётной записи по паролю.
  Future<AccountKeys> unlock() async {
    final store = await keyStore();
    if (!store.exists) {
      throw CliException(
        'Нет ключей в ${home.dir.path}; сначала init или recover',
      );
    }
    try {
      return await store.unlock(password());
    } on IntegrityException {
      throw const CliException('Неверный пароль');
    }
  }

  /// Хранилища этапа 1: папки-«узлы» и папка объектов.
  Future<LocalFolderStore> fragments(AppConfig config) async =>
      LocalFolderStore(
        Directory(config.nodes),
        await crypto(),
        nodeCount: config.nodeCount,
      );

  LocalObjectStore objects(AppConfig config) =>
      LocalObjectStore(Directory(config.objects));

  /// Локальный индекс. Если библиотека SQLite не загружается (например,
  /// слишком старая glibc), — понятная ошибка вместо трассировки.
  LocalIndex index() {
    try {
      return LocalIndex.open(home.indexPath);
      // Ошибку загрузки нативной библиотеки FFI бросает как ArgumentError.
      // ignore: avoid_catching_errors
    } on ArgumentError catch (e) {
      throw CliException('не загружается SQLite: ${_nativeHint('$e')}');
    }
  }

  final Random random = Random.secure();
}

/// Команда CLI: справка печатается в [Console], а не через `print`.
abstract class CliCommand extends Command<int> {
  new(this.ctx);

  final CliContext ctx;

  @override
  void printUsage() => ctx.console.out(usage);
}

/// Короткое объяснение ошибки загрузки нативной библиотеки.
String _nativeHint(String error) {
  final glibc = RegExp("version `(GLIBC_[0-9.]+)' not found").firstMatch(error);
  if (glibc != null) {
    return 'в системе слишком старая glibc, нужна ${glibc[1]} или новее '
        '(минимум для сборки — GLIBC_2.34, docs/cli.md)';
  }
  final line = error.split('\n').first;
  return line.length > 200 ? '${line.substring(0, 200)}…' : line;
}
