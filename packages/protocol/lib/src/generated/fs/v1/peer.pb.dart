// This is a generated file - do not edit.
//
// Generated from fs/v1/peer.proto.

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
import 'peer.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'peer.pbenum.dart';

/// Полезная нагрузка сообщений рукопожатия Noise 2 (от отвечающего) и 3
/// (от инициатора). certificate — fs.v1.Signed с DeviceCertificate (клиент)
/// или NodeCertificate (узел); его X25519-ключ обязан совпасть со
/// статическим ключом Noise собеседника.
class Hello extends $pb.GeneratedMessage {
  factory Hello({
    $core.Iterable<$core.int>? versions,
    PeerRole? role,
    $0.Signed? certificate,
    $core.String? software,
  }) {
    final result = Hello._();
    if (versions != null) result.versions.addAll(versions);
    if (role != null) result.role = role;
    if (certificate != null) result.certificate = certificate;
    if (software != null) result.software = software;
    return result;
  }

  Hello._();

  factory Hello.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Hello()..mergeFromBuffer(data, registry);
  factory Hello.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Hello()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Hello',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: Hello.$_createMessage)
    ..p<$core.int>(1, _omitFieldNames ? '' : 'versions', $pb.PbFieldType.KU3)
    ..aE<PeerRole>(2, _omitFieldNames ? '' : 'role',
        enumValues: PeerRole.values)
    ..aOM<$0.Signed>(3, _omitFieldNames ? '' : 'certificate',
        subBuilder: $0.Signed.$_createMessage)
    ..aOS(4, _omitFieldNames ? '' : 'software')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Hello clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Hello copyWith(void Function(Hello) updates) =>
      super.copyWith((message) => updates(message as Hello)) as Hello;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Hello() / Hello.new instead')
  static Hello create() => Hello._();
  static $pb.GeneratedMessage $_createMessage() => Hello._();
  @$core.override
  Hello createEmptyInstance() => Hello._();
  @$core.pragma('dart2js:noInline')
  static Hello getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Hello>(Hello.$_createMessage);
  static Hello? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<$core.int> get versions => $_getList(0);

