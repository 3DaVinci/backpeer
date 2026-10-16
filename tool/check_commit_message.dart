// Проверяет, что сообщение коммита соответствует Conventional Commits
// (см. CONTRIBUTING.md). Вызывается из хука commit-msg (lefthook):
//
//   dart run tool/check_commit_message.dart .git/COMMIT_EDITMSG

import 'dart:io';

const types = [
  'feat',
  'fix',
  'perf',
  'refactor',
  'test',
  'docs',
  'build',
  'ci',
  'chore',
  'style',
  'revert',
];

final _header = RegExp(
  '^(${types.join('|')})' // тип
  r'(\([a-z0-9][a-z0-9_\-]*(,[a-z0-9][a-z0-9_\-]*)*\))?' // (область)
  '!?: ' // признак несовместимого изменения
  r'\S.*$', // описание
);

/// Сообщения, которые git и melos создают сами.
final _generated = RegExp('^(Merge |Revert "|fixup! |squash! |amend! )');

void main(List<String> arguments) {
  if (arguments.length != 1) {
    stderr.writeln('Использование: check_commit_message.dart <файл сообщения>');
    exit(2);
  }
  final header = File(arguments.single)
      .readAsLinesSync()
      .firstWhere((line) => !line.startsWith('#'), orElse: () => '')
      .trimRight();

  if (_generated.hasMatch(header)) return;
  if (_header.hasMatch(header) && header.length <= 100) return;

  stderr
    ..writeln('Сообщение коммита не соответствует Conventional Commits:')
    ..writeln('  $header')
    ..writeln()
    ..writeln('Формат: <тип>(<область>): <описание>, не длиннее 100 символов.')
    ..writeln('Типы: ${types.join(', ')}.')
    ..writeln('Пример: feat(core): шифрование сегментов XChaCha20-Poly1305')
    ..writeln('Подробности в CONTRIBUTING.md.');
  exit(1);
}
