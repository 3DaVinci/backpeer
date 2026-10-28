import 'dart:typed_data';

import 'package:coordinator/src/auth/request_verifier.dart';
import 'package:coordinator/src/rpc/call_context.dart';
import 'package:coordinator/src/rpc/errors.dart';
import 'package:coordinator/src/rpc/service.dart';
import 'package:core/core.dart';
import 'package:protobuf/protobuf.dart';
import 'package:protocol/protocol.dart' as pb;

/// Предел тела запроса по умолчанию (protocol.md, раздел 4.1).
const int defaultMaxBody = 64 * 1024;

/// Предел тела `PutObject`: блоб до 8 МиБ и поля сообщения.
const int putObjectMaxBody = 8 * 1024 * 1024 + 64 * 1024;

/// Метод API: `POST /api/v1/<name>`.
final class RpcMethod<Q extends GeneratedMessage, R extends GeneratedMessage> {
  const new({
    required this.name,
    required this.auth,
    required this.parse,
    required this.handle,
    this.maxBodyBytes = defaultMaxBody,
  });

  final String name;
  final AuthRequirement auth;
  final Q Function(List<int> body) parse;
  final Future<R> Function(CallContext context, Q request) handle;
  final int maxBodyBytes;

  String get path => '/api/v1/$name';

  /// Разбирает тело, вызывает обработчик и сериализует ответ. Тело, которое
  /// не разбирается, — `BAD_REQUEST`.
  Future<Uint8List> call(CallContext context, List<int> body) async {
    final Q request;
    try {
      // Обёртка ловит и ArgumentError пакета protobuf на битых данных
      // (находка фаззинга 1.8.5).
      request = ManifestObjects.parseMessage(name, () => parse(body));
    } on DataFormatException {
      throw RpcException(
        pb.ErrorCode.ERROR_CODE_BAD_REQUEST,
        'тело не разбирается как ${name}Request',
      );
    }
    final response = await handle(context, request);
    return response.writeToBuffer();
  }
}

