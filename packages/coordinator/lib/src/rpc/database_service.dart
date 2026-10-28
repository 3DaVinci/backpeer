import 'package:coordinator/src/accounts/account_service.dart';
import 'package:coordinator/src/accounts/certificates.dart';
import 'package:coordinator/src/accounts/login_service.dart';
import 'package:coordinator/src/audits/audit_service.dart';
import 'package:coordinator/src/config.dart';
import 'package:coordinator/src/db/database.dart';
import 'package:coordinator/src/db/postgres_key_directory.dart';
import 'package:coordinator/src/nodes/node_service.dart';
import 'package:coordinator/src/nodes/rendezvous.dart';
import 'package:coordinator/src/objects/object_service.dart';
import 'package:coordinator/src/placement/placement.dart';
import 'package:coordinator/src/relay/relay_service.dart';
import 'package:coordinator/src/repair/repair_service.dart';
import 'package:coordinator/src/rpc/call_context.dart';
import 'package:coordinator/src/rpc/service.dart';
import 'package:coordinator/src/segments/segment_service.dart';
import 'package:coordinator/src/signer/ticket_signer.dart';
import 'package:core/core.dart';
import 'package:protocol/protocol.dart' as pb;

/// Методы координатора поверх PostgreSQL. Талоны подписывает [TicketSigner]
/// (в бою — отдельный процесс, `SocketTicketSigner`); без него методы
/// размещения отвечают `UNAVAILABLE`.
final class DatabaseCoordinatorService extends CoordinatorService {
  new({
    required Database db,
    required CryptoProvider crypto,
    CoordinatorConfig config = const CoordinatorConfig(),
    TicketSigner? signer,
    Placement? placement,
    Ed25519KeyPair? relayPassKey,
    DateTime Function()? clock,
  }) : this._parts(
         db,
         crypto,
         CertificateChecks(crypto, clock: clock),
         config,
         signer,
         placement,
         relayPassKey,
         clock,
       );

  new _parts(
    Database db,
    CryptoProvider crypto,
    CertificateChecks checks,
    CoordinatorConfig config,
    TicketSigner? signer,
    Placement? placement,
    Ed25519KeyPair? relayPassKey,
    DateTime Function()? clock,
  ) : accounts = AccountService(
        db,
        checks,
        maxDevices: config.maxDevicesPerAccount,
        clock: clock,
      ),
      login = LoginService(
        db,
        checks,
        ipLimiter: RateLimiter(
          perSecond: config.limits.loginPerMinute / 60,
          burst: config.limits.loginBurst,
          clock: clock,
        ),
        clock: clock,
      ),
      objects = ObjectService(
        db,
        maxAccountBytes: config.maxObjectBytesPerAccount,
        clock: clock,
      ),
      nodes = NodeService(
        db,
        checks,
        policy: config.nodes,
        coordinatorKeys: signer == null
            ? null
            : () async => [await signer.publicKey()],
        clock: clock,
      ),
      relay = RelayService(
        db: db,
        crypto: crypto,
        policy: config.relay,
        passKey: relayPassKey,
        clock: clock,
      ),
      audits = AuditService(
        db,
        crypto: crypto,
        policy: config.audits,
        clock: clock,
      ) {
    rendezvousService = RendezvousService(
      crypto: crypto,
      keys: PostgresKeyDirectory(db),
      policy: config.rendezvous,
      clock: clock,
    );
    segments = SegmentService(
      db,
      nodes,
      crypto: crypto,
      signer: signer,
      policy: config.placement,
      placement: placement,
      clock: clock,
    );
    repair = RepairService(
      db,
      crypto: crypto,
      nodes: nodes,
      signer: signer,
      policy: config.repair,
      placementPolicy: config.placement,
      clock: clock,
    );
  }

  /// Сведение узлов; каналы команд ему передаёт сервер.
  late final RendezvousService rendezvousService;

  final AccountService accounts;
  final LoginService login;
  final ObjectService objects;
  final NodeService nodes;
  late final SegmentService segments;

  /// Пропуска relay, отчёты relay и трафика; ключ пропусков — из
  /// `relay.pass_key_file` (`CoordinatorServer.start`).
  final RelayService relay;

  /// Аудиты хранения; каналы команд ему передаёт сервер.
  final AuditService audits;

  /// Ремонт сегментов; каналы команд ему передаёт сервер.
  late final RepairService repair;

  @override
  Future<pb.RegisterAccountResponse> registerAccount(
    CallContext context,
    pb.RegisterAccountRequest request,
  ) => accounts.register(context, request);

  @override
  Future<pb.AddDeviceResponse> addDevice(
    CallContext context,
    pb.AddDeviceRequest request,
  ) => accounts.addDevice(context, request);

