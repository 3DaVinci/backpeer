import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:node/node.dart';
import 'package:test/test.dart';

/// Подставной сервер PCP и NAT-PMP на loopback.
final class _FakeNatGateway {
  new _(this._socket, this.mode) {
    _socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final d = _socket.receive();
      if (d == null) return;
      requests.add(d.data);
      final reply = _reply(d.data);
      if (reply != null) _socket.send(reply, d.address, d.port);
    });
  }

  static Future<_FakeNatGateway> start(String mode) async => _FakeNatGateway._(
    await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0),
    mode,
  );

  final RawDatagramSocket _socket;

  /// `pcp`, `nat-pmp` или `silent`.
  final String mode;
  final requests = <Uint8List>[];

  /// Код результата PCP для следующих ответов.
  int pcpResult = 0;

  /// Внешний порт, который даёт шлюз; `null` — запрошенный.
  int? assignPort;

  int get port => _socket.port;

  Uint8List? _reply(Uint8List r) {
    if (mode == 'silent') return null;
    if (r[0] == 2) {
      if (mode != 'pcp') {
        // NAT-PMP-сервер на запрос PCP: версия 0, «неподдерживаемая версия».
        return Uint8List.fromList([0, r[1] | 0x80, 0, 1, 0, 0, 0, 1]);
      }
      final req = ByteData.sublistView(r);
      final out = Uint8List(60);
      final b = ByteData.sublistView(out)
        ..setUint8(0, 2)
        ..setUint8(1, 0x81)
        ..setUint8(3, pcpResult)
        ..setUint32(4, req.getUint32(4))
        ..setUint32(8, 1000)
        ..setUint8(36, req.getUint8(36))
        ..setUint16(40, req.getUint16(40))
        ..setUint16(42, assignPort ?? req.getUint16(42))
        ..setUint8(54, 0xff)
        ..setUint8(55, 0xff);
      out
        ..setRange(24, 36, r.sublist(24, 36))
        ..setRange(56, 60, [198, 51, 100, 20]);
      return b.buffer.asUint8List();
    }
    // NAT-PMP.
    if (r[1] == 0) {
      return Uint8List.fromList([0, 128, 0, 0, 0, 0, 3, 232, 192, 168, 0, 2]);
    }
    final req = ByteData.sublistView(r);
    final out = ByteData(16)
      ..setUint8(1, 128 + r[1])
      ..setUint32(4, 1000)
      ..setUint16(8, req.getUint16(4))
      ..setUint16(10, assignPort ?? req.getUint16(6))
      ..setUint32(12, req.getUint32(8));
    return out.buffer.asUint8List();
  }

  void close() => _socket.close();
}

/// Подставной роутер UPnP IGD: ответ SSDP, описание, SOAP.
final class _FakeIgd {
  new _(this._http, this._ssdp) {
    _http.listen(_handle);
    _ssdp.listen((event) {
      if (event != RawSocketEvent.read) return;
      final d = _ssdp.receive();
      if (d == null) return;
      searches.add(latin1.decode(d.data));
      _ssdp.send(
        latin1.encode(
          'HTTP/1.1 200 OK\r\n'
          'CACHE-CONTROL: max-age=120\r\n'
          'ST: urn:schemas-upnp-org:device:InternetGatewayDevice:1\r\n'
          'Location: http://127.0.0.1:${_http.port}/rootDesc.xml\r\n'
          '\r\n',
        ),
        d.address,
        d.port,
      );
    });
  }

