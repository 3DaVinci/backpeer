import 'dart:math' as math;

/// Что известно координатору об узле для репутации.
final class ReputationInput {
  const new({
    required this.availability,
    required this.age,
    this.auditsPassed = 0,
    this.auditsFailed = 0,
    this.recentFailures = 0,
    this.auditLatency,
  });

  /// Доступность за 30 дней (`Uptime`), 0–1.
  final double availability;

  /// Сколько прошло с регистрации узла.
  final Duration age;

  /// Пройденные и проваленные аудиты за всё время (`nodes.audits_*`).
  final int auditsPassed;
  final int auditsFailed;

  /// Провалов среди последних `audits.window` аудитов
  /// (`nodes.audit_window_failures`).
  final int recentFailures;

  /// Сглаженное время ответа на пройденные аудиты (`nodes.audit_latency_ms`);
  /// `null` — ответов ещё не было.
  final Duration? auditLatency;
}

/// Репутация узла (задача 4.2.1; `docs/spec/reputation.md`):
/// произведение четырёх множителей от 0 до 1,
///
///     R = A² · P⁴ · G · L,
///
/// где A — доступность, P — доля пройденных аудитов: меньшая из доли за
/// всё время со сглаживанием [auditPrior] условными успехами и доли в
/// окне [recentWindow] последних аудитов (свежие провалы старого узла не
/// тонут в его истории), G — возраст (от [minAgeFactor] при
/// регистрации до 1 через [matureAge]), L — скорость ответов (1 до
/// [fastLatency], дальше обратно пропорционально, не ниже
/// [minLatencyFactor]). У старого узла без провалов и с быстрыми ответами
/// R = A² — прежний вес размещения этапа 2.
///
/// Репутация — вес узла при размещении (`Placement`) и порог: узел с
/// репутацией ниже `PlacementPolicy.minReputation` новых фрагментов не
/// получает.
abstract final class Reputation {
  /// Условных пройденных аудитов у нового узла: одиночный провал
  /// (например, таймаут из-за перегруженного канала) не обнуляет его вес.
  static const int auditPrior = 10;

  /// Окно последних аудитов: доля в нём — `1 − провалы / 20`, у нового
  /// узла с меньшим числом аудитов недостающие считаются пройденными.
  static const int recentWindow = 20;

  /// Степень доли пройденных аудитов: 5 % провалов — вес × 0,81, 15 %
  /// (3 из 20, на шаг до исключения) — × 0,52.
  static const int auditExponent = 4;

  static const double minAgeFactor = 0.25;
  static const Duration matureAge = Duration(days: 30);

  static const Duration fastLatency = Duration(seconds: 2);
  static const double minLatencyFactor = 0.25;

  /// Множитель доступности A².
  static double availabilityFactor(ReputationInput node) {
    final a = node.availability.clamp(0.0, 1.0);
    return a * a;
  }

  /// Множитель аудитов P⁴, P = min((пройдено + 10) / (всего + 10),
  /// 1 − провалы в окне / 20).
  static double auditFactor(ReputationInput node) {
    final passed = math.max(0, node.auditsPassed);
    final failed = math.max(0, node.auditsFailed);
    final lifetime = (passed + auditPrior) / (passed + failed + auditPrior);
    final recent =
        1 - node.recentFailures.clamp(0, recentWindow) / recentWindow;
    return math.pow(math.min(lifetime, recent), auditExponent).toDouble();
  }

  /// Множитель возраста G: линейно от [minAgeFactor] до 1 за [matureAge].
  static double ageFactor(ReputationInput node) {
    final share = (node.age.inSeconds / matureAge.inSeconds).clamp(0.0, 1.0);
    return minAgeFactor + (1 - minAgeFactor) * share;
  }

  /// Множитель скорости L = min(1, 2 с / время ответа), не ниже
  /// [minLatencyFactor].
  static double latencyFactor(ReputationInput node) {
    final latency = node.auditLatency;
    if (latency == null || latency <= fastLatency) return 1;
    return math.max(
      minLatencyFactor,
      fastLatency.inMicroseconds / latency.inMicroseconds,
    );
  }

  static double of(ReputationInput node) =>
      availabilityFactor(node) *
      auditFactor(node) *
      ageFactor(node) *
      latencyFactor(node);

  /// Доля нового времени ответа в сглаженном: `новое = 0,8 · старое +
  /// 0,2 · ответ` — около десятка последних аудитов; считает
  /// `AuditService` в базе.
  static const double latencySmoothing = 0.2;
}