  @override
  Future<pb.ListDevicesResponse> listDevices(
    CallContext context,
    pb.ListDevicesRequest request,
  ) => accounts.listDevices(context, request);

  @override
  Future<pb.RevokeDeviceResponse> revokeDevice(
    CallContext context,
    pb.RevokeDeviceRequest request,
  ) => accounts.revokeDevice(context, request);

  @override
  Future<pb.ListRevocationsResponse> listRevocations(
    CallContext context,
    pb.ListRevocationsRequest request,
  ) => accounts.listRevocations(context, request);

  @override
  Future<pb.GetLoginParamsResponse> getLoginParams(
    CallContext context,
    pb.GetLoginParamsRequest request,
  ) => login.getLoginParams(context, request);

  @override
  Future<pb.GetKeyBundleResponse> getKeyBundle(
    CallContext context,
    pb.GetKeyBundleRequest request,
  ) => login.getKeyBundle(context, request);

  @override
  Future<pb.SetKeyBundleResponse> setKeyBundle(
    CallContext context,
    pb.SetKeyBundleRequest request,
  ) => login.setKeyBundle(context, request);

  @override
  Future<pb.PutObjectResponse> putObject(
    CallContext context,
    pb.PutObjectRequest request,
  ) => objects.put(context, request);

  @override
  Future<pb.ListObjectsResponse> listObjects(
    CallContext context,
    pb.ListObjectsRequest request,
  ) => objects.list(context, request);

  @override
  Future<pb.GetObjectResponse> getObject(
    CallContext context,
    pb.GetObjectRequest request,
  ) => objects.get(context, request);

  @override
  Future<pb.DeleteObjectResponse> deleteObject(
    CallContext context,
    pb.DeleteObjectRequest request,
  ) => objects.delete(context, request);

  @override
  Future<pb.RegisterNodeResponse> registerNode(
    CallContext context,
    pb.RegisterNodeRequest request,
  ) => nodes.register(context, request);

  @override
  Future<pb.HeartbeatResponse> heartbeat(
    CallContext context,
    pb.HeartbeatRequest request,
  ) => nodes.heartbeat(context, request);

  @override
  Future<pb.ReportDamagedFragmentsResponse> reportDamagedFragments(
    CallContext context,
    pb.ReportDamagedFragmentsRequest request,
  ) => nodes.reportDamaged(context, request);

  @override
  Future<pb.ReportRepairResponse> reportRepair(
    CallContext context,
    pb.ReportRepairRequest request,
  ) => repair.report(context, request);

  @override
  Future<pb.LeaveNetworkResponse> leaveNetwork(
    CallContext context,
    pb.LeaveNetworkRequest request,
  ) => repair.leave(context, request);

  @override
  Future<pb.ReconcileFragmentsResponse> reconcileFragments(
    CallContext context,
    pb.ReconcileFragmentsRequest request,
  ) => repair.reconcile(context, request);

  @override
  Future<pb.CheckReachabilityResponse> checkReachability(
    CallContext context,
    pb.CheckReachabilityRequest request,
  ) => nodes.checkReachability(context, request);

  @override
  Future<pb.GetRendezvousInfoResponse> getRendezvousInfo(
    CallContext context,
    pb.GetRendezvousInfoRequest request,
  ) => rendezvousService.info(context, request);

  @override
  Future<pb.RendezvousResponse> rendezvous(
    CallContext context,
    pb.RendezvousRequest request,
  ) => rendezvousService.rendezvous(context, request);

  @override
  Future<pb.GetRelayPassResponse> getRelayPass(
    CallContext context,
    pb.GetRelayPassRequest request,
  ) => relay.getPass(context, request);

  @override
  Future<pb.ReportRelayUsageResponse> reportRelayUsage(
    CallContext context,
    pb.ReportRelayUsageRequest request,
  ) => relay.report(context, request);

  @override
  Future<pb.ReportTrafficResponse> reportTraffic(
    CallContext context,
    pb.ReportTrafficRequest request,
  ) => relay.traffic(context, request);

  @override
  Future<pb.AllocateSegmentResponse> allocateSegment(
    CallContext context,
    pb.AllocateSegmentRequest request,
  ) => segments.allocate(context, request);

  @override
  Future<pb.CommitSegmentResponse> commitSegment(
    CallContext context,
    pb.CommitSegmentRequest request,
  ) => segments.commit(context, request);

  @override
  Future<pb.LocateSegmentResponse> locateSegment(
    CallContext context,
    pb.LocateSegmentRequest request,
  ) => segments.locate(context, request);

  @override
  Future<pb.DeleteSegmentResponse> deleteSegment(
    CallContext context,
    pb.DeleteSegmentRequest request,
  ) => segments.delete(context, request);
}
