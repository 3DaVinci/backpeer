import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  test('versionLine без параметров сборки', () {
    expect(versionLine('cli'), 'cli dev (unknown)');
  });
}
