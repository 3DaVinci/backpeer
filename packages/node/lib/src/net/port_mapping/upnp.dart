import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:node/src/net/port_mapping/port_mapping.dart';

/// Проброс порта через UPnP IGD (задача 3.5.2): поиск роутера по SSDP,
/// описание устройства, SOAP-вызовы `AddPortMapping`,
/// `GetExternalIPAddress`, `DeletePortMapping` службы `WANIPConnection`
/// (версии 1 и 2) или `WANPPPConnection:1`.
///
/// Своя небольшая реализация: готовые пакеты для Dart либо заброшены,
/// либо тянут лишние зависимости. XML описаний и ответов простой и
/// разбирается регулярными выражениями; размер ответов ограничен.
final class UpnpClient implements PortMappingProtocol {
  new({
    InternetAddress? ssdpAddress,
    this.ssdpPort = 1900,
    this.discoveryTimeout = const Duration(seconds: 2),
    this.requestTimeout = const Duration(seconds: 5),
    this.description = 'backpeer node',
    DateTime Function()? clock,
  }) : ssdpAddress = ssdpAddress ?? InternetAddress('239.255.255.250'),
       _clock = clock ?? DateTime.now;

  /// Куда отправлять M-SEARCH: групповой адрес SSDP; в тестах — свой.
  final InternetAddress ssdpAddress;
  final int ssdpPort;
  final Duration discoveryTimeout;
  final Duration requestTimeout;

  /// Описание проброса в интерфейсе роутера.
  final String description;
  final DateTime Function() _clock;

  static const _searchTargets = [
    'urn:schemas-upnp-org:device:InternetGatewayDevice:1',
    'urn:schemas-upnp-org:device:InternetGatewayDevice:2',
    'urn:schemas-upnp-org:service:WANIPConnection:1',
  ];

  static const _serviceTypes = [
    'urn:schemas-upnp-org:service:WANIPConnection:2',
    'urn:schemas-upnp-org:service:WANIPConnection:1',
    'urn:schemas-upnp-org:service:WANPPPConnection:1',
  ];

  /// Описание и ответы SOAP длиннее — отказ.
  static const int _maxResponseBytes = 256 * 1024;

  final HttpClient _http = HttpClient()..userAgent = 'backpeer-node UPnP/1.1';
  UpnpService? _service;

  @override
  String get name => 'upnp';

  /// Найденная служба роутера (после [map]).
  UpnpService? get service => _service;

  @override
  Future<PortMapping> map({
    required int internalPort,
    required int externalPort,
    required Duration lifetime,
  }) async {
    final service = _service ??= await discover();
    try {
      return await _map(service, internalPort, externalPort, lifetime);
    } on PortMappingException catch (e) {
      // Роутер сменился или перезагрузился с другим адресом: в следующий
      // раз искать заново.
      if (!e.conflict) _service = null;
      rethrow;
    }
  }

  Future<PortMapping> _map(
    UpnpService service,
    int internalPort,
    int externalPort,
    Duration lifetime,
  ) async {
    final local = await _localAddressTowards(service.controlUrl);
    Future<void> add(Duration lease) => _soap(service, 'AddPortMapping', {
      'NewRemoteHost': '',
      'NewExternalPort': '$externalPort',
      'NewProtocol': 'TCP',
      'NewInternalPort': '$internalPort',
      'NewInternalClient': local.address,
      'NewEnabled': '1',
      'NewPortMappingDescription': description,
      'NewLeaseDuration': '${lease.inSeconds}',
    });
    var lease = lifetime;
    try {
      await add(lease);
    } on UpnpSoapException catch (e) {
      // 725 OnlyPermanentLeasesSupported: старые роутеры умеют только
      // бессрочный проброс — его узел снимает при остановке сам.
      if (e.code != 725) throw e.toMappingException();
      lease = Duration.zero;
      try {
        await add(lease);
      } on UpnpSoapException catch (e) {
        throw e.toMappingException();
      }
    }
    InternetAddress? external;
    try {
      final r = await _soap(service, 'GetExternalIPAddress', const {});
      external = InternetAddress.tryParse(
        _element(r, 'NewExternalIPAddress') ?? '',
      );
    } on Object {
      // Адрес — для диагностики, без него проброс есть.
    }
    return PortMapping(
      method: name,
      internalPort: internalPort,
      externalPort: externalPort,
      externalAddress: external,
      lifetime: lease,
      createdAt: _clock(),
    );
  }