  @$pb.TagNumber(2)
  PeerRole get role => $_getN(1);
  @$pb.TagNumber(2)
  set role(PeerRole value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasRole() => $_has(1);
  @$pb.TagNumber(2)
  void clearRole() => $_clearField(2);

  @$pb.TagNumber(3)
  $0.Signed get certificate => $_getN(2);
  @$pb.TagNumber(3)
  set certificate($0.Signed value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasCertificate() => $_has(2);
  @$pb.TagNumber(3)
  void clearCertificate() => $_clearField(3);
  @$pb.TagNumber(3)
  $0.Signed ensureCertificate() => $_ensure(2);

  @$pb.TagNumber(4)
  $core.String get software => $_getSZ(3);
  @$pb.TagNumber(4)
  set software($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasSoftware() => $_has(3);
  @$pb.TagNumber(4)
  void clearSoftware() => $_clearField(4);
}

enum PeerMessage_Body {
  error,
  putFragment,
  fragmentData,
  putFragmentResult,
  getFragment,
  getFragmentResult,
  hasFragments,
  hasFragmentsResult,
  deleteFragment,
  deleteFragmentResult,
  ping,
  pong,
  notSet
}

/// Сообщения после рукопожатия. Каждое — в кадре приложения
/// (u32be длина || PeerMessage), см. protocol.md, раздел 3.3.
class PeerMessage extends $pb.GeneratedMessage {
  factory PeerMessage({
    $fixnum.Int64? requestId,
    $0.Error? error,
    PutFragment? putFragment,
    FragmentData? fragmentData,
    PutFragmentResult? putFragmentResult,
    GetFragment? getFragment,
    GetFragmentResult? getFragmentResult,
    HasFragments? hasFragments,
    HasFragmentsResult? hasFragmentsResult,
    DeleteFragment? deleteFragment,
    DeleteFragmentResult? deleteFragmentResult,
    Ping? ping,
    Pong? pong,
  }) {
    final result = PeerMessage._();
    if (requestId != null) result.requestId = requestId;
    if (error != null) result.error = error;
    if (putFragment != null) result.putFragment = putFragment;
    if (fragmentData != null) result.fragmentData = fragmentData;
    if (putFragmentResult != null) result.putFragmentResult = putFragmentResult;
    if (getFragment != null) result.getFragment = getFragment;
    if (getFragmentResult != null) result.getFragmentResult = getFragmentResult;
    if (hasFragments != null) result.hasFragments = hasFragments;
    if (hasFragmentsResult != null)
      result.hasFragmentsResult = hasFragmentsResult;
    if (deleteFragment != null) result.deleteFragment = deleteFragment;
    if (deleteFragmentResult != null)
      result.deleteFragmentResult = deleteFragmentResult;
    if (ping != null) result.ping = ping;
    if (pong != null) result.pong = pong;
    return result;
  }

  PeerMessage._();

  factory PeerMessage.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PeerMessage()..mergeFromBuffer(data, registry);
  factory PeerMessage.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PeerMessage()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, PeerMessage_Body> _PeerMessage_BodyByTag = {
    2: PeerMessage_Body.error,
    3: PeerMessage_Body.putFragment,
    4: PeerMessage_Body.fragmentData,
    5: PeerMessage_Body.putFragmentResult,
    6: PeerMessage_Body.getFragment,
    7: PeerMessage_Body.getFragmentResult,
    8: PeerMessage_Body.hasFragments,
    9: PeerMessage_Body.hasFragmentsResult,
    10: PeerMessage_Body.deleteFragment,
    11: PeerMessage_Body.deleteFragmentResult,
    12: PeerMessage_Body.ping,
    13: PeerMessage_Body.pong,
    0: PeerMessage_Body.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PeerMessage',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: PeerMessage.$_createMessage)
    ..oo(0, [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13])
    ..a<$fixnum.Int64>(
        1, _omitFieldNames ? '' : 'requestId', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOM<$0.Error>(2, _omitFieldNames ? '' : 'error',
        subBuilder: $0.Error.$_createMessage)
    ..aOM<PutFragment>(3, _omitFieldNames ? '' : 'putFragment',
        subBuilder: PutFragment.$_createMessage)
    ..aOM<FragmentData>(4, _omitFieldNames ? '' : 'fragmentData',
        subBuilder: FragmentData.$_createMessage)
    ..aOM<PutFragmentResult>(5, _omitFieldNames ? '' : 'putFragmentResult',
        subBuilder: PutFragmentResult.$_createMessage)
    ..aOM<GetFragment>(6, _omitFieldNames ? '' : 'getFragment',
        subBuilder: GetFragment.$_createMessage)
    ..aOM<GetFragmentResult>(7, _omitFieldNames ? '' : 'getFragmentResult',
        subBuilder: GetFragmentResult.$_createMessage)
    ..aOM<HasFragments>(8, _omitFieldNames ? '' : 'hasFragments',
        subBuilder: HasFragments.$_createMessage)
    ..aOM<HasFragmentsResult>(9, _omitFieldNames ? '' : 'hasFragmentsResult',
        subBuilder: HasFragmentsResult.$_createMessage)
    ..aOM<DeleteFragment>(10, _omitFieldNames ? '' : 'deleteFragment',
        subBuilder: DeleteFragment.$_createMessage)
    ..aOM<DeleteFragmentResult>(
        11, _omitFieldNames ? '' : 'deleteFragmentResult',
        subBuilder: DeleteFragmentResult.$_createMessage)
    ..aOM<Ping>(12, _omitFieldNames ? '' : 'ping',
        subBuilder: Ping.$_createMessage)
    ..aOM<Pong>(13, _omitFieldNames ? '' : 'pong',
        subBuilder: Pong.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PeerMessage clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PeerMessage copyWith(void Function(PeerMessage) updates) =>
      super.copyWith((message) => updates(message as PeerMessage))
          as PeerMessage;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use PeerMessage() / PeerMessage.new instead')
  static PeerMessage create() => PeerMessage._();
  static $pb.GeneratedMessage $_createMessage() => PeerMessage._();
  @$core.override
  PeerMessage createEmptyInstance() => PeerMessage._();
  @$core.pragma('dart2js:noInline')
  static PeerMessage getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PeerMessage>(
          PeerMessage.$_createMessage);
  static PeerMessage? _defaultInstance;

  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  @$pb.TagNumber(5)
  @$pb.TagNumber(6)
  @$pb.TagNumber(7)
  @$pb.TagNumber(8)
  @$pb.TagNumber(9)
  @$pb.TagNumber(10)
  @$pb.TagNumber(11)
  @$pb.TagNumber(12)
  @$pb.TagNumber(13)
  PeerMessage_Body whichBody() => _PeerMessage_BodyByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  @$pb.TagNumber(5)
  @$pb.TagNumber(6)
  @$pb.TagNumber(7)
  @$pb.TagNumber(8)
  @$pb.TagNumber(9)
  @$pb.TagNumber(10)
  @$pb.TagNumber(11)
  @$pb.TagNumber(12)
  @$pb.TagNumber(13)
  void clearBody() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  $fixnum.Int64 get requestId => $_getI64(0);
  @$pb.TagNumber(1)
  set requestId($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasRequestId() => $_has(0);
  @$pb.TagNumber(1)
  void clearRequestId() => $_clearField(1);

  @$pb.TagNumber(2)
  $0.Error get error => $_getN(1);
  @$pb.TagNumber(2)
  set error($0.Error value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasError() => $_has(1);
  @$pb.TagNumber(2)
  void clearError() => $_clearField(2);
  @$pb.TagNumber(2)
  $0.Error ensureError() => $_ensure(1);

  @$pb.TagNumber(3)
  PutFragment get putFragment => $_getN(2);
  @$pb.TagNumber(3)
  set putFragment(PutFragment value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasPutFragment() => $_has(2);
  @$pb.TagNumber(3)
  void clearPutFragment() => $_clearField(3);
  @$pb.TagNumber(3)
  PutFragment ensurePutFragment() => $_ensure(2);

  @$pb.TagNumber(4)
  FragmentData get fragmentData => $_getN(3);
  @$pb.TagNumber(4)
  set fragmentData(FragmentData value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasFragmentData() => $_has(3);
  @$pb.TagNumber(4)
  void clearFragmentData() => $_clearField(4);
  @$pb.TagNumber(4)
  FragmentData ensureFragmentData() => $_ensure(3);

  @$pb.TagNumber(5)
  PutFragmentResult get putFragmentResult => $_getN(4);
  @$pb.TagNumber(5)
  set putFragmentResult(PutFragmentResult value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasPutFragmentResult() => $_has(4);
  @$pb.TagNumber(5)
  void clearPutFragmentResult() => $_clearField(5);
  @$pb.TagNumber(5)
  PutFragmentResult ensurePutFragmentResult() => $_ensure(4);

  @$pb.TagNumber(6)
  GetFragment get getFragment => $_getN(5);
  @$pb.TagNumber(6)
  set getFragment(GetFragment value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasGetFragment() => $_has(5);
  @$pb.TagNumber(6)
  void clearGetFragment() => $_clearField(6);
  @$pb.TagNumber(6)
  GetFragment ensureGetFragment() => $_ensure(5);

  @$pb.TagNumber(7)
  GetFragmentResult get getFragmentResult => $_getN(6);
  @$pb.TagNumber(7)
  set getFragmentResult(GetFragmentResult value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasGetFragmentResult() => $_has(6);
  @$pb.TagNumber(7)
  void clearGetFragmentResult() => $_clearField(7);
  @$pb.TagNumber(7)
  GetFragmentResult ensureGetFragmentResult() => $_ensure(6);

  @$pb.TagNumber(8)
  HasFragments get hasFragments => $_getN(7);
  @$pb.TagNumber(8)
  set hasFragments(HasFragments value) => $_setField(8, value);
  @$pb.TagNumber(8)
  $core.bool hasHasFragments() => $_has(7);
  @$pb.TagNumber(8)
  void clearHasFragments() => $_clearField(8);
  @$pb.TagNumber(8)
  HasFragments ensureHasFragments() => $_ensure(7);

  @$pb.TagNumber(9)
  HasFragmentsResult get hasFragmentsResult => $_getN(8);
  @$pb.TagNumber(9)
  set hasFragmentsResult(HasFragmentsResult value) => $_setField(9, value);
  @$pb.TagNumber(9)
  $core.bool hasHasFragmentsResult() => $_has(8);
  @$pb.TagNumber(9)
  void clearHasFragmentsResult() => $_clearField(9);
  @$pb.TagNumber(9)
  HasFragmentsResult ensureHasFragmentsResult() => $_ensure(8);

  @$pb.TagNumber(10)
  DeleteFragment get deleteFragment => $_getN(9);
  @$pb.TagNumber(10)
  set deleteFragment(DeleteFragment value) => $_setField(10, value);
  @$pb.TagNumber(10)
  $core.bool hasDeleteFragment() => $_has(9);
  @$pb.TagNumber(10)
  void clearDeleteFragment() => $_clearField(10);
  @$pb.TagNumber(10)
  DeleteFragment ensureDeleteFragment() => $_ensure(9);

  @$pb.TagNumber(11)
  DeleteFragmentResult get deleteFragmentResult => $_getN(10);
  @$pb.TagNumber(11)
  set deleteFragmentResult(DeleteFragmentResult value) => $_setField(11, value);
  @$pb.TagNumber(11)
  $core.bool hasDeleteFragmentResult() => $_has(10);
  @$pb.TagNumber(11)
  void clearDeleteFragmentResult() => $_clearField(11);
  @$pb.TagNumber(11)
  DeleteFragmentResult ensureDeleteFragmentResult() => $_ensure(10);

  @$pb.TagNumber(12)
  Ping get ping => $_getN(11);
  @$pb.TagNumber(12)
  set ping(Ping value) => $_setField(12, value);
  @$pb.TagNumber(12)
  $core.bool hasPing() => $_has(11);
  @$pb.TagNumber(12)
  void clearPing() => $_clearField(12);
  @$pb.TagNumber(12)
  Ping ensurePing() => $_ensure(11);

  @$pb.TagNumber(13)
  Pong get pong => $_getN(12);
  @$pb.TagNumber(13)
  set pong(Pong value) => $_setField(13, value);
  @$pb.TagNumber(13)
  $core.bool hasPong() => $_has(12);
  @$pb.TagNumber(13)
  void clearPong() => $_clearField(13);
  @$pb.TagNumber(13)
  Pong ensurePong() => $_ensure(12);
}

/// Начало загрузки. Затем идут FragmentData с тем же request_id, последний
/// с last = true. Узел проверяет фрагмент (data-format.md, раздел 5) и
/// соответствие талону.
class PutFragment extends $pb.GeneratedMessage {
  factory PutFragment({
    $0.Signed? ticket,
  }) {
    final result = PutFragment._();
    if (ticket != null) result.ticket = ticket;
    return result;
  }

  PutFragment._();

  factory PutFragment.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PutFragment()..mergeFromBuffer(data, registry);
  factory PutFragment.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PutFragment()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PutFragment',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: PutFragment.$_createMessage)
    ..aOM<$0.Signed>(1, _omitFieldNames ? '' : 'ticket',
        subBuilder: $0.Signed.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PutFragment clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PutFragment copyWith(void Function(PutFragment) updates) =>
      super.copyWith((message) => updates(message as PutFragment))
          as PutFragment;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use PutFragment() / PutFragment.new instead')
  static PutFragment create() => PutFragment._();
  static $pb.GeneratedMessage $_createMessage() => PutFragment._();
  @$core.override
  PutFragment createEmptyInstance() => PutFragment._();
  @$core.pragma('dart2js:noInline')
  static PutFragment getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PutFragment>(
          PutFragment.$_createMessage);
  static PutFragment? _defaultInstance;

  @$pb.TagNumber(1)
  $0.Signed get ticket => $_getN(0);
  @$pb.TagNumber(1)
  set ticket($0.Signed value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasTicket() => $_has(0);
  @$pb.TagNumber(1)
  void clearTicket() => $_clearField(1);
  @$pb.TagNumber(1)
  $0.Signed ensureTicket() => $_ensure(0);
}

class FragmentData extends $pb.GeneratedMessage {
  factory FragmentData({
    $core.List<$core.int>? data,
    $core.bool? last,
  }) {
    final result = FragmentData._();
    if (data != null) result.data = data;
    if (last != null) result.last = last;
    return result;
  }

  FragmentData._();

  factory FragmentData.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FragmentData()..mergeFromBuffer(data, registry);
  factory FragmentData.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FragmentData()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FragmentData',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: FragmentData.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'data', $pb.PbFieldType.OY)
    ..aOB(2, _omitFieldNames ? '' : 'last')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FragmentData clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FragmentData copyWith(void Function(FragmentData) updates) =>
      super.copyWith((message) => updates(message as FragmentData))
          as FragmentData;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use FragmentData() / FragmentData.new instead')
  static FragmentData create() => FragmentData._();
  static $pb.GeneratedMessage $_createMessage() => FragmentData._();
  @$core.override
  FragmentData createEmptyInstance() => FragmentData._();
  @$core.pragma('dart2js:noInline')
  static FragmentData getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<FragmentData>(
          FragmentData.$_createMessage);
  static FragmentData? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get data => $_getN(0);
  @$pb.TagNumber(1)
  set data($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasData() => $_has(0);
  @$pb.TagNumber(1)
  void clearData() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.bool get last => $_getBF(1);
  @$pb.TagNumber(2)
  set last($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasLast() => $_has(1);
  @$pb.TagNumber(2)
  void clearLast() => $_clearField(2);
}

class PutFragmentResult extends $pb.GeneratedMessage {
  factory PutFragmentResult({
    $core.List<$core.int>? fragmentId,
  }) {
    final result = PutFragmentResult._();
    if (fragmentId != null) result.fragmentId = fragmentId;
    return result;
  }

  PutFragmentResult._();

  factory PutFragmentResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PutFragmentResult()..mergeFromBuffer(data, registry);
  factory PutFragmentResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PutFragmentResult()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PutFragmentResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: PutFragmentResult.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'fragmentId', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PutFragmentResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PutFragmentResult copyWith(void Function(PutFragmentResult) updates) =>
      super.copyWith((message) => updates(message as PutFragmentResult))
          as PutFragmentResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use PutFragmentResult() / PutFragmentResult.new instead')
  static PutFragmentResult create() => PutFragmentResult._();
  static $pb.GeneratedMessage $_createMessage() => PutFragmentResult._();
  @$core.override
  PutFragmentResult createEmptyInstance() => PutFragmentResult._();
  @$core.pragma('dart2js:noInline')
  static PutFragmentResult getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PutFragmentResult>(
          PutFragmentResult.$_createMessage);
  static PutFragmentResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get fragmentId => $_getN(0);
  @$pb.TagNumber(1)
  set fragmentId($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasFragmentId() => $_has(0);
  @$pb.TagNumber(1)
  void clearFragmentId() => $_clearField(1);
}

/// Ответ: GetFragmentResult, затем FragmentData с тем же request_id.
class GetFragment extends $pb.GeneratedMessage {
  factory GetFragment({
    $0.Signed? ticket,
  }) {
    final result = GetFragment._();
    if (ticket != null) result.ticket = ticket;
    return result;
  }

  GetFragment._();

  factory GetFragment.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetFragment()..mergeFromBuffer(data, registry);
  factory GetFragment.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetFragment()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetFragment',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: GetFragment.$_createMessage)
    ..aOM<$0.Signed>(1, _omitFieldNames ? '' : 'ticket',
        subBuilder: $0.Signed.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetFragment clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetFragment copyWith(void Function(GetFragment) updates) =>
      super.copyWith((message) => updates(message as GetFragment))
          as GetFragment;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use GetFragment() / GetFragment.new instead')
  static GetFragment create() => GetFragment._();
  static $pb.GeneratedMessage $_createMessage() => GetFragment._();
  @$core.override
  GetFragment createEmptyInstance() => GetFragment._();
  @$core.pragma('dart2js:noInline')
  static GetFragment getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GetFragment>(
          GetFragment.$_createMessage);
  static GetFragment? _defaultInstance;

  @$pb.TagNumber(1)
  $0.Signed get ticket => $_getN(0);
  @$pb.TagNumber(1)
  set ticket($0.Signed value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasTicket() => $_has(0);
  @$pb.TagNumber(1)
  void clearTicket() => $_clearField(1);
  @$pb.TagNumber(1)
  $0.Signed ensureTicket() => $_ensure(0);
}

class GetFragmentResult extends $pb.GeneratedMessage {
  factory GetFragmentResult({
    $core.int? fragmentSize,
  }) {
    final result = GetFragmentResult._();
    if (fragmentSize != null) result.fragmentSize = fragmentSize;
    return result;
  }

  GetFragmentResult._();

  factory GetFragmentResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetFragmentResult()..mergeFromBuffer(data, registry);
  factory GetFragmentResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetFragmentResult()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetFragmentResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: GetFragmentResult.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'fragmentSize',
        fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetFragmentResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetFragmentResult copyWith(void Function(GetFragmentResult) updates) =>
      super.copyWith((message) => updates(message as GetFragmentResult))
          as GetFragmentResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use GetFragmentResult() / GetFragmentResult.new instead')
  static GetFragmentResult create() => GetFragmentResult._();
  static $pb.GeneratedMessage $_createMessage() => GetFragmentResult._();
  @$core.override
  GetFragmentResult createEmptyInstance() => GetFragmentResult._();
  @$core.pragma('dart2js:noInline')
  static GetFragmentResult getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GetFragmentResult>(
          GetFragmentResult.$_createMessage);
  static GetFragmentResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get fragmentSize => $_getIZ(0);
  @$pb.TagNumber(1)
  set fragmentSize($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasFragmentSize() => $_has(0);
  @$pb.TagNumber(1)
  void clearFragmentSize() => $_clearField(1);
}

/// Есть ли фрагменты (быстрая проверка, без талона). Узел отвечает только
/// про фрагменты, загруженные этим же устройством или учётной записью.
class HasFragments extends $pb.GeneratedMessage {
  factory HasFragments({
    $core.Iterable<$core.List<$core.int>>? fragmentIds,
  }) {
    final result = HasFragments._();
    if (fragmentIds != null) result.fragmentIds.addAll(fragmentIds);
    return result;
  }

  HasFragments._();

  factory HasFragments.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      HasFragments()..mergeFromBuffer(data, registry);
  factory HasFragments.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      HasFragments()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'HasFragments',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: HasFragments.$_createMessage)
    ..p<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'fragmentIds', $pb.PbFieldType.PY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HasFragments clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HasFragments copyWith(void Function(HasFragments) updates) =>
      super.copyWith((message) => updates(message as HasFragments))
          as HasFragments;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use HasFragments() / HasFragments.new instead')
  static HasFragments create() => HasFragments._();
  static $pb.GeneratedMessage $_createMessage() => HasFragments._();
  @$core.override
  HasFragments createEmptyInstance() => HasFragments._();
  @$core.pragma('dart2js:noInline')
  static HasFragments getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<HasFragments>(
          HasFragments.$_createMessage);
  static HasFragments? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<$core.List<$core.int>> get fragmentIds => $_getList(0);
}

class HasFragmentsResult extends $pb.GeneratedMessage {
  factory HasFragmentsResult({
    $core.Iterable<$core.bool>? present,
  }) {
    final result = HasFragmentsResult._();
    if (present != null) result.present.addAll(present);
    return result;
  }

  HasFragmentsResult._();

  factory HasFragmentsResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      HasFragmentsResult()..mergeFromBuffer(data, registry);
  factory HasFragmentsResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      HasFragmentsResult()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'HasFragmentsResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: HasFragmentsResult.$_createMessage)
    ..p<$core.bool>(1, _omitFieldNames ? '' : 'present', $pb.PbFieldType.KB)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HasFragmentsResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HasFragmentsResult copyWith(void Function(HasFragmentsResult) updates) =>
      super.copyWith((message) => updates(message as HasFragmentsResult))
          as HasFragmentsResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use HasFragmentsResult() / HasFragmentsResult.new instead')
  static HasFragmentsResult create() => HasFragmentsResult._();
  static $pb.GeneratedMessage $_createMessage() => HasFragmentsResult._();
  @$core.override
  HasFragmentsResult createEmptyInstance() => HasFragmentsResult._();
  @$core.pragma('dart2js:noInline')
  static HasFragmentsResult getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<HasFragmentsResult>(
          HasFragmentsResult.$_createMessage);
  static HasFragmentsResult? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<$core.bool> get present => $_getList(0);
}

class DeleteFragment extends $pb.GeneratedMessage {
  factory DeleteFragment({
    $0.Signed? ticket,
  }) {
    final result = DeleteFragment._();
    if (ticket != null) result.ticket = ticket;
    return result;
  }

  DeleteFragment._();

  factory DeleteFragment.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DeleteFragment()..mergeFromBuffer(data, registry);
  factory DeleteFragment.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DeleteFragment()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DeleteFragment',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: DeleteFragment.$_createMessage)
    ..aOM<$0.Signed>(1, _omitFieldNames ? '' : 'ticket',
        subBuilder: $0.Signed.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeleteFragment clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeleteFragment copyWith(void Function(DeleteFragment) updates) =>
      super.copyWith((message) => updates(message as DeleteFragment))
          as DeleteFragment;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use DeleteFragment() / DeleteFragment.new instead')
  static DeleteFragment create() => DeleteFragment._();
  static $pb.GeneratedMessage $_createMessage() => DeleteFragment._();
  @$core.override
  DeleteFragment createEmptyInstance() => DeleteFragment._();
  @$core.pragma('dart2js:noInline')
  static DeleteFragment getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DeleteFragment>(
          DeleteFragment.$_createMessage);
  static DeleteFragment? _defaultInstance;

  @$pb.TagNumber(1)
  $0.Signed get ticket => $_getN(0);
  @$pb.TagNumber(1)
  set ticket($0.Signed value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasTicket() => $_has(0);
  @$pb.TagNumber(1)
  void clearTicket() => $_clearField(1);
  @$pb.TagNumber(1)
  $0.Signed ensureTicket() => $_ensure(0);
}

class DeleteFragmentResult extends $pb.GeneratedMessage {
  factory DeleteFragmentResult() => DeleteFragmentResult._();

  DeleteFragmentResult._();

  factory DeleteFragmentResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DeleteFragmentResult()..mergeFromBuffer(data, registry);
  factory DeleteFragmentResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DeleteFragmentResult()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DeleteFragmentResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: DeleteFragmentResult.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeleteFragmentResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeleteFragmentResult copyWith(void Function(DeleteFragmentResult) updates) =>
      super.copyWith((message) => updates(message as DeleteFragmentResult))
          as DeleteFragmentResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use DeleteFragmentResult() / DeleteFragmentResult.new instead')
  static DeleteFragmentResult create() => DeleteFragmentResult._();
  static $pb.GeneratedMessage $_createMessage() => DeleteFragmentResult._();
  @$core.override
  DeleteFragmentResult createEmptyInstance() => DeleteFragmentResult._();
  @$core.pragma('dart2js:noInline')
  static DeleteFragmentResult getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DeleteFragmentResult>(
          DeleteFragmentResult.$_createMessage);
  static DeleteFragmentResult? _defaultInstance;
}

class Ping extends $pb.GeneratedMessage {
  factory Ping({
    $fixnum.Int64? nonce,
  }) {
    final result = Ping._();
    if (nonce != null) result.nonce = nonce;
    return result;
  }

  Ping._();

  factory Ping.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Ping()..mergeFromBuffer(data, registry);
  factory Ping.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Ping()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Ping',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: Ping.$_createMessage)
    ..a<$fixnum.Int64>(1, _omitFieldNames ? '' : 'nonce', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Ping clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Ping copyWith(void Function(Ping) updates) =>
      super.copyWith((message) => updates(message as Ping)) as Ping;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Ping() / Ping.new instead')
  static Ping create() => Ping._();
  static $pb.GeneratedMessage $_createMessage() => Ping._();
  @$core.override
  Ping createEmptyInstance() => Ping._();
  @$core.pragma('dart2js:noInline')
  static Ping getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Ping>(Ping.$_createMessage);
  static Ping? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get nonce => $_getI64(0);
  @$pb.TagNumber(1)
  set nonce($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasNonce() => $_has(0);
  @$pb.TagNumber(1)
  void clearNonce() => $_clearField(1);
}

class Pong extends $pb.GeneratedMessage {
  factory Pong({
    $fixnum.Int64? nonce,
  }) {
    final result = Pong._();
    if (nonce != null) result.nonce = nonce;
    return result;
  }

  Pong._();

  factory Pong.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Pong()..mergeFromBuffer(data, registry);
  factory Pong.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Pong()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Pong',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: Pong.$_createMessage)
    ..a<$fixnum.Int64>(1, _omitFieldNames ? '' : 'nonce', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Pong clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Pong copyWith(void Function(Pong) updates) =>
      super.copyWith((message) => updates(message as Pong)) as Pong;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Pong() / Pong.new instead')
  static Pong create() => Pong._();
  static $pb.GeneratedMessage $_createMessage() => Pong._();
  @$core.override
  Pong createEmptyInstance() => Pong._();
  @$core.pragma('dart2js:noInline')
  static Pong getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Pong>(Pong.$_createMessage);
  static Pong? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get nonce => $_getI64(0);
  @$pb.TagNumber(1)
  set nonce($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasNonce() => $_has(0);
  @$pb.TagNumber(1)
  void clearNonce() => $_clearField(1);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