/// Таблица методов `coordinator.proto` с требованиями к подписи
/// (protocol.md, раздел 4.3) и пределами тела.
List<RpcMethod> coordinatorMethods(CoordinatorService s) => [
  RpcMethod<pb.RegisterAccountRequest, pb.RegisterAccountResponse>(
    name: 'RegisterAccount',
    auth: AuthRequirement.registering,
    parse: pb.RegisterAccountRequest.fromBuffer,
    handle: s.registerAccount,
  ),
  RpcMethod<pb.AddDeviceRequest, pb.AddDeviceResponse>(
    name: 'AddDevice',
    auth: AuthRequirement.account,
    parse: pb.AddDeviceRequest.fromBuffer,
    handle: s.addDevice,
  ),
  RpcMethod<pb.ListDevicesRequest, pb.ListDevicesResponse>(
    name: 'ListDevices',
    auth: AuthRequirement.account,
    parse: pb.ListDevicesRequest.fromBuffer,
    handle: s.listDevices,
  ),
  RpcMethod<pb.RevokeDeviceRequest, pb.RevokeDeviceResponse>(
    name: 'RevokeDevice',
    auth: AuthRequirement.account,
    parse: pb.RevokeDeviceRequest.fromBuffer,
    handle: s.revokeDevice,
  ),
  RpcMethod<pb.ListRevocationsRequest, pb.ListRevocationsResponse>(
    name: 'ListRevocations',
    auth: AuthRequirement.node,
    parse: pb.ListRevocationsRequest.fromBuffer,
    handle: s.listRevocations,
  ),
  RpcMethod<pb.GetLoginParamsRequest, pb.GetLoginParamsResponse>(
    name: 'GetLoginParams',
    auth: AuthRequirement.none,
    parse: pb.GetLoginParamsRequest.fromBuffer,
    handle: s.getLoginParams,
  ),
  RpcMethod<pb.GetKeyBundleRequest, pb.GetKeyBundleResponse>(
    name: 'GetKeyBundle',
    auth: AuthRequirement.none,
    parse: pb.GetKeyBundleRequest.fromBuffer,
    handle: s.getKeyBundle,
  ),
  RpcMethod<pb.SetKeyBundleRequest, pb.SetKeyBundleResponse>(
    name: 'SetKeyBundle',
    auth: AuthRequirement.account,
    parse: pb.SetKeyBundleRequest.fromBuffer,
    handle: s.setKeyBundle,
  ),
  RpcMethod<pb.PutObjectRequest, pb.PutObjectResponse>(
    name: 'PutObject',
    auth: AuthRequirement.device,
    parse: pb.PutObjectRequest.fromBuffer,
    handle: s.putObject,
    maxBodyBytes: putObjectMaxBody,
  ),
  RpcMethod<pb.ListObjectsRequest, pb.ListObjectsResponse>(
    name: 'ListObjects',
    auth: AuthRequirement.device,
    parse: pb.ListObjectsRequest.fromBuffer,
    handle: s.listObjects,
  ),
  RpcMethod<pb.GetObjectRequest, pb.GetObjectResponse>(
    name: 'GetObject',
    auth: AuthRequirement.device,
    parse: pb.GetObjectRequest.fromBuffer,
    handle: s.getObject,
  ),
  RpcMethod<pb.DeleteObjectRequest, pb.DeleteObjectResponse>(
    name: 'DeleteObject',
    auth: AuthRequirement.device,
    parse: pb.DeleteObjectRequest.fromBuffer,
    handle: s.deleteObject,
  ),
  RpcMethod<pb.AllocateSegmentRequest, pb.AllocateSegmentResponse>(
    name: 'AllocateSegment',
    auth: AuthRequirement.device,
    parse: pb.AllocateSegmentRequest.fromBuffer,
    handle: s.allocateSegment,
  ),
  RpcMethod<pb.CommitSegmentRequest, pb.CommitSegmentResponse>(
    name: 'CommitSegment',
    auth: AuthRequirement.device,
    parse: pb.CommitSegmentRequest.fromBuffer,
    handle: s.commitSegment,
  ),
  RpcMethod<pb.LocateSegmentRequest, pb.LocateSegmentResponse>(
    name: 'LocateSegment',
    auth: AuthRequirement.device,
    parse: pb.LocateSegmentRequest.fromBuffer,
    handle: s.locateSegment,
  ),
  RpcMethod<pb.DeleteSegmentRequest, pb.DeleteSegmentResponse>(
    name: 'DeleteSegment',
    auth: AuthRequirement.device,
    parse: pb.DeleteSegmentRequest.fromBuffer,
    handle: s.deleteSegment,
  ),
  RpcMethod<pb.RegisterNodeRequest, pb.RegisterNodeResponse>(
    name: 'RegisterNode',
    auth: AuthRequirement.registering,
    parse: pb.RegisterNodeRequest.fromBuffer,
    handle: s.registerNode,
  ),
  RpcMethod<pb.HeartbeatRequest, pb.HeartbeatResponse>(
    name: 'Heartbeat',
    auth: AuthRequirement.node,
    parse: pb.HeartbeatRequest.fromBuffer,
    handle: s.heartbeat,
  ),
  RpcMethod<
    pb.ReportDamagedFragmentsRequest,
    pb.ReportDamagedFragmentsResponse
  >(
    name: 'ReportDamagedFragments',
    auth: AuthRequirement.node,
    parse: pb.ReportDamagedFragmentsRequest.fromBuffer,
    handle: s.reportDamagedFragments,
  ),
  RpcMethod<pb.ReportRepairRequest, pb.ReportRepairResponse>(
    name: 'ReportRepair',
    auth: AuthRequirement.node,
    parse: pb.ReportRepairRequest.fromBuffer,
    handle: s.reportRepair,
  ),
  RpcMethod<pb.CheckReachabilityRequest, pb.CheckReachabilityResponse>(
    name: 'CheckReachability',
    auth: AuthRequirement.node,
    parse: pb.CheckReachabilityRequest.fromBuffer,
    handle: s.checkReachability,
  ),
  RpcMethod<pb.GetRendezvousInfoRequest, pb.GetRendezvousInfoResponse>(
    name: 'GetRendezvousInfo',
    auth: AuthRequirement.deviceOrNode,
    parse: pb.GetRendezvousInfoRequest.fromBuffer,
    handle: s.getRendezvousInfo,
  ),
  RpcMethod<pb.RendezvousRequest, pb.RendezvousResponse>(
    name: 'Rendezvous',
    auth: AuthRequirement.deviceOrNode,
    parse: pb.RendezvousRequest.fromBuffer,
    handle: s.rendezvous,
  ),
  RpcMethod<pb.GetRelayPassRequest, pb.GetRelayPassResponse>(
    name: 'GetRelayPass',
    auth: AuthRequirement.deviceOrNode,
    parse: pb.GetRelayPassRequest.fromBuffer,
    handle: s.getRelayPass,
  ),
  RpcMethod<pb.ReportRelayUsageRequest, pb.ReportRelayUsageResponse>(
    name: 'ReportRelayUsage',
    auth: AuthRequirement.relay,
    parse: pb.ReportRelayUsageRequest.fromBuffer,
    handle: s.reportRelayUsage,
    // До 10 000 учётных записей в отчёте.
    maxBodyBytes: 1 << 20,
  ),
  RpcMethod<pb.ReportTrafficRequest, pb.ReportTrafficResponse>(
    name: 'ReportTraffic',
    auth: AuthRequirement.deviceOrNode,
    parse: pb.ReportTrafficRequest.fromBuffer,
    handle: s.reportTraffic,
  ),
];
