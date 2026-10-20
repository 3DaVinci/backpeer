// Генерирует Dart-код из packages/protocol/proto/ (задача 0.3.5).
//
//   dart run tool/generate_proto.dart
//
// Нужны protoc (github.com/protocolbuffers/protobuf/releases) в PATH или
// в переменной PROTOC и плагин: `dart pub global activate protoc_plugin`.
// Сгенерированные файлы коммитятся: сборка и CI не требуют protoc.

import 'dart:io';

const protoRoot = 'packages/protocol/proto';
const outDir = 'packages/protocol/lib/src/generated';

void main() {
  final protoc = Platform.environment['PROTOC'] ?? 'protoc';
  final home =
      Platform.environment['HOME'] ?? Platform.environment['LOCALAPPDATA']!;
  final pubCache =
      Platform.environment['PUB_CACHE'] ??
      (Platform.isWindows ? '$home\\Pub\\Cache' : '$home/.pub-cache');
  final plugin = Platform.isWindows
      ? '$pubCache\\bin\\protoc-gen-dart.bat'
      : '$pubCache/bin/protoc-gen-dart';

  final protos =
      Directory(protoRoot)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.proto'))
          .map((f) => f.path.substring(protoRoot.length + 1))
          .toList()
        ..sort();

  final out = Directory(outDir);
  if (out.existsSync()) out.deleteSync(recursive: true);
  out.createSync(recursive: true);

  // Плагин запускается через `dart` из PATH; подставляем тот Dart, которым
  // запущен этот скрипт (версия из .fvmrc), иначе снимок плагина не загрузится.
  final dartDir = File(Platform.resolvedExecutable).parent.path;
  final separator = Platform.isWindows ? ';' : ':';
  final result = Process.runSync(
    protoc,
    [
      '--plugin=protoc-gen-dart=$plugin',
      '--dart_out=$outDir',
      '-I',
      protoRoot,
      ...protos,
    ],
    environment: {
      'PATH': '$dartDir$separator${Platform.environment['PATH'] ?? ''}',
    },
  );
  stdout.write(result.stdout);
  stderr.write(result.stderr);
  if (result.exitCode != 0) exit(result.exitCode);

  final format = Process.runSync(Platform.resolvedExecutable, [
    'format',
    outDir,
  ]);
  if (format.exitCode != 0) {
    stderr.write(format.stderr);
    exit(format.exitCode);
  }
  stdout.writeln('Сгенерировано из ${protos.length} файлов в $outDir');
}