  static Future<_FakeIgd> start() async => _FakeIgd._(
    await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0),
  );

  final HttpServer _http;
  final RawDatagramSocket _ssdp;
  final searches = <String>[];

  /// Вызовы SOAP: действие и тело.
  final actions = <(String, String)>[];

  /// Ошибки UPnP по действию: код в ответе 500.
  final errors = <String, List<int>>{};

  int get ssdpPort => _ssdp.port;

  static const description = '''
<?xml version="1.0"?>
<root xmlns="urn:schemas-upnp-org:device-1-0">
 <device>
  <deviceType>urn:schemas-upnp-org:device:InternetGatewayDevice:1</deviceType>
  <deviceList><device>
   <deviceType>urn:schemas-upnp-org:device:WANDevice:1</deviceType>
   <deviceList><device>
    <deviceType>urn:schemas-upnp-org:device:WANConnectionDevice:1</deviceType>
    <serviceList>
     <service>
      <serviceType>urn:schemas-upnp-org:service:WANCommonInterfaceConfig:1</serviceType>
      <controlURL>/ctl/CmnIfCfg</controlURL>
     </service>
     <service>
      <serviceType>urn:schemas-upnp-org:service:WANIPConnection:1</serviceType>
      <serviceId>urn:upnp-org:serviceId:WANIPConn1</serviceId>
      <controlURL>/ctl/IPConn</controlURL>
     </service>
    </serviceList>
   </device></deviceList>
  </device></deviceList>
 </device>
</root>''';

  Future<void> _handle(HttpRequest request) async {
    final body = await utf8.decodeStream(request);
    final response = request.response;
    if (request.method == 'GET' && request.uri.path == '/rootDesc.xml') {
      response.write(description);
    } else if (request.method == 'POST' && request.uri.path == '/ctl/IPConn') {
      final soapAction = request.headers.value('SOAPAction') ?? '';
      final action = soapAction.replaceAll('"', '').split('#').last;
      actions.add((action, body));
      final pending = errors[action];
      if (pending != null && pending.isNotEmpty) {
        response
          ..statusCode = 500
          ..write(
            '<s:Envelope><s:Body><s:Fault><detail><UPnPError>'
            '<errorCode>${pending.removeAt(0)}</errorCode>'
            '<errorDescription>отказ</errorDescription>'
            '</UPnPError></detail></s:Fault></s:Body></s:Envelope>',
          );
      } else if (action == 'GetExternalIPAddress') {
        response.write(
          '<s:Envelope><s:Body><u:GetExternalIPAddressResponse>'
          '<NewExternalIPAddress>100.64.1.2</NewExternalIPAddress>'
          '</u:GetExternalIPAddressResponse></s:Body></s:Envelope>',
        );
      } else {
        response.write('<s:Envelope><s:Body/></s:Envelope>');
      }
    } else {
      response.statusCode = 404;
    }
    await response.close();
  }

  Future<void> close() async {
    _ssdp.close();
    await _http.close(force: true);
  }
}

/// Протокол проброса по сценарию.
final class _ScriptedProtocol implements PortMappingProtocol {
  new(this.name, this.script);

  @override
  final String name;

  /// Ответы на вызовы [map] по очереди: [Duration] — успех с этим сроком,
  /// [PortMappingException] — отказ; кончились — повтор последнего.
  final List<Object> script;
  final mapped = <int>[];
  final unmapped = <int>[];
  bool closed = false;

  @override
  Future<PortMapping> map({
    required int internalPort,
    required int externalPort,
    required Duration lifetime,
  }) async {
    mapped.add(externalPort);
    final step = script.length > 1 ? script.removeAt(0) : script.single;
    if (step is PortMappingException) throw step;
    return PortMapping(
      method: name,
      internalPort: internalPort,
      externalPort: externalPort,
      lifetime: step as Duration,
      createdAt: DateTime.now(),
    );
  }

  @override
  Future<void> unmap(PortMapping mapping) async =>
      unmapped.add(mapping.externalPort);

  @override
  void close() => closed = true;
}

