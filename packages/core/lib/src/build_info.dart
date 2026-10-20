import 'package:core/src/build_info_values.dart';

/// Версия продукта. Подставляется при сборке (см. `tool/build_exe.dart`).
const String appVersion = buildAppVersion;

/// Короткий хэш коммита, из которого собран бинарник.
const String gitCommit = buildGitCommit;

/// Строка для `--version`, например `cli 0.1.0 (abc1234)`.
String versionLine(String program) => '$program $appVersion ($gitCommit)';
