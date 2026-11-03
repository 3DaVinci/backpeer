/// Совместимость версий при обновлении (docs/spec/updates.md, раздел 7).
library;

/// Версия локального API «приложение ↔ фоновые процессы» (agent, node). Оба
/// сообщают её в `status`; при расхождении приложение показывает «требуется
/// перезапуск» и не вызывает методы новой версии. Меняется, когда меняется
/// формат или набор методов локального API.
const int daemonApiVersion = 1;

/// Совместимы ли приложение (ожидаемая [daemonApiVersion]) и фоновый
/// процесс ([daemonApiVersion] из его `status`).
bool daemonCompatible(int expected, int actual) => expected == actual;
