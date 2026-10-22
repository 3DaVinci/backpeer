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
  /// восстановлена.
  static const int partial = 3;
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
  new({required this.console, required this.env, required this.home});

  final Console console;
  final Map<String, String> env;
  final AppHome home;

  CryptoProvider? _crypto;

  /// libsodium; если не загрузилась — запасная реализация на Dart.
  Future<CryptoProvider> crypto() async {
    if (_crypto case final c?) return c;
    try {
      return _crypto = await SodiumCryptoProvider.load();
    } on Object catch (e) {
      console.err('libsodium недоступна ($e), работаю медленнее, на Dart');
      return _crypto = DartCryptoProvider();
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
      console.out(
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

  LocalIndex index() => LocalIndex.open(home.indexPath);

  final Random random = Random.secure();
}

/// Команда CLI: справка печатается в [Console], а не через `print`.
abstract class CliCommand extends Command<int> {
  new(this.ctx);

  final CliContext ctx;

  @override
  void printUsage() => ctx.console.out(usage);
}
