/// Версия продукта. Подставляется при сборке:
/// `dart compile exe -DAPP_VERSION=0.1.0 ...` (см. `tool/build_exe.dart`).
const appVersion = String.fromEnvironment('APP_VERSION', defaultValue: 'dev');

/// Короткий хэш коммита, из которого собран бинарник.
const gitCommit = String.fromEnvironment('GIT_COMMIT', defaultValue: 'unknown');

/// Строка для `--version`, например `cli 0.1.0 (abc1234)`.
String versionLine(String program) => '$program $appVersion ($gitCommit)';
