import 'package:coordinator/src/rpc/call_context.dart';
import 'package:coordinator/src/rpc/errors.dart';
import 'package:protocol/protocol.dart' as pb;

/// Методы API координатора (`coordinator.proto`). По умолчанию каждый
/// отвечает `INTERNAL` «не реализован»; реализации появляются в задачах
/// 2.3–2.7 и переопределяют нужные методы.
///
/// Подпись запроса уже проверена ([CallContext.caller]); обработчик
/// проверяет поля запроса и права на объект. Ошибка — [RpcException].
abstract base class CoordinatorService {
  const new();

  Future<pb.RegisterAccountResponse> registerAccount(
    CallContext context,
    pb.RegisterAccountRequest request,
  ) => _unimplemented(context);

  Future<pb.AddDeviceResponse> addDevice(
    CallContext context,
    pb.AddDeviceRequest request,
  ) => _unimplemented(context);

  Future<pb.RevokeDeviceResponse> revokeDevice(
    CallContext context,
    pb.RevokeDeviceRequest request,
  ) => _unimplemented(context);

  Future<pb.ListDevicesResponse> listDevices(
    CallContext context,
    pb.ListDevicesRequest request,
  ) => _unimplemented(context);

  Future<pb.ListRevocationsResponse> listRevocations(
    CallContext context,
    pb.ListRevocationsRequest request,
  ) => _unimplemented(context);

  Future<pb.GetLoginParamsResponse> getLoginParams(
    CallContext context,
    pb.GetLoginParamsRequest request,
  ) => _unimplemented(context);

  Future<pb.SetKeyBundleResponse> setKeyBundle(
    CallContext context,
    pb.SetKeyBundleRequest request,
  ) => _unimplemented(context);

  Future<pb.GetKeyBundleResponse> getKeyBundle(
    CallContext context,
    pb.GetKeyBundleRequest request,
  ) => _unimplemented(context);

  Future<pb.PutObjectResponse> putObject(
    CallContext context,
    pb.PutObjectRequest request,
  ) => _unimplemented(context);

  Future<pb.ListObjectsResponse> listObjects(
    CallContext context,
    pb.ListObjectsRequest request,
  ) => _unimplemented(context);

  Future<pb.GetObjectResponse> getObject(
    CallContext context,
    pb.GetObjectRequest request,
  ) => _unimplemented(context);

  Future<pb.DeleteObjectResponse> deleteObject(
    CallContext context,
    pb.DeleteObjectRequest request,
  ) => _unimplemented(context);

  Future<pb.AllocateSegmentResponse> allocateSegment(
    CallContext context,
    pb.AllocateSegmentRequest request,
  ) => _unimplemented(context);

  Future<pb.CommitSegmentResponse> commitSegment(
    CallContext context,
    pb.CommitSegmentRequest request,
  ) => _unimplemented(context);

  Future<pb.LocateSegmentResponse> locateSegment(
    CallContext context,
    pb.LocateSegmentRequest request,
  ) => _unimplemented(context);

  Future<pb.DeleteSegmentResponse> deleteSegment(
    CallContext context,
    pb.DeleteSegmentRequest request,
  ) => _unimplemented(context);

  Future<pb.RegisterNodeResponse> registerNode(
    CallContext context,
    pb.RegisterNodeRequest request,
  ) => _unimplemented(context);

  Future<pb.HeartbeatResponse> heartbeat(
    CallContext context,
    pb.HeartbeatRequest request,
  ) => _unimplemented(context);

  Future<pb.ReportDamagedFragmentsResponse> reportDamagedFragments(
    CallContext context,
    pb.ReportDamagedFragmentsRequest request,
  ) => _unimplemented(context);

  Future<pb.ReportRepairResponse> reportRepair(
    CallContext context,
    pb.ReportRepairRequest request,
  ) => _unimplemented(context);

  Future<pb.LeaveNetworkResponse> leaveNetwork(
    CallContext context,
    pb.LeaveNetworkRequest request,
  ) => _unimplemented(context);

  Future<pb.ReconcileFragmentsResponse> reconcileFragments(
    CallContext context,
    pb.ReconcileFragmentsRequest request,
  ) => _unimplemented(context);

  Future<pb.GetBackupHealthResponse> getBackupHealth(
    CallContext context,
    pb.GetBackupHealthRequest request,
  ) => _unimplemented(context);

  Future<pb.CheckReachabilityResponse> checkReachability(
    CallContext context,
    pb.CheckReachabilityRequest request,
  ) => _unimplemented(context);

  Future<pb.GetRendezvousInfoResponse> getRendezvousInfo(
    CallContext context,
    pb.GetRendezvousInfoRequest request,
  ) => _unimplemented(context);

  Future<pb.RendezvousResponse> rendezvous(
    CallContext context,
    pb.RendezvousRequest request,
  ) => _unimplemented(context);

  Future<pb.GetRelayPassResponse> getRelayPass(
    CallContext context,
    pb.GetRelayPassRequest request,
  ) => _unimplemented(context);

  Future<pb.ReportRelayUsageResponse> reportRelayUsage(
    CallContext context,
    pb.ReportRelayUsageRequest request,
  ) => _unimplemented(context);

  Future<pb.ReportTrafficResponse> reportTraffic(
    CallContext context,
    pb.ReportTrafficRequest request,
  ) => _unimplemented(context);

  static Never _unimplemented(CallContext context) => throw RpcException(
    pb.ErrorCode.ERROR_CODE_INTERNAL,
    'метод ${context.method} не реализован',
  );
}

/// Сервис, в котором ни один метод не реализован (каркас 2.1.2).
final class UnimplementedCoordinatorService extends CoordinatorService {
  const new();
}
