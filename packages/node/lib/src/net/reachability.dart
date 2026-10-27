import 'dart:io';

import 'package:core/core.dart';
import 'package:logging/logging.dart';
import 'package:node/src/daemon/log.dart';
import 'package:protocol/protocol.dart' as pb;

/// Доступен ли узел извне и какие адреса он сообщает координатору
/// (задача 3.5.1).
///
/// Координатор по запросу `CheckReachability` подключается к адресу, с
/// которого пришёл запрос, на порт приёма и внешний порт проброса
/// ([ports]) и проверяет, что отвечает этот узел. Адреса узла
/// ([endpoints]) — заданные владельцем (`listen.endpoints`) и найденный
/// адрес `внешний IP:порт` для каждого достижимого порта.
///
/// Проверка повторяется через [interval], после ошибки — через
/// [retryAfterError], а при смене портов (проброс получен или снят) —
/// сразу ([invalidate]).
final class Reachability {
  new({
    required this.manualEndpoints,
    required this.ports,
    this.interval = const Duration(minutes: 30),
    this.retryAfterError = const Duration(minutes: 5),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// Адреса из настроек: сообщаются всегда, их координатор не проверяет.
  final List<String> manualEndpoints;

  /// Порты для проверки сейчас: порт приёма и внешний порт проброса.
  final List<int> Function() ports;
  final Duration interval;
  final Duration retryAfterError;
  final DateTime Function() _clock;

  static final _log = Logger('reachability');

  /// Адресов в `endpoints` не больше (protocol.md, раздел 4.9).
  static const maxEndpoints = 8;

  String? _observed;
  Map<int, pb.ReachabilityStatus> _results = const {};
  DateTime? _checkedAt;
  DateTime? _nextCheck;
  String? _lastError;
  List<int> _checkedPorts = const [];

  /// Внешний адрес узла, каким его видит координатор.
  String? get observedAddress => _observed;

  /// Проверка уже была (успешная).
  bool get checked => _checkedAt != null;

  /// Хотя бы один порт отвечает извне.
  bool get reachable => _results.values.any(_ok);

  /// Порт, проверенный как достижимый, или `null`.
  int? get reachablePort => [
    for (final MapEntry(:key, :value) in _results.entries)
      if (_ok(value)) key,
  ].firstOrNull;

  /// Пора ли проверять: проверки ещё не было, прошёл интервал или порты
  /// изменились.
  bool get due {
    final next = _nextCheck;
    return next == null ||
        !_clock().isBefore(next) ||
        !_sameList(ports(), _checkedPorts);
  }

  /// Проверить при следующей возможности.
  void invalidate() => _nextCheck = null;

  /// Адреса для `RegisterNode` и `Heartbeat`: заданные владельцем, затем
  /// найденные; без повторов, не больше [maxEndpoints].
  List<String> get endpoints {
    final out = <String>[...manualEndpoints];
    if (_observed case final ip?) {
      for (final MapEntry(:key, :value) in _results.entries) {
        if (_ok(value)) out.add(hostPort(ip, key));
      }
    }
    return out.toSet().take(maxEndpoints).toList();
  }

  /// Спрашивает координатора; возвращает, изменились ли [endpoints].
  /// Ошибка координатора не бросается: она в журнале и в [toJson],
  /// повтор — через [retryAfterError].
  Future<bool> check(CoordinatorClient client, Ed25519KeyPair nodeKey) async {
    final before = endpoints;
    final wanted = ports().toSet().take(4).toList();
    final now = _clock();
    if (wanted.isEmpty) {
      _results = const {};
      _checkedPorts = const [];
      _nextCheck = now.add(interval);
      return !_sameList(before, endpoints);
    }
    try {
      final response = await client.checkReachability(
        pb.CheckReachabilityRequest(ports: wanted),
        nodeKey: nodeKey,
      );
      final wasReachable = reachable;
      _observed = response.observedAddress.isEmpty
          ? null
          : response.observedAddress;
      _results = {for (final r in response.results) r.port: r.status};
      _checkedPorts = wanted;
      _checkedAt = now;
      _nextCheck = now.add(interval);
      _lastError = null;
      final event = LogEvent('reachability', {
        'observed': _observed,
        'ports': {
          for (final MapEntry(:key, :value) in _results.entries)
            '$key': statusName(value),
        },
      });
      if (reachable != wasReachable || !_sameList(before, endpoints)) {
        _log.info(event);
      } else {
        _log.fine(event);
      }
    } on CoordinatorException catch (e) {
      _lastError = '${e.code.name}: ${e.detail}';
      _checkedPorts = wanted;
      _nextCheck = now.add(retryAfterError);
      _log.warning(
        LogEvent('reachability_check_failed', {
          'code': e.code.name,
          'http_status': e.httpStatus,
        }),
      );
    }
    return !_sameList(before, endpoints);
  }

  Map<String, Object?> toJson() => {
    'reachable': reachable,
    'observedAddress': _observed,
    'checkedAt': _checkedAt?.toUtc().toIso8601String(),
    'ports': {
      for (final MapEntry(:key, :value) in _results.entries)
        '$key': statusName(value),
    },
    'endpoints': endpoints,
    'lastError': _lastError,
  };

  /// `reachable`, `refused`, `timeout`, `wrong_peer`, `not_checked`.
  static String statusName(pb.ReachabilityStatus s) =>
      s.name.replaceFirst('REACHABILITY_STATUS_', '').toLowerCase();

  /// `хост:порт`, IPv6 — в квадратных скобках.
  static String hostPort(String host, int port) {
    final ip = InternetAddress.tryParse(host);
    return ip?.type == InternetAddressType.IPv6
        ? '[$host]:$port'
        : '$host:$port';
  }

  static bool _ok(pb.ReachabilityStatus s) =>
      s == pb.ReachabilityStatus.REACHABILITY_STATUS_REACHABLE;

  static bool _sameList<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
