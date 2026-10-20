import 'dart:io';

import 'package:core/core.dart';

void main(List<String> arguments) {
  if (arguments.contains('--version')) {
    stdout.writeln(versionLine('node'));
    return;
  }
  stdout.writeln('node: not implemented yet');
}
