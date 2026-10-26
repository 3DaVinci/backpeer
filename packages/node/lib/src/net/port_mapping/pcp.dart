import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:node/src/net/port_mapping/local_network.dart';
import 'package:node/src/net/port_mapping/port_mapping.dart';

/// PCP (RFC 6887, запрос MAP) с откатом на NAT-PMP (RFC 6886): оба
/// протокола — UDP на порт 5351 шлюза. Роутер, который знает только
/// NAT-PMP, отвечает на запрос PCP ошибкой «неподдерживаемая версия» в
/// формате NAT-PMP (версия 0), и клиент переходит на NAT-PMP.
///
/// Запрос повторяется через 250 мс, удваивая паузу (RFC 6886, 3.1), но не
/// [attempts] раз, а меньше, чем в RFC: узел не ждёт ответа минутами.
final class PcpClient implements PortMappingProtocol {
  new({
    this.gateway,
    this.localAddress,
    this.serverPort = 5351,
    this.attempts = 4,
    this.firstWait = const Duration(milliseconds: 250),
    DateTime Function()? clock,
    Uint8List Function(int length)? random,
  }) : _clock = clock ?? DateTime.now,
       _random = random ?? _secureRandom;

  /// Шлюз; `null` — шлюз по умолчанию ([LocalNetwork.defaultGateway]).
  final InternetAddress? gateway;

  /// Свой адрес в сети шлюза; `null` — ближайший к шлюзу.
  final InternetAddress? localAddress;

  /// Порт сервера PCP и NAT-PMP; не 5351 — только в тестах.
  final int serverPort;
  final int attempts;
  final Duration firstWait;
  final DateTime Function() _clock;
  final Uint8List Function(int length) _random;

  static const _pcpVersion = 2;
  static const _opMap = 1;
  static const _tcp = 6;

  /// NAT-PMP вместо PCP: роутер сказал, что PCP не знает.
  bool _natPmp = false;

  /// Nonce запросов MAP: один на клиента, чтобы продление и снятие
  /// относились к тому же пробросу.
  late final Uint8List _nonce = _random(12);

  @override
  String get name => _natPmp ? 'nat-pmp' : 'pcp';

  @override
  Future<PortMapping> map({
    required int internalPort,
    required int externalPort,
    required Duration lifetime,
  }) async {
    final (gw, local) = await _endpoints();
    if (!_natPmp) {
      final response = await _exchange(
        gw,
        local,
        _pcpMapRequest(local, internalPort, externalPort, lifetime),
      );
      if (response[0] == 0) {
        // Ответ NAT-PMP: версия 0, «неподдерживаемая версия».
        _natPmp = true;
      } else {
        return _pcpMapResponse(response, internalPort);
      }
    }
    final response = await _exchange(
      gw,
      local,
      _natPmpMapRequest(internalPort, externalPort, lifetime),
    );
    final mapping = _natPmpMapResponse(response, internalPort);
    InternetAddress? external;
    try {
      external = _natPmpAddress(
        await _exchange(gw, local, Uint8List.fromList([0, 0])),
      );
    } on PortMappingException {
      // Адрес — для диагностики, без него проброс есть.
    }
    return PortMapping(
      method: name,
      internalPort: internalPort,
      externalPort: mapping.externalPort,
      externalAddress: external,
      lifetime: mapping.lifetime,
      createdAt: mapping.createdAt,
    );
  }

  @override
  Future<void> unmap(PortMapping mapping) async {
    final (gw, local) = await _endpoints();
    if (_natPmp) {
      // RFC 6886, 3.4: внешний порт 0 и срок 0 — снять.
      _natPmpMapResponse(
        await _exchange(
          gw,
          local,
          _natPmpMapRequest(mapping.internalPort, 0, Duration.zero),
        ),
        mapping.internalPort,
        deleting: true,
      );
    } else {
      _pcpMapResponse(
        await _exchange(
          gw,
          local,
          _pcpMapRequest(
            local,
            mapping.internalPort,
            mapping.externalPort,
            Duration.zero,
          ),
        ),
        mapping.internalPort,
        deleting: true,
      );
    }
  }

  @override
  void close() {}

  Future<(InternetAddress, InternetAddress)> _endpoints() async {
    final gw =
        gateway ??
        await LocalNetwork.defaultGateway() ??
        (throw const PortMappingException(
          'шлюз по умолчанию не найден',
          unsupported: true,
        ));
    final local =
        localAddress ??
        await LocalNetwork.addressTowards(gw) ??
        (throw const PortMappingException(
          'нет своего адреса IPv4',
          unsupported: true,
        ));
    return (gw, local);
  }

