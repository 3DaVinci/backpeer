/// Relay — ретранслятор соединений к узлам без входящих соединений
/// (задача 3.8; protocol.md, раздел 4.12). Без Flutter.
///
/// Протокол relay со стороны клиента и узла — в `core` (`net/relay/`);
/// здесь — сервер, его настройки и отчёты координатору.
library;

export 'src/config.dart';
export 'src/log.dart';
export 'src/relay_reporter.dart';
export 'src/relay_server.dart';
