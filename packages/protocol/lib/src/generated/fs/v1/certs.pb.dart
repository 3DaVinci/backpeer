// This is a generated file - do not edit.
//
// Generated from fs/v1/certs.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'certs.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'certs.pbenum.dart';

/// Контекст подписи "device-cert"; подписывает ключ учётной записи.
class DeviceCertificate extends $pb.GeneratedMessage {
  factory DeviceCertificate({
    $core.List<$core.int>? accountId,
    $core.List<$core.int>? deviceSign,
    $core.List<$core.int>? deviceDh,
    $fixnum.Int64? issuedAtUnixMs,
  }) {
    final result = DeviceCertificate._();
    if (accountId != null) result.accountId = accountId;
    if (deviceSign != null) result.deviceSign = deviceSign;
    if (deviceDh != null) result.deviceDh = deviceDh;
    if (issuedAtUnixMs != null) result.issuedAtUnixMs = issuedAtUnixMs;
    return result;
  }

  DeviceCertificate._();

  factory DeviceCertificate.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DeviceCertificate()..mergeFromBuffer(data, registry);
  factory DeviceCertificate.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DeviceCertificate()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DeviceCertificate',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: DeviceCertificate.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'accountId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'deviceSign', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'deviceDh', $pb.PbFieldType.OY)
    ..aInt64(4, _omitFieldNames ? '' : 'issuedAtUnixMs')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeviceCertificate clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeviceCertificate copyWith(void Function(DeviceCertificate) updates) =>
      super.copyWith((message) => updates(message as DeviceCertificate))
          as DeviceCertificate;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use DeviceCertificate() / DeviceCertificate.new instead')
  static DeviceCertificate create() => DeviceCertificate._();
  static $pb.GeneratedMessage $_createMessage() => DeviceCertificate._();
  @$core.override
  DeviceCertificate createEmptyInstance() => DeviceCertificate._();
  @$core.pragma('dart2js:noInline')
  static DeviceCertificate getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DeviceCertificate>(
          DeviceCertificate.$_createMessage);
  static DeviceCertificate? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get accountId => $_getN(0);
  @$pb.TagNumber(1)
  set accountId($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAccountId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccountId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get deviceSign => $_getN(1);
  @$pb.TagNumber(2)
  set deviceSign($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDeviceSign() => $_has(1);
  @$pb.TagNumber(2)
  void clearDeviceSign() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get deviceDh => $_getN(2);
  @$pb.TagNumber(3)
  set deviceDh($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(3)
  $core.bool hasDeviceDh() => $_has(2);
  @$pb.TagNumber(3)
  void clearDeviceDh() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get issuedAtUnixMs => $_getI64(3);
  @$pb.TagNumber(4)
  set issuedAtUnixMs($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasIssuedAtUnixMs() => $_has(3);
  @$pb.TagNumber(4)
  void clearIssuedAtUnixMs() => $_clearField(4);
}

/// Контекст подписи "device-revoke"; подписывает ключ учётной записи.
class DeviceRevocation extends $pb.GeneratedMessage {
  factory DeviceRevocation({
    $core.List<$core.int>? accountId,
    $core.List<$core.int>? deviceSign,
    $fixnum.Int64? revokedAtUnixMs,
  }) {
    final result = DeviceRevocation._();
    if (accountId != null) result.accountId = accountId;
    if (deviceSign != null) result.deviceSign = deviceSign;
    if (revokedAtUnixMs != null) result.revokedAtUnixMs = revokedAtUnixMs;
    return result;
  }

  DeviceRevocation._();

  factory DeviceRevocation.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DeviceRevocation()..mergeFromBuffer(data, registry);
  factory DeviceRevocation.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DeviceRevocation()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DeviceRevocation',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: DeviceRevocation.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'accountId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'deviceSign', $pb.PbFieldType.OY)
    ..aInt64(3, _omitFieldNames ? '' : 'revokedAtUnixMs')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeviceRevocation clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeviceRevocation copyWith(void Function(DeviceRevocation) updates) =>
      super.copyWith((message) => updates(message as DeviceRevocation))
          as DeviceRevocation;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use DeviceRevocation() / DeviceRevocation.new instead')
  static DeviceRevocation create() => DeviceRevocation._();
  static $pb.GeneratedMessage $_createMessage() => DeviceRevocation._();
  @$core.override
  DeviceRevocation createEmptyInstance() => DeviceRevocation._();
  @$core.pragma('dart2js:noInline')
  static DeviceRevocation getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DeviceRevocation>(
          DeviceRevocation.$_createMessage);
  static DeviceRevocation? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get accountId => $_getN(0);
  @$pb.TagNumber(1)
  set accountId($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAccountId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccountId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get deviceSign => $_getN(1);
  @$pb.TagNumber(2)
  set deviceSign($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDeviceSign() => $_has(1);
  @$pb.TagNumber(2)
  void clearDeviceSign() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get revokedAtUnixMs => $_getI64(2);
  @$pb.TagNumber(3)
  set revokedAtUnixMs($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasRevokedAtUnixMs() => $_has(2);
  @$pb.TagNumber(3)
  void clearRevokedAtUnixMs() => $_clearField(3);
}

/// Контекст подписи "node-cert"; подписывает ключ учётной записи владельца.
class NodeCertificate extends $pb.GeneratedMessage {
  factory NodeCertificate({
    $core.List<$core.int>? accountId,
    $core.List<$core.int>? nodeId,
    $core.List<$core.int>? nodeDh,
    $fixnum.Int64? issuedAtUnixMs,
  }) {
    final result = NodeCertificate._();
    if (accountId != null) result.accountId = accountId;
    if (nodeId != null) result.nodeId = nodeId;
    if (nodeDh != null) result.nodeDh = nodeDh;
    if (issuedAtUnixMs != null) result.issuedAtUnixMs = issuedAtUnixMs;
    return result;
  }

  NodeCertificate._();

  factory NodeCertificate.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      NodeCertificate()..mergeFromBuffer(data, registry);
  factory NodeCertificate.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      NodeCertificate()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'NodeCertificate',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: NodeCertificate.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'accountId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'nodeId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'nodeDh', $pb.PbFieldType.OY)
    ..aInt64(4, _omitFieldNames ? '' : 'issuedAtUnixMs')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  NodeCertificate clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  NodeCertificate copyWith(void Function(NodeCertificate) updates) =>
      super.copyWith((message) => updates(message as NodeCertificate))
          as NodeCertificate;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use NodeCertificate() / NodeCertificate.new instead')
  static NodeCertificate create() => NodeCertificate._();
  static $pb.GeneratedMessage $_createMessage() => NodeCertificate._();
  @$core.override
  NodeCertificate createEmptyInstance() => NodeCertificate._();
  @$core.pragma('dart2js:noInline')
  static NodeCertificate getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<NodeCertificate>(
          NodeCertificate.$_createMessage);
  static NodeCertificate? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get accountId => $_getN(0);
  @$pb.TagNumber(1)
  set accountId($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAccountId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccountId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get nodeId => $_getN(1);
  @$pb.TagNumber(2)
  set nodeId($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasNodeId() => $_has(1);
  @$pb.TagNumber(2)
  void clearNodeId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get nodeDh => $_getN(2);
  @$pb.TagNumber(3)
  set nodeDh($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(3)
  $core.bool hasNodeDh() => $_has(2);
  @$pb.TagNumber(3)
  void clearNodeDh() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get issuedAtUnixMs => $_getI64(3);
  @$pb.TagNumber(4)
  set issuedAtUnixMs($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasIssuedAtUnixMs() => $_has(3);
  @$pb.TagNumber(4)
  void clearIssuedAtUnixMs() => $_clearField(4);
}

/// Контекст подписи "ticket"; подписывает ключ координатора. Разрешает
/// устройству (или узлу-исполнителю ремонта) одну операцию с одним
/// фрагментом на одном узле.
class FragmentTicket extends $pb.GeneratedMessage {
  factory FragmentTicket({
    TicketOperation? operation,
    $core.List<$core.int>? nodeId,
    $core.List<$core.int>? deviceSign,
    $core.List<$core.int>? fragmentId,
    $core.int? fragmentSize,
    $fixnum.Int64? expiresAtUnixMs,
    $core.List<$core.int>? ticketId,
    $core.List<$core.int>? ownerAccount,
  }) {
    final result = FragmentTicket._();
    if (operation != null) result.operation = operation;
    if (nodeId != null) result.nodeId = nodeId;
    if (deviceSign != null) result.deviceSign = deviceSign;
    if (fragmentId != null) result.fragmentId = fragmentId;
    if (fragmentSize != null) result.fragmentSize = fragmentSize;
    if (expiresAtUnixMs != null) result.expiresAtUnixMs = expiresAtUnixMs;
    if (ticketId != null) result.ticketId = ticketId;
    if (ownerAccount != null) result.ownerAccount = ownerAccount;
    return result;
  }

  FragmentTicket._();

  factory FragmentTicket.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FragmentTicket()..mergeFromBuffer(data, registry);
  factory FragmentTicket.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FragmentTicket()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FragmentTicket',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: FragmentTicket.$_createMessage)
    ..aE<TicketOperation>(1, _omitFieldNames ? '' : 'operation',
        enumValues: TicketOperation.values)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'nodeId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'deviceSign', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        4, _omitFieldNames ? '' : 'fragmentId', $pb.PbFieldType.OY)
    ..aI(5, _omitFieldNames ? '' : 'fragmentSize',
        fieldType: $pb.PbFieldType.OU3)
    ..aInt64(6, _omitFieldNames ? '' : 'expiresAtUnixMs')
    ..a<$core.List<$core.int>>(
        7, _omitFieldNames ? '' : 'ticketId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        8, _omitFieldNames ? '' : 'ownerAccount', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FragmentTicket clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FragmentTicket copyWith(void Function(FragmentTicket) updates) =>
      super.copyWith((message) => updates(message as FragmentTicket))
          as FragmentTicket;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use FragmentTicket() / FragmentTicket.new instead')
  static FragmentTicket create() => FragmentTicket._();
  static $pb.GeneratedMessage $_createMessage() => FragmentTicket._();
  @$core.override
  FragmentTicket createEmptyInstance() => FragmentTicket._();
  @$core.pragma('dart2js:noInline')
  static FragmentTicket getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<FragmentTicket>(
          FragmentTicket.$_createMessage);
  static FragmentTicket? _defaultInstance;

  @$pb.TagNumber(1)
  TicketOperation get operation => $_getN(0);
  @$pb.TagNumber(1)
  set operation(TicketOperation value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasOperation() => $_has(0);
  @$pb.TagNumber(1)
  void clearOperation() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get nodeId => $_getN(1);
  @$pb.TagNumber(2)
  set nodeId($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasNodeId() => $_has(1);
  @$pb.TagNumber(2)
  void clearNodeId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get deviceSign => $_getN(2);
  @$pb.TagNumber(3)
  set deviceSign($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(3)
  $core.bool hasDeviceSign() => $_has(2);
  @$pb.TagNumber(3)
  void clearDeviceSign() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.List<$core.int> get fragmentId => $_getN(3);
  @$pb.TagNumber(4)
  set fragmentId($core.List<$core.int> value) => $_setBytes(3, value);
  @$pb.TagNumber(4)
  $core.bool hasFragmentId() => $_has(3);
  @$pb.TagNumber(4)
  void clearFragmentId() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get fragmentSize => $_getIZ(4);
  @$pb.TagNumber(5)
  set fragmentSize($core.int value) => $_setUnsignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasFragmentSize() => $_has(4);
  @$pb.TagNumber(5)
  void clearFragmentSize() => $_clearField(5);

  @$pb.TagNumber(6)
  $fixnum.Int64 get expiresAtUnixMs => $_getI64(5);
  @$pb.TagNumber(6)
  set expiresAtUnixMs($fixnum.Int64 value) => $_setInt64(5, value);
  @$pb.TagNumber(6)
  $core.bool hasExpiresAtUnixMs() => $_has(5);
  @$pb.TagNumber(6)
  void clearExpiresAtUnixMs() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.List<$core.int> get ticketId => $_getN(6);
  @$pb.TagNumber(7)
  set ticketId($core.List<$core.int> value) => $_setBytes(6, value);
  @$pb.TagNumber(7)
  $core.bool hasTicketId() => $_has(6);
  @$pb.TagNumber(7)
  void clearTicketId() => $_clearField(7);

  /// Только PUT от узла-исполнителя ремонта (protocol.md, раздел 4.14):
  /// учётная запись-владелец сегмента, 32 байта. Узел записывает её
  /// владельцем фрагмента — удалить его сможет только устройство этой
  /// учётной записи. У PUT от клиента и у GET, DELETE поле пустое.
  @$pb.TagNumber(8)
  $core.List<$core.int> get ownerAccount => $_getN(7);
  @$pb.TagNumber(8)
  set ownerAccount($core.List<$core.int> value) => $_setBytes(7, value);
  @$pb.TagNumber(8)
  $core.bool hasOwnerAccount() => $_has(7);
  @$pb.TagNumber(8)
  void clearOwnerAccount() => $_clearField(8);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
