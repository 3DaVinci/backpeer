// This is a generated file - do not edit.
//
// Generated from fs/v1/relay.proto.

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
import 'relay.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'relay.pbenum.dart';

/// Пропуск к relay: тело Signed, контекст "relay-pass", подписан ключом
/// пропусков координатора. Выдаёт GetRelayPass (coordinator.proto).
class RelayPass extends $pb.GeneratedMessage {
  factory RelayPass({
    RelayRole? role,
    $core.List<$core.int>? holder,
    $core.List<$core.int>? nodeId,
    $core.List<$core.int>? accountId,
    $core.String? relay,
    $core.List<$core.int>? passId,
    $fixnum.Int64? expiresAtUnixMs,
    $fixnum.Int64? maxBytes,
  }) {
    final result = RelayPass._();
    if (role != null) result.role = role;
    if (holder != null) result.holder = holder;
    if (nodeId != null) result.nodeId = nodeId;
    if (accountId != null) result.accountId = accountId;
    if (relay != null) result.relay = relay;
    if (passId != null) result.passId = passId;
    if (expiresAtUnixMs != null) result.expiresAtUnixMs = expiresAtUnixMs;
    if (maxBytes != null) result.maxBytes = maxBytes;
    return result;
  }

  RelayPass._();

  factory RelayPass.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RelayPass()..mergeFromBuffer(data, registry);
  factory RelayPass.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RelayPass()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RelayPass',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: RelayPass.$_createMessage)
    ..aE<RelayRole>(1, _omitFieldNames ? '' : 'role',
        enumValues: RelayRole.values)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'holder', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'nodeId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        4, _omitFieldNames ? '' : 'accountId', $pb.PbFieldType.OY)
    ..aOS(5, _omitFieldNames ? '' : 'relay')
    ..a<$core.List<$core.int>>(
        6, _omitFieldNames ? '' : 'passId', $pb.PbFieldType.OY)
    ..a<$fixnum.Int64>(
        7, _omitFieldNames ? '' : 'expiresAtUnixMs', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(
        8, _omitFieldNames ? '' : 'maxBytes', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RelayPass clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RelayPass copyWith(void Function(RelayPass) updates) =>
      super.copyWith((message) => updates(message as RelayPass)) as RelayPass;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use RelayPass() / RelayPass.new instead')
  static RelayPass create() => RelayPass._();
  static $pb.GeneratedMessage $_createMessage() => RelayPass._();
  @$core.override
  RelayPass createEmptyInstance() => RelayPass._();
  @$core.pragma('dart2js:noInline')
  static RelayPass getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RelayPass>(RelayPass.$_createMessage);
  static RelayPass? _defaultInstance;

  @$pb.TagNumber(1)
  RelayRole get role => $_getN(0);
  @$pb.TagNumber(1)
  set role(RelayRole value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasRole() => $_has(0);
  @$pb.TagNumber(1)
  void clearRole() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get holder => $_getN(1);
  @$pb.TagNumber(2)
  set holder($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasHolder() => $_has(1);
  @$pb.TagNumber(2)
  void clearHolder() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get nodeId => $_getN(2);
  @$pb.TagNumber(3)
  set nodeId($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(3)
  $core.bool hasNodeId() => $_has(2);
  @$pb.TagNumber(3)
  void clearNodeId() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.List<$core.int> get accountId => $_getN(3);
  @$pb.TagNumber(4)
  set accountId($core.List<$core.int> value) => $_setBytes(3, value);
  @$pb.TagNumber(4)
  $core.bool hasAccountId() => $_has(3);
  @$pb.TagNumber(4)
  void clearAccountId() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get relay => $_getSZ(4);
  @$pb.TagNumber(5)
  set relay($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasRelay() => $_has(4);
  @$pb.TagNumber(5)
  void clearRelay() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.List<$core.int> get passId => $_getN(5);
  @$pb.TagNumber(6)
  set passId($core.List<$core.int> value) => $_setBytes(5, value);
  @$pb.TagNumber(6)
  $core.bool hasPassId() => $_has(5);
  @$pb.TagNumber(6)
  void clearPassId() => $_clearField(6);

  @$pb.TagNumber(7)
  $fixnum.Int64 get expiresAtUnixMs => $_getI64(6);
  @$pb.TagNumber(7)
  set expiresAtUnixMs($fixnum.Int64 value) => $_setInt64(6, value);
  @$pb.TagNumber(7)
  $core.bool hasExpiresAtUnixMs() => $_has(6);
  @$pb.TagNumber(7)
  void clearExpiresAtUnixMs() => $_clearField(7);

  @$pb.TagNumber(8)
  $fixnum.Int64 get maxBytes => $_getI64(7);
  @$pb.TagNumber(8)
  set maxBytes($fixnum.Int64 value) => $_setInt64(7, value);
  @$pb.TagNumber(8)
  $core.bool hasMaxBytes() => $_has(7);
  @$pb.TagNumber(8)
  void clearMaxBytes() => $_clearField(8);
}

/// Relay → подключившемуся, первым кадром.
class RelayChallenge extends $pb.GeneratedMessage {
  factory RelayChallenge({
    $core.int? version,
    $core.List<$core.int>? nonce,
    $core.String? relay,
  }) {
    final result = RelayChallenge._();
    if (version != null) result.version = version;
    if (nonce != null) result.nonce = nonce;
    if (relay != null) result.relay = relay;
    return result;
  }

  RelayChallenge._();

  factory RelayChallenge.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RelayChallenge()..mergeFromBuffer(data, registry);
  factory RelayChallenge.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RelayChallenge()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RelayChallenge',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: RelayChallenge.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'version', fieldType: $pb.PbFieldType.OU3)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'nonce', $pb.PbFieldType.OY)
    ..aOS(3, _omitFieldNames ? '' : 'relay')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RelayChallenge clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RelayChallenge copyWith(void Function(RelayChallenge) updates) =>
      super.copyWith((message) => updates(message as RelayChallenge))
          as RelayChallenge;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use RelayChallenge() / RelayChallenge.new instead')
  static RelayChallenge create() => RelayChallenge._();
  static $pb.GeneratedMessage $_createMessage() => RelayChallenge._();
  @$core.override
  RelayChallenge createEmptyInstance() => RelayChallenge._();
  @$core.pragma('dart2js:noInline')
  static RelayChallenge getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RelayChallenge>(
          RelayChallenge.$_createMessage);
  static RelayChallenge? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get version => $_getIZ(0);
  @$pb.TagNumber(1)
  set version($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasVersion() => $_has(0);
  @$pb.TagNumber(1)
  void clearVersion() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get nonce => $_getN(1);
  @$pb.TagNumber(2)
  set nonce($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasNonce() => $_has(1);
  @$pb.TagNumber(2)
  void clearNonce() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get relay => $_getSZ(2);
  @$pb.TagNumber(3)
  set relay($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasRelay() => $_has(2);
  @$pb.TagNumber(3)
  void clearRelay() => $_clearField(3);
}

/// Подключившийся → relay.
class RelayOpen extends $pb.GeneratedMessage {
  factory RelayOpen({
    $0.Signed? pass,
    $core.List<$core.int>? proof,
    $core.List<$core.int>? accept,
  }) {
    final result = RelayOpen._();
    if (pass != null) result.pass = pass;
    if (proof != null) result.proof = proof;
    if (accept != null) result.accept = accept;
    return result;
  }

  RelayOpen._();

  factory RelayOpen.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RelayOpen()..mergeFromBuffer(data, registry);
  factory RelayOpen.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RelayOpen()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RelayOpen',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: RelayOpen.$_createMessage)
    ..aOM<$0.Signed>(1, _omitFieldNames ? '' : 'pass',
        subBuilder: $0.Signed.$_createMessage)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'proof', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'accept', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RelayOpen clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RelayOpen copyWith(void Function(RelayOpen) updates) =>
      super.copyWith((message) => updates(message as RelayOpen)) as RelayOpen;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use RelayOpen() / RelayOpen.new instead')
  static RelayOpen create() => RelayOpen._();
  static $pb.GeneratedMessage $_createMessage() => RelayOpen._();
  @$core.override
  RelayOpen createEmptyInstance() => RelayOpen._();
  @$core.pragma('dart2js:noInline')
  static RelayOpen getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RelayOpen>(RelayOpen.$_createMessage);
  static RelayOpen? _defaultInstance;

  @$pb.TagNumber(1)
  $0.Signed get pass => $_getN(0);
  @$pb.TagNumber(1)
  set pass($0.Signed value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasPass() => $_has(0);
  @$pb.TagNumber(1)
  void clearPass() => $_clearField(1);
  @$pb.TagNumber(1)
  $0.Signed ensurePass() => $_ensure(0);

  /// Ed25519-подпись holder, контекст "relay-open", над
  /// nonce || BLAKE2b-256(pass.body) || accept.
  @$pb.TagNumber(2)
  $core.List<$core.int> get proof => $_getN(1);
  @$pb.TagNumber(2)
  set proof($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasProof() => $_has(1);
  @$pb.TagNumber(2)
  void clearProof() => $_clearField(2);

  /// Только у LISTEN: номер сеанса из RelayIncoming, который узел
  /// принимает этим соединением; пусто — управляющее соединение.
  @$pb.TagNumber(3)
  $core.List<$core.int> get accept => $_getN(2);
  @$pb.TagNumber(3)
  set accept($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(3)
  $core.bool hasAccept() => $_has(2);
  @$pb.TagNumber(3)
  void clearAccept() => $_clearField(3);
}

/// Relay → подключившемуся: итог открытия.
class RelayOpened extends $pb.GeneratedMessage {
  factory RelayOpened({
    $0.Error? error,
  }) {
    final result = RelayOpened._();
    if (error != null) result.error = error;
    return result;
  }

  RelayOpened._();

  factory RelayOpened.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RelayOpened()..mergeFromBuffer(data, registry);
  factory RelayOpened.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RelayOpened()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RelayOpened',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: RelayOpened.$_createMessage)
    ..aOM<$0.Error>(1, _omitFieldNames ? '' : 'error',
        subBuilder: $0.Error.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RelayOpened clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RelayOpened copyWith(void Function(RelayOpened) updates) =>
      super.copyWith((message) => updates(message as RelayOpened))
          as RelayOpened;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use RelayOpened() / RelayOpened.new instead')
  static RelayOpened create() => RelayOpened._();
  static $pb.GeneratedMessage $_createMessage() => RelayOpened._();
  @$core.override
  RelayOpened createEmptyInstance() => RelayOpened._();
  @$core.pragma('dart2js:noInline')
  static RelayOpened getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RelayOpened>(
          RelayOpened.$_createMessage);
  static RelayOpened? _defaultInstance;

  @$pb.TagNumber(1)
  $0.Error get error => $_getN(0);
  @$pb.TagNumber(1)
  set error($0.Error value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasError() => $_has(0);
  @$pb.TagNumber(1)
  void clearError() => $_clearField(1);
  @$pb.TagNumber(1)
  $0.Error ensureError() => $_ensure(0);
}

enum RelayControl_Body { incoming, ping, pong, notSet }

/// Управляющее соединение узла после RelayOpened, в обе стороны.
class RelayControl extends $pb.GeneratedMessage {
  factory RelayControl({
    RelayIncoming? incoming,
    $fixnum.Int64? ping,
    $fixnum.Int64? pong,
  }) {
    final result = RelayControl._();
    if (incoming != null) result.incoming = incoming;
    if (ping != null) result.ping = ping;
    if (pong != null) result.pong = pong;
    return result;
  }

  RelayControl._();

  factory RelayControl.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RelayControl()..mergeFromBuffer(data, registry);
  factory RelayControl.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RelayControl()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, RelayControl_Body> _RelayControl_BodyByTag =
      {
    1: RelayControl_Body.incoming,
    2: RelayControl_Body.ping,
    3: RelayControl_Body.pong,
    0: RelayControl_Body.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RelayControl',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: RelayControl.$_createMessage)
    ..oo(0, [1, 2, 3])
    ..aOM<RelayIncoming>(1, _omitFieldNames ? '' : 'incoming',
        subBuilder: RelayIncoming.$_createMessage)
    ..a<$fixnum.Int64>(2, _omitFieldNames ? '' : 'ping', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(3, _omitFieldNames ? '' : 'pong', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RelayControl clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RelayControl copyWith(void Function(RelayControl) updates) =>
      super.copyWith((message) => updates(message as RelayControl))
          as RelayControl;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use RelayControl() / RelayControl.new instead')
  static RelayControl create() => RelayControl._();
  static $pb.GeneratedMessage $_createMessage() => RelayControl._();
  @$core.override
  RelayControl createEmptyInstance() => RelayControl._();
  @$core.pragma('dart2js:noInline')
  static RelayControl getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RelayControl>(
          RelayControl.$_createMessage);
  static RelayControl? _defaultInstance;

  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
  RelayControl_Body whichBody() => _RelayControl_BodyByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
  void clearBody() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  RelayIncoming get incoming => $_getN(0);
  @$pb.TagNumber(1)
  set incoming(RelayIncoming value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasIncoming() => $_has(0);
  @$pb.TagNumber(1)
  void clearIncoming() => $_clearField(1);
  @$pb.TagNumber(1)
  RelayIncoming ensureIncoming() => $_ensure(0);

  @$pb.TagNumber(2)
  $fixnum.Int64 get ping => $_getI64(1);
  @$pb.TagNumber(2)
  set ping($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasPing() => $_has(1);
  @$pb.TagNumber(2)
  void clearPing() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get pong => $_getI64(2);
  @$pb.TagNumber(3)
  set pong($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasPong() => $_has(2);
  @$pb.TagNumber(3)
  void clearPong() => $_clearField(3);
}

/// К узлу подключается holder пропуска CONNECT: узел открывает новое
/// соединение к relay с accept = session_id.
class RelayIncoming extends $pb.GeneratedMessage {
  factory RelayIncoming({
    $core.List<$core.int>? sessionId,
  }) {
    final result = RelayIncoming._();
    if (sessionId != null) result.sessionId = sessionId;
    return result;
  }

  RelayIncoming._();

  factory RelayIncoming.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RelayIncoming()..mergeFromBuffer(data, registry);
  factory RelayIncoming.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RelayIncoming()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RelayIncoming',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: RelayIncoming.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'sessionId', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RelayIncoming clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RelayIncoming copyWith(void Function(RelayIncoming) updates) =>
      super.copyWith((message) => updates(message as RelayIncoming))
          as RelayIncoming;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use RelayIncoming() / RelayIncoming.new instead')
  static RelayIncoming create() => RelayIncoming._();
  static $pb.GeneratedMessage $_createMessage() => RelayIncoming._();
  @$core.override
  RelayIncoming createEmptyInstance() => RelayIncoming._();
  @$core.pragma('dart2js:noInline')
  static RelayIncoming getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RelayIncoming>(
          RelayIncoming.$_createMessage);
  static RelayIncoming? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get sessionId => $_getN(0);
  @$pb.TagNumber(1)
  set sessionId($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSessionId() => $_has(0);
  @$pb.TagNumber(1)
  void clearSessionId() => $_clearField(1);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