void main() {
  group('PCP и NAT-PMP', () {
    late _FakeNatGateway gw;
    tearDown(() => gw.close());

    PcpClient client() => PcpClient(
      gateway: InternetAddress.loopbackIPv4,
      localAddress: InternetAddress.loopbackIPv4,
      serverPort: gw.port,
      attempts: 2,
      firstWait: const Duration(milliseconds: 50),
    );

    test('PCP MAP: проброс, продление с тем же nonce, снятие', () async {
      gw = await _FakeNatGateway.start('pcp');
      final pcp = client();
      final m = await pcp.map(
        internalPort: 7340,
        externalPort: 7340,
        lifetime: const Duration(hours: 1),
      );
      expect(pcp.name, 'pcp');
      expect(m.method, 'pcp');
      expect(m.externalPort, 7340);
      expect(m.externalAddress?.address, '198.51.100.20');
      expect(m.lifetime, const Duration(hours: 1));
      final first = gw.requests.single;
      expect(first.length, 60);
      expect(first[0], 2);
      expect(first[1], 1, reason: 'MAP');
      expect(first[36], 6, reason: 'TCP');
      expect(
        first.sublist(18, 24),
        [127, 0, 0, 1].toList()..insertAll(0, [0xff, 0xff]),
      );
      await pcp.map(
        internalPort: 7340,
        externalPort: 7340,
        lifetime: const Duration(hours: 1),
      );
      await pcp.unmap(m);
      expect(gw.requests, hasLength(3));
      final nonce = first.sublist(24, 36);
      for (final r in gw.requests) {
        expect(r.sublist(24, 36), nonce);
      }
      expect(ByteData.sublistView(gw.requests.last).getUint32(4), 0);
    });

    test('PCP: роутер даёт другой порт; «внешний порт недоступен» — '
        'конфликт', () async {
      gw = await _FakeNatGateway.start('pcp')
        ..assignPort = 51000;
      final pcp = client();
      final m = await pcp.map(
        internalPort: 7340,
        externalPort: 7340,
        lifetime: const Duration(hours: 1),
      );
      expect(m.externalPort, 51000);
      gw.pcpResult = 11;
      await expectLater(
        pcp.map(
          internalPort: 7340,
          externalPort: 7340,
          lifetime: const Duration(hours: 1),
        ),
        throwsA(
          isA<PortMappingException>().having(
            (e) => e.conflict,
            'conflict',
            true,
          ),
        ),
      );
    });

    test('роутер знает только NAT-PMP: откат, внешний адрес, снятие', () async {
      gw = await _FakeNatGateway.start('nat-pmp');
      final pcp = client();
      final m = await pcp.map(
        internalPort: 7340,
        externalPort: 7340,
        lifetime: const Duration(hours: 2),
      );
      expect(pcp.name, 'nat-pmp');
      expect(m.method, 'nat-pmp');
      expect(m.externalPort, 7340);
      expect(m.lifetime, const Duration(hours: 2));
      expect(m.externalAddress?.address, '192.168.0.2');
      expect(LocalNetwork.isPrivateV4(m.externalAddress!), isTrue);
      // PCP, NAT-PMP MAP, NAT-PMP адрес.
      expect([for (final r in gw.requests) r[0]], [2, 0, 0]);
      expect(gw.requests[1][1], 2, reason: 'NAT-PMP: TCP');
      await pcp.unmap(m);
      final del = ByteData.sublistView(gw.requests.last);
      expect(del.getUint16(4), 7340);
      expect(del.getUint16(6), 0);
      expect(del.getUint32(8), 0);
    });

    test('шлюз молчит — unsupported после повторов', () async {
      gw = await _FakeNatGateway.start('silent');
      await expectLater(
        client().map(
          internalPort: 7340,
          externalPort: 7340,
          lifetime: const Duration(hours: 1),
        ),
        throwsA(
          isA<PortMappingException>().having(
            (e) => e.unsupported,
            'unsupported',
            true,
          ),
        ),
      );
      expect(gw.requests, hasLength(2));
    });
  });

  group('UPnP IGD', () {
    late _FakeIgd igd;
    setUp(() async => igd = await _FakeIgd.start());
    tearDown(() => igd.close());

    UpnpClient client() => UpnpClient(
      ssdpAddress: InternetAddress.loopbackIPv4,
      ssdpPort: igd.ssdpPort,
      discoveryTimeout: const Duration(seconds: 1),
    );

    test('поиск, AddPortMapping, внешний адрес, DeletePortMapping', () async {
      final upnp = client();
      final m = await upnp.map(
        internalPort: 7340,
        externalPort: 7340,
        lifetime: const Duration(hours: 1),
      );
      expect(igd.searches.first, startsWith('M-SEARCH * HTTP/1.1'));
      expect(
        upnp.service?.type,
        'urn:schemas-upnp-org:service:WANIPConnection:1',
      );
      expect(m.method, 'upnp');
      expect(m.externalPort, 7340);
      expect(m.lifetime, const Duration(hours: 1));
      expect(m.externalAddress?.address, '100.64.1.2');
      final (action, body) = igd.actions.first;
      expect(action, 'AddPortMapping');
      expect(body, contains('<NewExternalPort>7340</NewExternalPort>'));
      expect(body, contains('<NewInternalPort>7340</NewInternalPort>'));
      expect(body, contains('<NewProtocol>TCP</NewProtocol>'));
      expect(
        body,
        contains('<NewInternalClient>127.0.0.1</NewInternalClient>'),
      );
      expect(body, contains('<NewLeaseDuration>3600</NewLeaseDuration>'));
      await upnp.unmap(m);
      expect(igd.actions.last.$1, 'DeletePortMapping');
      expect(igd.actions.last.$2, contains('<NewExternalPort>7340<'));
      upnp.close();
    });

    test('725: только бессрочный проброс; 718 — конфликт', () async {
      igd.errors['AddPortMapping'] = [725];
      final upnp = client();
      final m = await upnp.map(
        internalPort: 7340,
        externalPort: 7340,
        lifetime: const Duration(hours: 1),
      );
      expect(m.lifetime, Duration.zero);
      expect(
        [
          for (final (a, b) in igd.actions)
            if (a == 'AddPortMapping') b,
        ],
        [contains('<NewLeaseDuration>3600<'), contains('<NewLeaseDuration>0<')],
      );
      igd.errors['AddPortMapping'] = [718];
      await expectLater(
        upnp.map(
          internalPort: 7340,
          externalPort: 7340,
          lifetime: const Duration(hours: 1),
        ),
        throwsA(
          isA<PortMappingException>().having(
            (e) => e.conflict,
            'conflict',
            true,
          ),
        ),
      );
      upnp.close();
    });

    test('роутера нет — unsupported', () async {
      final silent = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(silent.close);
      final upnp = UpnpClient(
        ssdpAddress: InternetAddress.loopbackIPv4,
        ssdpPort: silent.port,
        discoveryTimeout: const Duration(milliseconds: 300),
      );
      await expectLater(
        upnp.map(
          internalPort: 7340,
          externalPort: 7340,
          lifetime: const Duration(hours: 1),
        ),
        throwsA(
          isA<PortMappingException>().having(
            (e) => e.unsupported,
            'unsupported',
            true,
          ),
        ),
      );
      upnp.close();
    });

    test('описание: URLBase, относительный адрес, WANPPPConnection, '
        'LOCATION только http', () {
      const xml = '''
<root><URLBase>http://192.168.1.1:5000/</URLBase>
<service><serviceType>urn:schemas-upnp-org:service:WANPPPConnection:1</serviceType>
<controlURL>ctl/PPP</controlURL></service></root>''';
      final s = UpnpClient.parseDescription(
        xml,
        Uri.parse('http://192.168.1.1:1900/desc.xml'),
      )!;
      expect(s.type, 'urn:schemas-upnp-org:service:WANPPPConnection:1');
      expect(s.controlUrl.toString(), 'http://192.168.1.1:5000/ctl/PPP');
      expect(
        UpnpClient.parseDescription(
          '<root/>',
          Uri.parse('http://192.168.1.1/'),
        ),
        isNull,
      );
      expect(
        UpnpClient.parseSsdpLocation(
          'HTTP/1.1 200 OK\r\nlocation: http://10.0.0.1:80/d.xml\r\n\r\n',
        ),
        Uri.parse('http://10.0.0.1:80/d.xml'),
      );
      expect(
        UpnpClient.parseSsdpLocation(
          'HTTP/1.1 200 OK\r\nLOCATION: file:///etc/passwd\r\n\r\n',
        ),
        isNull,
      );
      expect(UpnpClient.parseSsdpLocation('NOTIFY * HTTP/1.1\r\n'), isNull);
    });
  });

  group('PortMapper', () {
    test('первый протокол не работает — второй; продление; снятие при '
        'остановке', () async {
      final upnp = _ScriptedProtocol('upnp', [
        const PortMappingException('нет роутера', unsupported: true),
      ]);
      final pcp = _ScriptedProtocol('pcp', [const Duration(milliseconds: 200)]);
      var changes = 0;
      final mapper = PortMapper(
        internalPort: 7340,
        protocols: [upnp, pcp],
        minRenewInterval: const Duration(milliseconds: 50),
        onChange: () => changes++,
      );
      await mapper.refresh();
      expect(mapper.current?.method, 'pcp');
      expect(mapper.externalPort, 7340);
      expect(changes, 1);
      mapper.start();
      // Продление на половине срока — тем же протоколом, без изменений.
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(pcp.mapped.length, greaterThanOrEqualTo(3));
      expect(upnp.mapped, hasLength(1));
      expect(changes, 1);
      expect(mapper.toJson()['mapping'], isNotNull);
      await mapper.stop();
      expect(pcp.unmapped, [7340]);
      expect(mapper.current, isNull);
      expect(upnp.closed && pcp.closed, isTrue);
    });

    test('внешний порт занят — случайный порт; проброс пропал — '
        'onChange и current = null', () async {
      final p = _ScriptedProtocol('upnp', [
        const PortMappingException('занят', conflict: true),
        const Duration(hours: 1),
        const PortMappingException('роутер пропал'),
      ]);
      var changes = 0;
      final mapper = PortMapper(
        internalPort: 7340,
        protocols: [p],
        onChange: () => changes++,
      );
      await mapper.refresh();
      expect(p.mapped.first, 7340);
      final external = mapper.externalPort!;
      expect(external, inInclusiveRange(20000, 59999));
      expect(changes, 1);
      await mapper.refresh();
      expect(p.mapped.last, external, reason: 'продление — тот же порт');
      expect(mapper.current, isNull);
      expect(changes, 2);
      expect(mapper.toJson()['lastError'], contains('роутер пропал'));
      await mapper.stop();
      expect(p.unmapped, isEmpty);
    });

    test('режим off — без протоколов', () {
      expect(PortMapper.protocolsFor(PortMappingMode.off), isEmpty);
      final auto = PortMapper.protocolsFor(PortMappingMode.auto);
      expect([for (final p in auto) p.name], ['upnp', 'pcp']);
      for (final p in auto) {
        p.close();
      }
    });
  });

  group('шлюз по умолчанию', () {
    test('Linux /proc/net/route', () {
      const text =
          'Iface\tDestination\tGateway \tFlags\tRefCnt\tUse\tMetric\tMask\n'
          'eth0\t0010A8C0\t00000000\t0001\t0\t0\t0\t00FFFFFF\n'
          'eth0\t00000000\t0101A8C0\t0003\t0\t0\t100\t00000000\n';
      expect(LocalNetwork.gatewayFromProcRoute(text)?.address, '192.168.1.1');
      expect(LocalNetwork.gatewayFromProcRoute('Iface\n'), isNull);
    });

    test('macOS и Windows', () {
      expect(
        LocalNetwork.gatewayFromBsdRoute(
          '   route to: default\ndestination: default\n'
          '    gateway: 10.0.0.138\n  interface: en0\n',
        )?.address,
        '10.0.0.138',
      );
      expect(
        LocalNetwork.gatewayFromWindowsRoute(
          'IPv4 Route Table\n'
          'Network Destination        Netmask          Gateway       '
          'Interface  Metric\n'
          '          0.0.0.0          0.0.0.0      192.168.0.1    '
          '192.168.0.42     25\n',
        )?.address,
        '192.168.0.1',
      );
    });

    test('ближайший адрес и частные адреса', () {
      expect(LocalNetwork.commonPrefix([192, 168, 1, 5], [192, 168, 1, 1]), 29);
      expect(LocalNetwork.commonPrefix([10, 0, 0, 1], [192, 168, 1, 1]), 0);
      for (final ip in [
        '10.1.2.3',
        '172.20.0.1',
        '192.168.5.5',
        '100.100.0.1',
      ]) {
        expect(
          LocalNetwork.isPrivateV4(InternetAddress(ip)),
          isTrue,
          reason: ip,
        );
      }
      for (final ip in ['8.8.8.8', '100.128.0.1', '172.32.0.1']) {
        expect(
          LocalNetwork.isPrivateV4(InternetAddress(ip)),
          isFalse,
          reason: ip,
        );
      }
    });
  });
}
