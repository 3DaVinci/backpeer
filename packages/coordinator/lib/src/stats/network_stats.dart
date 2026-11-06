import 'package:coordinator/src/db/database.dart';
import 'package:postgres/postgres.dart';

/// Настройки публичной сводки о сети для сайта (задача С.3.5).
///
/// Сводка — только числа и города, без узлов и учётных записей: на сайте её
/// читает браузер посетителя, поэтому она открыта без подписи. Читателей
/// ограничивает список источников [allowedOrigins]: без него браузер не
/// получит ответ (CORS), а прямой запрос всё равно полезен для проверок.
final class StatsPolicy {
  const new({
    this.enabled = true,
    this.allowedOrigins = const [],
    this.perMinute = 60,
    this.maxAge = const Duration(seconds: 60),
    this.minCityHosts = 1,
  });

  /// Выключенная сводка отвечает `404`, как неизвестный метод.
  final bool enabled;

  /// Источники, которым браузер разрешает читать сводку: точные адреса
  /// вида `https://backpeer.example` без завершающего «/».
  final List<String> allowedOrigins;

  /// Предел запросов сводки с одного IP в минуту.
  final int perMinute;

  /// Сколько браузер может держать ответ в кеше.
  final Duration maxAge;

  /// Города, где меньше [minCityHosts] доступных узлов, на карту не
  /// попадают.
  final int minCityHosts;

  bool allows(String origin) => allowedOrigins.contains(origin);
}

/// Публичная сводка о сети: сколько узлов на связи, сколько у них места,
/// сколько данных хранится и где узлы (geoip).
///
/// Все числа — только сводные. Список узлов, их адреса и учётные записи
/// наружу не отдаются: сайт показывает общую картину (модель угроз, К-2).
final class NetworkStatsService {
  new(
    this._db, {
    required this.onlineWindow,
    this.policy = const StatsPolicy(),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Database _db;
  final StatsPolicy policy;

  /// Узел в сети, если heartbeat не старше этого срока (`NodePolicy`).
  final Duration onlineWindow;

  final DateTime Function() _clock;

  Map<String, Object?>? _cached;
  DateTime? _cachedAt;

  /// Сводка по сети. Ответ кешируется на [StatsPolicy.maxAge]: сайт
  /// опрашивает её раз в минуту, и каждый посетитель не должен стоить
  /// запроса к базе.
  Future<Map<String, Object?>> snapshot() async {
    final now = _clock();
    final cached = _cached;
    final cachedAt = _cachedAt;
    if (cached != null &&
        cachedAt != null &&
        now.difference(cachedAt) < policy.maxAge) {
      return cached;
    }
    final fresh = await _compute(now);
    _cached = fresh;
    _cachedAt = now;
    return fresh;
  }

  Future<Map<String, Object?>> _compute(DateTime now) => _db.run((s) async {
    final online = now.subtract(onlineWindow);
    final [
      known as int,
      available as int,
      capacity as int,
      used as int,
      free as int,
    ] = (await s.execute(
      Sql.named('''
        SELECT count(*),
               count(*) FILTER (
                 WHERE last_heartbeat_at >= @o:timestamptz
                   AND excluded_at IS NULL
                   AND leaving_at IS NULL),
               coalesce(sum(capacity_bytes) FILTER (
                 WHERE last_heartbeat_at >= @o:timestamptz
                   AND excluded_at IS NULL
                   AND leaving_at IS NULL), 0)::int8,
               coalesce(sum(used_bytes) FILTER (
                 WHERE last_heartbeat_at >= @o:timestamptz
                   AND excluded_at IS NULL
                   AND leaving_at IS NULL), 0)::int8,
               coalesce(sum(
                 coalesce(free_bytes, capacity_bytes - used_bytes)) FILTER (
                 WHERE last_heartbeat_at >= @o:timestamptz
                   AND excluded_at IS NULL
                   AND leaving_at IS NULL
                   AND capacity_bytes >= used_bytes), 0)::int8
          FROM nodes WHERE removed_at IS NULL'''),
      parameters: {'o': online},
    )).single;
    final [stored as int] = (await s.execute(
      'SELECT coalesce(sum(object_bytes), 0)::int8 FROM accounts',
    )).single;
    final countries = await s.execute(
      Sql.named('''
        SELECT country, count(*)::int8 FROM nodes
          WHERE removed_at IS NULL AND excluded_at IS NULL
            AND leaving_at IS NULL
            AND last_heartbeat_at >= @o:timestamptz
            AND country IS NOT NULL
          GROUP BY country ORDER BY country'''),
      parameters: {'o': online},
    );
    final cities = await s.execute(
      Sql.named('''
        SELECT country, city, round(avg(latitude)::numeric, 2)::float8,
               round(avg(longitude)::numeric, 2)::float8, count(*)::int8
          FROM nodes
          WHERE removed_at IS NULL AND excluded_at IS NULL
            AND leaving_at IS NULL
            AND last_heartbeat_at >= @o:timestamptz
            AND country IS NOT NULL AND city IS NOT NULL
            AND latitude IS NOT NULL AND longitude IS NOT NULL
          GROUP BY country, city HAVING count(*) >= @min:int
          ORDER BY country, city'''),
      parameters: {'o': online, 'min': policy.minCityHosts},
    );
    return {
      'schema': 1,
      'updatedAt': now.toUtc().toIso8601String(),
      'hosts': {'available': available, 'known': known},
      'space': {'freeBytes': free, 'capacityBytes': capacity},
      'data': {'storedBytes': stored, 'fragmentBytes': used},
      'countries': [
        for (final [code as String, nodes as int] in countries)
          {'code': code, 'hosts': nodes},
      ],
      'cities': [
        for (final [
              code as String,
              city as String,
              lat as double,
              lon as double,
              nodes as int,
            ]
            in cities)
          {
            'country': code,
            'city': city,
            'latitude': lat,
            'longitude': lon,
            'hosts': nodes,
          },
      ],
    };
  });
}
