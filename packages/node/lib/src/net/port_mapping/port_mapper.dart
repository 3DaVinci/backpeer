import 'dart:async';
import 'dart:math';

import 'package:daemon_kit/daemon_kit.dart';
import 'package:logging/logging.dart';
import 'package:node/src/net/port_mapping/local_network.dart';
import 'package:node/src/net/port_mapping/pcp.dart';
import 'package:node/src/net/port_mapping/port_mapping.dart';
import 'package:node/src/net/port_mapping/upnp.dart';

/// Способ проброса порта (`listen.port_mapping`).
enum PortMappingMode {
  /// UPnP, затем PCP или NAT-PMP.
  auto,
  upnp,

  /// PCP с откатом на NAT-PMP.
  pcp,
  off,
}

/// Проброс порта приёма на роутере (задача 3.5.2): получает проброс
/// первым сработавшим протоколом, продлевает аренду на половине срока,
/// после неудачи пробует снова через [retryInterval], при остановке
/// снимает проброс. Изменение проброса — [onChange] (повторная проверка
/// достижимости).
///
/// Внешний порт — сначала равный порту приёма; занят другим устройством
/// — случайный из 20000–60000, до [maxConflictRetries] попыток.
final class PortMapper {
  new({
    required this.internalPort,
    required this._protocols,
    this.lifetime = const Duration(hours: 1),
    this.retryInterval = const Duration(minutes: 10),
    this.refreshPermanent = const Duration(minutes: 30),
    this.minRenewInterval = const Duration(seconds: 30),
    this.onChange,
    Random? random,
  }) : _random = random ?? Random();

  /// Протоколы для режима [mode].
  static List<PortMappingProtocol> protocolsFor(PortMappingMode mode) =>
      switch (mode) {
        PortMappingMode.auto => [UpnpClient(), PcpClient()],
        PortMappingMode.upnp => [UpnpClient()],
        PortMappingMode.pcp => [PcpClient()],
        PortMappingMode.off => const [],
      };

  final int internalPort;
  final Duration lifetime;
  final Duration retryInterval;

  /// Как часто подтверждать бессрочный проброс UPnP: роутер мог
  /// перезагрузиться и забыть его.
  final Duration refreshPermanent;

  /// Продлевать не чаще: роутер мог дать очень короткую аренду.
  final Duration minRenewInterval;
  final void Function()? onChange;
  final List<PortMappingProtocol> _protocols;
  final Random _random;

  static const maxConflictRetries = 3;

  static final _log = Logger('port_mapping');

  PortMapping? _current;
  PortMappingProtocol? _protocol;
  String? _lastError;
  DateTime? _nextAttempt;
  Timer? _timer;
  Future<void>? _running;
  bool _stopped = false;

  /// Действующий проброс или `null`.
  PortMapping? get current => _current;

  /// Внешний порт действующего проброса.
  int? get externalPort => _current?.externalPort;

  /// Запускает первую попытку; дальше — по таймеру.
  void start() {
    if (_protocols.isEmpty) return;
    _schedule(Duration.zero);
  }

  /// Одна попытка получить или продлить проброс (для тестов — ждать её).
  Future<void> refresh() =>
      _running ??= _refresh().whenComplete(() => _running = null);

  void _schedule(Duration after) {
    _timer?.cancel();
    if (_stopped) return;
    _nextAttempt = DateTime.now().add(after);
    _timer = Timer(after, () => unawaited(refresh()));
  }

  Future<void> _refresh() async {
    if (_stopped) return;
    final before = _current;
    final protocols = [?_protocol, ..._protocols.where((p) => p != _protocol)];
    final errors = <String>[];
    for (final protocol in protocols) {
      try {
        final mapping = await _mapWith(protocol, before);
        if (_stopped) {
          await _unmapQuietly(protocol, mapping);
          return;
        }
        _current = mapping;
        _protocol = protocol;
        _lastError = null;
        final changed =
            before == null ||
            before.externalPort != mapping.externalPort ||
            before.method != mapping.method;
        if (changed) {
          _log.info(LogEvent('port_mapped', mapping.toJson()));
          if (mapping.externalAddress case final ip?
              when LocalNetwork.isPrivateV4(ip)) {
            _log.warning(
              LogEvent('port_mapping_double_nat', {'external': ip.address}),
            );
          }
          onChange?.call();
        } else {
          _log.fine(LogEvent('port_mapping_renewed', mapping.toJson()));
        }
        final renew = mapping.lifetime == Duration.zero
            ? refreshPermanent
            : mapping.lifetime ~/ 2;
        _schedule(renew < minRenewInterval ? minRenewInterval : renew);
        return;
      } on PortMappingException catch (e) {
        errors.add('${protocol.name}: ${e.message}');
        if (protocol == _protocol) _protocol = null;
      }
    }
    _lastError = errors.join('; ');
    if (before != null) {
      _current = null;
      _log.warning(LogEvent('port_mapping_lost', {'errors': errors}));
      onChange?.call();
    } else {
      _log.info(LogEvent('port_mapping_unavailable', {'errors': errors}));
    }
    _schedule(retryInterval);
  }

  /// Проброс протоколом [protocol]: тот же внешний порт, что был, иначе
  /// порт приёма; конфликт — случайный порт.
  Future<PortMapping> _mapWith(
    PortMappingProtocol protocol,
    PortMapping? before,
  ) async {
    var external = before?.externalPort ?? internalPort;
    for (var attempt = 0; ; attempt++) {
      try {
        return await protocol.map(
          internalPort: internalPort,
          externalPort: external,
          lifetime: lifetime,
        );
      } on PortMappingException catch (e) {
        if (!e.conflict || attempt >= maxConflictRetries) rethrow;
        external = 20000 + _random.nextInt(40000);
      }
    }
  }

  /// Снимает проброс (не дольше [wait]) и закрывает протоколы.
  Future<void> stop({Duration wait = const Duration(seconds: 3)}) async {
    _stopped = true;
    _timer?.cancel();
    try {
      await _running?.timeout(wait);
    } on TimeoutException {
      // Снимем то, что есть.
    }
    final mapping = _current;
    final protocol = _protocol;
    if (mapping != null && protocol != null) {
      await _unmapQuietly(protocol, mapping, wait: wait);
    }
    _current = null;
    for (final p in _protocols) {
      p.close();
    }
  }

  Future<void> _unmapQuietly(
    PortMappingProtocol protocol,
    PortMapping mapping, {
    Duration wait = const Duration(seconds: 3),
  }) async {
    try {
      await protocol.unmap(mapping).timeout(wait);
      _log.info(LogEvent('port_unmapped', mapping.toJson()));
    } on Object catch (e) {
      // Аренда со сроком истечёт сама.
      _log.warning(LogEvent('port_unmap_failed', {'error': '$e'}));
    }
  }

  Map<String, Object?> toJson() => {
    'enabled': _protocols.isNotEmpty,
    'mapping': _current?.toJson(),
    'lastError': _lastError,
    'nextAttemptAt': _nextAttempt?.toUtc().toIso8601String(),
  };
}
