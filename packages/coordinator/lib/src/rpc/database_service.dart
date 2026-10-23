import 'dart:typed_data';

import 'package:coordinator/src/accounts/account_service.dart';
import 'package:coordinator/src/accounts/certificates.dart';
import 'package:coordinator/src/accounts/login_service.dart';
import 'package:coordinator/src/config.dart';
import 'package:coordinator/src/db/database.dart';
import 'package:coordinator/src/limits/rate_limiter.dart';
import 'package:coordinator/src/nodes/node_service.dart';
import 'package:coordinator/src/objects/object_service.dart';
import 'package:coordinator/src/rpc/call_context.dart';
import 'package:coordinator/src/rpc/service.dart';
import 'package:core/core.dart';
import 'package:protocol/protocol.dart' as pb;

/// Методы координатора поверх PostgreSQL. Реализованные группы — по мере
/// задач этапа 2; остальные методы отвечают `INTERNAL` «не реализован».
final class DatabaseCoordinatorService extends CoordinatorService {
  new({
    required Database db,
    required CryptoProvider crypto,
    CoordinatorConfig config = const CoordinatorConfig(),
    List<Uint8List> coordinatorKeys = const [],
    DateTime Function()? clock,
  }) : this._parts(
         db,
         CertificateChecks(crypto, clock: clock),
         config,
         coordinatorKeys,
         clock,
       );

  new _parts(
    Database db,
    CertificateChecks checks,
    CoordinatorConfig config,
    List<Uint8List> coordinatorKeys,
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
        coordinatorKeys: coordinatorKeys,
        clock: clock,
      );

  final AccountService accounts;
  final LoginService login;
  final ObjectService objects;
  final NodeService nodes;

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
}