  @override
  Future<void> unmap(PortMapping mapping) async {
    final service = _service;
    if (service == null) return;
    try {
      await _soap(service, 'DeletePortMapping', {
        'NewRemoteHost': '',
        'NewExternalPort': '${mapping.externalPort}',
        'NewProtocol': 'TCP',
      });
    } on UpnpSoapException catch (e) {
      // 714 NoSuchEntryInArray: проброса уже нет.
      if (e.code != 714) throw e.toMappingException();
    }
  }

  @override
  void close() => _http.close(force: true);

  /// Ищет роутер по SSDP и читает его описание: первая служба из
  /// [_serviceTypes]. Нет ответа — [PortMappingException] с `unsupported`.
  Future<UpnpService> discover() async {
    final locations = await _search();
    PortMappingException? last;
    for (final location in locations) {
      try {
        final service = await _describe(location);
        if (service != null) return service;
      } on PortMappingException catch (e) {
        last = e;
      }
    }
    throw last ??
        const PortMappingException(
          'роутер с UPnP IGD не найден',
          unsupported: true,
        );
  }

  /// M-SEARCH и адреса описаний из ответов (заголовок LOCATION).
  Future<List<Uri>> _search() async {
    final RawDatagramSocket socket;
    try {
      socket = await RawDatagramSocket.bind(
        ssdpAddress.isLoopback
            ? InternetAddress.loopbackIPv4
            : InternetAddress.anyIPv4,
        0,
      );
    } on SocketException catch (e) {
      throw PortMappingException('UDP-сокет не открылся: ${e.message}');
    }
    final found = <Uri>{};
    final sub = socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final d = socket.receive();
      if (d == null) return;
      final location = parseSsdpLocation(latin1.decode(d.data));
      if (location != null) found.add(location);
    });
    try {
      for (final st in _searchTargets) {
        final message =
            'M-SEARCH * HTTP/1.1\r\n'
            'HOST: 239.255.255.250:1900\r\n'
            'MAN: "ssdp:discover"\r\n'
            'MX: ${discoveryTimeout.inSeconds.clamp(1, 5)}\r\n'
            'ST: $st\r\n\r\n';
        socket.send(ascii.encode(message), ssdpAddress, ssdpPort);
      }
      // Ответы приходят в течение MX секунд.
      final deadline = _clock().add(discoveryTimeout);
      while (_clock().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        if (found.isNotEmpty) {
          // Ещё немного: у роутера может быть несколько устройств.
          await Future<void>.delayed(const Duration(milliseconds: 200));
          break;
        }
      }
    } finally {
      await sub.cancel();
      socket.close();
    }
    return found.toList();
  }

  /// LOCATION из ответа SSDP: адрес http в частной сети (UPnP — только
  /// локальная сеть; иначе ответ мог бы направить узел куда угодно).
  static Uri? parseSsdpLocation(String response) {
    if (!response.startsWith('HTTP/1.1 200')) return null;
    for (final line in response.split('\r\n')) {
      final colon = line.indexOf(':');
      if (colon < 0) continue;
      if (line.substring(0, colon).trim().toLowerCase() != 'location') {
        continue;
      }
      final uri = Uri.tryParse(line.substring(colon + 1).trim());
      if (uri == null || uri.scheme != 'http' || uri.host.isEmpty) {
        return null;
      }
      return uri;
    }
    return null;
  }

  Future<UpnpService?> _describe(Uri location) async {
    final xml = await _get(location);
    return parseDescription(xml, location);
  }

  /// Первая подходящая служба из описания устройства [xml], адрес
  /// управления — относительно `URLBase` или адреса описания.
  static UpnpService? parseDescription(String xml, Uri location) {
    final base = switch (_element(xml, 'URLBase')) {
      final b? when b.trim().isNotEmpty => Uri.tryParse(b.trim()) ?? location,
      _ => location,
    };
    final services = RegExp(
      r'<(?:\w+:)?service>(.*?)</(?:\w+:)?service>',
      dotAll: true,
    ).allMatches(xml).map((m) => m.group(1)!).toList();
    for (final type in _serviceTypes) {
      for (final s in services) {
        if (_element(s, 'serviceType')?.trim() != type) continue;
        final control = _element(s, 'controlURL')?.trim();
        if (control == null || control.isEmpty) continue;
        final url = base.resolve(control);
        if (url.scheme != 'http') continue;
        return UpnpService(type, url);
      }
    }
    return null;
  }

  Future<String> _get(Uri url) async {
    try {
      final request = await _http.getUrl(url).timeout(requestTimeout);
      final response = await request.close().timeout(requestTimeout);
      final body = await _readBody(response);
      if (response.statusCode != 200) {
        throw PortMappingException(
          'описание UPnP: HTTP ${response.statusCode}',
        );
      }
      return body;
    } on TimeoutException {
      throw const PortMappingException('описание UPnP: нет ответа');
    } on IOException catch (e) {
      throw PortMappingException('описание UPnP: $e');
    }
  }

  /// SOAP-вызов [action]; ответ — тело. Ошибка UPnP —
  /// [UpnpSoapException], сбой связи — [PortMappingException].
  Future<String> _soap(
    UpnpService service,
    String action,
    Map<String, String> arguments,
  ) async {
    final args = [
      for (final MapEntry(:key, :value) in arguments.entries)
        '<$key>${_escape(value)}</$key>',
    ].join();
    final body = [
      '<?xml version="1.0"?>\r\n',
      '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" ',
      's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">',
      '<s:Body><u:$action xmlns:u="${service.type}">$args</u:$action>',
      '</s:Body></s:Envelope>\r\n',
    ].join();
    try {
      final request = await _http
          .postUrl(service.controlUrl)
          .timeout(requestTimeout);
      final bytes = utf8.encode(body);
      request.headers
        ..contentType = ContentType('text', 'xml', charset: 'utf-8')
        ..set('SOAPAction', '"${service.type}#$action"');
      request
        ..contentLength = bytes.length
        ..add(bytes);
      final response = await request.close().timeout(requestTimeout);
      final text = await _readBody(response);
      if (response.statusCode == 200) return text;
      final code = int.tryParse(_element(text, 'errorCode')?.trim() ?? '');
      throw UpnpSoapException(
        action,
        code,
        _element(text, 'errorDescription')?.trim() ??
            'HTTP ${response.statusCode}',
      );
    } on TimeoutException {
      throw PortMappingException('UPnP $action: нет ответа');
    } on IOException catch (e) {
      throw PortMappingException('UPnP $action: $e');
    }
  }

  Future<String> _readBody(HttpClientResponse response) async {
    final out = BytesBuilder(copy: false);
    await for (final chunk in response.timeout(requestTimeout)) {
      out.add(chunk);
      if (out.length > _maxResponseBytes) {
        throw const PortMappingException('UPnP: слишком длинный ответ');
      }
    }
    return utf8.decode(out.takeBytes(), allowMalformed: true);
  }

  /// Свой адрес, с которого виден роутер: им заполняется
  /// `NewInternalClient`.
  Future<InternetAddress> _localAddressTowards(Uri url) async {
    try {
      final socket = await Socket.connect(
        url.host,
        url.port,
        timeout: requestTimeout,
      );
      final address = socket.address;
      socket.destroy();
      return address;
    } on SocketException catch (e) {
      throw PortMappingException('роутер UPnP недоступен: ${e.message}');
    }
  }

  /// Текст первого элемента [name] (с любым префиксом пространства имён).
  static String? _element(String xml, String name) => RegExp(
    '<(?:\\w+:)?$name(?:\\s[^>]*)?>(.*?)</(?:\\w+:)?$name>',
    dotAll: true,
  ).firstMatch(xml)?.group(1);

  static String _escape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}

/// Служба роутера для проброса.
final class UpnpService {
  const new(this.type, this.controlUrl);

  final String type;
  final Uri controlUrl;
}

/// Ошибка UPnP из ответа SOAP (`UPnPError`).
final class UpnpSoapException implements Exception {
  const new(this.action, this.code, this.description);

  final String action;
  final int? code;
  final String description;

  /// 718 ConflictInMappingEntry: внешний порт занят другим устройством.
  bool get conflict => code == 718;

  PortMappingException toMappingException() => PortMappingException(
    'UPnP $action: ${code ?? '-'} $description',
    conflict: conflict,
  );

  @override
  String toString() => 'UpnpSoapException($action: $code $description)';
}
