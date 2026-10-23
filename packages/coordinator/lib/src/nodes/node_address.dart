import 'dart:io';
import 'dart:typed_data';

/// Адреса узла (protocol.md, раздел 4.9).
abstract final class NodeAddresses {
  /// Адресов в `endpoints` не больше.
  static const maxEndpoints = 8;

  static const _maxEndpointLength = 261; // имя 253 + ":" + порт + []

  static final _hostname = RegExp(
    r'^(?=.{1,253}$)[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?'
    r'(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)*$',
    caseSensitive: false,
  );

  /// Подсеть, в которой узлы считаются одним местом для разнообразия
  /// размещения: IPv4 — /24, IPv6 — /48 (обычный размер сети одного
  /// абонента). IPv4, отображённый в IPv6 (`::ffff:a.b.c.d`), — как IPv4.
  /// Адрес не разбирается — `null`.
  static String? subnetOf(String address) {
    final ip = InternetAddress.tryParse(address);
    if (ip == null) return null;
    var raw = ip.rawAddress;
    if (raw.length == 16 && _isMappedV4(raw)) raw = raw.sublist(12);
    if (raw.length == 4) return '${raw[0]}.${raw[1]}.${raw[2]}.0/24';
    final groups = [
      for (var i = 0; i < 6; i += 2)
        ((raw[i] << 8) | raw[i + 1]).toRadixString(16),
    ];
    return '${groups.join(':')}::/48';
  }

  static bool _isMappedV4(Uint8List raw) {
    for (var i = 0; i < 10; i++) {
      if (raw[i] != 0) return false;
    }
    return raw[10] == 0xff && raw[11] == 0xff;
  }

  /// Проверяет адрес `host:port` для TCP: host — IPv4, `[IPv6]` или имя
  /// DNS, порт 1–65535. Описание ошибки или `null`.
  static String? endpointProblem(String endpoint) {
    if (endpoint.isEmpty || endpoint.length > _maxEndpointLength) {
      return 'адрес пустой или слишком длинный';
    }
    final String host;
    final String port;
    if (endpoint.startsWith('[')) {
      final close = endpoint.indexOf(']:');
      if (close < 0) return 'IPv6-адрес — в виде [адрес]:порт';
      host = endpoint.substring(1, close);
      port = endpoint.substring(close + 2);
      final ip = InternetAddress.tryParse(host);
      if (ip == null || ip.type != InternetAddressType.IPv6) {
        return 'неверный IPv6-адрес';
      }
    } else {
      final colon = endpoint.lastIndexOf(':');
      if (colon <= 0) return 'адрес — в виде хост:порт';
      host = endpoint.substring(0, colon);
      port = endpoint.substring(colon + 1);
      if (host.contains(':')) return 'IPv6-адрес — в квадратных скобках';
      if (!_hostname.hasMatch(host)) return 'неверное имя хоста';
    }
    final p = int.tryParse(port);
    if (p == null || p < 1 || p > 65535 || '$p' != port) {
      return 'порт — число от 1 до 65535';
    }
    return null;
  }

  /// Проверяет список адресов: не больше [maxEndpoints], без повторов.
  /// Описание ошибки или `null`.
  static String? endpointsProblem(List<String> endpoints) {
    if (endpoints.length > maxEndpoints) {
      return 'адресов больше $maxEndpoints';
    }
    if (endpoints.toSet().length != endpoints.length) {
      return 'адреса повторяются';
    }
    for (final e in endpoints) {
      final problem = endpointProblem(e);
      if (problem != null) return problem;
    }
    return null;
  }
}
