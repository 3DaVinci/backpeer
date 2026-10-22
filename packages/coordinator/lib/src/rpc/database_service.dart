import 'package:coordinator/src/accounts/account_service.dart';
import 'package:coordinator/src/accounts/certificates.dart';
import 'package:coordinator/src/accounts/login_service.dart';
import 'package:coordinator/src/config.dart';
import 'package:coordinator/src/db/database.dart';
import 'package:coordinator/src/limits/rate_limiter.dart';
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
    DateTime Function()? clock,
  }) : this._parts(db, CertificateChecks(crypto, clock: clock), config, clock);

  new _parts(
    Database db,
    CertificateChecks checks,
    CoordinatorConfig config,
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
      );

  final AccountService accounts;
  final LoginService login;

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
}
