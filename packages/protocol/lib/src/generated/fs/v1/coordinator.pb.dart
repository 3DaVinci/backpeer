// This is a generated file - do not edit.
//
// Generated from fs/v1/coordinator.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'common.pb.dart' as $0;
import 'coordinator.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'coordinator.pbenum.dart';

/// Регистрация учётной записи. Запрос подписан ключом учётной записи
/// (контекст "api-request"), а не устройства. Правила — protocol.md,
/// раздел 4.7.
class RegisterAccountRequest extends $pb.GeneratedMessage {
  factory RegisterAccountRequest({
    $0.Signed? deviceCertificate,
    $core.List<$core.int>? keyBundle,
    $core.List<$core.int>? authVerifier,
    $core.String? login,
  }) {
    final result = RegisterAccountRequest._();
    if (deviceCertificate != null) result.deviceCertificate = deviceCertificate;
    if (keyBundle != null) result.keyBundle = keyBundle;
    if (authVerifier != null) result.authVerifier = authVerifier;
    if (login != null) result.login = login;
    return result;
  }

  RegisterAccountRequest._();

  factory RegisterAccountRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RegisterAccountRequest()..mergeFromBuffer(data, registry);
  factory RegisterAccountRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RegisterAccountRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RegisterAccountRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: RegisterAccountRequest.$_createMessage)
    ..aOM<$0.Signed>(1, _omitFieldNames ? '' : 'deviceCertificate',
        subBuilder: $0.Signed.$_createMessage)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'keyBundle', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'authVerifier', $pb.PbFieldType.OY)
    ..aOS(4, _omitFieldNames ? '' : 'login')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RegisterAccountRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RegisterAccountRequest copyWith(
          void Function(RegisterAccountRequest) updates) =>
      super.copyWith((message) => updates(message as RegisterAccountRequest))
          as RegisterAccountRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use RegisterAccountRequest() / RegisterAccountRequest.new instead')
  static RegisterAccountRequest create() => RegisterAccountRequest._();
  static $pb.GeneratedMessage $_createMessage() => RegisterAccountRequest._();
  @$core.override
  RegisterAccountRequest createEmptyInstance() => RegisterAccountRequest._();
  @$core.pragma('dart2js:noInline')
  static RegisterAccountRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RegisterAccountRequest>(
          RegisterAccountRequest.$_createMessage);
  static RegisterAccountRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $0.Signed get deviceCertificate => $_getN(0);
  @$pb.TagNumber(1)
  set deviceCertificate($0.Signed value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasDeviceCertificate() => $_has(0);
  @$pb.TagNumber(1)
  void clearDeviceCertificate() => $_clearField(1);
  @$pb.TagNumber(1)
  $0.Signed ensureDeviceCertificate() => $_ensure(0);

  @$pb.TagNumber(2)
  $core.List<$core.int> get keyBundle => $_getN(1);
  @$pb.TagNumber(2)
  set keyBundle($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasKeyBundle() => $_has(1);
  @$pb.TagNumber(2)
  void clearKeyBundle() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get authVerifier => $_getN(2);
  @$pb.TagNumber(3)
  set authVerifier($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(3)
  $core.bool hasAuthVerifier() => $_has(2);
  @$pb.TagNumber(3)
  void clearAuthVerifier() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get login => $_getSZ(3);
  @$pb.TagNumber(4)
  set login($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasLogin() => $_has(3);
  @$pb.TagNumber(4)
  void clearLogin() => $_clearField(4);
}

class RegisterAccountResponse extends $pb.GeneratedMessage {
  factory RegisterAccountResponse() => RegisterAccountResponse._();

  RegisterAccountResponse._();

  factory RegisterAccountResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RegisterAccountResponse()..mergeFromBuffer(data, registry);
  factory RegisterAccountResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RegisterAccountResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RegisterAccountResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: RegisterAccountResponse.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RegisterAccountResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RegisterAccountResponse copyWith(
          void Function(RegisterAccountResponse) updates) =>
      super.copyWith((message) => updates(message as RegisterAccountResponse))
          as RegisterAccountResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use RegisterAccountResponse() / RegisterAccountResponse.new instead')
  static RegisterAccountResponse create() => RegisterAccountResponse._();
  static $pb.GeneratedMessage $_createMessage() => RegisterAccountResponse._();
  @$core.override
  RegisterAccountResponse createEmptyInstance() => RegisterAccountResponse._();
  @$core.pragma('dart2js:noInline')
  static RegisterAccountResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RegisterAccountResponse>(
          RegisterAccountResponse.$_createMessage);
  static RegisterAccountResponse? _defaultInstance;
}

class AddDeviceRequest extends $pb.GeneratedMessage {
  factory AddDeviceRequest({
    $0.Signed? deviceCertificate,
  }) {
    final result = AddDeviceRequest._();
    if (deviceCertificate != null) result.deviceCertificate = deviceCertificate;
    return result;
  }

  AddDeviceRequest._();

  factory AddDeviceRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      AddDeviceRequest()..mergeFromBuffer(data, registry);
  factory AddDeviceRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      AddDeviceRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AddDeviceRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: AddDeviceRequest.$_createMessage)
    ..aOM<$0.Signed>(1, _omitFieldNames ? '' : 'deviceCertificate',
        subBuilder: $0.Signed.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AddDeviceRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AddDeviceRequest copyWith(void Function(AddDeviceRequest) updates) =>
      super.copyWith((message) => updates(message as AddDeviceRequest))
          as AddDeviceRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use AddDeviceRequest() / AddDeviceRequest.new instead')
  static AddDeviceRequest create() => AddDeviceRequest._();
  static $pb.GeneratedMessage $_createMessage() => AddDeviceRequest._();
  @$core.override
  AddDeviceRequest createEmptyInstance() => AddDeviceRequest._();
  @$core.pragma('dart2js:noInline')
  static AddDeviceRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<AddDeviceRequest>(
          AddDeviceRequest.$_createMessage);
  static AddDeviceRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $0.Signed get deviceCertificate => $_getN(0);
  @$pb.TagNumber(1)
  set deviceCertificate($0.Signed value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasDeviceCertificate() => $_has(0);
  @$pb.TagNumber(1)
  void clearDeviceCertificate() => $_clearField(1);
  @$pb.TagNumber(1)
  $0.Signed ensureDeviceCertificate() => $_ensure(0);
}

class AddDeviceResponse extends $pb.GeneratedMessage {
  factory AddDeviceResponse() => AddDeviceResponse._();

  AddDeviceResponse._();

  factory AddDeviceResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      AddDeviceResponse()..mergeFromBuffer(data, registry);
  factory AddDeviceResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      AddDeviceResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AddDeviceResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: AddDeviceResponse.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AddDeviceResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AddDeviceResponse copyWith(void Function(AddDeviceResponse) updates) =>
      super.copyWith((message) => updates(message as AddDeviceResponse))
          as AddDeviceResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use AddDeviceResponse() / AddDeviceResponse.new instead')
  static AddDeviceResponse create() => AddDeviceResponse._();
  static $pb.GeneratedMessage $_createMessage() => AddDeviceResponse._();
  @$core.override
  AddDeviceResponse createEmptyInstance() => AddDeviceResponse._();
  @$core.pragma('dart2js:noInline')
  static AddDeviceResponse getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<AddDeviceResponse>(
          AddDeviceResponse.$_createMessage);
  static AddDeviceResponse? _defaultInstance;
}

/// Устройства учётной записи, включая отозванные.
class ListDevicesRequest extends $pb.GeneratedMessage {
  factory ListDevicesRequest() => ListDevicesRequest._();

  ListDevicesRequest._();

  factory ListDevicesRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListDevicesRequest()..mergeFromBuffer(data, registry);
  factory ListDevicesRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListDevicesRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListDevicesRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: ListDevicesRequest.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListDevicesRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListDevicesRequest copyWith(void Function(ListDevicesRequest) updates) =>
      super.copyWith((message) => updates(message as ListDevicesRequest))
          as ListDevicesRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ListDevicesRequest() / ListDevicesRequest.new instead')
  static ListDevicesRequest create() => ListDevicesRequest._();
  static $pb.GeneratedMessage $_createMessage() => ListDevicesRequest._();
  @$core.override
  ListDevicesRequest createEmptyInstance() => ListDevicesRequest._();
  @$core.pragma('dart2js:noInline')
  static ListDevicesRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListDevicesRequest>(
          ListDevicesRequest.$_createMessage);
  static ListDevicesRequest? _defaultInstance;
}

class ListDevicesResponse extends $pb.GeneratedMessage {
  factory ListDevicesResponse({
    $core.Iterable<DeviceInfo>? devices,
  }) {
    final result = ListDevicesResponse._();
    if (devices != null) result.devices.addAll(devices);
    return result;
  }

  ListDevicesResponse._();

  factory ListDevicesResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListDevicesResponse()..mergeFromBuffer(data, registry);
  factory ListDevicesResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListDevicesResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListDevicesResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: ListDevicesResponse.$_createMessage)
    ..pPM<DeviceInfo>(1, _omitFieldNames ? '' : 'devices',
        subBuilder: DeviceInfo.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListDevicesResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListDevicesResponse copyWith(void Function(ListDevicesResponse) updates) =>
      super.copyWith((message) => updates(message as ListDevicesResponse))
          as ListDevicesResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use ListDevicesResponse() / ListDevicesResponse.new instead')
  static ListDevicesResponse create() => ListDevicesResponse._();
  static $pb.GeneratedMessage $_createMessage() => ListDevicesResponse._();
  @$core.override
  ListDevicesResponse createEmptyInstance() => ListDevicesResponse._();
  @$core.pragma('dart2js:noInline')
  static ListDevicesResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListDevicesResponse>(
          ListDevicesResponse.$_createMessage);
  static ListDevicesResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<DeviceInfo> get devices => $_getList(0);
}

class DeviceInfo extends $pb.GeneratedMessage {
  factory DeviceInfo({
    $0.Signed? certificate,
    $fixnum.Int64? addedAtUnixMs,
    $fixnum.Int64? revokedAtUnixMs,
  }) {
    final result = DeviceInfo._();
    if (certificate != null) result.certificate = certificate;
    if (addedAtUnixMs != null) result.addedAtUnixMs = addedAtUnixMs;
    if (revokedAtUnixMs != null) result.revokedAtUnixMs = revokedAtUnixMs;
    return result;
  }

  DeviceInfo._();

  factory DeviceInfo.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DeviceInfo()..mergeFromBuffer(data, registry);
  factory DeviceInfo.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DeviceInfo()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DeviceInfo',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: DeviceInfo.$_createMessage)
    ..aOM<$0.Signed>(1, _omitFieldNames ? '' : 'certificate',
        subBuilder: $0.Signed.$_createMessage)
    ..aInt64(2, _omitFieldNames ? '' : 'addedAtUnixMs')
    ..aInt64(3, _omitFieldNames ? '' : 'revokedAtUnixMs')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeviceInfo clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeviceInfo copyWith(void Function(DeviceInfo) updates) =>
      super.copyWith((message) => updates(message as DeviceInfo)) as DeviceInfo;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use DeviceInfo() / DeviceInfo.new instead')
  static DeviceInfo create() => DeviceInfo._();
  static $pb.GeneratedMessage $_createMessage() => DeviceInfo._();
  @$core.override
  DeviceInfo createEmptyInstance() => DeviceInfo._();
  @$core.pragma('dart2js:noInline')
  static DeviceInfo getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DeviceInfo>(DeviceInfo.$_createMessage);
  static DeviceInfo? _defaultInstance;

  @$pb.TagNumber(1)
  $0.Signed get certificate => $_getN(0);
  @$pb.TagNumber(1)
  set certificate($0.Signed value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasCertificate() => $_has(0);
  @$pb.TagNumber(1)
  void clearCertificate() => $_clearField(1);
  @$pb.TagNumber(1)
  $0.Signed ensureCertificate() => $_ensure(0);

  @$pb.TagNumber(2)
  $fixnum.Int64 get addedAtUnixMs => $_getI64(1);
  @$pb.TagNumber(2)
  set addedAtUnixMs($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasAddedAtUnixMs() => $_has(1);
  @$pb.TagNumber(2)
  void clearAddedAtUnixMs() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get revokedAtUnixMs => $_getI64(2);
  @$pb.TagNumber(3)
  set revokedAtUnixMs($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasRevokedAtUnixMs() => $_has(2);
  @$pb.TagNumber(3)
  void clearRevokedAtUnixMs() => $_clearField(3);
}

/// Отзыв устройства (потеряно или украдено). Запрос подписан ключом учётной
/// записи; revocation — fs.v1.Signed с DeviceRevocation (контекст
/// "device-revoke"). После отзыва координатор не принимает запросы и не
/// выдаёт талоны этому устройству.
class RevokeDeviceRequest extends $pb.GeneratedMessage {
  factory RevokeDeviceRequest({
    $0.Signed? revocation,
  }) {
    final result = RevokeDeviceRequest._();
    if (revocation != null) result.revocation = revocation;
    return result;
  }

  RevokeDeviceRequest._();

  factory RevokeDeviceRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RevokeDeviceRequest()..mergeFromBuffer(data, registry);
  factory RevokeDeviceRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RevokeDeviceRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RevokeDeviceRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: RevokeDeviceRequest.$_createMessage)
    ..aOM<$0.Signed>(1, _omitFieldNames ? '' : 'revocation',
        subBuilder: $0.Signed.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RevokeDeviceRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RevokeDeviceRequest copyWith(void Function(RevokeDeviceRequest) updates) =>
      super.copyWith((message) => updates(message as RevokeDeviceRequest))
          as RevokeDeviceRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use RevokeDeviceRequest() / RevokeDeviceRequest.new instead')
  static RevokeDeviceRequest create() => RevokeDeviceRequest._();
  static $pb.GeneratedMessage $_createMessage() => RevokeDeviceRequest._();
  @$core.override
  RevokeDeviceRequest createEmptyInstance() => RevokeDeviceRequest._();
  @$core.pragma('dart2js:noInline')
  static RevokeDeviceRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RevokeDeviceRequest>(
          RevokeDeviceRequest.$_createMessage);
  static RevokeDeviceRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $0.Signed get revocation => $_getN(0);
  @$pb.TagNumber(1)
  set revocation($0.Signed value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasRevocation() => $_has(0);
  @$pb.TagNumber(1)
  void clearRevocation() => $_clearField(1);
  @$pb.TagNumber(1)
  $0.Signed ensureRevocation() => $_ensure(0);
}

class RevokeDeviceResponse extends $pb.GeneratedMessage {
  factory RevokeDeviceResponse() => RevokeDeviceResponse._();

  RevokeDeviceResponse._();

  factory RevokeDeviceResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RevokeDeviceResponse()..mergeFromBuffer(data, registry);
  factory RevokeDeviceResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RevokeDeviceResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RevokeDeviceResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: RevokeDeviceResponse.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RevokeDeviceResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RevokeDeviceResponse copyWith(void Function(RevokeDeviceResponse) updates) =>
      super.copyWith((message) => updates(message as RevokeDeviceResponse))
          as RevokeDeviceResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use RevokeDeviceResponse() / RevokeDeviceResponse.new instead')
  static RevokeDeviceResponse create() => RevokeDeviceResponse._();
  static $pb.GeneratedMessage $_createMessage() => RevokeDeviceResponse._();
  @$core.override
  RevokeDeviceResponse createEmptyInstance() => RevokeDeviceResponse._();
  @$core.pragma('dart2js:noInline')
  static RevokeDeviceResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RevokeDeviceResponse>(
          RevokeDeviceResponse.$_createMessage);
  static RevokeDeviceResponse? _defaultInstance;
}

/// Отзывы устройств для узлов (подписан ключом узла), по возрастанию
/// sequence.
class ListRevocationsRequest extends $pb.GeneratedMessage {
  factory ListRevocationsRequest({
    $fixnum.Int64? afterSequence,
    $core.int? limit,
  }) {
    final result = ListRevocationsRequest._();
    if (afterSequence != null) result.afterSequence = afterSequence;
    if (limit != null) result.limit = limit;
    return result;
  }

  ListRevocationsRequest._();

  factory ListRevocationsRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListRevocationsRequest()..mergeFromBuffer(data, registry);
  factory ListRevocationsRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListRevocationsRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListRevocationsRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: ListRevocationsRequest.$_createMessage)
    ..a<$fixnum.Int64>(
        1, _omitFieldNames ? '' : 'afterSequence', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aI(2, _omitFieldNames ? '' : 'limit', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListRevocationsRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListRevocationsRequest copyWith(
          void Function(ListRevocationsRequest) updates) =>
      super.copyWith((message) => updates(message as ListRevocationsRequest))
          as ListRevocationsRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use ListRevocationsRequest() / ListRevocationsRequest.new instead')
  static ListRevocationsRequest create() => ListRevocationsRequest._();
  static $pb.GeneratedMessage $_createMessage() => ListRevocationsRequest._();
  @$core.override
  ListRevocationsRequest createEmptyInstance() => ListRevocationsRequest._();
  @$core.pragma('dart2js:noInline')
  static ListRevocationsRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListRevocationsRequest>(
          ListRevocationsRequest.$_createMessage);
  static ListRevocationsRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get afterSequence => $_getI64(0);
  @$pb.TagNumber(1)
  set afterSequence($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAfterSequence() => $_has(0);
  @$pb.TagNumber(1)
  void clearAfterSequence() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get limit => $_getIZ(1);
  @$pb.TagNumber(2)
  set limit($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasLimit() => $_has(1);
  @$pb.TagNumber(2)
  void clearLimit() => $_clearField(2);
}

class ListRevocationsResponse extends $pb.GeneratedMessage {
  factory ListRevocationsResponse({
    $core.Iterable<RevocationEntry>? revocations,
    $core.bool? more,
  }) {
    final result = ListRevocationsResponse._();
    if (revocations != null) result.revocations.addAll(revocations);
    if (more != null) result.more = more;
    return result;
  }

  ListRevocationsResponse._();

  factory ListRevocationsResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListRevocationsResponse()..mergeFromBuffer(data, registry);
  factory ListRevocationsResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListRevocationsResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListRevocationsResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: ListRevocationsResponse.$_createMessage)
    ..pPM<RevocationEntry>(1, _omitFieldNames ? '' : 'revocations',
        subBuilder: RevocationEntry.$_createMessage)
    ..aOB(2, _omitFieldNames ? '' : 'more')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListRevocationsResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListRevocationsResponse copyWith(
          void Function(ListRevocationsResponse) updates) =>
      super.copyWith((message) => updates(message as ListRevocationsResponse))
          as ListRevocationsResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use ListRevocationsResponse() / ListRevocationsResponse.new instead')
  static ListRevocationsResponse create() => ListRevocationsResponse._();
  static $pb.GeneratedMessage $_createMessage() => ListRevocationsResponse._();
  @$core.override
  ListRevocationsResponse createEmptyInstance() => ListRevocationsResponse._();
  @$core.pragma('dart2js:noInline')
  static ListRevocationsResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListRevocationsResponse>(
          ListRevocationsResponse.$_createMessage);
  static ListRevocationsResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<RevocationEntry> get revocations => $_getList(0);

  @$pb.TagNumber(2)
  $core.bool get more => $_getBF(1);
  @$pb.TagNumber(2)
  set more($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMore() => $_has(1);
  @$pb.TagNumber(2)
  void clearMore() => $_clearField(2);
}

class RevocationEntry extends $pb.GeneratedMessage {
  factory RevocationEntry({
    $fixnum.Int64? sequence,
    $0.Signed? revocation,
  }) {
    final result = RevocationEntry._();
    if (sequence != null) result.sequence = sequence;
    if (revocation != null) result.revocation = revocation;
    return result;
  }

  RevocationEntry._();

  factory RevocationEntry.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RevocationEntry()..mergeFromBuffer(data, registry);
  factory RevocationEntry.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RevocationEntry()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RevocationEntry',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: RevocationEntry.$_createMessage)
    ..a<$fixnum.Int64>(
        1, _omitFieldNames ? '' : 'sequence', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOM<$0.Signed>(2, _omitFieldNames ? '' : 'revocation',
        subBuilder: $0.Signed.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RevocationEntry clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RevocationEntry copyWith(void Function(RevocationEntry) updates) =>
      super.copyWith((message) => updates(message as RevocationEntry))
          as RevocationEntry;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use RevocationEntry() / RevocationEntry.new instead')
  static RevocationEntry create() => RevocationEntry._();
  static $pb.GeneratedMessage $_createMessage() => RevocationEntry._();
  @$core.override
  RevocationEntry createEmptyInstance() => RevocationEntry._();
  @$core.pragma('dart2js:noInline')
  static RevocationEntry getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RevocationEntry>(
          RevocationEntry.$_createMessage);
  static RevocationEntry? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get sequence => $_getI64(0);
  @$pb.TagNumber(1)
  set sequence($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSequence() => $_has(0);
  @$pb.TagNumber(1)
  void clearSequence() => $_clearField(1);

  @$pb.TagNumber(2)
  $0.Signed get revocation => $_getN(1);
  @$pb.TagNumber(2)
  set revocation($0.Signed value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasRevocation() => $_has(1);
  @$pb.TagNumber(2)
  void clearRevocation() => $_clearField(2);
  @$pb.TagNumber(2)
  $0.Signed ensureRevocation() => $_ensure(1);
}

/// Вход по паролю на новом устройстве (protocol.md, раздел 4.7; crypto.md,
/// раздел 4.4). Оба запроса без подписи.
class GetLoginParamsRequest extends $pb.GeneratedMessage {
  factory GetLoginParamsRequest({
    $core.String? login,
  }) {
    final result = GetLoginParamsRequest._();
    if (login != null) result.login = login;
    return result;
  }

  GetLoginParamsRequest._();

  factory GetLoginParamsRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetLoginParamsRequest()..mergeFromBuffer(data, registry);
  factory GetLoginParamsRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetLoginParamsRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetLoginParamsRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: GetLoginParamsRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'login')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetLoginParamsRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetLoginParamsRequest copyWith(
          void Function(GetLoginParamsRequest) updates) =>
      super.copyWith((message) => updates(message as GetLoginParamsRequest))
          as GetLoginParamsRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use GetLoginParamsRequest() / GetLoginParamsRequest.new instead')
  static GetLoginParamsRequest create() => GetLoginParamsRequest._();
  static $pb.GeneratedMessage $_createMessage() => GetLoginParamsRequest._();
  @$core.override
  GetLoginParamsRequest createEmptyInstance() => GetLoginParamsRequest._();
  @$core.pragma('dart2js:noInline')
  static GetLoginParamsRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GetLoginParamsRequest>(
          GetLoginParamsRequest.$_createMessage);
  static GetLoginParamsRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get login => $_getSZ(0);
  @$pb.TagNumber(1)
  set login($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasLogin() => $_has(0);
  @$pb.TagNumber(1)
  void clearLogin() => $_clearField(1);
}

class GetLoginParamsResponse extends $pb.GeneratedMessage {
  factory GetLoginParamsResponse({
    $core.List<$core.int>? salt,
    $core.int? memoryKib,
    $core.int? iterations,
    $core.int? parallelism,
  }) {
    final result = GetLoginParamsResponse._();
    if (salt != null) result.salt = salt;
    if (memoryKib != null) result.memoryKib = memoryKib;
    if (iterations != null) result.iterations = iterations;
    if (parallelism != null) result.parallelism = parallelism;
    return result;
  }

  GetLoginParamsResponse._();

  factory GetLoginParamsResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetLoginParamsResponse()..mergeFromBuffer(data, registry);
  factory GetLoginParamsResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetLoginParamsResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetLoginParamsResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: GetLoginParamsResponse.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'salt', $pb.PbFieldType.OY)
    ..aI(2, _omitFieldNames ? '' : 'memoryKib', fieldType: $pb.PbFieldType.OU3)
    ..aI(3, _omitFieldNames ? '' : 'iterations', fieldType: $pb.PbFieldType.OU3)
    ..aI(4, _omitFieldNames ? '' : 'parallelism',
        fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetLoginParamsResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetLoginParamsResponse copyWith(
          void Function(GetLoginParamsResponse) updates) =>
      super.copyWith((message) => updates(message as GetLoginParamsResponse))
          as GetLoginParamsResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use GetLoginParamsResponse() / GetLoginParamsResponse.new instead')
  static GetLoginParamsResponse create() => GetLoginParamsResponse._();
  static $pb.GeneratedMessage $_createMessage() => GetLoginParamsResponse._();
  @$core.override
  GetLoginParamsResponse createEmptyInstance() => GetLoginParamsResponse._();
  @$core.pragma('dart2js:noInline')
  static GetLoginParamsResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GetLoginParamsResponse>(
          GetLoginParamsResponse.$_createMessage);
  static GetLoginParamsResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get salt => $_getN(0);
  @$pb.TagNumber(1)
  set salt($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSalt() => $_has(0);
  @$pb.TagNumber(1)
  void clearSalt() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get memoryKib => $_getIZ(1);
  @$pb.TagNumber(2)
  set memoryKib($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMemoryKib() => $_has(1);
  @$pb.TagNumber(2)
  void clearMemoryKib() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get iterations => $_getIZ(2);
  @$pb.TagNumber(3)
  set iterations($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasIterations() => $_has(2);
  @$pb.TagNumber(3)
  void clearIterations() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get parallelism => $_getIZ(3);
  @$pb.TagNumber(4)
  set parallelism($core.int value) => $_setUnsignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasParallelism() => $_has(3);
  @$pb.TagNumber(4)
  void clearParallelism() => $_clearField(4);
}

class GetKeyBundleRequest extends $pb.GeneratedMessage {
  factory GetKeyBundleRequest({
    $core.List<$core.int>? authProof,
    $core.String? login,
    $fixnum.Int64? timeUnixMs,
  }) {
    final result = GetKeyBundleRequest._();
    if (authProof != null) result.authProof = authProof;
    if (login != null) result.login = login;
    if (timeUnixMs != null) result.timeUnixMs = timeUnixMs;
    return result;
  }

  GetKeyBundleRequest._();

  factory GetKeyBundleRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetKeyBundleRequest()..mergeFromBuffer(data, registry);
  factory GetKeyBundleRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetKeyBundleRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetKeyBundleRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: GetKeyBundleRequest.$_createMessage)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'authProof', $pb.PbFieldType.OY)
    ..aOS(3, _omitFieldNames ? '' : 'login')
    ..aInt64(4, _omitFieldNames ? '' : 'timeUnixMs')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetKeyBundleRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetKeyBundleRequest copyWith(void Function(GetKeyBundleRequest) updates) =>
      super.copyWith((message) => updates(message as GetKeyBundleRequest))
          as GetKeyBundleRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use GetKeyBundleRequest() / GetKeyBundleRequest.new instead')
  static GetKeyBundleRequest create() => GetKeyBundleRequest._();
  static $pb.GeneratedMessage $_createMessage() => GetKeyBundleRequest._();
  @$core.override
  GetKeyBundleRequest createEmptyInstance() => GetKeyBundleRequest._();
  @$core.pragma('dart2js:noInline')
  static GetKeyBundleRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GetKeyBundleRequest>(
          GetKeyBundleRequest.$_createMessage);
  static GetKeyBundleRequest? _defaultInstance;

  @$pb.TagNumber(2)
  $core.List<$core.int> get authProof => $_getN(0);
  @$pb.TagNumber(2)
  set authProof($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(2)
  $core.bool hasAuthProof() => $_has(0);
  @$pb.TagNumber(2)
  void clearAuthProof() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get login => $_getSZ(1);
  @$pb.TagNumber(3)
  set login($core.String value) => $_setString(1, value);
  @$pb.TagNumber(3)
  $core.bool hasLogin() => $_has(1);
  @$pb.TagNumber(3)
  void clearLogin() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get timeUnixMs => $_getI64(2);
  @$pb.TagNumber(4)
  set timeUnixMs($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(4)
  $core.bool hasTimeUnixMs() => $_has(2);
  @$pb.TagNumber(4)
  void clearTimeUnixMs() => $_clearField(4);
}

class GetKeyBundleResponse extends $pb.GeneratedMessage {
  factory GetKeyBundleResponse({
    $core.List<$core.int>? keyBundle,
  }) {
    final result = GetKeyBundleResponse._();
    if (keyBundle != null) result.keyBundle = keyBundle;
    return result;
  }

  GetKeyBundleResponse._();

  factory GetKeyBundleResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetKeyBundleResponse()..mergeFromBuffer(data, registry);
  factory GetKeyBundleResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetKeyBundleResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetKeyBundleResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: GetKeyBundleResponse.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'keyBundle', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetKeyBundleResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetKeyBundleResponse copyWith(void Function(GetKeyBundleResponse) updates) =>
      super.copyWith((message) => updates(message as GetKeyBundleResponse))
          as GetKeyBundleResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use GetKeyBundleResponse() / GetKeyBundleResponse.new instead')
  static GetKeyBundleResponse create() => GetKeyBundleResponse._();
  static $pb.GeneratedMessage $_createMessage() => GetKeyBundleResponse._();
  @$core.override
  GetKeyBundleResponse createEmptyInstance() => GetKeyBundleResponse._();
  @$core.pragma('dart2js:noInline')
  static GetKeyBundleResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GetKeyBundleResponse>(
          GetKeyBundleResponse.$_createMessage);
  static GetKeyBundleResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get keyBundle => $_getN(0);
  @$pb.TagNumber(1)
  set keyBundle($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasKeyBundle() => $_has(0);
  @$pb.TagNumber(1)
  void clearKeyBundle() => $_clearField(1);
}

/// Смена пароля или переход в режим без копии мастер-ключа (оба поля
/// пусты). Подписан ключом учётной записи.
class SetKeyBundleRequest extends $pb.GeneratedMessage {
  factory SetKeyBundleRequest({
    $core.List<$core.int>? keyBundle,
    $core.List<$core.int>? authVerifier,
  }) {
    final result = SetKeyBundleRequest._();
    if (keyBundle != null) result.keyBundle = keyBundle;
    if (authVerifier != null) result.authVerifier = authVerifier;
    return result;
  }

  SetKeyBundleRequest._();

  factory SetKeyBundleRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SetKeyBundleRequest()..mergeFromBuffer(data, registry);
  factory SetKeyBundleRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SetKeyBundleRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SetKeyBundleRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: SetKeyBundleRequest.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'keyBundle', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'authVerifier', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetKeyBundleRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetKeyBundleRequest copyWith(void Function(SetKeyBundleRequest) updates) =>
      super.copyWith((message) => updates(message as SetKeyBundleRequest))
          as SetKeyBundleRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use SetKeyBundleRequest() / SetKeyBundleRequest.new instead')
  static SetKeyBundleRequest create() => SetKeyBundleRequest._();
  static $pb.GeneratedMessage $_createMessage() => SetKeyBundleRequest._();
  @$core.override
  SetKeyBundleRequest createEmptyInstance() => SetKeyBundleRequest._();
  @$core.pragma('dart2js:noInline')
  static SetKeyBundleRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SetKeyBundleRequest>(
          SetKeyBundleRequest.$_createMessage);
  static SetKeyBundleRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get keyBundle => $_getN(0);
  @$pb.TagNumber(1)
  set keyBundle($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasKeyBundle() => $_has(0);
  @$pb.TagNumber(1)
  void clearKeyBundle() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get authVerifier => $_getN(1);
  @$pb.TagNumber(2)
  set authVerifier($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasAuthVerifier() => $_has(1);
  @$pb.TagNumber(2)
  void clearAuthVerifier() => $_clearField(2);
}

class SetKeyBundleResponse extends $pb.GeneratedMessage {
  factory SetKeyBundleResponse() => SetKeyBundleResponse._();

  SetKeyBundleResponse._();

  factory SetKeyBundleResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SetKeyBundleResponse()..mergeFromBuffer(data, registry);
  factory SetKeyBundleResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SetKeyBundleResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SetKeyBundleResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: SetKeyBundleResponse.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetKeyBundleResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetKeyBundleResponse copyWith(void Function(SetKeyBundleResponse) updates) =>
      super.copyWith((message) => updates(message as SetKeyBundleResponse))
          as SetKeyBundleResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use SetKeyBundleResponse() / SetKeyBundleResponse.new instead')
  static SetKeyBundleResponse create() => SetKeyBundleResponse._();
  static $pb.GeneratedMessage $_createMessage() => SetKeyBundleResponse._();
  @$core.override
  SetKeyBundleResponse createEmptyInstance() => SetKeyBundleResponse._();
  @$core.pragma('dart2js:noInline')
  static SetKeyBundleResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SetKeyBundleResponse>(
          SetKeyBundleResponse.$_createMessage);
  static SetKeyBundleResponse? _defaultInstance;
}

class PutObjectRequest extends $pb.GeneratedMessage {
  factory PutObjectRequest({
    ObjectKind? kind,
    $core.List<$core.int>? objectId,
    $core.List<$core.int>? blob,
    $fixnum.Int64? sequence,
  }) {
    final result = PutObjectRequest._();
    if (kind != null) result.kind = kind;
    if (objectId != null) result.objectId = objectId;
    if (blob != null) result.blob = blob;
    if (sequence != null) result.sequence = sequence;
    return result;
  }

  PutObjectRequest._();

  factory PutObjectRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PutObjectRequest()..mergeFromBuffer(data, registry);
  factory PutObjectRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PutObjectRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PutObjectRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: PutObjectRequest.$_createMessage)
    ..aE<ObjectKind>(1, _omitFieldNames ? '' : 'kind',
        enumValues: ObjectKind.values)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'objectId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'blob', $pb.PbFieldType.OY)
    ..a<$fixnum.Int64>(
        4, _omitFieldNames ? '' : 'sequence', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PutObjectRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PutObjectRequest copyWith(void Function(PutObjectRequest) updates) =>
      super.copyWith((message) => updates(message as PutObjectRequest))
          as PutObjectRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use PutObjectRequest() / PutObjectRequest.new instead')
  static PutObjectRequest create() => PutObjectRequest._();
  static $pb.GeneratedMessage $_createMessage() => PutObjectRequest._();
  @$core.override
  PutObjectRequest createEmptyInstance() => PutObjectRequest._();
  @$core.pragma('dart2js:noInline')
  static PutObjectRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PutObjectRequest>(
          PutObjectRequest.$_createMessage);
  static PutObjectRequest? _defaultInstance;

  @$pb.TagNumber(1)
  ObjectKind get kind => $_getN(0);
  @$pb.TagNumber(1)
  set kind(ObjectKind value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasKind() => $_has(0);
  @$pb.TagNumber(1)
  void clearKind() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get objectId => $_getN(1);
  @$pb.TagNumber(2)
  set objectId($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasObjectId() => $_has(1);
  @$pb.TagNumber(2)
  void clearObjectId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get blob => $_getN(2);
  @$pb.TagNumber(3)
  set blob($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(3)
  $core.bool hasBlob() => $_has(2);
  @$pb.TagNumber(3)
  void clearBlob() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get sequence => $_getI64(3);
  @$pb.TagNumber(4)
  set sequence($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasSequence() => $_has(3);
  @$pb.TagNumber(4)
  void clearSequence() => $_clearField(4);
}

class PutObjectResponse extends $pb.GeneratedMessage {
  factory PutObjectResponse() => PutObjectResponse._();

  PutObjectResponse._();

  factory PutObjectResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PutObjectResponse()..mergeFromBuffer(data, registry);
  factory PutObjectResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PutObjectResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PutObjectResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: PutObjectResponse.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PutObjectResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PutObjectResponse copyWith(void Function(PutObjectResponse) updates) =>
      super.copyWith((message) => updates(message as PutObjectResponse))
          as PutObjectResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use PutObjectResponse() / PutObjectResponse.new instead')
  static PutObjectResponse create() => PutObjectResponse._();
  static $pb.GeneratedMessage $_createMessage() => PutObjectResponse._();
  @$core.override
  PutObjectResponse createEmptyInstance() => PutObjectResponse._();
  @$core.pragma('dart2js:noInline')
  static PutObjectResponse getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PutObjectResponse>(
          PutObjectResponse.$_createMessage);
  static PutObjectResponse? _defaultInstance;
}

class ListObjectsRequest extends $pb.GeneratedMessage {
  factory ListObjectsRequest({
    ObjectKind? kind,
    $core.List<$core.int>? afterObjectId,
    $core.int? limit,
  }) {
    final result = ListObjectsRequest._();
    if (kind != null) result.kind = kind;
    if (afterObjectId != null) result.afterObjectId = afterObjectId;
    if (limit != null) result.limit = limit;
    return result;
  }

  ListObjectsRequest._();

  factory ListObjectsRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListObjectsRequest()..mergeFromBuffer(data, registry);
  factory ListObjectsRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListObjectsRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListObjectsRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: ListObjectsRequest.$_createMessage)
    ..aE<ObjectKind>(1, _omitFieldNames ? '' : 'kind',
        enumValues: ObjectKind.values)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'afterObjectId', $pb.PbFieldType.OY)
    ..aI(3, _omitFieldNames ? '' : 'limit', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListObjectsRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListObjectsRequest copyWith(void Function(ListObjectsRequest) updates) =>
      super.copyWith((message) => updates(message as ListObjectsRequest))
          as ListObjectsRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ListObjectsRequest() / ListObjectsRequest.new instead')
  static ListObjectsRequest create() => ListObjectsRequest._();
  static $pb.GeneratedMessage $_createMessage() => ListObjectsRequest._();
  @$core.override
  ListObjectsRequest createEmptyInstance() => ListObjectsRequest._();
  @$core.pragma('dart2js:noInline')
  static ListObjectsRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListObjectsRequest>(
          ListObjectsRequest.$_createMessage);
  static ListObjectsRequest? _defaultInstance;

  @$pb.TagNumber(1)
  ObjectKind get kind => $_getN(0);
  @$pb.TagNumber(1)
  set kind(ObjectKind value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasKind() => $_has(0);
  @$pb.TagNumber(1)
  void clearKind() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get afterObjectId => $_getN(1);
  @$pb.TagNumber(2)
  set afterObjectId($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasAfterObjectId() => $_has(1);
  @$pb.TagNumber(2)
  void clearAfterObjectId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get limit => $_getIZ(2);
  @$pb.TagNumber(3)
  set limit($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasLimit() => $_has(2);
  @$pb.TagNumber(3)
  void clearLimit() => $_clearField(3);
}

class ListObjectsResponse extends $pb.GeneratedMessage {
  factory ListObjectsResponse({
    $core.Iterable<ObjectInfo>? objects,
    $core.bool? more,
  }) {
    final result = ListObjectsResponse._();
    if (objects != null) result.objects.addAll(objects);
    if (more != null) result.more = more;
    return result;
  }

  ListObjectsResponse._();

  factory ListObjectsResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListObjectsResponse()..mergeFromBuffer(data, registry);
  factory ListObjectsResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListObjectsResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListObjectsResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: ListObjectsResponse.$_createMessage)
    ..pPM<ObjectInfo>(1, _omitFieldNames ? '' : 'objects',
        subBuilder: ObjectInfo.$_createMessage)
    ..aOB(2, _omitFieldNames ? '' : 'more')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListObjectsResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListObjectsResponse copyWith(void Function(ListObjectsResponse) updates) =>
      super.copyWith((message) => updates(message as ListObjectsResponse))
          as ListObjectsResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use ListObjectsResponse() / ListObjectsResponse.new instead')
  static ListObjectsResponse create() => ListObjectsResponse._();
  static $pb.GeneratedMessage $_createMessage() => ListObjectsResponse._();
  @$core.override
  ListObjectsResponse createEmptyInstance() => ListObjectsResponse._();
  @$core.pragma('dart2js:noInline')
  static ListObjectsResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListObjectsResponse>(
          ListObjectsResponse.$_createMessage);
  static ListObjectsResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<ObjectInfo> get objects => $_getList(0);

  @$pb.TagNumber(2)
  $core.bool get more => $_getBF(1);
  @$pb.TagNumber(2)
  set more($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMore() => $_has(1);
  @$pb.TagNumber(2)
  void clearMore() => $_clearField(2);
}

class ObjectInfo extends $pb.GeneratedMessage {
  factory ObjectInfo({
    $core.List<$core.int>? objectId,
    $core.int? size,
    $fixnum.Int64? storedAtUnixMs,
    $fixnum.Int64? sequence,
  }) {
    final result = ObjectInfo._();
    if (objectId != null) result.objectId = objectId;
    if (size != null) result.size = size;
    if (storedAtUnixMs != null) result.storedAtUnixMs = storedAtUnixMs;
    if (sequence != null) result.sequence = sequence;
    return result;
  }

  ObjectInfo._();

  factory ObjectInfo.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ObjectInfo()..mergeFromBuffer(data, registry);
  factory ObjectInfo.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ObjectInfo()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ObjectInfo',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: ObjectInfo.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'objectId', $pb.PbFieldType.OY)
    ..aI(2, _omitFieldNames ? '' : 'size', fieldType: $pb.PbFieldType.OU3)
    ..aInt64(3, _omitFieldNames ? '' : 'storedAtUnixMs')
    ..a<$fixnum.Int64>(
        4, _omitFieldNames ? '' : 'sequence', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ObjectInfo clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ObjectInfo copyWith(void Function(ObjectInfo) updates) =>
      super.copyWith((message) => updates(message as ObjectInfo)) as ObjectInfo;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ObjectInfo() / ObjectInfo.new instead')
  static ObjectInfo create() => ObjectInfo._();
  static $pb.GeneratedMessage $_createMessage() => ObjectInfo._();
  @$core.override
  ObjectInfo createEmptyInstance() => ObjectInfo._();
  @$core.pragma('dart2js:noInline')
  static ObjectInfo getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ObjectInfo>(ObjectInfo.$_createMessage);
  static ObjectInfo? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get objectId => $_getN(0);
  @$pb.TagNumber(1)
  set objectId($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasObjectId() => $_has(0);
  @$pb.TagNumber(1)
  void clearObjectId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get size => $_getIZ(1);
  @$pb.TagNumber(2)
  set size($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSize() => $_has(1);
  @$pb.TagNumber(2)
  void clearSize() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get storedAtUnixMs => $_getI64(2);
  @$pb.TagNumber(3)
  set storedAtUnixMs($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasStoredAtUnixMs() => $_has(2);
  @$pb.TagNumber(3)
  void clearStoredAtUnixMs() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get sequence => $_getI64(3);
  @$pb.TagNumber(4)
  set sequence($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasSequence() => $_has(3);
  @$pb.TagNumber(4)
  void clearSequence() => $_clearField(4);
}

class GetObjectRequest extends $pb.GeneratedMessage {
  factory GetObjectRequest({
    ObjectKind? kind,
    $core.List<$core.int>? objectId,
  }) {
    final result = GetObjectRequest._();
    if (kind != null) result.kind = kind;
    if (objectId != null) result.objectId = objectId;
    return result;
  }

  GetObjectRequest._();

  factory GetObjectRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetObjectRequest()..mergeFromBuffer(data, registry);
  factory GetObjectRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetObjectRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetObjectRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: GetObjectRequest.$_createMessage)
    ..aE<ObjectKind>(1, _omitFieldNames ? '' : 'kind',
        enumValues: ObjectKind.values)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'objectId', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetObjectRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetObjectRequest copyWith(void Function(GetObjectRequest) updates) =>
      super.copyWith((message) => updates(message as GetObjectRequest))
          as GetObjectRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use GetObjectRequest() / GetObjectRequest.new instead')
  static GetObjectRequest create() => GetObjectRequest._();
  static $pb.GeneratedMessage $_createMessage() => GetObjectRequest._();
  @$core.override
  GetObjectRequest createEmptyInstance() => GetObjectRequest._();
  @$core.pragma('dart2js:noInline')
  static GetObjectRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GetObjectRequest>(
          GetObjectRequest.$_createMessage);
  static GetObjectRequest? _defaultInstance;

  @$pb.TagNumber(1)
  ObjectKind get kind => $_getN(0);
  @$pb.TagNumber(1)
  set kind(ObjectKind value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasKind() => $_has(0);
  @$pb.TagNumber(1)
  void clearKind() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get objectId => $_getN(1);
  @$pb.TagNumber(2)
  set objectId($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasObjectId() => $_has(1);
  @$pb.TagNumber(2)
  void clearObjectId() => $_clearField(2);
}

class GetObjectResponse extends $pb.GeneratedMessage {
  factory GetObjectResponse({
    $core.List<$core.int>? blob,
  }) {
    final result = GetObjectResponse._();
    if (blob != null) result.blob = blob;
    return result;
  }

  GetObjectResponse._();

  factory GetObjectResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetObjectResponse()..mergeFromBuffer(data, registry);
  factory GetObjectResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetObjectResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetObjectResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: GetObjectResponse.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'blob', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetObjectResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetObjectResponse copyWith(void Function(GetObjectResponse) updates) =>
      super.copyWith((message) => updates(message as GetObjectResponse))
          as GetObjectResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use GetObjectResponse() / GetObjectResponse.new instead')
  static GetObjectResponse create() => GetObjectResponse._();
  static $pb.GeneratedMessage $_createMessage() => GetObjectResponse._();
  @$core.override
  GetObjectResponse createEmptyInstance() => GetObjectResponse._();
  @$core.pragma('dart2js:noInline')
  static GetObjectResponse getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GetObjectResponse>(
          GetObjectResponse.$_createMessage);
  static GetObjectResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get blob => $_getN(0);
  @$pb.TagNumber(1)
  set blob($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasBlob() => $_has(0);
  @$pb.TagNumber(1)
  void clearBlob() => $_clearField(1);
}

class DeleteObjectRequest extends $pb.GeneratedMessage {
  factory DeleteObjectRequest({
    ObjectKind? kind,
    $core.List<$core.int>? objectId,
  }) {
    final result = DeleteObjectRequest._();
    if (kind != null) result.kind = kind;
    if (objectId != null) result.objectId = objectId;
    return result;
  }

  DeleteObjectRequest._();

  factory DeleteObjectRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DeleteObjectRequest()..mergeFromBuffer(data, registry);
  factory DeleteObjectRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DeleteObjectRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DeleteObjectRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: DeleteObjectRequest.$_createMessage)
    ..aE<ObjectKind>(1, _omitFieldNames ? '' : 'kind',
        enumValues: ObjectKind.values)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'objectId', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeleteObjectRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeleteObjectRequest copyWith(void Function(DeleteObjectRequest) updates) =>
      super.copyWith((message) => updates(message as DeleteObjectRequest))
          as DeleteObjectRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use DeleteObjectRequest() / DeleteObjectRequest.new instead')
  static DeleteObjectRequest create() => DeleteObjectRequest._();
  static $pb.GeneratedMessage $_createMessage() => DeleteObjectRequest._();
  @$core.override
  DeleteObjectRequest createEmptyInstance() => DeleteObjectRequest._();
  @$core.pragma('dart2js:noInline')
  static DeleteObjectRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DeleteObjectRequest>(
          DeleteObjectRequest.$_createMessage);
  static DeleteObjectRequest? _defaultInstance;

  @$pb.TagNumber(1)
  ObjectKind get kind => $_getN(0);
  @$pb.TagNumber(1)
  set kind(ObjectKind value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasKind() => $_has(0);
  @$pb.TagNumber(1)
  void clearKind() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get objectId => $_getN(1);
  @$pb.TagNumber(2)
  set objectId($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasObjectId() => $_has(1);
  @$pb.TagNumber(2)
  void clearObjectId() => $_clearField(2);
}

class DeleteObjectResponse extends $pb.GeneratedMessage {
  factory DeleteObjectResponse() => DeleteObjectResponse._();

  DeleteObjectResponse._();

  factory DeleteObjectResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DeleteObjectResponse()..mergeFromBuffer(data, registry);
  factory DeleteObjectResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DeleteObjectResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DeleteObjectResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: DeleteObjectResponse.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeleteObjectResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeleteObjectResponse copyWith(void Function(DeleteObjectResponse) updates) =>
      super.copyWith((message) => updates(message as DeleteObjectResponse))
          as DeleteObjectResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use DeleteObjectResponse() / DeleteObjectResponse.new instead')
  static DeleteObjectResponse create() => DeleteObjectResponse._();
  static $pb.GeneratedMessage $_createMessage() => DeleteObjectResponse._();
  @$core.override
  DeleteObjectResponse createEmptyInstance() => DeleteObjectResponse._();
  @$core.pragma('dart2js:noInline')
  static DeleteObjectResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DeleteObjectResponse>(
          DeleteObjectResponse.$_createMessage);
  static DeleteObjectResponse? _defaultInstance;
}

/// Клиент сообщает параметры нового сегмента и получает узлы и талоны PUT.
class AllocateSegmentRequest extends $pb.GeneratedMessage {
  factory AllocateSegmentRequest({
    $core.List<$core.int>? segmentId,
    $core.int? k,
    $core.int? n,
    $core.int? fragmentSize,
    $core.Iterable<$core.List<$core.int>>? fragmentIds,
    $core.Iterable<$core.List<$core.int>>? bodyRoots,
    $core.int? repairThreshold,
  }) {
    final result = AllocateSegmentRequest._();
    if (segmentId != null) result.segmentId = segmentId;
    if (k != null) result.k = k;
    if (n != null) result.n = n;
    if (fragmentSize != null) result.fragmentSize = fragmentSize;
    if (fragmentIds != null) result.fragmentIds.addAll(fragmentIds);
    if (bodyRoots != null) result.bodyRoots.addAll(bodyRoots);
    if (repairThreshold != null) result.repairThreshold = repairThreshold;
    return result;
  }

  AllocateSegmentRequest._();

  factory AllocateSegmentRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      AllocateSegmentRequest()..mergeFromBuffer(data, registry);
  factory AllocateSegmentRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      AllocateSegmentRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AllocateSegmentRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: AllocateSegmentRequest.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'segmentId', $pb.PbFieldType.OY)
    ..aI(2, _omitFieldNames ? '' : 'k', fieldType: $pb.PbFieldType.OU3)
    ..aI(3, _omitFieldNames ? '' : 'n', fieldType: $pb.PbFieldType.OU3)
    ..aI(4, _omitFieldNames ? '' : 'fragmentSize',
        fieldType: $pb.PbFieldType.OU3)
    ..p<$core.List<$core.int>>(
        5, _omitFieldNames ? '' : 'fragmentIds', $pb.PbFieldType.PY)
    ..p<$core.List<$core.int>>(
        6, _omitFieldNames ? '' : 'bodyRoots', $pb.PbFieldType.PY)
    ..aI(7, _omitFieldNames ? '' : 'repairThreshold',
        fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AllocateSegmentRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AllocateSegmentRequest copyWith(
          void Function(AllocateSegmentRequest) updates) =>
      super.copyWith((message) => updates(message as AllocateSegmentRequest))
          as AllocateSegmentRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use AllocateSegmentRequest() / AllocateSegmentRequest.new instead')
  static AllocateSegmentRequest create() => AllocateSegmentRequest._();
  static $pb.GeneratedMessage $_createMessage() => AllocateSegmentRequest._();
  @$core.override
  AllocateSegmentRequest createEmptyInstance() => AllocateSegmentRequest._();
  @$core.pragma('dart2js:noInline')
  static AllocateSegmentRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<AllocateSegmentRequest>(
          AllocateSegmentRequest.$_createMessage);
  static AllocateSegmentRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get segmentId => $_getN(0);
  @$pb.TagNumber(1)
  set segmentId($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSegmentId() => $_has(0);
  @$pb.TagNumber(1)
  void clearSegmentId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get k => $_getIZ(1);
  @$pb.TagNumber(2)
  set k($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasK() => $_has(1);
  @$pb.TagNumber(2)
  void clearK() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get n => $_getIZ(2);
  @$pb.TagNumber(3)
  set n($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasN() => $_has(2);
  @$pb.TagNumber(3)
  void clearN() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get fragmentSize => $_getIZ(3);
  @$pb.TagNumber(4)
  set fragmentSize($core.int value) => $_setUnsignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasFragmentSize() => $_has(3);
  @$pb.TagNumber(4)
  void clearFragmentSize() => $_clearField(4);

  @$pb.TagNumber(5)
  $pb.PbList<$core.List<$core.int>> get fragmentIds => $_getList(4);

  @$pb.TagNumber(6)
  $pb.PbList<$core.List<$core.int>> get bodyRoots => $_getList(5);

  @$pb.TagNumber(7)
  $core.int get repairThreshold => $_getIZ(6);
  @$pb.TagNumber(7)
  set repairThreshold($core.int value) => $_setUnsignedInt32(6, value);
  @$pb.TagNumber(7)
  $core.bool hasRepairThreshold() => $_has(6);
  @$pb.TagNumber(7)
  void clearRepairThreshold() => $_clearField(7);
}

class AllocateSegmentResponse extends $pb.GeneratedMessage {
  factory AllocateSegmentResponse({
    $core.Iterable<Placement>? placements,
  }) {
    final result = AllocateSegmentResponse._();
    if (placements != null) result.placements.addAll(placements);
    return result;
  }

  AllocateSegmentResponse._();

  factory AllocateSegmentResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      AllocateSegmentResponse()..mergeFromBuffer(data, registry);
  factory AllocateSegmentResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      AllocateSegmentResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AllocateSegmentResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: AllocateSegmentResponse.$_createMessage)
    ..pPM<Placement>(1, _omitFieldNames ? '' : 'placements',
        subBuilder: Placement.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AllocateSegmentResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AllocateSegmentResponse copyWith(
          void Function(AllocateSegmentResponse) updates) =>
      super.copyWith((message) => updates(message as AllocateSegmentResponse))
          as AllocateSegmentResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use AllocateSegmentResponse() / AllocateSegmentResponse.new instead')
  static AllocateSegmentResponse create() => AllocateSegmentResponse._();
  static $pb.GeneratedMessage $_createMessage() => AllocateSegmentResponse._();
  @$core.override
  AllocateSegmentResponse createEmptyInstance() => AllocateSegmentResponse._();
  @$core.pragma('dart2js:noInline')
  static AllocateSegmentResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<AllocateSegmentResponse>(
          AllocateSegmentResponse.$_createMessage);
  static AllocateSegmentResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<Placement> get placements => $_getList(0);
}

class Placement extends $pb.GeneratedMessage {
  factory Placement({
    $core.int? index,
    NodeAddress? node,
    $0.Signed? ticket,
  }) {
    final result = Placement._();
    if (index != null) result.index = index;
    if (node != null) result.node = node;
    if (ticket != null) result.ticket = ticket;
    return result;
  }

  Placement._();

  factory Placement.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Placement()..mergeFromBuffer(data, registry);
  factory Placement.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Placement()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Placement',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: Placement.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'index', fieldType: $pb.PbFieldType.OU3)
    ..aOM<NodeAddress>(2, _omitFieldNames ? '' : 'node',
        subBuilder: NodeAddress.$_createMessage)
    ..aOM<$0.Signed>(3, _omitFieldNames ? '' : 'ticket',
        subBuilder: $0.Signed.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Placement clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Placement copyWith(void Function(Placement) updates) =>
      super.copyWith((message) => updates(message as Placement)) as Placement;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Placement() / Placement.new instead')
  static Placement create() => Placement._();
  static $pb.GeneratedMessage $_createMessage() => Placement._();
  @$core.override
  Placement createEmptyInstance() => Placement._();
  @$core.pragma('dart2js:noInline')
  static Placement getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Placement>(Placement.$_createMessage);
  static Placement? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get index => $_getIZ(0);
  @$pb.TagNumber(1)
  set index($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasIndex() => $_has(0);
  @$pb.TagNumber(1)
  void clearIndex() => $_clearField(1);

  @$pb.TagNumber(2)
  NodeAddress get node => $_getN(1);
  @$pb.TagNumber(2)
  set node(NodeAddress value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasNode() => $_has(1);
  @$pb.TagNumber(2)
  void clearNode() => $_clearField(2);
  @$pb.TagNumber(2)
  NodeAddress ensureNode() => $_ensure(1);

  @$pb.TagNumber(3)
  $0.Signed get ticket => $_getN(2);
  @$pb.TagNumber(3)
  set ticket($0.Signed value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasTicket() => $_has(2);
  @$pb.TagNumber(3)
  void clearTicket() => $_clearField(3);
  @$pb.TagNumber(3)
  $0.Signed ensureTicket() => $_ensure(2);
}

class NodeAddress extends $pb.GeneratedMessage {
  factory NodeAddress({
    $core.List<$core.int>? nodeId,
    $core.Iterable<$core.String>? endpoints,
    $core.bool? needsRelay,
  }) {
    final result = NodeAddress._();
    if (nodeId != null) result.nodeId = nodeId;
    if (endpoints != null) result.endpoints.addAll(endpoints);
    if (needsRelay != null) result.needsRelay = needsRelay;
    return result;
  }

  NodeAddress._();

  factory NodeAddress.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      NodeAddress()..mergeFromBuffer(data, registry);
  factory NodeAddress.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      NodeAddress()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'NodeAddress',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: NodeAddress.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'nodeId', $pb.PbFieldType.OY)
    ..pPS(2, _omitFieldNames ? '' : 'endpoints')
    ..aOB(3, _omitFieldNames ? '' : 'needsRelay')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  NodeAddress clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  NodeAddress copyWith(void Function(NodeAddress) updates) =>
      super.copyWith((message) => updates(message as NodeAddress))
          as NodeAddress;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use NodeAddress() / NodeAddress.new instead')
  static NodeAddress create() => NodeAddress._();
  static $pb.GeneratedMessage $_createMessage() => NodeAddress._();
  @$core.override
  NodeAddress createEmptyInstance() => NodeAddress._();
  @$core.pragma('dart2js:noInline')
  static NodeAddress getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<NodeAddress>(
          NodeAddress.$_createMessage);
  static NodeAddress? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get nodeId => $_getN(0);
  @$pb.TagNumber(1)
  set nodeId($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasNodeId() => $_has(0);
  @$pb.TagNumber(1)
  void clearNodeId() => $_clearField(1);

  @$pb.TagNumber(2)
  $pb.PbList<$core.String> get endpoints => $_getList(1);

  @$pb.TagNumber(3)
  $core.bool get needsRelay => $_getBF(2);
  @$pb.TagNumber(3)
  set needsRelay($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasNeedsRelay() => $_has(2);
  @$pb.TagNumber(3)
  void clearNeedsRelay() => $_clearField(3);
}

/// Клиент подтверждает, какие фрагменты загружены.
class CommitSegmentRequest extends $pb.GeneratedMessage {
  factory CommitSegmentRequest({
    $core.List<$core.int>? segmentId,
    $core.Iterable<$core.int>? storedIndexes,
  }) {
    final result = CommitSegmentRequest._();
    if (segmentId != null) result.segmentId = segmentId;
    if (storedIndexes != null) result.storedIndexes.addAll(storedIndexes);
    return result;
  }

  CommitSegmentRequest._();

  factory CommitSegmentRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CommitSegmentRequest()..mergeFromBuffer(data, registry);
  factory CommitSegmentRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CommitSegmentRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CommitSegmentRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: CommitSegmentRequest.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'segmentId', $pb.PbFieldType.OY)
    ..p<$core.int>(
        2, _omitFieldNames ? '' : 'storedIndexes', $pb.PbFieldType.KU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CommitSegmentRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CommitSegmentRequest copyWith(void Function(CommitSegmentRequest) updates) =>
      super.copyWith((message) => updates(message as CommitSegmentRequest))
          as CommitSegmentRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use CommitSegmentRequest() / CommitSegmentRequest.new instead')
  static CommitSegmentRequest create() => CommitSegmentRequest._();
  static $pb.GeneratedMessage $_createMessage() => CommitSegmentRequest._();
  @$core.override
  CommitSegmentRequest createEmptyInstance() => CommitSegmentRequest._();
  @$core.pragma('dart2js:noInline')
  static CommitSegmentRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CommitSegmentRequest>(
          CommitSegmentRequest.$_createMessage);
  static CommitSegmentRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get segmentId => $_getN(0);
  @$pb.TagNumber(1)
  set segmentId($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSegmentId() => $_has(0);
  @$pb.TagNumber(1)
  void clearSegmentId() => $_clearField(1);

  @$pb.TagNumber(2)
  $pb.PbList<$core.int> get storedIndexes => $_getList(1);
}

class CommitSegmentResponse extends $pb.GeneratedMessage {
  factory CommitSegmentResponse() => CommitSegmentResponse._();

  CommitSegmentResponse._();

  factory CommitSegmentResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CommitSegmentResponse()..mergeFromBuffer(data, registry);
  factory CommitSegmentResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CommitSegmentResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CommitSegmentResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: CommitSegmentResponse.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CommitSegmentResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CommitSegmentResponse copyWith(
          void Function(CommitSegmentResponse) updates) =>
      super.copyWith((message) => updates(message as CommitSegmentResponse))
          as CommitSegmentResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use CommitSegmentResponse() / CommitSegmentResponse.new instead')
  static CommitSegmentResponse create() => CommitSegmentResponse._();
  static $pb.GeneratedMessage $_createMessage() => CommitSegmentResponse._();
  @$core.override
  CommitSegmentResponse createEmptyInstance() => CommitSegmentResponse._();
  @$core.pragma('dart2js:noInline')
  static CommitSegmentResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CommitSegmentResponse>(
          CommitSegmentResponse.$_createMessage);
  static CommitSegmentResponse? _defaultInstance;
}

/// Где лежат фрагменты сегмента; талоны GET на чтение.
class LocateSegmentRequest extends $pb.GeneratedMessage {
  factory LocateSegmentRequest({
    $core.List<$core.int>? segmentId,
  }) {
    final result = LocateSegmentRequest._();
    if (segmentId != null) result.segmentId = segmentId;
    return result;
  }

  LocateSegmentRequest._();

  factory LocateSegmentRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      LocateSegmentRequest()..mergeFromBuffer(data, registry);
  factory LocateSegmentRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      LocateSegmentRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'LocateSegmentRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: LocateSegmentRequest.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'segmentId', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LocateSegmentRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LocateSegmentRequest copyWith(void Function(LocateSegmentRequest) updates) =>
      super.copyWith((message) => updates(message as LocateSegmentRequest))
          as LocateSegmentRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use LocateSegmentRequest() / LocateSegmentRequest.new instead')
  static LocateSegmentRequest create() => LocateSegmentRequest._();
  static $pb.GeneratedMessage $_createMessage() => LocateSegmentRequest._();
  @$core.override
  LocateSegmentRequest createEmptyInstance() => LocateSegmentRequest._();
  @$core.pragma('dart2js:noInline')
  static LocateSegmentRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<LocateSegmentRequest>(
          LocateSegmentRequest.$_createMessage);
  static LocateSegmentRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get segmentId => $_getN(0);
  @$pb.TagNumber(1)
  set segmentId($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSegmentId() => $_has(0);
  @$pb.TagNumber(1)
  void clearSegmentId() => $_clearField(1);
}

class LocateSegmentResponse extends $pb.GeneratedMessage {
  factory LocateSegmentResponse({
    $core.Iterable<Placement>? placements,
  }) {
    final result = LocateSegmentResponse._();
    if (placements != null) result.placements.addAll(placements);
    return result;
  }

  LocateSegmentResponse._();

  factory LocateSegmentResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      LocateSegmentResponse()..mergeFromBuffer(data, registry);
  factory LocateSegmentResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      LocateSegmentResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'LocateSegmentResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: LocateSegmentResponse.$_createMessage)
    ..pPM<Placement>(1, _omitFieldNames ? '' : 'placements',
        subBuilder: Placement.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LocateSegmentResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LocateSegmentResponse copyWith(
          void Function(LocateSegmentResponse) updates) =>
      super.copyWith((message) => updates(message as LocateSegmentResponse))
          as LocateSegmentResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use LocateSegmentResponse() / LocateSegmentResponse.new instead')
  static LocateSegmentResponse create() => LocateSegmentResponse._();
  static $pb.GeneratedMessage $_createMessage() => LocateSegmentResponse._();
  @$core.override
  LocateSegmentResponse createEmptyInstance() => LocateSegmentResponse._();
  @$core.pragma('dart2js:noInline')
  static LocateSegmentResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<LocateSegmentResponse>(
          LocateSegmentResponse.$_createMessage);
  static LocateSegmentResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<Placement> get placements => $_getList(0);
}

/// Сборка мусора (manifest.md, раздел 7): сегмент больше не нужен.
/// Координатор забывает его и выдаёт талоны DELETE на фрагменты; удаляет их
/// с узлов клиент.
class DeleteSegmentRequest extends $pb.GeneratedMessage {
  factory DeleteSegmentRequest({
    $core.List<$core.int>? segmentId,
  }) {
    final result = DeleteSegmentRequest._();
    if (segmentId != null) result.segmentId = segmentId;
    return result;
  }

  DeleteSegmentRequest._();

  factory DeleteSegmentRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DeleteSegmentRequest()..mergeFromBuffer(data, registry);
  factory DeleteSegmentRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DeleteSegmentRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DeleteSegmentRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: DeleteSegmentRequest.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'segmentId', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeleteSegmentRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeleteSegmentRequest copyWith(void Function(DeleteSegmentRequest) updates) =>
      super.copyWith((message) => updates(message as DeleteSegmentRequest))
          as DeleteSegmentRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use DeleteSegmentRequest() / DeleteSegmentRequest.new instead')
  static DeleteSegmentRequest create() => DeleteSegmentRequest._();
  static $pb.GeneratedMessage $_createMessage() => DeleteSegmentRequest._();
  @$core.override
  DeleteSegmentRequest createEmptyInstance() => DeleteSegmentRequest._();
  @$core.pragma('dart2js:noInline')
  static DeleteSegmentRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DeleteSegmentRequest>(
          DeleteSegmentRequest.$_createMessage);
  static DeleteSegmentRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get segmentId => $_getN(0);
  @$pb.TagNumber(1)
  set segmentId($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSegmentId() => $_has(0);
  @$pb.TagNumber(1)
  void clearSegmentId() => $_clearField(1);
}

class DeleteSegmentResponse extends $pb.GeneratedMessage {
  factory DeleteSegmentResponse({
    $core.Iterable<Placement>? placements,
  }) {
    final result = DeleteSegmentResponse._();
    if (placements != null) result.placements.addAll(placements);
    return result;
  }

  DeleteSegmentResponse._();

  factory DeleteSegmentResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DeleteSegmentResponse()..mergeFromBuffer(data, registry);
  factory DeleteSegmentResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DeleteSegmentResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DeleteSegmentResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: DeleteSegmentResponse.$_createMessage)
    ..pPM<Placement>(1, _omitFieldNames ? '' : 'placements',
        subBuilder: Placement.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeleteSegmentResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeleteSegmentResponse copyWith(
          void Function(DeleteSegmentResponse) updates) =>
      super.copyWith((message) => updates(message as DeleteSegmentResponse))
          as DeleteSegmentResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use DeleteSegmentResponse() / DeleteSegmentResponse.new instead')
  static DeleteSegmentResponse create() => DeleteSegmentResponse._();
  static $pb.GeneratedMessage $_createMessage() => DeleteSegmentResponse._();
  @$core.override
  DeleteSegmentResponse createEmptyInstance() => DeleteSegmentResponse._();
  @$core.pragma('dart2js:noInline')
  static DeleteSegmentResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DeleteSegmentResponse>(
          DeleteSegmentResponse.$_createMessage);
  static DeleteSegmentResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<Placement> get placements => $_getList(0);
}

class RegisterNodeRequest extends $pb.GeneratedMessage {
  factory RegisterNodeRequest({
    $0.Signed? nodeCertificate,
    $fixnum.Int64? capacityBytes,
    $core.Iterable<$core.String>? endpoints,
    $core.Iterable<$core.int>? versions,
    $core.String? software,
  }) {
    final result = RegisterNodeRequest._();
    if (nodeCertificate != null) result.nodeCertificate = nodeCertificate;
    if (capacityBytes != null) result.capacityBytes = capacityBytes;
    if (endpoints != null) result.endpoints.addAll(endpoints);
    if (versions != null) result.versions.addAll(versions);
    if (software != null) result.software = software;
    return result;
  }

  RegisterNodeRequest._();

  factory RegisterNodeRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RegisterNodeRequest()..mergeFromBuffer(data, registry);
  factory RegisterNodeRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RegisterNodeRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RegisterNodeRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: RegisterNodeRequest.$_createMessage)
    ..aOM<$0.Signed>(1, _omitFieldNames ? '' : 'nodeCertificate',
        subBuilder: $0.Signed.$_createMessage)
    ..a<$fixnum.Int64>(
        2, _omitFieldNames ? '' : 'capacityBytes', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..pPS(3, _omitFieldNames ? '' : 'endpoints')
    ..p<$core.int>(4, _omitFieldNames ? '' : 'versions', $pb.PbFieldType.KU3)
    ..aOS(5, _omitFieldNames ? '' : 'software')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RegisterNodeRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RegisterNodeRequest copyWith(void Function(RegisterNodeRequest) updates) =>
      super.copyWith((message) => updates(message as RegisterNodeRequest))
          as RegisterNodeRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use RegisterNodeRequest() / RegisterNodeRequest.new instead')
  static RegisterNodeRequest create() => RegisterNodeRequest._();
  static $pb.GeneratedMessage $_createMessage() => RegisterNodeRequest._();
  @$core.override
  RegisterNodeRequest createEmptyInstance() => RegisterNodeRequest._();
  @$core.pragma('dart2js:noInline')
  static RegisterNodeRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RegisterNodeRequest>(
          RegisterNodeRequest.$_createMessage);
  static RegisterNodeRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $0.Signed get nodeCertificate => $_getN(0);
  @$pb.TagNumber(1)
  set nodeCertificate($0.Signed value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasNodeCertificate() => $_has(0);
  @$pb.TagNumber(1)
  void clearNodeCertificate() => $_clearField(1);
  @$pb.TagNumber(1)
  $0.Signed ensureNodeCertificate() => $_ensure(0);

  @$pb.TagNumber(2)
  $fixnum.Int64 get capacityBytes => $_getI64(1);
  @$pb.TagNumber(2)
  set capacityBytes($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasCapacityBytes() => $_has(1);
  @$pb.TagNumber(2)
  void clearCapacityBytes() => $_clearField(2);

  @$pb.TagNumber(3)
  $pb.PbList<$core.String> get endpoints => $_getList(2);

  @$pb.TagNumber(4)
  $pb.PbList<$core.int> get versions => $_getList(3);

  @$pb.TagNumber(5)
  $core.String get software => $_getSZ(4);
  @$pb.TagNumber(5)
  set software($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasSoftware() => $_has(4);
  @$pb.TagNumber(5)
  void clearSoftware() => $_clearField(5);
}

class RegisterNodeResponse extends $pb.GeneratedMessage {
  factory RegisterNodeResponse({
    $core.Iterable<$core.List<$core.int>>? coordinatorKeys,
  }) {
    final result = RegisterNodeResponse._();
    if (coordinatorKeys != null) result.coordinatorKeys.addAll(coordinatorKeys);
    return result;
  }

  RegisterNodeResponse._();

  factory RegisterNodeResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RegisterNodeResponse()..mergeFromBuffer(data, registry);
  factory RegisterNodeResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RegisterNodeResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RegisterNodeResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: RegisterNodeResponse.$_createMessage)
    ..p<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'coordinatorKeys', $pb.PbFieldType.PY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RegisterNodeResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RegisterNodeResponse copyWith(void Function(RegisterNodeResponse) updates) =>
      super.copyWith((message) => updates(message as RegisterNodeResponse))
          as RegisterNodeResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use RegisterNodeResponse() / RegisterNodeResponse.new instead')
  static RegisterNodeResponse create() => RegisterNodeResponse._();
  static $pb.GeneratedMessage $_createMessage() => RegisterNodeResponse._();
  @$core.override
  RegisterNodeResponse createEmptyInstance() => RegisterNodeResponse._();
  @$core.pragma('dart2js:noInline')
  static RegisterNodeResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RegisterNodeResponse>(
          RegisterNodeResponse.$_createMessage);
  static RegisterNodeResponse? _defaultInstance;

  /// Ключи, которыми координатор подписывает талоны сейчас; узел сверяет их
  /// с вшитым списком (protocol.md, раздел 5.1), но доверяет только ему.
  @$pb.TagNumber(1)
  $pb.PbList<$core.List<$core.int>> get coordinatorKeys => $_getList(0);
}

class HeartbeatRequest extends $pb.GeneratedMessage {
  factory HeartbeatRequest({
    $fixnum.Int64? usedBytes,
    $fixnum.Int64? capacityBytes,
    $core.Iterable<$core.String>? endpoints,
    $fixnum.Int64? freeBytes,
  }) {
    final result = HeartbeatRequest._();
    if (usedBytes != null) result.usedBytes = usedBytes;
    if (capacityBytes != null) result.capacityBytes = capacityBytes;
    if (endpoints != null) result.endpoints.addAll(endpoints);
    if (freeBytes != null) result.freeBytes = freeBytes;
    return result;
  }

  HeartbeatRequest._();

  factory HeartbeatRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      HeartbeatRequest()..mergeFromBuffer(data, registry);
  factory HeartbeatRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      HeartbeatRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'HeartbeatRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: HeartbeatRequest.$_createMessage)
    ..a<$fixnum.Int64>(
        1, _omitFieldNames ? '' : 'usedBytes', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(
        2, _omitFieldNames ? '' : 'capacityBytes', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..pPS(3, _omitFieldNames ? '' : 'endpoints')
    ..a<$fixnum.Int64>(
        4, _omitFieldNames ? '' : 'freeBytes', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HeartbeatRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HeartbeatRequest copyWith(void Function(HeartbeatRequest) updates) =>
      super.copyWith((message) => updates(message as HeartbeatRequest))
          as HeartbeatRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use HeartbeatRequest() / HeartbeatRequest.new instead')
  static HeartbeatRequest create() => HeartbeatRequest._();
  static $pb.GeneratedMessage $_createMessage() => HeartbeatRequest._();
  @$core.override
  HeartbeatRequest createEmptyInstance() => HeartbeatRequest._();
  @$core.pragma('dart2js:noInline')
  static HeartbeatRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<HeartbeatRequest>(
          HeartbeatRequest.$_createMessage);
  static HeartbeatRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get usedBytes => $_getI64(0);
  @$pb.TagNumber(1)
  set usedBytes($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasUsedBytes() => $_has(0);
  @$pb.TagNumber(1)
  void clearUsedBytes() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get capacityBytes => $_getI64(1);
  @$pb.TagNumber(2)
  set capacityBytes($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasCapacityBytes() => $_has(1);
  @$pb.TagNumber(2)
  void clearCapacityBytes() => $_clearField(2);

  @$pb.TagNumber(3)
  $pb.PbList<$core.String> get endpoints => $_getList(2);

  /// Сколько ещё байт фрагментов узел готов принять сейчас: меньшее из
  /// остатка квоты и свободного места на диске за вычетом запаса
  /// (protocol.md, раздел 4.9). Нет поля — узел не сообщает, координатор
  /// считает по ёмкости.
  @$pb.TagNumber(4)
  $fixnum.Int64 get freeBytes => $_getI64(3);
  @$pb.TagNumber(4)
  set freeBytes($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasFreeBytes() => $_has(3);
  @$pb.TagNumber(4)
  void clearFreeBytes() => $_clearField(4);
}

class HeartbeatResponse extends $pb.GeneratedMessage {
  factory HeartbeatResponse({
    $core.int? nextHeartbeatMs,
    $core.bool? reconcile,
    NodeStanding? standing,
  }) {
    final result = HeartbeatResponse._();
    if (nextHeartbeatMs != null) result.nextHeartbeatMs = nextHeartbeatMs;
    if (reconcile != null) result.reconcile = reconcile;
    if (standing != null) result.standing = standing;
    return result;
  }

  HeartbeatResponse._();

  factory HeartbeatResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      HeartbeatResponse()..mergeFromBuffer(data, registry);
  factory HeartbeatResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      HeartbeatResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'HeartbeatResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: HeartbeatResponse.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'nextHeartbeatMs',
        fieldType: $pb.PbFieldType.OU3)
    ..aOB(2, _omitFieldNames ? '' : 'reconcile')
    ..aOM<NodeStanding>(3, _omitFieldNames ? '' : 'standing',
        subBuilder: NodeStanding.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HeartbeatResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HeartbeatResponse copyWith(void Function(HeartbeatResponse) updates) =>
      super.copyWith((message) => updates(message as HeartbeatResponse))
          as HeartbeatResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use HeartbeatResponse() / HeartbeatResponse.new instead')
  static HeartbeatResponse create() => HeartbeatResponse._();
  static $pb.GeneratedMessage $_createMessage() => HeartbeatResponse._();
  @$core.override
  HeartbeatResponse createEmptyInstance() => HeartbeatResponse._();
  @$core.pragma('dart2js:noInline')
  static HeartbeatResponse getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<HeartbeatResponse>(
          HeartbeatResponse.$_createMessage);
  static HeartbeatResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get nextHeartbeatMs => $_getIZ(0);
  @$pb.TagNumber(1)
  set nextHeartbeatMs($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasNextHeartbeatMs() => $_has(0);
  @$pb.TagNumber(1)
  void clearNextHeartbeatMs() => $_clearField(1);

  /// Пора сверить фрагменты узла (ReconcileFragments, задача 4.4.3):
  /// координатор перестал учитывать какие-то из них — ремонт перенёс их на
  /// другие узлы, сегмент удалён, загрузка не засчитана.
  @$pb.TagNumber(2)
  $core.bool get reconcile => $_getBF(1);
  @$pb.TagNumber(2)
  set reconcile($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasReconcile() => $_has(1);
  @$pb.TagNumber(2)
  void clearReconcile() => $_clearField(2);

  /// Как координатор видит узел сейчас — для статистики хранителя в
  /// приложении (задача 5.5.2). Нет поля — старый координатор.
  @$pb.TagNumber(3)
  NodeStanding get standing => $_getN(2);
  @$pb.TagNumber(3)
  set standing(NodeStanding value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasStanding() => $_has(2);
  @$pb.TagNumber(3)
  void clearStanding() => $_clearField(3);
  @$pb.TagNumber(3)
  NodeStanding ensureStanding() => $_ensure(2);
}

/// Положение узла у координатора (protocol.md, раздел 4.9).
class NodeStanding extends $pb.GeneratedMessage {
  factory NodeStanding({
    $core.double? availability,
    $core.double? reputation,
    $core.bool? onProbation,
    $fixnum.Int64? probationEndsUnixMs,
    $fixnum.Int64? auditsPassed,
    $fixnum.Int64? auditsFailed,
    $core.bool? excluded,
    $fixnum.Int64? registeredUnixMs,
  }) {
    final result = NodeStanding._();
    if (availability != null) result.availability = availability;
    if (reputation != null) result.reputation = reputation;
    if (onProbation != null) result.onProbation = onProbation;
    if (probationEndsUnixMs != null)
      result.probationEndsUnixMs = probationEndsUnixMs;
    if (auditsPassed != null) result.auditsPassed = auditsPassed;
    if (auditsFailed != null) result.auditsFailed = auditsFailed;
    if (excluded != null) result.excluded = excluded;
    if (registeredUnixMs != null) result.registeredUnixMs = registeredUnixMs;
    return result;
  }

  NodeStanding._();

  factory NodeStanding.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      NodeStanding()..mergeFromBuffer(data, registry);
  factory NodeStanding.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      NodeStanding()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'NodeStanding',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: NodeStanding.$_createMessage)
    ..aD(1, _omitFieldNames ? '' : 'availability')
    ..aD(2, _omitFieldNames ? '' : 'reputation')
    ..aOB(3, _omitFieldNames ? '' : 'onProbation')
    ..aInt64(4, _omitFieldNames ? '' : 'probationEndsUnixMs')
    ..a<$fixnum.Int64>(
        5, _omitFieldNames ? '' : 'auditsPassed', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(
        6, _omitFieldNames ? '' : 'auditsFailed', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOB(7, _omitFieldNames ? '' : 'excluded')
    ..aInt64(8, _omitFieldNames ? '' : 'registeredUnixMs')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  NodeStanding clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  NodeStanding copyWith(void Function(NodeStanding) updates) =>
      super.copyWith((message) => updates(message as NodeStanding))
          as NodeStanding;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use NodeStanding() / NodeStanding.new instead')
  static NodeStanding create() => NodeStanding._();
  static $pb.GeneratedMessage $_createMessage() => NodeStanding._();
  @$core.override
  NodeStanding createEmptyInstance() => NodeStanding._();
  @$core.pragma('dart2js:noInline')
  static NodeStanding getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<NodeStanding>(
          NodeStanding.$_createMessage);
  static NodeStanding? _defaultInstance;

  @$pb.TagNumber(1)
  $core.double get availability => $_getN(0);
  @$pb.TagNumber(1)
  set availability($core.double value) => $_setDouble(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAvailability() => $_has(0);
  @$pb.TagNumber(1)
  void clearAvailability() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.double get reputation => $_getN(1);
  @$pb.TagNumber(2)
  set reputation($core.double value) => $_setDouble(1, value);
  @$pb.TagNumber(2)
  $core.bool hasReputation() => $_has(1);
  @$pb.TagNumber(2)
  void clearReputation() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.bool get onProbation => $_getBF(2);
  @$pb.TagNumber(3)
  set onProbation($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasOnProbation() => $_has(2);
  @$pb.TagNumber(3)
  void clearOnProbation() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get probationEndsUnixMs => $_getI64(3);
  @$pb.TagNumber(4)
  set probationEndsUnixMs($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasProbationEndsUnixMs() => $_has(3);
  @$pb.TagNumber(4)
  void clearProbationEndsUnixMs() => $_clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get auditsPassed => $_getI64(4);
  @$pb.TagNumber(5)
  set auditsPassed($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(5)
  $core.bool hasAuditsPassed() => $_has(4);
  @$pb.TagNumber(5)
  void clearAuditsPassed() => $_clearField(5);

  @$pb.TagNumber(6)
  $fixnum.Int64 get auditsFailed => $_getI64(5);
  @$pb.TagNumber(6)
  set auditsFailed($fixnum.Int64 value) => $_setInt64(5, value);
  @$pb.TagNumber(6)
  $core.bool hasAuditsFailed() => $_has(5);
  @$pb.TagNumber(6)
  void clearAuditsFailed() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.bool get excluded => $_getBF(6);
  @$pb.TagNumber(7)
  set excluded($core.bool value) => $_setBool(6, value);
  @$pb.TagNumber(7)
  $core.bool hasExcluded() => $_has(6);
  @$pb.TagNumber(7)
  void clearExcluded() => $_clearField(7);

  @$pb.TagNumber(8)
  $fixnum.Int64 get registeredUnixMs => $_getI64(7);
  @$pb.TagNumber(8)
  set registeredUnixMs($fixnum.Int64 value) => $_setInt64(7, value);
  @$pb.TagNumber(8)
  $core.bool hasRegisteredUnixMs() => $_has(7);
  @$pb.TagNumber(8)
  void clearRegisteredUnixMs() => $_clearField(8);
}

/// Узел нашёл у себя фрагменты, не прошедшие проверку целостности или
/// пропавшие с диска (фоновая проверка, задача 3.2.4). Обработка — ремонт
/// (этап 4).
class ReportDamagedFragmentsRequest extends $pb.GeneratedMessage {
  factory ReportDamagedFragmentsRequest({
    $core.Iterable<$core.List<$core.int>>? fragmentIds,
  }) {
    final result = ReportDamagedFragmentsRequest._();
    if (fragmentIds != null) result.fragmentIds.addAll(fragmentIds);
    return result;
  }

  ReportDamagedFragmentsRequest._();

  factory ReportDamagedFragmentsRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ReportDamagedFragmentsRequest()..mergeFromBuffer(data, registry);
  factory ReportDamagedFragmentsRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ReportDamagedFragmentsRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ReportDamagedFragmentsRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: ReportDamagedFragmentsRequest.$_createMessage)
    ..p<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'fragmentIds', $pb.PbFieldType.PY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReportDamagedFragmentsRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReportDamagedFragmentsRequest copyWith(
          void Function(ReportDamagedFragmentsRequest) updates) =>
      super.copyWith(
              (message) => updates(message as ReportDamagedFragmentsRequest))
          as ReportDamagedFragmentsRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use ReportDamagedFragmentsRequest() / ReportDamagedFragmentsRequest.new instead')
  static ReportDamagedFragmentsRequest create() =>
      ReportDamagedFragmentsRequest._();
  static $pb.GeneratedMessage $_createMessage() =>
      ReportDamagedFragmentsRequest._();
  @$core.override
  ReportDamagedFragmentsRequest createEmptyInstance() =>
      ReportDamagedFragmentsRequest._();
  @$core.pragma('dart2js:noInline')
  static ReportDamagedFragmentsRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ReportDamagedFragmentsRequest>(
          ReportDamagedFragmentsRequest.$_createMessage);
  static ReportDamagedFragmentsRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<$core.List<$core.int>> get fragmentIds => $_getList(0);
}

class ReportDamagedFragmentsResponse extends $pb.GeneratedMessage {
  factory ReportDamagedFragmentsResponse({
    $core.int? known,
  }) {
    final result = ReportDamagedFragmentsResponse._();
    if (known != null) result.known = known;
    return result;
  }

  ReportDamagedFragmentsResponse._();

  factory ReportDamagedFragmentsResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ReportDamagedFragmentsResponse()..mergeFromBuffer(data, registry);
  factory ReportDamagedFragmentsResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ReportDamagedFragmentsResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ReportDamagedFragmentsResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: ReportDamagedFragmentsResponse.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'known', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReportDamagedFragmentsResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReportDamagedFragmentsResponse copyWith(
          void Function(ReportDamagedFragmentsResponse) updates) =>
      super.copyWith(
              (message) => updates(message as ReportDamagedFragmentsResponse))
          as ReportDamagedFragmentsResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use ReportDamagedFragmentsResponse() / ReportDamagedFragmentsResponse.new instead')
  static ReportDamagedFragmentsResponse create() =>
      ReportDamagedFragmentsResponse._();
  static $pb.GeneratedMessage $_createMessage() =>
      ReportDamagedFragmentsResponse._();
  @$core.override
  ReportDamagedFragmentsResponse createEmptyInstance() =>
      ReportDamagedFragmentsResponse._();
  @$core.pragma('dart2js:noInline')
  static ReportDamagedFragmentsResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ReportDamagedFragmentsResponse>(
          ReportDamagedFragmentsResponse.$_createMessage);
  static ReportDamagedFragmentsResponse? _defaultInstance;

  /// Сколько из перечисленных фрагментов координатор знает на этом узле;
  /// остальные — фрагменты без ссылок (например, неподтверждённых сегментов).
  @$pb.TagNumber(1)
  $core.int get known => $_getIZ(0);
  @$pb.TagNumber(1)
  set known($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasKnown() => $_has(0);
  @$pb.TagNumber(1)
  void clearKnown() => $_clearField(1);
}

/// Проверка достижимости (задача 3.5.1): координатор подключается по TCP к
/// адресу, с которого пришёл запрос, на каждый порт из списка и начинает
/// рукопожатие Noise XX; порт достижим, если отвечающий во втором сообщении
/// показал статический ключ node_dh из сертификата узла (protocol.md,
/// раздел 4.9). Другие адреса координатор не проверяет: иначе узел мог бы
/// направить его соединения куда угодно.
class CheckReachabilityRequest extends $pb.GeneratedMessage {
  factory CheckReachabilityRequest({
    $core.Iterable<$core.int>? ports,
  }) {
    final result = CheckReachabilityRequest._();
    if (ports != null) result.ports.addAll(ports);
    return result;
  }

  CheckReachabilityRequest._();

  factory CheckReachabilityRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CheckReachabilityRequest()..mergeFromBuffer(data, registry);
  factory CheckReachabilityRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CheckReachabilityRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CheckReachabilityRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: CheckReachabilityRequest.$_createMessage)
    ..p<$core.int>(1, _omitFieldNames ? '' : 'ports', $pb.PbFieldType.KU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CheckReachabilityRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CheckReachabilityRequest copyWith(
          void Function(CheckReachabilityRequest) updates) =>
      super.copyWith((message) => updates(message as CheckReachabilityRequest))
          as CheckReachabilityRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use CheckReachabilityRequest() / CheckReachabilityRequest.new instead')
  static CheckReachabilityRequest create() => CheckReachabilityRequest._();
  static $pb.GeneratedMessage $_createMessage() => CheckReachabilityRequest._();
  @$core.override
  CheckReachabilityRequest createEmptyInstance() =>
      CheckReachabilityRequest._();
  @$core.pragma('dart2js:noInline')
  static CheckReachabilityRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CheckReachabilityRequest>(
          CheckReachabilityRequest.$_createMessage);
  static CheckReachabilityRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<$core.int> get ports => $_getList(0);
}

class CheckReachabilityResponse extends $pb.GeneratedMessage {
  factory CheckReachabilityResponse({
    $core.String? observedAddress,
    $core.Iterable<ReachabilityResult>? results,
  }) {
    final result = CheckReachabilityResponse._();
    if (observedAddress != null) result.observedAddress = observedAddress;
    if (results != null) result.results.addAll(results);
    return result;
  }

  CheckReachabilityResponse._();

  factory CheckReachabilityResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CheckReachabilityResponse()..mergeFromBuffer(data, registry);
  factory CheckReachabilityResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CheckReachabilityResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CheckReachabilityResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: CheckReachabilityResponse.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'observedAddress')
    ..pPM<ReachabilityResult>(2, _omitFieldNames ? '' : 'results',
        subBuilder: ReachabilityResult.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CheckReachabilityResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CheckReachabilityResponse copyWith(
          void Function(CheckReachabilityResponse) updates) =>
      super.copyWith((message) => updates(message as CheckReachabilityResponse))
          as CheckReachabilityResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use CheckReachabilityResponse() / CheckReachabilityResponse.new instead')
  static CheckReachabilityResponse create() => CheckReachabilityResponse._();
  static $pb.GeneratedMessage $_createMessage() =>
      CheckReachabilityResponse._();
  @$core.override
  CheckReachabilityResponse createEmptyInstance() =>
      CheckReachabilityResponse._();
  @$core.pragma('dart2js:noInline')
  static CheckReachabilityResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CheckReachabilityResponse>(
          CheckReachabilityResponse.$_createMessage);
  static CheckReachabilityResponse? _defaultInstance;

  /// Адрес, с которого пришёл запрос (IPv4 или IPv6 без скобок и порта):
  /// внешний адрес узла, каким его видит координатор.
  @$pb.TagNumber(1)
  $core.String get observedAddress => $_getSZ(0);
  @$pb.TagNumber(1)
  set observedAddress($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasObservedAddress() => $_has(0);
  @$pb.TagNumber(1)
  void clearObservedAddress() => $_clearField(1);

  @$pb.TagNumber(2)
  $pb.PbList<ReachabilityResult> get results => $_getList(1);
}

class ReachabilityResult extends $pb.GeneratedMessage {
  factory ReachabilityResult({
    $core.int? port,
    ReachabilityStatus? status,
  }) {
    final result = ReachabilityResult._();
    if (port != null) result.port = port;
    if (status != null) result.status = status;
    return result;
  }

  ReachabilityResult._();

  factory ReachabilityResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ReachabilityResult()..mergeFromBuffer(data, registry);
  factory ReachabilityResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ReachabilityResult()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ReachabilityResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: ReachabilityResult.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'port', fieldType: $pb.PbFieldType.OU3)
    ..aE<ReachabilityStatus>(2, _omitFieldNames ? '' : 'status',
        enumValues: ReachabilityStatus.values)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReachabilityResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReachabilityResult copyWith(void Function(ReachabilityResult) updates) =>
      super.copyWith((message) => updates(message as ReachabilityResult))
          as ReachabilityResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ReachabilityResult() / ReachabilityResult.new instead')
  static ReachabilityResult create() => ReachabilityResult._();
  static $pb.GeneratedMessage $_createMessage() => ReachabilityResult._();
  @$core.override
  ReachabilityResult createEmptyInstance() => ReachabilityResult._();
  @$core.pragma('dart2js:noInline')
  static ReachabilityResult getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ReachabilityResult>(
          ReachabilityResult.$_createMessage);
  static ReachabilityResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get port => $_getIZ(0);
  @$pb.TagNumber(1)
  set port($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPort() => $_has(0);
  @$pb.TagNumber(1)
  void clearPort() => $_clearField(1);

  @$pb.TagNumber(2)
  ReachabilityStatus get status => $_getN(1);
  @$pb.TagNumber(2)
  set status(ReachabilityStatus value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasStatus() => $_has(1);
  @$pb.TagNumber(2)
  void clearStatus() => $_clearField(2);
}

/// Узел начинает привязку. Подписан ключом узла (ещё без сертификата, ключ
/// может быть неизвестен координатору).
class NodePairStartRequest extends $pb.GeneratedMessage {
  factory NodePairStartRequest({
    $core.List<$core.int>? nodeDh,
  }) {
    final result = NodePairStartRequest._();
    if (nodeDh != null) result.nodeDh = nodeDh;
    return result;
  }

  NodePairStartRequest._();

  factory NodePairStartRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      NodePairStartRequest()..mergeFromBuffer(data, registry);
  factory NodePairStartRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      NodePairStartRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'NodePairStartRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: NodePairStartRequest.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'nodeDh', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  NodePairStartRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  NodePairStartRequest copyWith(void Function(NodePairStartRequest) updates) =>
      super.copyWith((message) => updates(message as NodePairStartRequest))
          as NodePairStartRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use NodePairStartRequest() / NodePairStartRequest.new instead')
  static NodePairStartRequest create() => NodePairStartRequest._();
  static $pb.GeneratedMessage $_createMessage() => NodePairStartRequest._();
  @$core.override
  NodePairStartRequest createEmptyInstance() => NodePairStartRequest._();
  @$core.pragma('dart2js:noInline')
  static NodePairStartRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<NodePairStartRequest>(
          NodePairStartRequest.$_createMessage);
  static NodePairStartRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get nodeDh => $_getN(0);
  @$pb.TagNumber(1)
  set nodeDh($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasNodeDh() => $_has(0);
  @$pb.TagNumber(1)
  void clearNodeDh() => $_clearField(1);
}

class NodePairStartResponse extends $pb.GeneratedMessage {
  factory NodePairStartResponse({
    $core.String? code,
    $fixnum.Int64? expiresAtUnixMs,
  }) {
    final result = NodePairStartResponse._();
    if (code != null) result.code = code;
    if (expiresAtUnixMs != null) result.expiresAtUnixMs = expiresAtUnixMs;
    return result;
  }

  NodePairStartResponse._();

  factory NodePairStartResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      NodePairStartResponse()..mergeFromBuffer(data, registry);
  factory NodePairStartResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      NodePairStartResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'NodePairStartResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: NodePairStartResponse.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'code')
    ..aInt64(2, _omitFieldNames ? '' : 'expiresAtUnixMs')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  NodePairStartResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  NodePairStartResponse copyWith(
          void Function(NodePairStartResponse) updates) =>
      super.copyWith((message) => updates(message as NodePairStartResponse))
          as NodePairStartResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use NodePairStartResponse() / NodePairStartResponse.new instead')
  static NodePairStartResponse create() => NodePairStartResponse._();
  static $pb.GeneratedMessage $_createMessage() => NodePairStartResponse._();
  @$core.override
  NodePairStartResponse createEmptyInstance() => NodePairStartResponse._();
  @$core.pragma('dart2js:noInline')
  static NodePairStartResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<NodePairStartResponse>(
          NodePairStartResponse.$_createMessage);
  static NodePairStartResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get code => $_getSZ(0);
  @$pb.TagNumber(1)
  set code($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasCode() => $_has(0);
  @$pb.TagNumber(1)
  void clearCode() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get expiresAtUnixMs => $_getI64(1);
  @$pb.TagNumber(2)
  set expiresAtUnixMs($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasExpiresAtUnixMs() => $_has(1);
  @$pb.TagNumber(2)
  void clearExpiresAtUnixMs() => $_clearField(2);
}

/// Узел спрашивает, не подписан ли его сертификат. Подписан ключом узла.
class NodePairStatusRequest extends $pb.GeneratedMessage {
  factory NodePairStatusRequest() => NodePairStatusRequest._();

  NodePairStatusRequest._();

  factory NodePairStatusRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      NodePairStatusRequest()..mergeFromBuffer(data, registry);
  factory NodePairStatusRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      NodePairStatusRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'NodePairStatusRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: NodePairStatusRequest.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  NodePairStatusRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  NodePairStatusRequest copyWith(
          void Function(NodePairStatusRequest) updates) =>
      super.copyWith((message) => updates(message as NodePairStatusRequest))
          as NodePairStatusRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use NodePairStatusRequest() / NodePairStatusRequest.new instead')
  static NodePairStatusRequest create() => NodePairStatusRequest._();
  static $pb.GeneratedMessage $_createMessage() => NodePairStatusRequest._();
  @$core.override
  NodePairStatusRequest createEmptyInstance() => NodePairStatusRequest._();
  @$core.pragma('dart2js:noInline')
  static NodePairStatusRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<NodePairStatusRequest>(
          NodePairStatusRequest.$_createMessage);
  static NodePairStatusRequest? _defaultInstance;
}

class NodePairStatusResponse extends $pb.GeneratedMessage {
  factory NodePairStatusResponse({
    NodePairStatus? status,
    $0.Signed? nodeCertificate,
    $fixnum.Int64? expiresAtUnixMs,
  }) {
    final result = NodePairStatusResponse._();
    if (status != null) result.status = status;
    if (nodeCertificate != null) result.nodeCertificate = nodeCertificate;
    if (expiresAtUnixMs != null) result.expiresAtUnixMs = expiresAtUnixMs;
    return result;
  }

  NodePairStatusResponse._();

  factory NodePairStatusResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      NodePairStatusResponse()..mergeFromBuffer(data, registry);
  factory NodePairStatusResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      NodePairStatusResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'NodePairStatusResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: NodePairStatusResponse.$_createMessage)
    ..aE<NodePairStatus>(1, _omitFieldNames ? '' : 'status',
        enumValues: NodePairStatus.values)
    ..aOM<$0.Signed>(2, _omitFieldNames ? '' : 'nodeCertificate',
        subBuilder: $0.Signed.$_createMessage)
    ..aInt64(3, _omitFieldNames ? '' : 'expiresAtUnixMs')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  NodePairStatusResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  NodePairStatusResponse copyWith(
          void Function(NodePairStatusResponse) updates) =>
      super.copyWith((message) => updates(message as NodePairStatusResponse))
          as NodePairStatusResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use NodePairStatusResponse() / NodePairStatusResponse.new instead')
  static NodePairStatusResponse create() => NodePairStatusResponse._();
  static $pb.GeneratedMessage $_createMessage() => NodePairStatusResponse._();
  @$core.override
  NodePairStatusResponse createEmptyInstance() => NodePairStatusResponse._();
  @$core.pragma('dart2js:noInline')
  static NodePairStatusResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<NodePairStatusResponse>(
          NodePairStatusResponse.$_createMessage);
  static NodePairStatusResponse? _defaultInstance;

  @$pb.TagNumber(1)
  NodePairStatus get status => $_getN(0);
  @$pb.TagNumber(1)
  set status(NodePairStatus value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasStatus() => $_has(0);
  @$pb.TagNumber(1)
  void clearStatus() => $_clearField(1);

  @$pb.TagNumber(2)
  $0.Signed get nodeCertificate => $_getN(1);
  @$pb.TagNumber(2)
  set nodeCertificate($0.Signed value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasNodeCertificate() => $_has(1);
  @$pb.TagNumber(2)
  void clearNodeCertificate() => $_clearField(2);
  @$pb.TagNumber(2)
  $0.Signed ensureNodeCertificate() => $_ensure(1);

  @$pb.TagNumber(3)
  $fixnum.Int64 get expiresAtUnixMs => $_getI64(2);
  @$pb.TagNumber(3)
  set expiresAtUnixMs($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasExpiresAtUnixMs() => $_has(2);
  @$pb.TagNumber(3)
  void clearExpiresAtUnixMs() => $_clearField(3);
}

/// Владелец вводит код и узнаёт ключи узла, чтобы сверить отпечаток.
/// Подписан ключом учётной записи.
class NodePairLookupRequest extends $pb.GeneratedMessage {
  factory NodePairLookupRequest({
    $core.String? code,
  }) {
    final result = NodePairLookupRequest._();
    if (code != null) result.code = code;
    return result;
  }

  NodePairLookupRequest._();

  factory NodePairLookupRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      NodePairLookupRequest()..mergeFromBuffer(data, registry);
  factory NodePairLookupRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      NodePairLookupRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'NodePairLookupRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: NodePairLookupRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'code')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  NodePairLookupRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  NodePairLookupRequest copyWith(
          void Function(NodePairLookupRequest) updates) =>
      super.copyWith((message) => updates(message as NodePairLookupRequest))
          as NodePairLookupRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use NodePairLookupRequest() / NodePairLookupRequest.new instead')
  static NodePairLookupRequest create() => NodePairLookupRequest._();
  static $pb.GeneratedMessage $_createMessage() => NodePairLookupRequest._();
  @$core.override
  NodePairLookupRequest createEmptyInstance() => NodePairLookupRequest._();
  @$core.pragma('dart2js:noInline')
  static NodePairLookupRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<NodePairLookupRequest>(
          NodePairLookupRequest.$_createMessage);
  static NodePairLookupRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get code => $_getSZ(0);
  @$pb.TagNumber(1)
  set code($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasCode() => $_has(0);
  @$pb.TagNumber(1)
  void clearCode() => $_clearField(1);
}

class NodePairLookupResponse extends $pb.GeneratedMessage {
  factory NodePairLookupResponse({
    $core.List<$core.int>? nodeId,
    $core.List<$core.int>? nodeDh,
    $fixnum.Int64? expiresAtUnixMs,
  }) {
    final result = NodePairLookupResponse._();
    if (nodeId != null) result.nodeId = nodeId;
    if (nodeDh != null) result.nodeDh = nodeDh;
    if (expiresAtUnixMs != null) result.expiresAtUnixMs = expiresAtUnixMs;
    return result;
  }

  NodePairLookupResponse._();

  factory NodePairLookupResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      NodePairLookupResponse()..mergeFromBuffer(data, registry);
  factory NodePairLookupResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      NodePairLookupResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'NodePairLookupResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: NodePairLookupResponse.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'nodeId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'nodeDh', $pb.PbFieldType.OY)
    ..aInt64(3, _omitFieldNames ? '' : 'expiresAtUnixMs')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  NodePairLookupResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  NodePairLookupResponse copyWith(
          void Function(NodePairLookupResponse) updates) =>
      super.copyWith((message) => updates(message as NodePairLookupResponse))
          as NodePairLookupResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use NodePairLookupResponse() / NodePairLookupResponse.new instead')
  static NodePairLookupResponse create() => NodePairLookupResponse._();
  static $pb.GeneratedMessage $_createMessage() => NodePairLookupResponse._();
  @$core.override
  NodePairLookupResponse createEmptyInstance() => NodePairLookupResponse._();
  @$core.pragma('dart2js:noInline')
  static NodePairLookupResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<NodePairLookupResponse>(
          NodePairLookupResponse.$_createMessage);
  static NodePairLookupResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get nodeId => $_getN(0);
  @$pb.TagNumber(1)
  set nodeId($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasNodeId() => $_has(0);
  @$pb.TagNumber(1)
  void clearNodeId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get nodeDh => $_getN(1);
  @$pb.TagNumber(2)
  set nodeDh($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasNodeDh() => $_has(1);
  @$pb.TagNumber(2)
  void clearNodeDh() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get expiresAtUnixMs => $_getI64(2);
  @$pb.TagNumber(3)
  set expiresAtUnixMs($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasExpiresAtUnixMs() => $_has(2);
  @$pb.TagNumber(3)
  void clearExpiresAtUnixMs() => $_clearField(3);
}

/// Владелец подтвердил отпечаток и передаёт подписанный сертификат узла.
/// Подписан ключом учётной записи.
class NodePairSignRequest extends $pb.GeneratedMessage {
  factory NodePairSignRequest({
    $core.String? code,
    $0.Signed? nodeCertificate,
  }) {
    final result = NodePairSignRequest._();
    if (code != null) result.code = code;
    if (nodeCertificate != null) result.nodeCertificate = nodeCertificate;
    return result;
  }

  NodePairSignRequest._();

  factory NodePairSignRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      NodePairSignRequest()..mergeFromBuffer(data, registry);
  factory NodePairSignRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      NodePairSignRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'NodePairSignRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: NodePairSignRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'code')
    ..aOM<$0.Signed>(2, _omitFieldNames ? '' : 'nodeCertificate',
        subBuilder: $0.Signed.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  NodePairSignRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  NodePairSignRequest copyWith(void Function(NodePairSignRequest) updates) =>
      super.copyWith((message) => updates(message as NodePairSignRequest))
          as NodePairSignRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use NodePairSignRequest() / NodePairSignRequest.new instead')
  static NodePairSignRequest create() => NodePairSignRequest._();
  static $pb.GeneratedMessage $_createMessage() => NodePairSignRequest._();
  @$core.override
  NodePairSignRequest createEmptyInstance() => NodePairSignRequest._();
  @$core.pragma('dart2js:noInline')
  static NodePairSignRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<NodePairSignRequest>(
          NodePairSignRequest.$_createMessage);
  static NodePairSignRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get code => $_getSZ(0);
  @$pb.TagNumber(1)
  set code($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasCode() => $_has(0);
  @$pb.TagNumber(1)
  void clearCode() => $_clearField(1);

  @$pb.TagNumber(2)
  $0.Signed get nodeCertificate => $_getN(1);
  @$pb.TagNumber(2)
  set nodeCertificate($0.Signed value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasNodeCertificate() => $_has(1);
  @$pb.TagNumber(2)
  void clearNodeCertificate() => $_clearField(2);
  @$pb.TagNumber(2)
  $0.Signed ensureNodeCertificate() => $_ensure(1);
}

class NodePairSignResponse extends $pb.GeneratedMessage {
  factory NodePairSignResponse() => NodePairSignResponse._();

  NodePairSignResponse._();

  factory NodePairSignResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      NodePairSignResponse()..mergeFromBuffer(data, registry);
  factory NodePairSignResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      NodePairSignResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'NodePairSignResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: NodePairSignResponse.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  NodePairSignResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  NodePairSignResponse copyWith(void Function(NodePairSignResponse) updates) =>
      super.copyWith((message) => updates(message as NodePairSignResponse))
          as NodePairSignResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use NodePairSignResponse() / NodePairSignResponse.new instead')
  static NodePairSignResponse create() => NodePairSignResponse._();
  static $pb.GeneratedMessage $_createMessage() => NodePairSignResponse._();
  @$core.override
  NodePairSignResponse createEmptyInstance() => NodePairSignResponse._();
  @$core.pragma('dart2js:noInline')
  static NodePairSignResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<NodePairSignResponse>(
          NodePairSignResponse.$_createMessage);
  static NodePairSignResponse? _defaultInstance;
}

enum NodeChannelMessage_Body {
  heartbeat,
  done,
  error,
  rendezvous,
  audit,
  notSet
}

class NodeChannelMessage extends $pb.GeneratedMessage {
  factory NodeChannelMessage({
    $fixnum.Int64? id,
    $fixnum.Int64? replyTo,
    HeartbeatRequest? heartbeat,
    CommandDone? done,
    $0.Error? error,
    RendezvousReply? rendezvous,
    AuditReply? audit,
  }) {
    final result = NodeChannelMessage._();
    if (id != null) result.id = id;
    if (replyTo != null) result.replyTo = replyTo;
    if (heartbeat != null) result.heartbeat = heartbeat;
    if (done != null) result.done = done;
    if (error != null) result.error = error;
    if (rendezvous != null) result.rendezvous = rendezvous;
    if (audit != null) result.audit = audit;
    return result;
  }

  NodeChannelMessage._();

  factory NodeChannelMessage.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      NodeChannelMessage()..mergeFromBuffer(data, registry);
  factory NodeChannelMessage.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      NodeChannelMessage()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, NodeChannelMessage_Body>
      _NodeChannelMessage_BodyByTag = {
    3: NodeChannelMessage_Body.heartbeat,
    4: NodeChannelMessage_Body.done,
    5: NodeChannelMessage_Body.error,
    6: NodeChannelMessage_Body.rendezvous,
    7: NodeChannelMessage_Body.audit,
    0: NodeChannelMessage_Body.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'NodeChannelMessage',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: NodeChannelMessage.$_createMessage)
    ..oo(0, [3, 4, 5, 6, 7])
    ..a<$fixnum.Int64>(1, _omitFieldNames ? '' : 'id', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(2, _omitFieldNames ? '' : 'replyTo', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOM<HeartbeatRequest>(3, _omitFieldNames ? '' : 'heartbeat',
        subBuilder: HeartbeatRequest.$_createMessage)
    ..aOM<CommandDone>(4, _omitFieldNames ? '' : 'done',
        subBuilder: CommandDone.$_createMessage)
    ..aOM<$0.Error>(5, _omitFieldNames ? '' : 'error',
        subBuilder: $0.Error.$_createMessage)
    ..aOM<RendezvousReply>(6, _omitFieldNames ? '' : 'rendezvous',
        subBuilder: RendezvousReply.$_createMessage)
    ..aOM<AuditReply>(7, _omitFieldNames ? '' : 'audit',
        subBuilder: AuditReply.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  NodeChannelMessage clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  NodeChannelMessage copyWith(void Function(NodeChannelMessage) updates) =>
      super.copyWith((message) => updates(message as NodeChannelMessage))
          as NodeChannelMessage;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use NodeChannelMessage() / NodeChannelMessage.new instead')
  static NodeChannelMessage create() => NodeChannelMessage._();
  static $pb.GeneratedMessage $_createMessage() => NodeChannelMessage._();
  @$core.override
  NodeChannelMessage createEmptyInstance() => NodeChannelMessage._();
  @$core.pragma('dart2js:noInline')
  static NodeChannelMessage getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<NodeChannelMessage>(
          NodeChannelMessage.$_createMessage);
  static NodeChannelMessage? _defaultInstance;

  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  @$pb.TagNumber(5)
  @$pb.TagNumber(6)
  @$pb.TagNumber(7)
  NodeChannelMessage_Body whichBody() =>
      _NodeChannelMessage_BodyByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  @$pb.TagNumber(5)
  @$pb.TagNumber(6)
  @$pb.TagNumber(7)
  void clearBody() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  $fixnum.Int64 get id => $_getI64(0);
  @$pb.TagNumber(1)
  set id($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get replyTo => $_getI64(1);
  @$pb.TagNumber(2)
  set replyTo($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasReplyTo() => $_has(1);
  @$pb.TagNumber(2)
  void clearReplyTo() => $_clearField(2);

  @$pb.TagNumber(3)
  HeartbeatRequest get heartbeat => $_getN(2);
  @$pb.TagNumber(3)
  set heartbeat(HeartbeatRequest value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasHeartbeat() => $_has(2);
  @$pb.TagNumber(3)
  void clearHeartbeat() => $_clearField(3);
  @$pb.TagNumber(3)
  HeartbeatRequest ensureHeartbeat() => $_ensure(2);

  @$pb.TagNumber(4)
  CommandDone get done => $_getN(3);
  @$pb.TagNumber(4)
  set done(CommandDone value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasDone() => $_has(3);
  @$pb.TagNumber(4)
  void clearDone() => $_clearField(4);
  @$pb.TagNumber(4)
  CommandDone ensureDone() => $_ensure(3);

  @$pb.TagNumber(5)
  $0.Error get error => $_getN(4);
  @$pb.TagNumber(5)
  set error($0.Error value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasError() => $_has(4);
  @$pb.TagNumber(5)
  void clearError() => $_clearField(5);
  @$pb.TagNumber(5)
  $0.Error ensureError() => $_ensure(4);

  @$pb.TagNumber(6)
  RendezvousReply get rendezvous => $_getN(5);
  @$pb.TagNumber(6)
  set rendezvous(RendezvousReply value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasRendezvous() => $_has(5);
  @$pb.TagNumber(6)
  void clearRendezvous() => $_clearField(6);
  @$pb.TagNumber(6)
  RendezvousReply ensureRendezvous() => $_ensure(5);

  @$pb.TagNumber(7)
  AuditReply get audit => $_getN(6);
  @$pb.TagNumber(7)
  set audit(AuditReply value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasAudit() => $_has(6);
  @$pb.TagNumber(7)
  void clearAudit() => $_clearField(7);
  @$pb.TagNumber(7)
  AuditReply ensureAudit() => $_ensure(6);
}

enum CoordinatorChannelMessage_Body {
  heartbeat,
  error,
  ping,
  syncRevocations,
  rendezvous,
  audit,
  repair,
  relocate,
  notSet
}

class CoordinatorChannelMessage extends $pb.GeneratedMessage {
  factory CoordinatorChannelMessage({
    $fixnum.Int64? id,
    $fixnum.Int64? replyTo,
    HeartbeatResponse? heartbeat,
    $0.Error? error,
    PingCommand? ping,
    SyncRevocationsCommand? syncRevocations,
    RendezvousCommand? rendezvous,
    AuditCommand? audit,
    RepairCommand? repair,
    RelocateCommand? relocate,
  }) {
    final result = CoordinatorChannelMessage._();
    if (id != null) result.id = id;
    if (replyTo != null) result.replyTo = replyTo;
    if (heartbeat != null) result.heartbeat = heartbeat;
    if (error != null) result.error = error;
    if (ping != null) result.ping = ping;
    if (syncRevocations != null) result.syncRevocations = syncRevocations;
    if (rendezvous != null) result.rendezvous = rendezvous;
    if (audit != null) result.audit = audit;
    if (repair != null) result.repair = repair;
    if (relocate != null) result.relocate = relocate;
    return result;
  }

  CoordinatorChannelMessage._();

  factory CoordinatorChannelMessage.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CoordinatorChannelMessage()..mergeFromBuffer(data, registry);
  factory CoordinatorChannelMessage.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CoordinatorChannelMessage()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, CoordinatorChannelMessage_Body>
      _CoordinatorChannelMessage_BodyByTag = {
    3: CoordinatorChannelMessage_Body.heartbeat,
    4: CoordinatorChannelMessage_Body.error,
    5: CoordinatorChannelMessage_Body.ping,
    6: CoordinatorChannelMessage_Body.syncRevocations,
    7: CoordinatorChannelMessage_Body.rendezvous,
    8: CoordinatorChannelMessage_Body.audit,
    9: CoordinatorChannelMessage_Body.repair,
    10: CoordinatorChannelMessage_Body.relocate,
    0: CoordinatorChannelMessage_Body.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CoordinatorChannelMessage',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: CoordinatorChannelMessage.$_createMessage)
    ..oo(0, [3, 4, 5, 6, 7, 8, 9, 10])
    ..a<$fixnum.Int64>(1, _omitFieldNames ? '' : 'id', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(2, _omitFieldNames ? '' : 'replyTo', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOM<HeartbeatResponse>(3, _omitFieldNames ? '' : 'heartbeat',
        subBuilder: HeartbeatResponse.$_createMessage)
    ..aOM<$0.Error>(4, _omitFieldNames ? '' : 'error',
        subBuilder: $0.Error.$_createMessage)
    ..aOM<PingCommand>(5, _omitFieldNames ? '' : 'ping',
        subBuilder: PingCommand.$_createMessage)
    ..aOM<SyncRevocationsCommand>(6, _omitFieldNames ? '' : 'syncRevocations',
        subBuilder: SyncRevocationsCommand.$_createMessage)
    ..aOM<RendezvousCommand>(7, _omitFieldNames ? '' : 'rendezvous',
        subBuilder: RendezvousCommand.$_createMessage)
    ..aOM<AuditCommand>(8, _omitFieldNames ? '' : 'audit',
        subBuilder: AuditCommand.$_createMessage)
    ..aOM<RepairCommand>(9, _omitFieldNames ? '' : 'repair',
        subBuilder: RepairCommand.$_createMessage)
    ..aOM<RelocateCommand>(10, _omitFieldNames ? '' : 'relocate',
        subBuilder: RelocateCommand.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CoordinatorChannelMessage clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CoordinatorChannelMessage copyWith(
          void Function(CoordinatorChannelMessage) updates) =>
      super.copyWith((message) => updates(message as CoordinatorChannelMessage))
          as CoordinatorChannelMessage;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use CoordinatorChannelMessage() / CoordinatorChannelMessage.new instead')
  static CoordinatorChannelMessage create() => CoordinatorChannelMessage._();
  static $pb.GeneratedMessage $_createMessage() =>
      CoordinatorChannelMessage._();
  @$core.override
  CoordinatorChannelMessage createEmptyInstance() =>
      CoordinatorChannelMessage._();
  @$core.pragma('dart2js:noInline')
  static CoordinatorChannelMessage getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CoordinatorChannelMessage>(
          CoordinatorChannelMessage.$_createMessage);
  static CoordinatorChannelMessage? _defaultInstance;

  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  @$pb.TagNumber(5)
  @$pb.TagNumber(6)
  @$pb.TagNumber(7)
  @$pb.TagNumber(8)
  @$pb.TagNumber(9)
  @$pb.TagNumber(10)
  CoordinatorChannelMessage_Body whichBody() =>
      _CoordinatorChannelMessage_BodyByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  @$pb.TagNumber(5)
  @$pb.TagNumber(6)
  @$pb.TagNumber(7)
  @$pb.TagNumber(8)
  @$pb.TagNumber(9)
  @$pb.TagNumber(10)
  void clearBody() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  $fixnum.Int64 get id => $_getI64(0);
  @$pb.TagNumber(1)
  set id($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get replyTo => $_getI64(1);
  @$pb.TagNumber(2)
  set replyTo($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasReplyTo() => $_has(1);
  @$pb.TagNumber(2)
  void clearReplyTo() => $_clearField(2);

  @$pb.TagNumber(3)
  HeartbeatResponse get heartbeat => $_getN(2);
  @$pb.TagNumber(3)
  set heartbeat(HeartbeatResponse value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasHeartbeat() => $_has(2);
  @$pb.TagNumber(3)
  void clearHeartbeat() => $_clearField(3);
  @$pb.TagNumber(3)
  HeartbeatResponse ensureHeartbeat() => $_ensure(2);

  @$pb.TagNumber(4)
  $0.Error get error => $_getN(3);
  @$pb.TagNumber(4)
  set error($0.Error value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasError() => $_has(3);
  @$pb.TagNumber(4)
  void clearError() => $_clearField(4);
  @$pb.TagNumber(4)
  $0.Error ensureError() => $_ensure(3);

  @$pb.TagNumber(5)
  PingCommand get ping => $_getN(4);
  @$pb.TagNumber(5)
  set ping(PingCommand value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasPing() => $_has(4);
  @$pb.TagNumber(5)
  void clearPing() => $_clearField(5);
  @$pb.TagNumber(5)
  PingCommand ensurePing() => $_ensure(4);

  @$pb.TagNumber(6)
  SyncRevocationsCommand get syncRevocations => $_getN(5);
  @$pb.TagNumber(6)
  set syncRevocations(SyncRevocationsCommand value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasSyncRevocations() => $_has(5);
  @$pb.TagNumber(6)
  void clearSyncRevocations() => $_clearField(6);
  @$pb.TagNumber(6)
  SyncRevocationsCommand ensureSyncRevocations() => $_ensure(5);

  @$pb.TagNumber(7)
  RendezvousCommand get rendezvous => $_getN(6);
  @$pb.TagNumber(7)
  set rendezvous(RendezvousCommand value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasRendezvous() => $_has(6);
  @$pb.TagNumber(7)
  void clearRendezvous() => $_clearField(7);
  @$pb.TagNumber(7)
  RendezvousCommand ensureRendezvous() => $_ensure(6);

  @$pb.TagNumber(8)
  AuditCommand get audit => $_getN(7);
  @$pb.TagNumber(8)
  set audit(AuditCommand value) => $_setField(8, value);
  @$pb.TagNumber(8)
  $core.bool hasAudit() => $_has(7);
  @$pb.TagNumber(8)
  void clearAudit() => $_clearField(8);
  @$pb.TagNumber(8)
  AuditCommand ensureAudit() => $_ensure(7);

  @$pb.TagNumber(9)
  RepairCommand get repair => $_getN(8);
  @$pb.TagNumber(9)
  set repair(RepairCommand value) => $_setField(9, value);
  @$pb.TagNumber(9)
  $core.bool hasRepair() => $_has(8);
  @$pb.TagNumber(9)
  void clearRepair() => $_clearField(9);
  @$pb.TagNumber(9)
  RepairCommand ensureRepair() => $_ensure(8);

  @$pb.TagNumber(10)
  RelocateCommand get relocate => $_getN(9);
  @$pb.TagNumber(10)
  set relocate(RelocateCommand value) => $_setField(10, value);
  @$pb.TagNumber(10)
  $core.bool hasRelocate() => $_has(9);
  @$pb.TagNumber(10)
  void clearRelocate() => $_clearField(10);
  @$pb.TagNumber(10)
  RelocateCommand ensureRelocate() => $_ensure(9);
}

class CommandDone extends $pb.GeneratedMessage {
  factory CommandDone() => CommandDone._();

  CommandDone._();

  factory CommandDone.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CommandDone()..mergeFromBuffer(data, registry);
  factory CommandDone.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CommandDone()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CommandDone',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: CommandDone.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CommandDone clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CommandDone copyWith(void Function(CommandDone) updates) =>
      super.copyWith((message) => updates(message as CommandDone))
          as CommandDone;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use CommandDone() / CommandDone.new instead')
  static CommandDone create() => CommandDone._();
  static $pb.GeneratedMessage $_createMessage() => CommandDone._();
  @$core.override
  CommandDone createEmptyInstance() => CommandDone._();
  @$core.pragma('dart2js:noInline')
  static CommandDone getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<CommandDone>(
          CommandDone.$_createMessage);
  static CommandDone? _defaultInstance;
}

/// Проверка канала: узел отвечает CommandDone.
class PingCommand extends $pb.GeneratedMessage {
  factory PingCommand() => PingCommand._();

  PingCommand._();

  factory PingCommand.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PingCommand()..mergeFromBuffer(data, registry);
  factory PingCommand.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PingCommand()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PingCommand',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: PingCommand.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PingCommand clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PingCommand copyWith(void Function(PingCommand) updates) =>
      super.copyWith((message) => updates(message as PingCommand))
          as PingCommand;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use PingCommand() / PingCommand.new instead')
  static PingCommand create() => PingCommand._();
  static $pb.GeneratedMessage $_createMessage() => PingCommand._();
  @$core.override
  PingCommand createEmptyInstance() => PingCommand._();
  @$core.pragma('dart2js:noInline')
  static PingCommand getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PingCommand>(
          PingCommand.$_createMessage);
  static PingCommand? _defaultInstance;
}

/// Появился отзыв устройства с номером sequence (ListRevocations): узел,
/// у которого номер последнего полученного отзыва меньше, дочитывает список.
class SyncRevocationsCommand extends $pb.GeneratedMessage {
  factory SyncRevocationsCommand({
    $fixnum.Int64? sequence,
  }) {
    final result = SyncRevocationsCommand._();
    if (sequence != null) result.sequence = sequence;
    return result;
  }

  SyncRevocationsCommand._();

  factory SyncRevocationsCommand.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SyncRevocationsCommand()..mergeFromBuffer(data, registry);
  factory SyncRevocationsCommand.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SyncRevocationsCommand()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SyncRevocationsCommand',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: SyncRevocationsCommand.$_createMessage)
    ..a<$fixnum.Int64>(
        1, _omitFieldNames ? '' : 'sequence', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SyncRevocationsCommand clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SyncRevocationsCommand copyWith(
          void Function(SyncRevocationsCommand) updates) =>
      super.copyWith((message) => updates(message as SyncRevocationsCommand))
          as SyncRevocationsCommand;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use SyncRevocationsCommand() / SyncRevocationsCommand.new instead')
  static SyncRevocationsCommand create() => SyncRevocationsCommand._();
  static $pb.GeneratedMessage $_createMessage() => SyncRevocationsCommand._();
  @$core.override
  SyncRevocationsCommand createEmptyInstance() => SyncRevocationsCommand._();
  @$core.pragma('dart2js:noInline')
  static SyncRevocationsCommand getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SyncRevocationsCommand>(
          SyncRevocationsCommand.$_createMessage);
  static SyncRevocationsCommand? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get sequence => $_getI64(0);
  @$pb.TagNumber(1)
  set sequence($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSequence() => $_has(0);
  @$pb.TagNumber(1)
  void clearSequence() => $_clearField(1);
}

/// Адреса сводника. Подписан ключом устройства или узла.
class GetRendezvousInfoRequest extends $pb.GeneratedMessage {
  factory GetRendezvousInfoRequest() => GetRendezvousInfoRequest._();

  GetRendezvousInfoRequest._();

  factory GetRendezvousInfoRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetRendezvousInfoRequest()..mergeFromBuffer(data, registry);
  factory GetRendezvousInfoRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetRendezvousInfoRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetRendezvousInfoRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: GetRendezvousInfoRequest.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetRendezvousInfoRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetRendezvousInfoRequest copyWith(
          void Function(GetRendezvousInfoRequest) updates) =>
      super.copyWith((message) => updates(message as GetRendezvousInfoRequest))
          as GetRendezvousInfoRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use GetRendezvousInfoRequest() / GetRendezvousInfoRequest.new instead')
  static GetRendezvousInfoRequest create() => GetRendezvousInfoRequest._();
  static $pb.GeneratedMessage $_createMessage() => GetRendezvousInfoRequest._();
  @$core.override
  GetRendezvousInfoRequest createEmptyInstance() =>
      GetRendezvousInfoRequest._();
  @$core.pragma('dart2js:noInline')
  static GetRendezvousInfoRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GetRendezvousInfoRequest>(
          GetRendezvousInfoRequest.$_createMessage);
  static GetRendezvousInfoRequest? _defaultInstance;
}

class GetRendezvousInfoResponse extends $pb.GeneratedMessage {
  factory GetRendezvousInfoResponse({
    $core.Iterable<$core.String>? servers,
  }) {
    final result = GetRendezvousInfoResponse._();
    if (servers != null) result.servers.addAll(servers);
    return result;
  }

  GetRendezvousInfoResponse._();

  factory GetRendezvousInfoResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetRendezvousInfoResponse()..mergeFromBuffer(data, registry);
  factory GetRendezvousInfoResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetRendezvousInfoResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetRendezvousInfoResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: GetRendezvousInfoResponse.$_createMessage)
    ..pPS(1, _omitFieldNames ? '' : 'servers')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetRendezvousInfoResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetRendezvousInfoResponse copyWith(
          void Function(GetRendezvousInfoResponse) updates) =>
      super.copyWith((message) => updates(message as GetRendezvousInfoResponse))
          as GetRendezvousInfoResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use GetRendezvousInfoResponse() / GetRendezvousInfoResponse.new instead')
  static GetRendezvousInfoResponse create() => GetRendezvousInfoResponse._();
  static $pb.GeneratedMessage $_createMessage() =>
      GetRendezvousInfoResponse._();
  @$core.override
  GetRendezvousInfoResponse createEmptyInstance() =>
      GetRendezvousInfoResponse._();
  @$core.pragma('dart2js:noInline')
  static GetRendezvousInfoResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GetRendezvousInfoResponse>(
          GetRendezvousInfoResponse.$_createMessage);
  static GetRendezvousInfoResponse? _defaultInstance;

  /// Два адреса "IPv4:порт" — порты сводника; пусто — сведение выключено.
  @$pb.TagNumber(1)
  $pb.PbList<$core.String> get servers => $_getList(0);
}

/// Внешний UDP-адрес стороны, каким его увидел сводник.
class UdpBinding extends $pb.GeneratedMessage {
  factory UdpBinding({
    $core.String? endpoint,
    $core.List<$core.int>? token,
  }) {
    final result = UdpBinding._();
    if (endpoint != null) result.endpoint = endpoint;
    if (token != null) result.token = token;
    return result;
  }

  UdpBinding._();

  factory UdpBinding.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      UdpBinding()..mergeFromBuffer(data, registry);
  factory UdpBinding.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      UdpBinding()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UdpBinding',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: UdpBinding.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'endpoint')
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'token', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UdpBinding clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UdpBinding copyWith(void Function(UdpBinding) updates) =>
      super.copyWith((message) => updates(message as UdpBinding)) as UdpBinding;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use UdpBinding() / UdpBinding.new instead')
  static UdpBinding create() => UdpBinding._();
  static $pb.GeneratedMessage $_createMessage() => UdpBinding._();
  @$core.override
  UdpBinding createEmptyInstance() => UdpBinding._();
  @$core.pragma('dart2js:noInline')
  static UdpBinding getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<UdpBinding>(UdpBinding.$_createMessage);
  static UdpBinding? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get endpoint => $_getSZ(0);
  @$pb.TagNumber(1)
  set endpoint($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasEndpoint() => $_has(0);
  @$pb.TagNumber(1)
  void clearEndpoint() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get token => $_getN(1);
  @$pb.TagNumber(2)
  set token($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasToken() => $_has(1);
  @$pb.TagNumber(2)
  void clearToken() => $_clearField(2);
}

/// Инициатор (клиент или узел при ремонте) просит свести его с узлом.
/// Подписан ключом устройства или узла.
class RendezvousRequest extends $pb.GeneratedMessage {
  factory RendezvousRequest({
    $core.List<$core.int>? nodeId,
    UdpBinding? binding,
  }) {
    final result = RendezvousRequest._();
    if (nodeId != null) result.nodeId = nodeId;
    if (binding != null) result.binding = binding;
    return result;
  }

  RendezvousRequest._();

  factory RendezvousRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RendezvousRequest()..mergeFromBuffer(data, registry);
  factory RendezvousRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RendezvousRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RendezvousRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: RendezvousRequest.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'nodeId', $pb.PbFieldType.OY)
    ..aOM<UdpBinding>(2, _omitFieldNames ? '' : 'binding',
        subBuilder: UdpBinding.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RendezvousRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RendezvousRequest copyWith(void Function(RendezvousRequest) updates) =>
      super.copyWith((message) => updates(message as RendezvousRequest))
          as RendezvousRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use RendezvousRequest() / RendezvousRequest.new instead')
  static RendezvousRequest create() => RendezvousRequest._();
  static $pb.GeneratedMessage $_createMessage() => RendezvousRequest._();
  @$core.override
  RendezvousRequest createEmptyInstance() => RendezvousRequest._();
  @$core.pragma('dart2js:noInline')
  static RendezvousRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RendezvousRequest>(
          RendezvousRequest.$_createMessage);
  static RendezvousRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get nodeId => $_getN(0);
  @$pb.TagNumber(1)
  set nodeId($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasNodeId() => $_has(0);
  @$pb.TagNumber(1)
  void clearNodeId() => $_clearField(1);

  @$pb.TagNumber(2)
  UdpBinding get binding => $_getN(1);
  @$pb.TagNumber(2)
  set binding(UdpBinding value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasBinding() => $_has(1);
  @$pb.TagNumber(2)
  void clearBinding() => $_clearField(2);
  @$pb.TagNumber(2)
  UdpBinding ensureBinding() => $_ensure(1);
}

class RendezvousResponse extends $pb.GeneratedMessage {
  factory RendezvousResponse({
    $core.String? nodeEndpoint,
    $core.List<$core.int>? punchId,
    $core.bool? nodeSymmetricNat,
  }) {
    final result = RendezvousResponse._();
    if (nodeEndpoint != null) result.nodeEndpoint = nodeEndpoint;
    if (punchId != null) result.punchId = punchId;
    if (nodeSymmetricNat != null) result.nodeSymmetricNat = nodeSymmetricNat;
    return result;
  }

  RendezvousResponse._();

  factory RendezvousResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RendezvousResponse()..mergeFromBuffer(data, registry);
  factory RendezvousResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RendezvousResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RendezvousResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: RendezvousResponse.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'nodeEndpoint')
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'punchId', $pb.PbFieldType.OY)
    ..aOB(3, _omitFieldNames ? '' : 'nodeSymmetricNat')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RendezvousResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RendezvousResponse copyWith(void Function(RendezvousResponse) updates) =>
      super.copyWith((message) => updates(message as RendezvousResponse))
          as RendezvousResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use RendezvousResponse() / RendezvousResponse.new instead')
  static RendezvousResponse create() => RendezvousResponse._();
  static $pb.GeneratedMessage $_createMessage() => RendezvousResponse._();
  @$core.override
  RendezvousResponse createEmptyInstance() => RendezvousResponse._();
  @$core.pragma('dart2js:noInline')
  static RendezvousResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RendezvousResponse>(
          RendezvousResponse.$_createMessage);
  static RendezvousResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get nodeEndpoint => $_getSZ(0);
  @$pb.TagNumber(1)
  set nodeEndpoint($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasNodeEndpoint() => $_has(0);
  @$pb.TagNumber(1)
  void clearNodeEndpoint() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get punchId => $_getN(1);
  @$pb.TagNumber(2)
  set punchId($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasPunchId() => $_has(1);
  @$pb.TagNumber(2)
  void clearPunchId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.bool get nodeSymmetricNat => $_getBF(2);
  @$pb.TagNumber(3)
  set nodeSymmetricNat($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasNodeSymmetricNat() => $_has(2);
  @$pb.TagNumber(3)
  void clearNodeSymmetricNat() => $_clearField(3);
}

/// Команда узлу: начать пробивание к инициатору.
class RendezvousCommand extends $pb.GeneratedMessage {
  factory RendezvousCommand({
    $core.String? peerEndpoint,
    $core.List<$core.int>? peerKey,
    $core.List<$core.int>? punchId,
    $core.Iterable<$core.String>? servers,
  }) {
    final result = RendezvousCommand._();
    if (peerEndpoint != null) result.peerEndpoint = peerEndpoint;
    if (peerKey != null) result.peerKey = peerKey;
    if (punchId != null) result.punchId = punchId;
    if (servers != null) result.servers.addAll(servers);
    return result;
  }

  RendezvousCommand._();

  factory RendezvousCommand.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RendezvousCommand()..mergeFromBuffer(data, registry);
  factory RendezvousCommand.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RendezvousCommand()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RendezvousCommand',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: RendezvousCommand.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'peerEndpoint')
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'peerKey', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'punchId', $pb.PbFieldType.OY)
    ..pPS(4, _omitFieldNames ? '' : 'servers')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RendezvousCommand clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RendezvousCommand copyWith(void Function(RendezvousCommand) updates) =>
      super.copyWith((message) => updates(message as RendezvousCommand))
          as RendezvousCommand;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use RendezvousCommand() / RendezvousCommand.new instead')
  static RendezvousCommand create() => RendezvousCommand._();
  static $pb.GeneratedMessage $_createMessage() => RendezvousCommand._();
  @$core.override
  RendezvousCommand createEmptyInstance() => RendezvousCommand._();
  @$core.pragma('dart2js:noInline')
  static RendezvousCommand getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RendezvousCommand>(
          RendezvousCommand.$_createMessage);
  static RendezvousCommand? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get peerEndpoint => $_getSZ(0);
  @$pb.TagNumber(1)
  set peerEndpoint($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPeerEndpoint() => $_has(0);
  @$pb.TagNumber(1)
  void clearPeerEndpoint() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get peerKey => $_getN(1);
  @$pb.TagNumber(2)
  set peerKey($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasPeerKey() => $_has(1);
  @$pb.TagNumber(2)
  void clearPeerKey() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get punchId => $_getN(2);
  @$pb.TagNumber(3)
  set punchId($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(3)
  $core.bool hasPunchId() => $_has(2);
  @$pb.TagNumber(3)
  void clearPunchId() => $_clearField(3);

  @$pb.TagNumber(4)
  $pb.PbList<$core.String> get servers => $_getList(3);
}

/// Ответ узла: его внешний адрес от сводника.
class RendezvousReply extends $pb.GeneratedMessage {
  factory RendezvousReply({
    UdpBinding? binding,
    $core.bool? symmetricNat,
  }) {
    final result = RendezvousReply._();
    if (binding != null) result.binding = binding;
    if (symmetricNat != null) result.symmetricNat = symmetricNat;
    return result;
  }

  RendezvousReply._();

  factory RendezvousReply.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RendezvousReply()..mergeFromBuffer(data, registry);
  factory RendezvousReply.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RendezvousReply()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RendezvousReply',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: RendezvousReply.$_createMessage)
    ..aOM<UdpBinding>(1, _omitFieldNames ? '' : 'binding',
        subBuilder: UdpBinding.$_createMessage)
    ..aOB(2, _omitFieldNames ? '' : 'symmetricNat')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RendezvousReply clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RendezvousReply copyWith(void Function(RendezvousReply) updates) =>
      super.copyWith((message) => updates(message as RendezvousReply))
          as RendezvousReply;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use RendezvousReply() / RendezvousReply.new instead')
  static RendezvousReply create() => RendezvousReply._();
  static $pb.GeneratedMessage $_createMessage() => RendezvousReply._();
  @$core.override
  RendezvousReply createEmptyInstance() => RendezvousReply._();
  @$core.pragma('dart2js:noInline')
  static RendezvousReply getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RendezvousReply>(
          RendezvousReply.$_createMessage);
  static RendezvousReply? _defaultInstance;

  @$pb.TagNumber(1)
  UdpBinding get binding => $_getN(0);
  @$pb.TagNumber(1)
  set binding(UdpBinding value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasBinding() => $_has(0);
  @$pb.TagNumber(1)
  void clearBinding() => $_clearField(1);
  @$pb.TagNumber(1)
  UdpBinding ensureBinding() => $_ensure(0);

  @$pb.TagNumber(2)
  $core.bool get symmetricNat => $_getBF(1);
  @$pb.TagNumber(2)
  set symmetricNat($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSymmetricNat() => $_has(1);
  @$pb.TagNumber(2)
  void clearSymmetricNat() => $_clearField(2);
}

/// Команда узлу: доказать хранение блока block_index фрагмента fragment_id.
class AuditCommand extends $pb.GeneratedMessage {
  factory AuditCommand({
    $core.List<$core.int>? fragmentId,
    $core.int? blockIndex,
  }) {
    final result = AuditCommand._();
    if (fragmentId != null) result.fragmentId = fragmentId;
    if (blockIndex != null) result.blockIndex = blockIndex;
    return result;
  }

  AuditCommand._();

  factory AuditCommand.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      AuditCommand()..mergeFromBuffer(data, registry);
  factory AuditCommand.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      AuditCommand()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AuditCommand',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: AuditCommand.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'fragmentId', $pb.PbFieldType.OY)
    ..aI(2, _omitFieldNames ? '' : 'blockIndex', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AuditCommand clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AuditCommand copyWith(void Function(AuditCommand) updates) =>
      super.copyWith((message) => updates(message as AuditCommand))
          as AuditCommand;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use AuditCommand() / AuditCommand.new instead')
  static AuditCommand create() => AuditCommand._();
  static $pb.GeneratedMessage $_createMessage() => AuditCommand._();
  @$core.override
  AuditCommand createEmptyInstance() => AuditCommand._();
  @$core.pragma('dart2js:noInline')
  static AuditCommand getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<AuditCommand>(
          AuditCommand.$_createMessage);
  static AuditCommand? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get fragmentId => $_getN(0);
  @$pb.TagNumber(1)
  set fragmentId($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasFragmentId() => $_has(0);
  @$pb.TagNumber(1)
  void clearFragmentId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get blockIndex => $_getIZ(1);
  @$pb.TagNumber(2)
  set blockIndex($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasBlockIndex() => $_has(1);
  @$pb.TagNumber(2)
  void clearBlockIndex() => $_clearField(2);
}

/// Ответ узла. Фрагмента нет или он повреждён — Error с NOT_FOUND.
class AuditReply extends $pb.GeneratedMessage {
  factory AuditReply({
    $core.List<$core.int>? block,
    $core.Iterable<$core.List<$core.int>>? path,
  }) {
    final result = AuditReply._();
    if (block != null) result.block = block;
    if (path != null) result.path.addAll(path);
    return result;
  }

  AuditReply._();

  factory AuditReply.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      AuditReply()..mergeFromBuffer(data, registry);
  factory AuditReply.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      AuditReply()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AuditReply',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: AuditReply.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'block', $pb.PbFieldType.OY)
    ..p<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'path', $pb.PbFieldType.PY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AuditReply clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AuditReply copyWith(void Function(AuditReply) updates) =>
      super.copyWith((message) => updates(message as AuditReply)) as AuditReply;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use AuditReply() / AuditReply.new instead')
  static AuditReply create() => AuditReply._();
  static $pb.GeneratedMessage $_createMessage() => AuditReply._();
  @$core.override
  AuditReply createEmptyInstance() => AuditReply._();
  @$core.pragma('dart2js:noInline')
  static AuditReply getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<AuditReply>(AuditReply.$_createMessage);
  static AuditReply? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get block => $_getN(0);
  @$pb.TagNumber(1)
  set block($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasBlock() => $_has(0);
  @$pb.TagNumber(1)
  void clearBlock() => $_clearField(1);

  @$pb.TagNumber(2)
  $pb.PbList<$core.List<$core.int>> get path => $_getList(1);
}

/// Команда исполнителю. Размер — до 64 КиБ, как любое сообщение
/// координатора в канале.
class RepairCommand extends $pb.GeneratedMessage {
  factory RepairCommand({
    $core.List<$core.int>? jobId,
    $core.int? k,
    $core.int? n,
    $core.int? fragmentSize,
    $core.Iterable<Placement>? sources,
    $core.Iterable<Placement>? targets,
    $fixnum.Int64? deadlineUnixMs,
  }) {
    final result = RepairCommand._();
    if (jobId != null) result.jobId = jobId;
    if (k != null) result.k = k;
    if (n != null) result.n = n;
    if (fragmentSize != null) result.fragmentSize = fragmentSize;
    if (sources != null) result.sources.addAll(sources);
    if (targets != null) result.targets.addAll(targets);
    if (deadlineUnixMs != null) result.deadlineUnixMs = deadlineUnixMs;
    return result;
  }

  RepairCommand._();

  factory RepairCommand.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RepairCommand()..mergeFromBuffer(data, registry);
  factory RepairCommand.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RepairCommand()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RepairCommand',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: RepairCommand.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'jobId', $pb.PbFieldType.OY)
    ..aI(2, _omitFieldNames ? '' : 'k', fieldType: $pb.PbFieldType.OU3)
    ..aI(3, _omitFieldNames ? '' : 'n', fieldType: $pb.PbFieldType.OU3)
    ..aI(4, _omitFieldNames ? '' : 'fragmentSize',
        fieldType: $pb.PbFieldType.OU3)
    ..pPM<Placement>(5, _omitFieldNames ? '' : 'sources',
        subBuilder: Placement.$_createMessage)
    ..pPM<Placement>(6, _omitFieldNames ? '' : 'targets',
        subBuilder: Placement.$_createMessage)
    ..aInt64(7, _omitFieldNames ? '' : 'deadlineUnixMs')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RepairCommand clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RepairCommand copyWith(void Function(RepairCommand) updates) =>
      super.copyWith((message) => updates(message as RepairCommand))
          as RepairCommand;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use RepairCommand() / RepairCommand.new instead')
  static RepairCommand create() => RepairCommand._();
  static $pb.GeneratedMessage $_createMessage() => RepairCommand._();
  @$core.override
  RepairCommand createEmptyInstance() => RepairCommand._();
  @$core.pragma('dart2js:noInline')
  static RepairCommand getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RepairCommand>(
          RepairCommand.$_createMessage);
  static RepairCommand? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get jobId => $_getN(0);
  @$pb.TagNumber(1)
  set jobId($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasJobId() => $_has(0);
  @$pb.TagNumber(1)
  void clearJobId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get k => $_getIZ(1);
  @$pb.TagNumber(2)
  set k($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasK() => $_has(1);
  @$pb.TagNumber(2)
  void clearK() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get n => $_getIZ(2);
  @$pb.TagNumber(3)
  set n($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasN() => $_has(2);
  @$pb.TagNumber(3)
  void clearN() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get fragmentSize => $_getIZ(3);
  @$pb.TagNumber(4)
  set fragmentSize($core.int value) => $_setUnsignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasFragmentSize() => $_has(3);
  @$pb.TagNumber(4)
  void clearFragmentSize() => $_clearField(4);

  /// Живые фрагменты, сначала узлы в сети и с большей доступностью;
  /// талоны GET с device_sign = node_id исполнителя. Не меньше k.
  @$pb.TagNumber(5)
  $pb.PbList<Placement> get sources => $_getList(4);

  /// Недостающие фрагменты по номерам: узел и талон PUT с device_sign =
  /// node_id исполнителя и owner_account. fragment_id — в талоне.
  @$pb.TagNumber(6)
  $pb.PbList<Placement> get targets => $_getList(5);

  @$pb.TagNumber(7)
  $fixnum.Int64 get deadlineUnixMs => $_getI64(6);
  @$pb.TagNumber(7)
  set deadlineUnixMs($fixnum.Int64 value) => $_setInt64(6, value);
  @$pb.TagNumber(7)
  $core.bool hasDeadlineUnixMs() => $_has(6);
  @$pb.TagNumber(7)
  void clearDeadlineUnixMs() => $_clearField(7);
}

/// Отчёт исполнителя. Подписан ключом узла-исполнителя.
class ReportRepairRequest extends $pb.GeneratedMessage {
  factory ReportRepairRequest({
    $core.List<$core.int>? jobId,
    $core.Iterable<$core.int>? storedIndexes,
    $core.Iterable<RepairFailure>? failures,
    $core.String? error,
    $fixnum.Int64? bytesDownloaded,
    $fixnum.Int64? bytesUploaded,
  }) {
    final result = ReportRepairRequest._();
    if (jobId != null) result.jobId = jobId;
    if (storedIndexes != null) result.storedIndexes.addAll(storedIndexes);
    if (failures != null) result.failures.addAll(failures);
    if (error != null) result.error = error;
    if (bytesDownloaded != null) result.bytesDownloaded = bytesDownloaded;
    if (bytesUploaded != null) result.bytesUploaded = bytesUploaded;
    return result;
  }

  ReportRepairRequest._();

  factory ReportRepairRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ReportRepairRequest()..mergeFromBuffer(data, registry);
  factory ReportRepairRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ReportRepairRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ReportRepairRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: ReportRepairRequest.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'jobId', $pb.PbFieldType.OY)
    ..p<$core.int>(
        2, _omitFieldNames ? '' : 'storedIndexes', $pb.PbFieldType.KU3)
    ..pPM<RepairFailure>(3, _omitFieldNames ? '' : 'failures',
        subBuilder: RepairFailure.$_createMessage)
    ..aOS(4, _omitFieldNames ? '' : 'error')
    ..a<$fixnum.Int64>(
        5, _omitFieldNames ? '' : 'bytesDownloaded', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(
        6, _omitFieldNames ? '' : 'bytesUploaded', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReportRepairRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReportRepairRequest copyWith(void Function(ReportRepairRequest) updates) =>
      super.copyWith((message) => updates(message as ReportRepairRequest))
          as ReportRepairRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use ReportRepairRequest() / ReportRepairRequest.new instead')
  static ReportRepairRequest create() => ReportRepairRequest._();
  static $pb.GeneratedMessage $_createMessage() => ReportRepairRequest._();
  @$core.override
  ReportRepairRequest createEmptyInstance() => ReportRepairRequest._();
  @$core.pragma('dart2js:noInline')
  static ReportRepairRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ReportRepairRequest>(
          ReportRepairRequest.$_createMessage);
  static ReportRepairRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get jobId => $_getN(0);
  @$pb.TagNumber(1)
  set jobId($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasJobId() => $_has(0);
  @$pb.TagNumber(1)
  void clearJobId() => $_clearField(1);

  @$pb.TagNumber(2)
  $pb.PbList<$core.int> get storedIndexes => $_getList(1);

  @$pb.TagNumber(3)
  $pb.PbList<RepairFailure> get failures => $_getList(2);

  @$pb.TagNumber(4)
  $core.String get error => $_getSZ(3);
  @$pb.TagNumber(4)
  set error($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasError() => $_has(3);
  @$pb.TagNumber(4)
  void clearError() => $_clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get bytesDownloaded => $_getI64(4);
  @$pb.TagNumber(5)
  set bytesDownloaded($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(5)
  $core.bool hasBytesDownloaded() => $_has(4);
  @$pb.TagNumber(5)
  void clearBytesDownloaded() => $_clearField(5);

  @$pb.TagNumber(6)
  $fixnum.Int64 get bytesUploaded => $_getI64(5);
  @$pb.TagNumber(6)
  set bytesUploaded($fixnum.Int64 value) => $_setInt64(5, value);
  @$pb.TagNumber(6)
  $core.bool hasBytesUploaded() => $_has(5);
  @$pb.TagNumber(6)
  void clearBytesUploaded() => $_clearField(6);
}

class RepairFailure extends $pb.GeneratedMessage {
  factory RepairFailure({
    $core.int? index,
    $core.String? reason,
  }) {
    final result = RepairFailure._();
    if (index != null) result.index = index;
    if (reason != null) result.reason = reason;
    return result;
  }

  RepairFailure._();

  factory RepairFailure.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RepairFailure()..mergeFromBuffer(data, registry);
  factory RepairFailure.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RepairFailure()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RepairFailure',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: RepairFailure.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'index', fieldType: $pb.PbFieldType.OU3)
    ..aOS(2, _omitFieldNames ? '' : 'reason')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RepairFailure clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RepairFailure copyWith(void Function(RepairFailure) updates) =>
      super.copyWith((message) => updates(message as RepairFailure))
          as RepairFailure;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use RepairFailure() / RepairFailure.new instead')
  static RepairFailure create() => RepairFailure._();
  static $pb.GeneratedMessage $_createMessage() => RepairFailure._();
  @$core.override
  RepairFailure createEmptyInstance() => RepairFailure._();
  @$core.pragma('dart2js:noInline')
  static RepairFailure getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RepairFailure>(
          RepairFailure.$_createMessage);
  static RepairFailure? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get index => $_getIZ(0);
  @$pb.TagNumber(1)
  set index($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasIndex() => $_has(0);
  @$pb.TagNumber(1)
  void clearIndex() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get reason => $_getSZ(1);
  @$pb.TagNumber(2)
  set reason($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasReason() => $_has(1);
  @$pb.TagNumber(2)
  void clearReason() => $_clearField(2);
}

class ReportRepairResponse extends $pb.GeneratedMessage {
  factory ReportRepairResponse() => ReportRepairResponse._();

  ReportRepairResponse._();

  factory ReportRepairResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ReportRepairResponse()..mergeFromBuffer(data, registry);
  factory ReportRepairResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ReportRepairResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ReportRepairResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: ReportRepairResponse.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReportRepairResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReportRepairResponse copyWith(void Function(ReportRepairResponse) updates) =>
      super.copyWith((message) => updates(message as ReportRepairResponse))
          as ReportRepairResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use ReportRepairResponse() / ReportRepairResponse.new instead')
  static ReportRepairResponse create() => ReportRepairResponse._();
  static $pb.GeneratedMessage $_createMessage() => ReportRepairResponse._();
  @$core.override
  ReportRepairResponse createEmptyInstance() => ReportRepairResponse._();
  @$core.pragma('dart2js:noInline')
  static ReportRepairResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ReportRepairResponse>(
          ReportRepairResponse.$_createMessage);
  static ReportRepairResponse? _defaultInstance;
}

/// Перенос одного фрагмента: узел-исполнитель — тот, кто его хранит.
class RelocateCommand extends $pb.GeneratedMessage {
  factory RelocateCommand({
    $core.List<$core.int>? jobId,
    Placement? target,
    $fixnum.Int64? deadlineUnixMs,
  }) {
    final result = RelocateCommand._();
    if (jobId != null) result.jobId = jobId;
    if (target != null) result.target = target;
    if (deadlineUnixMs != null) result.deadlineUnixMs = deadlineUnixMs;
    return result;
  }

  RelocateCommand._();

  factory RelocateCommand.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RelocateCommand()..mergeFromBuffer(data, registry);
  factory RelocateCommand.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RelocateCommand()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RelocateCommand',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: RelocateCommand.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'jobId', $pb.PbFieldType.OY)
    ..aOM<Placement>(2, _omitFieldNames ? '' : 'target',
        subBuilder: Placement.$_createMessage)
    ..aInt64(3, _omitFieldNames ? '' : 'deadlineUnixMs')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RelocateCommand clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RelocateCommand copyWith(void Function(RelocateCommand) updates) =>
      super.copyWith((message) => updates(message as RelocateCommand))
          as RelocateCommand;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use RelocateCommand() / RelocateCommand.new instead')
  static RelocateCommand create() => RelocateCommand._();
  static $pb.GeneratedMessage $_createMessage() => RelocateCommand._();
  @$core.override
  RelocateCommand createEmptyInstance() => RelocateCommand._();
  @$core.pragma('dart2js:noInline')
  static RelocateCommand getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RelocateCommand>(
          RelocateCommand.$_createMessage);
  static RelocateCommand? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get jobId => $_getN(0);
  @$pb.TagNumber(1)
  set jobId($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasJobId() => $_has(0);
  @$pb.TagNumber(1)
  void clearJobId() => $_clearField(1);

  /// Новый узел и талон PUT с device_sign = node_id исполнителя и
  /// owner_account. fragment_id и fragment_size — в талоне.
  @$pb.TagNumber(2)
  Placement get target => $_getN(1);
  @$pb.TagNumber(2)
  set target(Placement value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasTarget() => $_has(1);
  @$pb.TagNumber(2)
  void clearTarget() => $_clearField(2);
  @$pb.TagNumber(2)
  Placement ensureTarget() => $_ensure(1);

  @$pb.TagNumber(3)
  $fixnum.Int64 get deadlineUnixMs => $_getI64(2);
  @$pb.TagNumber(3)
  set deadlineUnixMs($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasDeadlineUnixMs() => $_has(2);
  @$pb.TagNumber(3)
  void clearDeadlineUnixMs() => $_clearField(3);
}

/// Узел объявляет выход из сети или проверяет, как идёт перенос. Подписан
/// ключом узла.
class LeaveNetworkRequest extends $pb.GeneratedMessage {
  factory LeaveNetworkRequest({
    $core.bool? cancel,
  }) {
    final result = LeaveNetworkRequest._();
    if (cancel != null) result.cancel = cancel;
    return result;
  }

  LeaveNetworkRequest._();

  factory LeaveNetworkRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      LeaveNetworkRequest()..mergeFromBuffer(data, registry);
  factory LeaveNetworkRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      LeaveNetworkRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'LeaveNetworkRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: LeaveNetworkRequest.$_createMessage)
    ..aOB(1, _omitFieldNames ? '' : 'cancel')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LeaveNetworkRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LeaveNetworkRequest copyWith(void Function(LeaveNetworkRequest) updates) =>
      super.copyWith((message) => updates(message as LeaveNetworkRequest))
          as LeaveNetworkRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use LeaveNetworkRequest() / LeaveNetworkRequest.new instead')
  static LeaveNetworkRequest create() => LeaveNetworkRequest._();
  static $pb.GeneratedMessage $_createMessage() => LeaveNetworkRequest._();
  @$core.override
  LeaveNetworkRequest createEmptyInstance() => LeaveNetworkRequest._();
  @$core.pragma('dart2js:noInline')
  static LeaveNetworkRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<LeaveNetworkRequest>(
          LeaveNetworkRequest.$_createMessage);
  static LeaveNetworkRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get cancel => $_getBF(0);
  @$pb.TagNumber(1)
  set cancel($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasCancel() => $_has(0);
  @$pb.TagNumber(1)
  void clearCancel() => $_clearField(1);
}

class LeaveNetworkResponse extends $pb.GeneratedMessage {
  factory LeaveNetworkResponse({
    $fixnum.Int64? remainingFragments,
    $fixnum.Int64? remainingBytes,
    $core.bool? done,
  }) {
    final result = LeaveNetworkResponse._();
    if (remainingFragments != null)
      result.remainingFragments = remainingFragments;
    if (remainingBytes != null) result.remainingBytes = remainingBytes;
    if (done != null) result.done = done;
    return result;
  }

  LeaveNetworkResponse._();

  factory LeaveNetworkResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      LeaveNetworkResponse()..mergeFromBuffer(data, registry);
  factory LeaveNetworkResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      LeaveNetworkResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'LeaveNetworkResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: LeaveNetworkResponse.$_createMessage)
    ..a<$fixnum.Int64>(
        1, _omitFieldNames ? '' : 'remainingFragments', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(
        2, _omitFieldNames ? '' : 'remainingBytes', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOB(3, _omitFieldNames ? '' : 'done')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LeaveNetworkResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LeaveNetworkResponse copyWith(void Function(LeaveNetworkResponse) updates) =>
      super.copyWith((message) => updates(message as LeaveNetworkResponse))
          as LeaveNetworkResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use LeaveNetworkResponse() / LeaveNetworkResponse.new instead')
  static LeaveNetworkResponse create() => LeaveNetworkResponse._();
  static $pb.GeneratedMessage $_createMessage() => LeaveNetworkResponse._();
  @$core.override
  LeaveNetworkResponse createEmptyInstance() => LeaveNetworkResponse._();
  @$core.pragma('dart2js:noInline')
  static LeaveNetworkResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<LeaveNetworkResponse>(
          LeaveNetworkResponse.$_createMessage);
  static LeaveNetworkResponse? _defaultInstance;

  /// Сохранённых фрагментов подтверждённых сегментов ещё на узле.
  @$pb.TagNumber(1)
  $fixnum.Int64 get remainingFragments => $_getI64(0);
  @$pb.TagNumber(1)
  set remainingFragments($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasRemainingFragments() => $_has(0);
  @$pb.TagNumber(1)
  void clearRemainingFragments() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get remainingBytes => $_getI64(1);
  @$pb.TagNumber(2)
  set remainingBytes($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasRemainingBytes() => $_has(1);
  @$pb.TagNumber(2)
  void clearRemainingBytes() => $_clearField(2);

  /// Переносить нечего: узел удалён из сети, фрагменты можно удалить.
  @$pb.TagNumber(3)
  $core.bool get done => $_getBF(2);
  @$pb.TagNumber(3)
  set done($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasDone() => $_has(2);
  @$pb.TagNumber(3)
  void clearDone() => $_clearField(3);
}

/// Сверка: какие из фрагментов узла координатор больше не учитывает на
/// нём. Подписан ключом узла.
class ReconcileFragmentsRequest extends $pb.GeneratedMessage {
  factory ReconcileFragmentsRequest({
    $core.Iterable<$core.List<$core.int>>? fragmentIds,
    $core.bool? first,
  }) {
    final result = ReconcileFragmentsRequest._();
    if (fragmentIds != null) result.fragmentIds.addAll(fragmentIds);
    if (first != null) result.first = first;
    return result;
  }

  ReconcileFragmentsRequest._();

  factory ReconcileFragmentsRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ReconcileFragmentsRequest()..mergeFromBuffer(data, registry);
  factory ReconcileFragmentsRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ReconcileFragmentsRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ReconcileFragmentsRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: ReconcileFragmentsRequest.$_createMessage)
    ..p<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'fragmentIds', $pb.PbFieldType.PY)
    ..aOB(2, _omitFieldNames ? '' : 'first')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReconcileFragmentsRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReconcileFragmentsRequest copyWith(
          void Function(ReconcileFragmentsRequest) updates) =>
      super.copyWith((message) => updates(message as ReconcileFragmentsRequest))
          as ReconcileFragmentsRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use ReconcileFragmentsRequest() / ReconcileFragmentsRequest.new instead')
  static ReconcileFragmentsRequest create() => ReconcileFragmentsRequest._();
  static $pb.GeneratedMessage $_createMessage() =>
      ReconcileFragmentsRequest._();
  @$core.override
  ReconcileFragmentsRequest createEmptyInstance() =>
      ReconcileFragmentsRequest._();
  @$core.pragma('dart2js:noInline')
  static ReconcileFragmentsRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ReconcileFragmentsRequest>(
          ReconcileFragmentsRequest.$_createMessage);
  static ReconcileFragmentsRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<$core.List<$core.int>> get fragmentIds => $_getList(0);

  @$pb.TagNumber(2)
  $core.bool get first => $_getBF(1);
  @$pb.TagNumber(2)
  set first($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasFirst() => $_has(1);
  @$pb.TagNumber(2)
  void clearFirst() => $_clearField(2);
}

class ReconcileFragmentsResponse extends $pb.GeneratedMessage {
  factory ReconcileFragmentsResponse({
    $core.Iterable<$core.List<$core.int>>? unknown,
  }) {
    final result = ReconcileFragmentsResponse._();
    if (unknown != null) result.unknown.addAll(unknown);
    return result;
  }

  ReconcileFragmentsResponse._();

  factory ReconcileFragmentsResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ReconcileFragmentsResponse()..mergeFromBuffer(data, registry);
  factory ReconcileFragmentsResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ReconcileFragmentsResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ReconcileFragmentsResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: ReconcileFragmentsResponse.$_createMessage)
    ..p<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'unknown', $pb.PbFieldType.PY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReconcileFragmentsResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReconcileFragmentsResponse copyWith(
          void Function(ReconcileFragmentsResponse) updates) =>
      super.copyWith(
              (message) => updates(message as ReconcileFragmentsResponse))
          as ReconcileFragmentsResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use ReconcileFragmentsResponse() / ReconcileFragmentsResponse.new instead')
  static ReconcileFragmentsResponse create() => ReconcileFragmentsResponse._();
  static $pb.GeneratedMessage $_createMessage() =>
      ReconcileFragmentsResponse._();
  @$core.override
  ReconcileFragmentsResponse createEmptyInstance() =>
      ReconcileFragmentsResponse._();
  @$core.pragma('dart2js:noInline')
  static ReconcileFragmentsResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ReconcileFragmentsResponse>(
          ReconcileFragmentsResponse.$_createMessage);
  static ReconcileFragmentsResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<$core.List<$core.int>> get unknown => $_getList(0);
}

/// Подписан ключом устройства.
class GetBackupHealthRequest extends $pb.GeneratedMessage {
  factory GetBackupHealthRequest({
    $core.Iterable<$core.List<$core.int>>? segmentIds,
    $fixnum.Int64? auditedSinceUnixMs,
  }) {
    final result = GetBackupHealthRequest._();
    if (segmentIds != null) result.segmentIds.addAll(segmentIds);
    if (auditedSinceUnixMs != null)
      result.auditedSinceUnixMs = auditedSinceUnixMs;
    return result;
  }

  GetBackupHealthRequest._();

  factory GetBackupHealthRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetBackupHealthRequest()..mergeFromBuffer(data, registry);
  factory GetBackupHealthRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetBackupHealthRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetBackupHealthRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: GetBackupHealthRequest.$_createMessage)
    ..p<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'segmentIds', $pb.PbFieldType.PY)
    ..aInt64(2, _omitFieldNames ? '' : 'auditedSinceUnixMs')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetBackupHealthRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetBackupHealthRequest copyWith(
          void Function(GetBackupHealthRequest) updates) =>
      super.copyWith((message) => updates(message as GetBackupHealthRequest))
          as GetBackupHealthRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use GetBackupHealthRequest() / GetBackupHealthRequest.new instead')
  static GetBackupHealthRequest create() => GetBackupHealthRequest._();
  static $pb.GeneratedMessage $_createMessage() => GetBackupHealthRequest._();
  @$core.override
  GetBackupHealthRequest createEmptyInstance() => GetBackupHealthRequest._();
  @$core.pragma('dart2js:noInline')
  static GetBackupHealthRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GetBackupHealthRequest>(
          GetBackupHealthRequest.$_createMessage);
  static GetBackupHealthRequest? _defaultInstance;

  /// До 1000 сегментов по 32 байта, без повторов; пусто — только сводка.
  @$pb.TagNumber(1)
  $pb.PbList<$core.List<$core.int>> get segmentIds => $_getList(0);

  /// Фрагмент считается проверенным, если прошёл аудит не раньше этого
  /// времени; 0 — за 30 суток до запроса.
  @$pb.TagNumber(2)
  $fixnum.Int64 get auditedSinceUnixMs => $_getI64(1);
  @$pb.TagNumber(2)
  set auditedSinceUnixMs($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasAuditedSinceUnixMs() => $_has(1);
  @$pb.TagNumber(2)
  void clearAuditedSinceUnixMs() => $_clearField(2);
}

class GetBackupHealthResponse extends $pb.GeneratedMessage {
  factory GetBackupHealthResponse({
    BackupHealthSummary? summary,
    $core.Iterable<SegmentHealth>? segments,
    $fixnum.Int64? auditedSinceUnixMs,
  }) {
    final result = GetBackupHealthResponse._();
    if (summary != null) result.summary = summary;
    if (segments != null) result.segments.addAll(segments);
    if (auditedSinceUnixMs != null)
      result.auditedSinceUnixMs = auditedSinceUnixMs;
    return result;
  }

  GetBackupHealthResponse._();

  factory GetBackupHealthResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetBackupHealthResponse()..mergeFromBuffer(data, registry);
  factory GetBackupHealthResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetBackupHealthResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetBackupHealthResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: GetBackupHealthResponse.$_createMessage)
    ..aOM<BackupHealthSummary>(1, _omitFieldNames ? '' : 'summary',
        subBuilder: BackupHealthSummary.$_createMessage)
    ..pPM<SegmentHealth>(2, _omitFieldNames ? '' : 'segments',
        subBuilder: SegmentHealth.$_createMessage)
    ..aInt64(3, _omitFieldNames ? '' : 'auditedSinceUnixMs')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetBackupHealthResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetBackupHealthResponse copyWith(
          void Function(GetBackupHealthResponse) updates) =>
      super.copyWith((message) => updates(message as GetBackupHealthResponse))
          as GetBackupHealthResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use GetBackupHealthResponse() / GetBackupHealthResponse.new instead')
  static GetBackupHealthResponse create() => GetBackupHealthResponse._();
  static $pb.GeneratedMessage $_createMessage() => GetBackupHealthResponse._();
  @$core.override
  GetBackupHealthResponse createEmptyInstance() => GetBackupHealthResponse._();
  @$core.pragma('dart2js:noInline')
  static GetBackupHealthResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GetBackupHealthResponse>(
          GetBackupHealthResponse.$_createMessage);
  static GetBackupHealthResponse? _defaultInstance;

  @$pb.TagNumber(1)
  BackupHealthSummary get summary => $_getN(0);
  @$pb.TagNumber(1)
  set summary(BackupHealthSummary value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasSummary() => $_has(0);
  @$pb.TagNumber(1)
  void clearSummary() => $_clearField(1);
  @$pb.TagNumber(1)
  BackupHealthSummary ensureSummary() => $_ensure(0);

  /// По запрошенным сегментам, которые координатор знает как сохранённые,
  /// в порядке запроса; отсутствующего в ответе сегмента у координатора нет.
  @$pb.TagNumber(2)
  $pb.PbList<SegmentHealth> get segments => $_getList(1);

  @$pb.TagNumber(3)
  $fixnum.Int64 get auditedSinceUnixMs => $_getI64(2);
  @$pb.TagNumber(3)
  set auditedSinceUnixMs($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasAuditedSinceUnixMs() => $_has(2);
  @$pb.TagNumber(3)
  void clearAuditedSinceUnixMs() => $_clearField(3);
}

class BackupHealthSummary extends $pb.GeneratedMessage {
  factory BackupHealthSummary({
    $fixnum.Int64? segments,
    $fixnum.Int64? healthy,
    $fixnum.Int64? reduced,
    $fixnum.Int64? atRisk,
    $fixnum.Int64? lost,
    $fixnum.Int64? repairing,
    $fixnum.Int64? readableNow,
    $fixnum.Int64? liveFragments,
    $fixnum.Int64? auditedFragments,
    $fixnum.Int64? lastAuditUnixMs,
    $fixnum.Int64? fragmentBytes,
  }) {
    final result = BackupHealthSummary._();
    if (segments != null) result.segments = segments;
    if (healthy != null) result.healthy = healthy;
    if (reduced != null) result.reduced = reduced;
    if (atRisk != null) result.atRisk = atRisk;
    if (lost != null) result.lost = lost;
    if (repairing != null) result.repairing = repairing;
    if (readableNow != null) result.readableNow = readableNow;
    if (liveFragments != null) result.liveFragments = liveFragments;
    if (auditedFragments != null) result.auditedFragments = auditedFragments;
    if (lastAuditUnixMs != null) result.lastAuditUnixMs = lastAuditUnixMs;
    if (fragmentBytes != null) result.fragmentBytes = fragmentBytes;
    return result;
  }

  BackupHealthSummary._();

  factory BackupHealthSummary.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      BackupHealthSummary()..mergeFromBuffer(data, registry);
  factory BackupHealthSummary.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      BackupHealthSummary()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'BackupHealthSummary',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: BackupHealthSummary.$_createMessage)
    ..a<$fixnum.Int64>(
        1, _omitFieldNames ? '' : 'segments', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(2, _omitFieldNames ? '' : 'healthy', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(3, _omitFieldNames ? '' : 'reduced', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(4, _omitFieldNames ? '' : 'atRisk', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(5, _omitFieldNames ? '' : 'lost', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(
        6, _omitFieldNames ? '' : 'repairing', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(
        7, _omitFieldNames ? '' : 'readableNow', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(
        8, _omitFieldNames ? '' : 'liveFragments', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(
        9, _omitFieldNames ? '' : 'auditedFragments', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aInt64(10, _omitFieldNames ? '' : 'lastAuditUnixMs')
    ..a<$fixnum.Int64>(
        11, _omitFieldNames ? '' : 'fragmentBytes', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  BackupHealthSummary clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  BackupHealthSummary copyWith(void Function(BackupHealthSummary) updates) =>
      super.copyWith((message) => updates(message as BackupHealthSummary))
          as BackupHealthSummary;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use BackupHealthSummary() / BackupHealthSummary.new instead')
  static BackupHealthSummary create() => BackupHealthSummary._();
  static $pb.GeneratedMessage $_createMessage() => BackupHealthSummary._();
  @$core.override
  BackupHealthSummary createEmptyInstance() => BackupHealthSummary._();
  @$core.pragma('dart2js:noInline')
  static BackupHealthSummary getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<BackupHealthSummary>(
          BackupHealthSummary.$_createMessage);
  static BackupHealthSummary? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get segments => $_getI64(0);
  @$pb.TagNumber(1)
  set segments($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSegments() => $_has(0);
  @$pb.TagNumber(1)
  void clearSegments() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get healthy => $_getI64(1);
  @$pb.TagNumber(2)
  set healthy($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasHealthy() => $_has(1);
  @$pb.TagNumber(2)
  void clearHealthy() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get reduced => $_getI64(2);
  @$pb.TagNumber(3)
  set reduced($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasReduced() => $_has(2);
  @$pb.TagNumber(3)
  void clearReduced() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get atRisk => $_getI64(3);
  @$pb.TagNumber(4)
  set atRisk($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasAtRisk() => $_has(3);
  @$pb.TagNumber(4)
  void clearAtRisk() => $_clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get lost => $_getI64(4);
  @$pb.TagNumber(5)
  set lost($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(5)
  $core.bool hasLost() => $_has(4);
  @$pb.TagNumber(5)
  void clearLost() => $_clearField(5);

  @$pb.TagNumber(6)
  $fixnum.Int64 get repairing => $_getI64(5);
  @$pb.TagNumber(6)
  set repairing($fixnum.Int64 value) => $_setInt64(5, value);
  @$pb.TagNumber(6)
  $core.bool hasRepairing() => $_has(5);
  @$pb.TagNumber(6)
  void clearRepairing() => $_clearField(6);

  @$pb.TagNumber(7)
  $fixnum.Int64 get readableNow => $_getI64(6);
  @$pb.TagNumber(7)
  set readableNow($fixnum.Int64 value) => $_setInt64(6, value);
  @$pb.TagNumber(7)
  $core.bool hasReadableNow() => $_has(6);
  @$pb.TagNumber(7)
  void clearReadableNow() => $_clearField(7);

  @$pb.TagNumber(8)
  $fixnum.Int64 get liveFragments => $_getI64(7);
  @$pb.TagNumber(8)
  set liveFragments($fixnum.Int64 value) => $_setInt64(7, value);
  @$pb.TagNumber(8)
  $core.bool hasLiveFragments() => $_has(7);
  @$pb.TagNumber(8)
  void clearLiveFragments() => $_clearField(8);

  @$pb.TagNumber(9)
  $fixnum.Int64 get auditedFragments => $_getI64(8);
  @$pb.TagNumber(9)
  set auditedFragments($fixnum.Int64 value) => $_setInt64(8, value);
  @$pb.TagNumber(9)
  $core.bool hasAuditedFragments() => $_has(8);
  @$pb.TagNumber(9)
  void clearAuditedFragments() => $_clearField(9);

  @$pb.TagNumber(10)
  $fixnum.Int64 get lastAuditUnixMs => $_getI64(9);
  @$pb.TagNumber(10)
  set lastAuditUnixMs($fixnum.Int64 value) => $_setInt64(9, value);
  @$pb.TagNumber(10)
  $core.bool hasLastAuditUnixMs() => $_has(9);
  @$pb.TagNumber(10)
  void clearLastAuditUnixMs() => $_clearField(10);

  @$pb.TagNumber(11)
  $fixnum.Int64 get fragmentBytes => $_getI64(10);
  @$pb.TagNumber(11)
  set fragmentBytes($fixnum.Int64 value) => $_setInt64(10, value);
  @$pb.TagNumber(11)
  $core.bool hasFragmentBytes() => $_has(10);
  @$pb.TagNumber(11)
  void clearFragmentBytes() => $_clearField(11);
}

class SegmentHealth extends $pb.GeneratedMessage {
  factory SegmentHealth({
    $core.List<$core.int>? segmentId,
    $core.int? k,
    $core.int? n,
    $core.int? repairThreshold,
    $core.int? live,
    $core.int? online,
    $core.int? audited,
    $fixnum.Int64? lastAuditUnixMs,
    $core.bool? repairing,
  }) {
    final result = SegmentHealth._();
    if (segmentId != null) result.segmentId = segmentId;
    if (k != null) result.k = k;
    if (n != null) result.n = n;
    if (repairThreshold != null) result.repairThreshold = repairThreshold;
    if (live != null) result.live = live;
    if (online != null) result.online = online;
    if (audited != null) result.audited = audited;
    if (lastAuditUnixMs != null) result.lastAuditUnixMs = lastAuditUnixMs;
    if (repairing != null) result.repairing = repairing;
    return result;
  }

  SegmentHealth._();

  factory SegmentHealth.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SegmentHealth()..mergeFromBuffer(data, registry);
  factory SegmentHealth.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SegmentHealth()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SegmentHealth',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: SegmentHealth.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'segmentId', $pb.PbFieldType.OY)
    ..aI(2, _omitFieldNames ? '' : 'k', fieldType: $pb.PbFieldType.OU3)
    ..aI(3, _omitFieldNames ? '' : 'n', fieldType: $pb.PbFieldType.OU3)
    ..aI(4, _omitFieldNames ? '' : 'repairThreshold',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(5, _omitFieldNames ? '' : 'live', fieldType: $pb.PbFieldType.OU3)
    ..aI(6, _omitFieldNames ? '' : 'online', fieldType: $pb.PbFieldType.OU3)
    ..aI(7, _omitFieldNames ? '' : 'audited', fieldType: $pb.PbFieldType.OU3)
    ..aInt64(8, _omitFieldNames ? '' : 'lastAuditUnixMs')
    ..aOB(9, _omitFieldNames ? '' : 'repairing')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SegmentHealth clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SegmentHealth copyWith(void Function(SegmentHealth) updates) =>
      super.copyWith((message) => updates(message as SegmentHealth))
          as SegmentHealth;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use SegmentHealth() / SegmentHealth.new instead')
  static SegmentHealth create() => SegmentHealth._();
  static $pb.GeneratedMessage $_createMessage() => SegmentHealth._();
  @$core.override
  SegmentHealth createEmptyInstance() => SegmentHealth._();
  @$core.pragma('dart2js:noInline')
  static SegmentHealth getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SegmentHealth>(
          SegmentHealth.$_createMessage);
  static SegmentHealth? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get segmentId => $_getN(0);
  @$pb.TagNumber(1)
  set segmentId($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSegmentId() => $_has(0);
  @$pb.TagNumber(1)
  void clearSegmentId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get k => $_getIZ(1);
  @$pb.TagNumber(2)
  set k($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasK() => $_has(1);
  @$pb.TagNumber(2)
  void clearK() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get n => $_getIZ(2);
  @$pb.TagNumber(3)
  set n($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasN() => $_has(2);
  @$pb.TagNumber(3)
  void clearN() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get repairThreshold => $_getIZ(3);
  @$pb.TagNumber(4)
  set repairThreshold($core.int value) => $_setUnsignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasRepairThreshold() => $_has(3);
  @$pb.TagNumber(4)
  void clearRepairThreshold() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get live => $_getIZ(4);
  @$pb.TagNumber(5)
  set live($core.int value) => $_setUnsignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasLive() => $_has(4);
  @$pb.TagNumber(5)
  void clearLive() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.int get online => $_getIZ(5);
  @$pb.TagNumber(6)
  set online($core.int value) => $_setUnsignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasOnline() => $_has(5);
  @$pb.TagNumber(6)
  void clearOnline() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.int get audited => $_getIZ(6);
  @$pb.TagNumber(7)
  set audited($core.int value) => $_setUnsignedInt32(6, value);
  @$pb.TagNumber(7)
  $core.bool hasAudited() => $_has(6);
  @$pb.TagNumber(7)
  void clearAudited() => $_clearField(7);

  @$pb.TagNumber(8)
  $fixnum.Int64 get lastAuditUnixMs => $_getI64(7);
  @$pb.TagNumber(8)
  set lastAuditUnixMs($fixnum.Int64 value) => $_setInt64(7, value);
  @$pb.TagNumber(8)
  $core.bool hasLastAuditUnixMs() => $_has(7);
  @$pb.TagNumber(8)
  void clearLastAuditUnixMs() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.bool get repairing => $_getBF(8);
  @$pb.TagNumber(9)
  set repairing($core.bool value) => $_setBool(8, value);
  @$pb.TagNumber(9)
  $core.bool hasRepairing() => $_has(8);
  @$pb.TagNumber(9)
  void clearRepairing() => $_clearField(9);
}

/// Пропуск к relay. Узел (ключ узла, node_id — свой) получает пропуск
/// LISTEN: держать управляющее соединение и принимать через relay.
/// Устройство или узел при ремонте (node_id — другой узел) — CONNECT к узлу.
class GetRelayPassRequest extends $pb.GeneratedMessage {
  factory GetRelayPassRequest({
    $core.List<$core.int>? nodeId,
  }) {
    final result = GetRelayPassRequest._();
    if (nodeId != null) result.nodeId = nodeId;
    return result;
  }

  GetRelayPassRequest._();

  factory GetRelayPassRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetRelayPassRequest()..mergeFromBuffer(data, registry);
  factory GetRelayPassRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetRelayPassRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetRelayPassRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: GetRelayPassRequest.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'nodeId', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetRelayPassRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetRelayPassRequest copyWith(void Function(GetRelayPassRequest) updates) =>
      super.copyWith((message) => updates(message as GetRelayPassRequest))
          as GetRelayPassRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use GetRelayPassRequest() / GetRelayPassRequest.new instead')
  static GetRelayPassRequest create() => GetRelayPassRequest._();
  static $pb.GeneratedMessage $_createMessage() => GetRelayPassRequest._();
  @$core.override
  GetRelayPassRequest createEmptyInstance() => GetRelayPassRequest._();
  @$core.pragma('dart2js:noInline')
  static GetRelayPassRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GetRelayPassRequest>(
          GetRelayPassRequest.$_createMessage);
  static GetRelayPassRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get nodeId => $_getN(0);
  @$pb.TagNumber(1)
  set nodeId($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasNodeId() => $_has(0);
  @$pb.TagNumber(1)
  void clearNodeId() => $_clearField(1);
}

class GetRelayPassResponse extends $pb.GeneratedMessage {
  factory GetRelayPassResponse({
    $core.String? relayEndpoint,
    $0.Signed? pass,
  }) {
    final result = GetRelayPassResponse._();
    if (relayEndpoint != null) result.relayEndpoint = relayEndpoint;
    if (pass != null) result.pass = pass;
    return result;
  }

  GetRelayPassResponse._();

  factory GetRelayPassResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetRelayPassResponse()..mergeFromBuffer(data, registry);
  factory GetRelayPassResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetRelayPassResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetRelayPassResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: GetRelayPassResponse.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'relayEndpoint')
    ..aOM<$0.Signed>(2, _omitFieldNames ? '' : 'pass',
        subBuilder: $0.Signed.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetRelayPassResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetRelayPassResponse copyWith(void Function(GetRelayPassResponse) updates) =>
      super.copyWith((message) => updates(message as GetRelayPassResponse))
          as GetRelayPassResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use GetRelayPassResponse() / GetRelayPassResponse.new instead')
  static GetRelayPassResponse create() => GetRelayPassResponse._();
  static $pb.GeneratedMessage $_createMessage() => GetRelayPassResponse._();
  @$core.override
  GetRelayPassResponse createEmptyInstance() => GetRelayPassResponse._();
  @$core.pragma('dart2js:noInline')
  static GetRelayPassResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GetRelayPassResponse>(
          GetRelayPassResponse.$_createMessage);
  static GetRelayPassResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get relayEndpoint => $_getSZ(0);
  @$pb.TagNumber(1)
  set relayEndpoint($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasRelayEndpoint() => $_has(0);
  @$pb.TagNumber(1)
  void clearRelayEndpoint() => $_clearField(1);

  @$pb.TagNumber(2)
  $0.Signed get pass => $_getN(1);
  @$pb.TagNumber(2)
  set pass($0.Signed value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasPass() => $_has(1);
  @$pb.TagNumber(2)
  void clearPass() => $_clearField(2);
  @$pb.TagNumber(2)
  $0.Signed ensurePass() => $_ensure(1);
}

/// Отчёт relay о трафике с прошлого отчёта. Подписан ключом relay.
class ReportRelayUsageRequest extends $pb.GeneratedMessage {
  factory ReportRelayUsageRequest({
    $core.String? relay,
    $core.Iterable<RelayAccountUsage>? usage,
    $core.int? listeners,
    $core.int? sessions,
    $fixnum.Int64? sessionsOpened,
    $fixnum.Int64? bytes,
  }) {
    final result = ReportRelayUsageRequest._();
    if (relay != null) result.relay = relay;
    if (usage != null) result.usage.addAll(usage);
    if (listeners != null) result.listeners = listeners;
    if (sessions != null) result.sessions = sessions;
    if (sessionsOpened != null) result.sessionsOpened = sessionsOpened;
    if (bytes != null) result.bytes = bytes;
    return result;
  }

  ReportRelayUsageRequest._();

  factory ReportRelayUsageRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ReportRelayUsageRequest()..mergeFromBuffer(data, registry);
  factory ReportRelayUsageRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ReportRelayUsageRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ReportRelayUsageRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: ReportRelayUsageRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'relay')
    ..pPM<RelayAccountUsage>(2, _omitFieldNames ? '' : 'usage',
        subBuilder: RelayAccountUsage.$_createMessage)
    ..aI(3, _omitFieldNames ? '' : 'listeners', fieldType: $pb.PbFieldType.OU3)
    ..aI(4, _omitFieldNames ? '' : 'sessions', fieldType: $pb.PbFieldType.OU3)
    ..a<$fixnum.Int64>(
        5, _omitFieldNames ? '' : 'sessionsOpened', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(6, _omitFieldNames ? '' : 'bytes', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReportRelayUsageRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReportRelayUsageRequest copyWith(
          void Function(ReportRelayUsageRequest) updates) =>
      super.copyWith((message) => updates(message as ReportRelayUsageRequest))
          as ReportRelayUsageRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use ReportRelayUsageRequest() / ReportRelayUsageRequest.new instead')
  static ReportRelayUsageRequest create() => ReportRelayUsageRequest._();
  static $pb.GeneratedMessage $_createMessage() => ReportRelayUsageRequest._();
  @$core.override
  ReportRelayUsageRequest createEmptyInstance() => ReportRelayUsageRequest._();
  @$core.pragma('dart2js:noInline')
  static ReportRelayUsageRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ReportRelayUsageRequest>(
          ReportRelayUsageRequest.$_createMessage);
  static ReportRelayUsageRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get relay => $_getSZ(0);
  @$pb.TagNumber(1)
  set relay($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasRelay() => $_has(0);
  @$pb.TagNumber(1)
  void clearRelay() => $_clearField(1);

  @$pb.TagNumber(2)
  $pb.PbList<RelayAccountUsage> get usage => $_getList(1);

  @$pb.TagNumber(3)
  $core.int get listeners => $_getIZ(2);
  @$pb.TagNumber(3)
  set listeners($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasListeners() => $_has(2);
  @$pb.TagNumber(3)
  void clearListeners() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get sessions => $_getIZ(3);
  @$pb.TagNumber(4)
  set sessions($core.int value) => $_setUnsignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasSessions() => $_has(3);
  @$pb.TagNumber(4)
  void clearSessions() => $_clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get sessionsOpened => $_getI64(4);
  @$pb.TagNumber(5)
  set sessionsOpened($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(5)
  $core.bool hasSessionsOpened() => $_has(4);
  @$pb.TagNumber(5)
  void clearSessionsOpened() => $_clearField(5);

  @$pb.TagNumber(6)
  $fixnum.Int64 get bytes => $_getI64(5);
  @$pb.TagNumber(6)
  set bytes($fixnum.Int64 value) => $_setInt64(5, value);
  @$pb.TagNumber(6)
  $core.bool hasBytes() => $_has(5);
  @$pb.TagNumber(6)
  void clearBytes() => $_clearField(6);
}

class RelayAccountUsage extends $pb.GeneratedMessage {
  factory RelayAccountUsage({
    $core.List<$core.int>? accountId,
    $fixnum.Int64? bytes,
    $core.int? sessions,
  }) {
    final result = RelayAccountUsage._();
    if (accountId != null) result.accountId = accountId;
    if (bytes != null) result.bytes = bytes;
    if (sessions != null) result.sessions = sessions;
    return result;
  }

  RelayAccountUsage._();

  factory RelayAccountUsage.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RelayAccountUsage()..mergeFromBuffer(data, registry);
  factory RelayAccountUsage.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RelayAccountUsage()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RelayAccountUsage',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: RelayAccountUsage.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'accountId', $pb.PbFieldType.OY)
    ..a<$fixnum.Int64>(2, _omitFieldNames ? '' : 'bytes', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aI(3, _omitFieldNames ? '' : 'sessions', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RelayAccountUsage clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RelayAccountUsage copyWith(void Function(RelayAccountUsage) updates) =>
      super.copyWith((message) => updates(message as RelayAccountUsage))
          as RelayAccountUsage;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use RelayAccountUsage() / RelayAccountUsage.new instead')
  static RelayAccountUsage create() => RelayAccountUsage._();
  static $pb.GeneratedMessage $_createMessage() => RelayAccountUsage._();
  @$core.override
  RelayAccountUsage createEmptyInstance() => RelayAccountUsage._();
  @$core.pragma('dart2js:noInline')
  static RelayAccountUsage getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RelayAccountUsage>(
          RelayAccountUsage.$_createMessage);
  static RelayAccountUsage? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get accountId => $_getN(0);
  @$pb.TagNumber(1)
  set accountId($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAccountId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccountId() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get bytes => $_getI64(1);
  @$pb.TagNumber(2)
  set bytes($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasBytes() => $_has(1);
  @$pb.TagNumber(2)
  void clearBytes() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get sessions => $_getIZ(2);
  @$pb.TagNumber(3)
  set sessions($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSessions() => $_has(2);
  @$pb.TagNumber(3)
  void clearSessions() => $_clearField(3);
}

class ReportRelayUsageResponse extends $pb.GeneratedMessage {
  factory ReportRelayUsageResponse({
    $core.int? nextReportMs,
  }) {
    final result = ReportRelayUsageResponse._();
    if (nextReportMs != null) result.nextReportMs = nextReportMs;
    return result;
  }

  ReportRelayUsageResponse._();

  factory ReportRelayUsageResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ReportRelayUsageResponse()..mergeFromBuffer(data, registry);
  factory ReportRelayUsageResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ReportRelayUsageResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ReportRelayUsageResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: ReportRelayUsageResponse.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'nextReportMs',
        fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReportRelayUsageResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReportRelayUsageResponse copyWith(
          void Function(ReportRelayUsageResponse) updates) =>
      super.copyWith((message) => updates(message as ReportRelayUsageResponse))
          as ReportRelayUsageResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use ReportRelayUsageResponse() / ReportRelayUsageResponse.new instead')
  static ReportRelayUsageResponse create() => ReportRelayUsageResponse._();
  static $pb.GeneratedMessage $_createMessage() => ReportRelayUsageResponse._();
  @$core.override
  ReportRelayUsageResponse createEmptyInstance() =>
      ReportRelayUsageResponse._();
  @$core.pragma('dart2js:noInline')
  static ReportRelayUsageResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ReportRelayUsageResponse>(
          ReportRelayUsageResponse.$_createMessage);
  static ReportRelayUsageResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get nextReportMs => $_getIZ(0);
  @$pb.TagNumber(1)
  set nextReportMs($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasNextReportMs() => $_has(0);
  @$pb.TagNumber(1)
  void clearNextReportMs() => $_clearField(1);
}

/// Отчёт клиента или узла о трафике фрагментов с прошлого отчёта: доля
/// relay в трафике сети (контрольная точка 3.10.4). Подписан ключом
/// устройства или узла.
class ReportTrafficRequest extends $pb.GeneratedMessage {
  factory ReportTrafficRequest({
    $core.Iterable<TrafficByMethod>? traffic,
  }) {
    final result = ReportTrafficRequest._();
    if (traffic != null) result.traffic.addAll(traffic);
    return result;
  }

  ReportTrafficRequest._();

  factory ReportTrafficRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ReportTrafficRequest()..mergeFromBuffer(data, registry);
  factory ReportTrafficRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ReportTrafficRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ReportTrafficRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: ReportTrafficRequest.$_createMessage)
    ..pPM<TrafficByMethod>(1, _omitFieldNames ? '' : 'traffic',
        subBuilder: TrafficByMethod.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReportTrafficRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReportTrafficRequest copyWith(void Function(ReportTrafficRequest) updates) =>
      super.copyWith((message) => updates(message as ReportTrafficRequest))
          as ReportTrafficRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use ReportTrafficRequest() / ReportTrafficRequest.new instead')
  static ReportTrafficRequest create() => ReportTrafficRequest._();
  static $pb.GeneratedMessage $_createMessage() => ReportTrafficRequest._();
  @$core.override
  ReportTrafficRequest createEmptyInstance() => ReportTrafficRequest._();
  @$core.pragma('dart2js:noInline')
  static ReportTrafficRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ReportTrafficRequest>(
          ReportTrafficRequest.$_createMessage);
  static ReportTrafficRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<TrafficByMethod> get traffic => $_getList(0);
}

class TrafficByMethod extends $pb.GeneratedMessage {
  factory TrafficByMethod({
    ConnectionMethod? method,
    $fixnum.Int64? bytes,
    $core.int? connections,
  }) {
    final result = TrafficByMethod._();
    if (method != null) result.method = method;
    if (bytes != null) result.bytes = bytes;
    if (connections != null) result.connections = connections;
    return result;
  }

  TrafficByMethod._();

  factory TrafficByMethod.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      TrafficByMethod()..mergeFromBuffer(data, registry);
  factory TrafficByMethod.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      TrafficByMethod()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TrafficByMethod',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: TrafficByMethod.$_createMessage)
    ..aE<ConnectionMethod>(1, _omitFieldNames ? '' : 'method',
        enumValues: ConnectionMethod.values)
    ..a<$fixnum.Int64>(2, _omitFieldNames ? '' : 'bytes', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aI(3, _omitFieldNames ? '' : 'connections',
        fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TrafficByMethod clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TrafficByMethod copyWith(void Function(TrafficByMethod) updates) =>
      super.copyWith((message) => updates(message as TrafficByMethod))
          as TrafficByMethod;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use TrafficByMethod() / TrafficByMethod.new instead')
  static TrafficByMethod create() => TrafficByMethod._();
  static $pb.GeneratedMessage $_createMessage() => TrafficByMethod._();
  @$core.override
  TrafficByMethod createEmptyInstance() => TrafficByMethod._();
  @$core.pragma('dart2js:noInline')
  static TrafficByMethod getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<TrafficByMethod>(
          TrafficByMethod.$_createMessage);
  static TrafficByMethod? _defaultInstance;

  @$pb.TagNumber(1)
  ConnectionMethod get method => $_getN(0);
  @$pb.TagNumber(1)
  set method(ConnectionMethod value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasMethod() => $_has(0);
  @$pb.TagNumber(1)
  void clearMethod() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get bytes => $_getI64(1);
  @$pb.TagNumber(2)
  set bytes($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasBytes() => $_has(1);
  @$pb.TagNumber(2)
  void clearBytes() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get connections => $_getIZ(2);
  @$pb.TagNumber(3)
  set connections($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasConnections() => $_has(2);
  @$pb.TagNumber(3)
  void clearConnections() => $_clearField(3);
}

class ReportTrafficResponse extends $pb.GeneratedMessage {
  factory ReportTrafficResponse() => ReportTrafficResponse._();

  ReportTrafficResponse._();

  factory ReportTrafficResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ReportTrafficResponse()..mergeFromBuffer(data, registry);
  factory ReportTrafficResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ReportTrafficResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ReportTrafficResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: ReportTrafficResponse.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReportTrafficResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReportTrafficResponse copyWith(
          void Function(ReportTrafficResponse) updates) =>
      super.copyWith((message) => updates(message as ReportTrafficResponse))
          as ReportTrafficResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use ReportTrafficResponse() / ReportTrafficResponse.new instead')
  static ReportTrafficResponse create() => ReportTrafficResponse._();
  static $pb.GeneratedMessage $_createMessage() => ReportTrafficResponse._();
  @$core.override
  ReportTrafficResponse createEmptyInstance() => ReportTrafficResponse._();
  @$core.pragma('dart2js:noInline')
  static ReportTrafficResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ReportTrafficResponse>(
          ReportTrafficResponse.$_createMessage);
  static ReportTrafficResponse? _defaultInstance;
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
