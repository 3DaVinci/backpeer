import 'dart:io';

import 'package:cli/src/app_config.dart';
import 'package:core/core.dart';
import 'package:protocol/protocol.dart' as pb;

/// Ошибка сборки сессии, понятная пользователю; [usage] — неверный адрес
/// или настройка, а не сбой.
final class SessionException implements Exception {
  const new(this.message, {this.usage = false});

  final String message;
  final bool usage;

  @override
  String toString() => message;
}

/// Клиент координатора по адресу [url]: `https`, `http` — только к
/// localhost; [ca] — сертификат УЦ стенда в PEM; [device] подписывает
/// запросы.
CoordinatorClient openCoordinatorClient(
  String url, {
  required CryptoProvider crypto,
  required String userAgent,
  String? ca,
  DeviceKeys? device,
}) {
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasAuthority) {
    throw SessionException('Неверный адрес координатора: $url', usage: true);
  }
  SecurityContext? trusted;
  if (ca != null) {
    try {
      trusted = SecurityContext()..setTrustedCertificates(ca);
    } on TlsException catch (e) {
      throw SessionException('Сертификат УЦ $ca не загружен: ${e.message}');
    }
  }
  const local = {'localhost', '127.0.0.1', '::1', '[::1]'};
  if (!uri.isScheme('https') &&
      !(uri.isScheme('http') && local.contains(uri.host))) {
    throw SessionException(
      'Адрес координатора $url: нужен https (http — только к localhost)',
      usage: true,
    );
  }
  return CoordinatorClient(
    baseUri: uri,
    crypto: crypto,
    deviceKey: device?.sign,
    trustedCertificates: trusted,
    userAgent: userAgent,
  );
}

/// Хранилища для работы с данными по настройкам [config] (CLI и агент
/// бэкапа). [keys], [device] и [index] переходят во владение сессии: их
/// освобождает [Session.close], а при ошибке — сама функция.
/// [software] — имя и версия программы для координатора и узлов.
Future<Session> openSession({
  required AppConfig config,
  required CryptoProvider crypto,
  required AccountKeys keys,
  required DeviceKeys? device,
  required LocalIndex index,
  required String software,
}) async {
  void release() {
    index.close();
    keys.dispose();
    device?.dispose();
  }

  final url = config.coordinator;
  if (url == null) {
    final fragments = LocalFolderStore(
      Directory(config.nodes),
      crypto,
      nodeCount: config.nodeCount,
    );
    return Session._(
      keys: keys,
      device: device,
      index: index,
      fragments: fragments,
      objects: LocalObjectStore(Directory(config.objects)),
      releaser: LocalSegmentReleaser(index, fragments),
    );
  }
  if (device == null) {
    release();
    throw const SessionException(
      'На этом устройстве нет ключей устройства для координатора',
    );
  }
  final CoordinatorClient client;
  try {
    client = openCoordinatorClient(
      url,
      crypto: crypto,
      ca: config.coordinatorCa,
      device: device,
      userAgent: software,
    );
  } on Object {
    release();
    rethrow;
  }
  if (config.usesNetwork) {
    try {
      return await _networkSession(
        config,
        crypto,
        keys,
        device,
        index,
        client,
        software,
      );
    } on Object {
      client.close();
      release();
      rethrow;
    }
  }
  final folders = NodeFolders(Directory(config.nodes), crypto);
  final segments = CoordinatorSegments(
    client: client,
    crypto: crypto,
    nodes: folders,
    accountId: keys.accountId,
    fallbackReleaser: LocalSegmentReleaser(index, folders),
    distinctSubnets: config.distinctSubnets,
  );
  return Session._(
    keys: keys,
    device: device,
    index: index,
    fragments: folders,
    objects: CoordinatorObjectStore(client),
    placer: segments,
    locator: segments,
    releaser: segments,
    client: client,
  );
}

/// Фрагменты по сети (задача 3.9): узлы и талоны — из ответов
/// координатора, подключение — стратегией TCP → UDP → relay, трафик по
/// способам уходит координатору при закрытии сессии.
Future<Session> _networkSession(
  AppConfig config,
  CryptoProvider crypto,
  AccountKeys keys,
  DeviceKeys device,
  LocalIndex index,
  CoordinatorClient client,
  String software,
) async {
  // Сертификат устройства для Hello: его выпускает ключ учётной записи,
  // который сессия уже открыла.
  final certificate = await DeviceCertificates.issue(
    crypto,
    keys,
    device,
    issuedAt: DateTime.now(),
  );
  final meter = TrafficMeter();
  final book = TicketBook();
  // Пределы скорости сети из `config.json` (0 — без предела): один на
  // отдачу фрагментов и один на приём, общие для всех узлов сессии.
  final upload = config.uploadBytesPerSecond;
  final download = config.downloadBytesPerSecond;
  final store = NetworkFragmentStore(
    crypto: crypto,
    transport: ConnectionStrategy.forCoordinator(
      crypto: crypto,
      local: LocalPeer(
        role: pb.PeerRole.PEER_ROLE_CLIENT,
        staticKey: device.dh,
        certificate: certificate,
        software: software,
      ),
      client: client,
      meter: meter,
    ),
    access: book,
    uploadLimiter: upload > 0 ? BandwidthLimiter(() => upload) : null,
    downloadLimiter: download > 0 ? BandwidthLimiter(() => download) : null,
  );
  final segments = CoordinatorSegments(
    client: client,
    crypto: crypto,
    nodes: store,
    accountId: keys.accountId,
    tickets: book,
    fallbackReleaser: const _ForgottenSegment(),
    distinctSubnets: config.distinctSubnets,
  );
  return Session._(
    keys: keys,
    device: device,
    index: index,
    fragments: store,
    objects: CoordinatorObjectStore(client),
    placer: segments,
    locator: segments,
    releaser: segments,
    client: client,
    onClose: () async {
      await store.close();
      await TrafficReporter(client: client, meter: meter).report();
    },
  );
}

/// Сегмент, которого координатор уже не знает (повтор сборки мусора после
/// обрыва), по сети: талонов DELETE на его фрагменты нет, удалять нечего —
/// фрагменты без ссылок убирает узел (этап 4).
final class _ForgottenSegment implements SegmentReleaser {
  const new();

  @override
  Future<List<FragmentLocation>> release(SegmentEntry segment) async =>
      const [];
}

/// Ключи и хранилища одной команды: без координатора — папки-«узлы» и папка
/// объектов, с координатором — объекты и размещение на нём, фрагменты на
/// узлах по сети или в папках-«узлах», зарегистрированных на координаторе.
final class Session {
  new _({
    required this.keys,
    required this.device,
    required this.index,
    required this.fragments,
    required this.objects,
    required this.releaser,
    this.placer,
    this.locator,
    this.client,
    this.onClose,
  });

  final AccountKeys keys;
  final DeviceKeys? device;
  final LocalIndex index;
  final FragmentStore fragments;
  final ObjectStore objects;
  final SegmentReleaser releaser;
  final SegmentPlacer? placer;
  final SegmentLocator? locator;
  final CoordinatorClient? client;
  final Future<void> Function()? onClose;

  /// Закрывает соединения с узлами, отправляет отчёт о трафике.
  Future<void> close() async {
    try {
      await onClose?.call();
    } on CoreException {
      // Отчёт о трафике не дошёл — не повод ронять команду.
    } finally {
      index.close();
      keys.dispose();
      device?.dispose();
      client?.close();
    }
  }
}
