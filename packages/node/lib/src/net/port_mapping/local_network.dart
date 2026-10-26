import 'dart:io';
import 'dart:typed_data';

/// Шлюз по умолчанию и свой адрес в его сети — для PCP и NAT-PMP
/// (задача 3.5.2). В Dart нет API таблицы маршрутов, поэтому шлюз
/// читается по-своему на каждой ОС: `/proc/net/route` на Linux, вывод
/// `route -n get default` на macOS и `route print` на Windows (на macOS и
/// Windows не проверено — ждёт раннеров, 0.2.x).
abstract final class LocalNetwork {
  /// IPv4-адрес шлюза по умолчанию или `null`.
  static Future<InternetAddress?> defaultGateway() async {
    try {
      if (Platform.isLinux || Platform.isAndroid) {
        return gatewayFromProcRoute(
          await File('/proc/net/route').readAsString(),
        );
      }
      if (Platform.isMacOS) {
        final r = await Process.run('/sbin/route', ['-n', 'get', 'default']);
        return gatewayFromBsdRoute('${r.stdout}');
      }
      if (Platform.isWindows) {
        final r = await Process.run('route', ['print', '-4', '0.0.0.0']);
        return gatewayFromWindowsRoute('${r.stdout}');
      }
    } on IOException {
      // Нет файла или команды: шлюз неизвестен.
    }
    return null;
  }

  /// Разбор `/proc/net/route`: маршрут с назначением 0.0.0.0 и флагом
  /// RTF_GATEWAY; адрес — hex в порядке байт little-endian.
  static InternetAddress? gatewayFromProcRoute(String text) {
    for (final line in text.split('\n').skip(1)) {
      final f = line.trim().split(RegExp(r'\s+'));
      if (f.length < 4 || f[1] != '00000000') continue;
      final flags = int.tryParse(f[3], radix: 16) ?? 0;
      final gw = int.tryParse(f[2], radix: 16);
      if (gw == null || gw == 0 || flags & 0x2 == 0) continue;
      return InternetAddress.fromRawAddress(
        Uint8List.fromList([
          gw & 0xff,
          (gw >> 8) & 0xff,
          (gw >> 16) & 0xff,
          (gw >> 24) & 0xff,
        ]),
        type: InternetAddressType.IPv4,
      );
    }
    return null;
  }

  /// Разбор `route -n get default` (macOS): строка `gateway: a.b.c.d`.
  static InternetAddress? gatewayFromBsdRoute(String text) {
    final m = RegExp(r'gateway:\s*(\d+\.\d+\.\d+\.\d+)').firstMatch(text);
    return m == null ? null : InternetAddress.tryParse(m.group(1)!);
  }

  /// Разбор `route print -4 0.0.0.0` (Windows): строка
  /// `0.0.0.0  0.0.0.0  <шлюз>  <интерфейс>  <метрика>`.
  static InternetAddress? gatewayFromWindowsRoute(String text) {
    for (final line in text.split('\n')) {
      final f = line.trim().split(RegExp(r'\s+'));
      if (f.length >= 5 && f[0] == '0.0.0.0' && f[1] == '0.0.0.0') {
        final ip = InternetAddress.tryParse(f[2]);
        if (ip != null && ip.type == InternetAddressType.IPv4) return ip;
      }
    }
    return null;
  }

  /// Свой IPv4-адрес, ближайший к [gateway]: с самым длинным общим
  /// префиксом (маски подсети Dart не сообщает).
  static Future<InternetAddress?> addressTowards(
    InternetAddress gateway,
  ) async {
    final List<NetworkInterface> interfaces;
    try {
      interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
    } on SocketException {
      return null;
    }
    InternetAddress? best;
    var bestPrefix = -1;
    for (final i in interfaces) {
      for (final a in i.addresses) {
        if (a.isLoopback) continue;
        final prefix = commonPrefix(a.rawAddress, gateway.rawAddress);
        if (prefix > bestPrefix) {
          best = a;
          bestPrefix = prefix;
        }
      }
    }
    return best;
  }

  /// Число общих старших бит.
  static int commonPrefix(List<int> a, List<int> b) {
    var bits = 0;
    for (var i = 0; i < a.length && i < b.length; i++) {
      final x = a[i] ^ b[i];
      if (x == 0) {
        bits += 8;
        continue;
      }
      var mask = 0x80;
      while (mask != 0 && x & mask == 0) {
        bits++;
        mask >>= 1;
      }
      break;
    }
    return bits;
  }

  /// Частный или иной не публичный IPv4: проброс на таком роутере не
  /// делает узел доступным из интернета (двойной NAT, NAT провайдера).
  static bool isPrivateV4(InternetAddress ip) {
    final b = ip.rawAddress;
    if (b.length != 4) return false;
    return b[0] == 0 ||
        b[0] == 10 ||
        b[0] == 127 ||
        (b[0] == 100 && b[1] >= 64 && b[1] < 128) ||
        (b[0] == 169 && b[1] == 254) ||
        (b[0] == 172 && b[1] >= 16 && b[1] < 32) ||
        (b[0] == 192 && b[1] == 168);
  }
}
