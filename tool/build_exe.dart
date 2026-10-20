// Собирает исполняемые файлы `cli` и `node` через `dart compile exe`
// (задача 0.2.2). Работает одинаково локально и в CI на всех ОС.
//
//   dart run tool/build_exe.dart                      # под текущую платформу
//   dart run tool/build_exe.dart linux arm64          # кросс-компиляция
//
// Кросс-компиляция поддерживается только для Linux (x64, arm64) с хостов
// Linux и macOS. Под Windows и macOS собирают на соответствующей ОС.
//
// Результат: build/bin/<os>-<arch>/<программа>[.exe]. В бинарник
// встраиваются версия продукта и хэш коммита (см. `core/build_info.dart`).

import 'dart:ffi';
import 'dart:io';

const programs = ['cli', 'node'];

void main(List<String> arguments) {
  if (arguments.isNotEmpty && arguments.length != 2) {
    stderr.writeln('Использование: build_exe.dart [<os> <arch>]');
    exit(2);
  }
  final hostOs = Platform.operatingSystem;
  final hostArch = _hostArch();
  final os = arguments.isEmpty ? hostOs : arguments[0];
  final arch = arguments.isEmpty ? hostArch : arguments[1];
  final cross = os != hostOs || arch != hostArch;

  final version = _productVersion();
  final commit = _gitCommit();
  final outDir = Directory('build/bin/$os-$arch')..createSync(recursive: true);
  final suffix = os == 'windows' ? '.exe' : '';

  for (final program in programs) {
    final output = '${outDir.path}/$program$suffix';
    stdout.writeln('Сборка $output ($version, $commit)');
    final result = Process.runSync(Platform.resolvedExecutable, [
      'compile',
      'exe',
      if (cross) ...['--target-os=$os', '--target-arch=$arch'],
      '-DAPP_VERSION=$version',
      '-DGIT_COMMIT=$commit',
      'packages/$program/bin/$program.dart',
      '-o',
      output,
    ]);
    stdout.write(result.stdout);
    stderr.write(result.stderr);
    if (result.exitCode != 0) exit(result.exitCode);
  }
}

/// Архитектура текущей машины в терминах `dart compile exe --target-arch`.
String _hostArch() => switch (Abi.current()) {
  Abi.linuxArm64 || Abi.macosArm64 || Abi.windowsArm64 => 'arm64',
  Abi.linuxX64 || Abi.macosX64 || Abi.windowsX64 => 'x64',
  final abi => throw UnsupportedError('Неподдерживаемая платформа: $abi'),
};

/// Версия продукта. Версии всех пакетов совпадают (см. CONTRIBUTING.md),
/// поэтому берём её из pubspec.yaml пакета `cli`.
String _productVersion() {
  final pubspec = File('packages/cli/pubspec.yaml').readAsStringSync();
  final match = RegExp(
    r'^version:\s*(\S+)',
    multiLine: true,
  ).firstMatch(pubspec);
  if (match == null) {
    throw StateError('В packages/cli/pubspec.yaml нет version');
  }
  return match.group(1)!;
}

String _gitCommit() {
  final fromCi = Platform.environment['CI_COMMIT_SHORT_SHA'];
  if (fromCi != null && fromCi.isNotEmpty) return fromCi;
  final result = Process.runSync('git', ['rev-parse', '--short', 'HEAD']);
  return result.exitCode == 0 ? (result.stdout as String).trim() : 'unknown';
}
