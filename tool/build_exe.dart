// Собирает `cli`, `node` и `agent` через `dart build cli` (задачи 0.2.2,
// 5.1.3).
// Работает одинаково локально и в CI на всех ОС.
//
//   dart run tool/build_exe.dart                      # под текущую платформу
//   dart run tool/build_exe.dart linux arm64          # кросс-компиляция
//
// `dart compile exe` не подходит: он не поддерживает build hooks, а через
// них подключаются нативные библиотеки (libsodium, SQLite). Результат —
// папка, а не одиночный файл:
//
//   build/bin/<os>-<arch>/<программа>/bundle/bin/<программа>[.exe]
//   build/bin/<os>-<arch>/<программа>/bundle/lib/<библиотеки>
//
// Кросс-компиляция поддерживается только для Linux. Build hook пакета
// sodium при кросс-сборке молча собирает libsodium под архитектуру хоста
// (замеры 0.5, docs/benchmarks.md), поэтому для Linux скрипт проверяет
// архитектуру каждого ELF-файла в сборке и падает при несовпадении.
//
// Версия продукта и хэш коммита встраиваются в бинарник через файл
// packages/core/lib/src/build_info_values.dart: `dart build cli` не
// поддерживает `--define`, поэтому скрипт на время сборки записывает
// значения в этот файл и затем возвращает исходное содержимое.

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

const programs = ['cli', 'node', 'agent'];

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
  final root = Directory.current.absolute.path;

  final values = File('packages/core/lib/src/build_info_values.dart');
  final original = values.readAsStringSync();
  values.writeAsStringSync(
    original
        .replaceFirst("buildAppVersion = 'dev'", "buildAppVersion = '$version'")
        .replaceFirst(
          "buildGitCommit = 'unknown'",
          "buildGitCommit = '$commit'",
        ),
  );
  try {
    for (final program in programs) {
      _build(program, os, arch, cross: cross, root: root);
      stdout.writeln('Собрано: $program ($version, $commit)');
    }
  } on Exception catch (e) {
    stderr.writeln(e);
    exitCode = 1;
  } finally {
    values.writeAsStringSync(original);
  }
}

void _build(
  String program,
  String os,
  String arch, {
  required bool cross,
  required String root,
}) {
  final output = '$root/build/bin/$os-$arch/$program';
  final outputDir = Directory(output);
  if (outputDir.existsSync()) outputDir.deleteSync(recursive: true);
  final result = Process.runSync(Platform.resolvedExecutable, [
    'build',
    'cli',
    if (cross) ...['--target-os=$os', '--target-arch=$arch'],
    '-t',
    'bin/$program.dart',
    '-o',
    output,
  ], workingDirectory: 'packages/$program');
  if (result.exitCode != 0) {
    throw ProcessException(
      'dart',
      ['build', 'cli'],
      'Сборка $program не удалась:\n${result.stdout}${result.stderr}',
      result.exitCode,
    );
  }
  if (os == 'linux') _checkElfArch(Directory('$output/bundle'), arch);
}

/// Проверяет, что все ELF-файлы сборки собраны под [arch].
void _checkElfArch(Directory bundle, String arch) {
  const machines = {'x64': 62, 'arm64': 183};
  final expected = machines[arch];
  if (expected == null) return;
  final wrong = <String>[];
  for (final file in bundle.listSync(recursive: true).whereType<File>()) {
    final handle = file.openSync();
    final bytes = handle.readSync(20);
    handle.closeSync();
    final isElf =
        bytes.length == 20 &&
        bytes[0] == 0x7F &&
        bytes[1] == 0x45 && // E
        bytes[2] == 0x4C && // L
        bytes[3] == 0x46; // F
    if (!isElf) continue;
    final machine = ByteData.sublistView(bytes).getUint16(18, Endian.little);
    if (machine != expected) wrong.add('${file.path} (e_machine=$machine)');
  }
  if (wrong.isNotEmpty) {
    // Исключение, а не exit(): main должен вернуть build_info_values.dart.
    throw _BuildException(
      'Файлы собраны не под $arch:\n${wrong.map((w) => '  $w').join('\n')}',
    );
  }
}

class _BuildException implements Exception {
  new(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Архитектура текущей машины в терминах `--target-arch`.
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
