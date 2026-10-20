import 'dart:io';

import 'package:core/core.dart';

void main(List<String> arguments) {
  if (arguments.contains('--version')) {
    stdout.writeln(versionLine('cli'));
    return;
  }
  stdout.writeln('cli: not implemented yet');
}