  /// Отправляет [request] и ждёт ответ шлюза с повторами.
  Future<Uint8List> _exchange(
    InternetAddress gw,
    InternetAddress local,
    Uint8List request,
  ) async {
    final RawDatagramSocket socket;
    try {
      socket = await RawDatagramSocket.bind(
        gw.isLoopback ? InternetAddress.loopbackIPv4 : local,
        0,
      );
    } on SocketException catch (e) {
      throw PortMappingException('UDP-сокет не открылся: ${e.message}');
    }
    final opcode = request[1] | 0x80;
    Completer<Uint8List>? pending;
    final sub = socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final d = socket.receive();
      // Ответ только от шлюза и с его порта (RFC 6886, 3.1).
      if (d == null || d.address != gw || d.port != serverPort) return;
      if (d.data.length < 4 || d.data[1] != opcode) return;
      if (pending case final p? when !p.isCompleted) p.complete(d.data);
    });
    try {
      var wait = firstWait;
      for (var i = 0; i < attempts; i++) {
        final p = pending = Completer<Uint8List>();
        socket.send(request, gw, serverPort);
        try {
          return await p.future.timeout(wait);
        } on TimeoutException {
          // Повтор с удвоенной паузой.
        }
        wait *= 2;
      }
      throw const PortMappingException(
        'шлюз не ответил на PCP и NAT-PMP',
        unsupported: true,
      );
    } finally {
      await sub.cancel();
      socket.close();
    }
  }

  // --- PCP ------------------------------------------------------------

  Uint8List _pcpMapRequest(
    InternetAddress local,
    int internalPort,
    int externalPort,
    Duration lifetime,
  ) {
    final b = ByteData(60)
      ..setUint8(0, _pcpVersion)
      ..setUint8(1, _opMap)
      ..setUint32(4, lifetime.inSeconds)
      ..setUint8(36, _tcp)
      ..setUint16(40, internalPort)
      ..setUint16(42, externalPort)
      // Предлагаемый внешний адрес — «любой IPv4»: ::ffff:0.0.0.0.
      ..setUint8(54, 0xff)
      ..setUint8(55, 0xff);
    _putMappedV4(b, 8, local);
    return b.buffer.asUint8List()..setRange(24, 36, _nonce);
  }

  PortMapping _pcpMapResponse(
    Uint8List r,
    int internalPort, {
    bool deleting = false,
  }) {
    if (r.length < 60) {
      throw const PortMappingException('короткий ответ PCP');
    }
    final b = ByteData.sublistView(r);
    final result = b.getUint8(3);
    if (result != 0) {
      throw PortMappingException(
        'PCP: ${_pcpResults[result] ?? 'код $result'}',
        conflict: result == 11, // CANNOT_PROVIDE_EXTERNAL
      );
    }
    if (!_sameBytes(r.sublist(24, 36), _nonce) ||
        b.getUint8(36) != _tcp ||
        b.getUint16(40) != internalPort) {
      throw const PortMappingException('ответ PCP на другой запрос');
    }
    final external = b.getUint16(42);
    if (!deleting && external == 0) {
      throw const PortMappingException('PCP: роутер не дал внешний порт');
    }
    return PortMapping(
      method: 'pcp',
      internalPort: internalPort,
      externalPort: external,
      externalAddress: _readMappedV4(r, 44),
      lifetime: Duration(seconds: b.getUint32(4)),
      createdAt: _clock(),
    );
  }

  static const _pcpResults = {
    1: 'неподдерживаемая версия',
    2: 'запрещено настройками роутера',
    3: 'неверный запрос',
    4: 'неподдерживаемая операция',
    7: 'неверные параметры',
    8: 'у роутера кончились ресурсы',
    11: 'внешний порт недоступен',
    12: 'адрес клиента не совпал (NAT между узлом и роутером)',
  };

  static void _putMappedV4(ByteData b, int offset, InternetAddress ip) {
    b
      ..setUint8(offset + 10, 0xff)
      ..setUint8(offset + 11, 0xff);
    final raw = ip.rawAddress;
    for (var i = 0; i < 4 && raw.length == 4; i++) {
      b.setUint8(offset + 12 + i, raw[i]);
    }
  }

  static InternetAddress? _readMappedV4(Uint8List r, int offset) {
    for (var i = 0; i < 10; i++) {
      if (r[offset + i] != 0) return null;
    }
    if (r[offset + 10] != 0xff || r[offset + 11] != 0xff) return null;
    return InternetAddress.fromRawAddress(
      Uint8List.fromList(r.sublist(offset + 12, offset + 16)),
    );
  }

  // --- NAT-PMP --------------------------------------------------------

  static Uint8List _natPmpMapRequest(
    int internalPort,
    int externalPort,
    Duration lifetime,
  ) {
    final b = ByteData(12)
      ..setUint8(0, 0)
      ..setUint8(1, 2) // TCP
      ..setUint16(4, internalPort)
      ..setUint16(6, externalPort)
      ..setUint32(8, lifetime.inSeconds);
    return b.buffer.asUint8List();
  }

  PortMapping _natPmpMapResponse(
    Uint8List r,
    int internalPort, {
    bool deleting = false,
  }) {
    if (r.length < 16) {
      throw const PortMappingException('короткий ответ NAT-PMP');
    }
    final b = ByteData.sublistView(r);
    final result = b.getUint16(2);
    if (result != 0) {
      throw PortMappingException(
        'NAT-PMP: ${_natPmpResults[result] ?? 'код $result'}',
      );
    }
    if (b.getUint16(8) != internalPort) {
      throw const PortMappingException('ответ NAT-PMP на другой запрос');
    }
    final external = b.getUint16(10);
    if (!deleting && external == 0) {
      throw const PortMappingException('NAT-PMP: роутер не дал внешний порт');
    }
    return PortMapping(
      method: 'nat-pmp',
      internalPort: internalPort,
      externalPort: external,
      lifetime: Duration(seconds: b.getUint32(12)),
      createdAt: _clock(),
    );
  }

  static InternetAddress _natPmpAddress(Uint8List r) {
    if (r.length < 12 || r[1] != 128) {
      throw const PortMappingException('неверный ответ NAT-PMP');
    }
    if ((r[2] << 8 | r[3]) != 0) {
      throw const PortMappingException('NAT-PMP не сообщил адрес');
    }
    return InternetAddress.fromRawAddress(Uint8List.fromList(r.sublist(8, 12)));
  }

  static const _natPmpResults = {
    1: 'неподдерживаемая версия',
    2: 'запрещено настройками роутера',
    3: 'сбой сети роутера',
    4: 'у роутера кончились ресурсы',
    5: 'неподдерживаемая операция',
  };

  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static Uint8List _secureRandom(int length) {
    final r = Random.secure();
    return Uint8List.fromList(List.generate(length, (_) => r.nextInt(256)));
  }
}
