// This is a generated file - do not edit.
//
// Generated from fs/v1/manifest.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'manifest.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'manifest.pbenum.dart';

/// Объект-снимок. Хранится на координаторе как блоб типа 2
/// (docs/spec/crypto.md, раздел 5), идентификатор блоба = snapshot_id.
class Snapshot extends $pb.GeneratedMessage {
  factory Snapshot({
    $core.int? formatVersion,
    $core.List<$core.int>? snapshotId,
    $fixnum.Int64? sequence,
    $core.List<$core.int>? parentSnapshotId,
    $fixnum.Int64? createdAtUnixMs,
    $core.String? hostname,
    $core.List<$core.int>? deviceId,
    $core.Iterable<$core.String>? paths,
    $core.Iterable<$core.List<$core.int>>? rootTree,
    $core.Iterable<$core.String>? tags,
    SnapshotStats? stats,
  }) {
    final result = Snapshot._();
    if (formatVersion != null) result.formatVersion = formatVersion;
    if (snapshotId != null) result.snapshotId = snapshotId;
    if (sequence != null) result.sequence = sequence;
    if (parentSnapshotId != null) result.parentSnapshotId = parentSnapshotId;
    if (createdAtUnixMs != null) result.createdAtUnixMs = createdAtUnixMs;
    if (hostname != null) result.hostname = hostname;
    if (deviceId != null) result.deviceId = deviceId;
    if (paths != null) result.paths.addAll(paths);
    if (rootTree != null) result.rootTree.addAll(rootTree);
    if (tags != null) result.tags.addAll(tags);
    if (stats != null) result.stats = stats;
    return result;
  }

  Snapshot._();

  factory Snapshot.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Snapshot()..mergeFromBuffer(data, registry);
  factory Snapshot.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Snapshot()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Snapshot',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: Snapshot.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'formatVersion',
        fieldType: $pb.PbFieldType.OU3)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'snapshotId', $pb.PbFieldType.OY)
    ..a<$fixnum.Int64>(
        3, _omitFieldNames ? '' : 'sequence', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$core.List<$core.int>>(
        4, _omitFieldNames ? '' : 'parentSnapshotId', $pb.PbFieldType.OY)
    ..aInt64(5, _omitFieldNames ? '' : 'createdAtUnixMs')
    ..aOS(6, _omitFieldNames ? '' : 'hostname')
    ..a<$core.List<$core.int>>(
        7, _omitFieldNames ? '' : 'deviceId', $pb.PbFieldType.OY)
    ..pPS(8, _omitFieldNames ? '' : 'paths')
    ..p<$core.List<$core.int>>(
        9, _omitFieldNames ? '' : 'rootTree', $pb.PbFieldType.PY)
    ..pPS(10, _omitFieldNames ? '' : 'tags')
    ..aOM<SnapshotStats>(11, _omitFieldNames ? '' : 'stats',
        subBuilder: SnapshotStats.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Snapshot clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Snapshot copyWith(void Function(Snapshot) updates) =>
      super.copyWith((message) => updates(message as Snapshot)) as Snapshot;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Snapshot() / Snapshot.new instead')
  static Snapshot create() => Snapshot._();
  static $pb.GeneratedMessage $_createMessage() => Snapshot._();
  @$core.override
  Snapshot createEmptyInstance() => Snapshot._();
  @$core.pragma('dart2js:noInline')
  static Snapshot getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Snapshot>(Snapshot.$_createMessage);
  static Snapshot? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get formatVersion => $_getIZ(0);
  @$pb.TagNumber(1)
  set formatVersion($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasFormatVersion() => $_has(0);
  @$pb.TagNumber(1)
  void clearFormatVersion() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get snapshotId => $_getN(1);
  @$pb.TagNumber(2)
  set snapshotId($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSnapshotId() => $_has(1);
  @$pb.TagNumber(2)
  void clearSnapshotId() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get sequence => $_getI64(2);
  @$pb.TagNumber(3)
  set sequence($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSequence() => $_has(2);
  @$pb.TagNumber(3)
  void clearSequence() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.List<$core.int> get parentSnapshotId => $_getN(3);
  @$pb.TagNumber(4)
  set parentSnapshotId($core.List<$core.int> value) => $_setBytes(3, value);
  @$pb.TagNumber(4)
  $core.bool hasParentSnapshotId() => $_has(3);
  @$pb.TagNumber(4)
  void clearParentSnapshotId() => $_clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get createdAtUnixMs => $_getI64(4);
  @$pb.TagNumber(5)
  set createdAtUnixMs($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(5)
  $core.bool hasCreatedAtUnixMs() => $_has(4);
  @$pb.TagNumber(5)
  void clearCreatedAtUnixMs() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get hostname => $_getSZ(5);
  @$pb.TagNumber(6)
  set hostname($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasHostname() => $_has(5);
  @$pb.TagNumber(6)
  void clearHostname() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.List<$core.int> get deviceId => $_getN(6);
  @$pb.TagNumber(7)
  set deviceId($core.List<$core.int> value) => $_setBytes(6, value);
  @$pb.TagNumber(7)
  $core.bool hasDeviceId() => $_has(6);
  @$pb.TagNumber(7)
  void clearDeviceId() => $_clearField(7);

  @$pb.TagNumber(8)
  $pb.PbList<$core.String> get paths => $_getList(7);

  @$pb.TagNumber(9)
  $pb.PbList<$core.List<$core.int>> get rootTree => $_getList(8);

  @$pb.TagNumber(10)
  $pb.PbList<$core.String> get tags => $_getList(9);

  @$pb.TagNumber(11)
  SnapshotStats get stats => $_getN(10);
  @$pb.TagNumber(11)
  set stats(SnapshotStats value) => $_setField(11, value);
  @$pb.TagNumber(11)
  $core.bool hasStats() => $_has(10);
  @$pb.TagNumber(11)
  void clearStats() => $_clearField(11);
  @$pb.TagNumber(11)
  SnapshotStats ensureStats() => $_ensure(10);
}

class SnapshotStats extends $pb.GeneratedMessage {
  factory SnapshotStats({
    $fixnum.Int64? files,
    $fixnum.Int64? directories,
    $fixnum.Int64? bytes,
    $fixnum.Int64? newChunks,
    $fixnum.Int64? newBytes,
    $fixnum.Int64? skipped,
  }) {
    final result = SnapshotStats._();
    if (files != null) result.files = files;
    if (directories != null) result.directories = directories;
    if (bytes != null) result.bytes = bytes;
    if (newChunks != null) result.newChunks = newChunks;
    if (newBytes != null) result.newBytes = newBytes;
    if (skipped != null) result.skipped = skipped;
    return result;
  }

  SnapshotStats._();

  factory SnapshotStats.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SnapshotStats()..mergeFromBuffer(data, registry);
  factory SnapshotStats.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SnapshotStats()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SnapshotStats',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: SnapshotStats.$_createMessage)
    ..a<$fixnum.Int64>(1, _omitFieldNames ? '' : 'files', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(
        2, _omitFieldNames ? '' : 'directories', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(3, _omitFieldNames ? '' : 'bytes', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(
        4, _omitFieldNames ? '' : 'newChunks', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(
        5, _omitFieldNames ? '' : 'newBytes', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(6, _omitFieldNames ? '' : 'skipped', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SnapshotStats clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SnapshotStats copyWith(void Function(SnapshotStats) updates) =>
      super.copyWith((message) => updates(message as SnapshotStats))
          as SnapshotStats;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use SnapshotStats() / SnapshotStats.new instead')
  static SnapshotStats create() => SnapshotStats._();
  static $pb.GeneratedMessage $_createMessage() => SnapshotStats._();
  @$core.override
  SnapshotStats createEmptyInstance() => SnapshotStats._();
  @$core.pragma('dart2js:noInline')
  static SnapshotStats getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SnapshotStats>(
          SnapshotStats.$_createMessage);
  static SnapshotStats? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get files => $_getI64(0);
  @$pb.TagNumber(1)
  set files($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasFiles() => $_has(0);
  @$pb.TagNumber(1)
  void clearFiles() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get directories => $_getI64(1);
  @$pb.TagNumber(2)
  set directories($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDirectories() => $_has(1);
  @$pb.TagNumber(2)
  void clearDirectories() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get bytes => $_getI64(2);
  @$pb.TagNumber(3)
  set bytes($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasBytes() => $_has(2);
  @$pb.TagNumber(3)
  void clearBytes() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get newChunks => $_getI64(3);
  @$pb.TagNumber(4)
  set newChunks($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasNewChunks() => $_has(3);
  @$pb.TagNumber(4)
  void clearNewChunks() => $_clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get newBytes => $_getI64(4);
  @$pb.TagNumber(5)
  set newBytes($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(5)
  $core.bool hasNewBytes() => $_has(4);
  @$pb.TagNumber(5)
  void clearNewBytes() => $_clearField(5);

  @$pb.TagNumber(6)
  $fixnum.Int64 get skipped => $_getI64(5);
  @$pb.TagNumber(6)
  set skipped($fixnum.Int64 value) => $_setInt64(5, value);
  @$pb.TagNumber(6)
  $core.bool hasSkipped() => $_has(5);
  @$pb.TagNumber(6)
  void clearSkipped() => $_clearField(6);
}

/// Содержимое каталога. Сериализуется, режется FastCDC и хранится как чанки
/// типа 2 в сегментах (docs/spec/data-format.md, раздел 3).
class Tree extends $pb.GeneratedMessage {
  factory Tree({
    $core.Iterable<Node>? nodes,
  }) {
    final result = Tree._();
    if (nodes != null) result.nodes.addAll(nodes);
    return result;
  }

  Tree._();

  factory Tree.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Tree()..mergeFromBuffer(data, registry);
  factory Tree.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Tree()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Tree',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: Tree.$_createMessage)
    ..pPM<Node>(1, _omitFieldNames ? '' : 'nodes',
        subBuilder: Node.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Tree clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Tree copyWith(void Function(Tree) updates) =>
      super.copyWith((message) => updates(message as Tree)) as Tree;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Tree() / Tree.new instead')
  static Tree create() => Tree._();
  static $pb.GeneratedMessage $_createMessage() => Tree._();
  @$core.override
  Tree createEmptyInstance() => Tree._();
  @$core.pragma('dart2js:noInline')
  static Tree getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Tree>(Tree.$_createMessage);
  static Tree? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<Node> get nodes => $_getList(0);
}

class Node extends $pb.GeneratedMessage {
  factory Node({
    $core.List<$core.int>? name,
    NodeType? type,
    $fixnum.Int64? size,
    $fixnum.Int64? mtimeNs,
    $core.int? mode,
    $core.int? uid,
    $core.int? gid,
    $core.int? windowsAttributes,
    $core.List<$core.int>? symlinkTarget,
    $core.Iterable<$core.List<$core.int>>? content,
    $core.Iterable<$core.List<$core.int>>? subtree,
  }) {
    final result = Node._();
    if (name != null) result.name = name;
    if (type != null) result.type = type;
    if (size != null) result.size = size;
    if (mtimeNs != null) result.mtimeNs = mtimeNs;
    if (mode != null) result.mode = mode;
    if (uid != null) result.uid = uid;
    if (gid != null) result.gid = gid;
    if (windowsAttributes != null) result.windowsAttributes = windowsAttributes;
    if (symlinkTarget != null) result.symlinkTarget = symlinkTarget;
    if (content != null) result.content.addAll(content);
    if (subtree != null) result.subtree.addAll(subtree);
    return result;
  }

  Node._();

  factory Node.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Node()..mergeFromBuffer(data, registry);
  factory Node.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Node()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Node',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: Node.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'name', $pb.PbFieldType.OY)
    ..aE<NodeType>(2, _omitFieldNames ? '' : 'type',
        enumValues: NodeType.values)
    ..a<$fixnum.Int64>(3, _omitFieldNames ? '' : 'size', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aInt64(4, _omitFieldNames ? '' : 'mtimeNs')
    ..aI(5, _omitFieldNames ? '' : 'mode', fieldType: $pb.PbFieldType.OU3)
    ..aI(6, _omitFieldNames ? '' : 'uid', fieldType: $pb.PbFieldType.OU3)
    ..aI(7, _omitFieldNames ? '' : 'gid', fieldType: $pb.PbFieldType.OU3)
    ..aI(8, _omitFieldNames ? '' : 'windowsAttributes',
        fieldType: $pb.PbFieldType.OU3)
    ..a<$core.List<$core.int>>(
        9, _omitFieldNames ? '' : 'symlinkTarget', $pb.PbFieldType.OY)
    ..p<$core.List<$core.int>>(
        10, _omitFieldNames ? '' : 'content', $pb.PbFieldType.PY)
    ..p<$core.List<$core.int>>(
        11, _omitFieldNames ? '' : 'subtree', $pb.PbFieldType.PY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Node clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Node copyWith(void Function(Node) updates) =>
      super.copyWith((message) => updates(message as Node)) as Node;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Node() / Node.new instead')
  static Node create() => Node._();
  static $pb.GeneratedMessage $_createMessage() => Node._();
  @$core.override
  Node createEmptyInstance() => Node._();
  @$core.pragma('dart2js:noInline')
  static Node getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Node>(Node.$_createMessage);
  static Node? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get name => $_getN(0);
  @$pb.TagNumber(1)
  set name($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => $_clearField(1);

  @$pb.TagNumber(2)
  NodeType get type => $_getN(1);
  @$pb.TagNumber(2)
  set type(NodeType value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasType() => $_has(1);
  @$pb.TagNumber(2)
  void clearType() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get size => $_getI64(2);
  @$pb.TagNumber(3)
  set size($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSize() => $_has(2);
  @$pb.TagNumber(3)
  void clearSize() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get mtimeNs => $_getI64(3);
  @$pb.TagNumber(4)
  set mtimeNs($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasMtimeNs() => $_has(3);
  @$pb.TagNumber(4)
  void clearMtimeNs() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get mode => $_getIZ(4);
  @$pb.TagNumber(5)
  set mode($core.int value) => $_setUnsignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasMode() => $_has(4);
  @$pb.TagNumber(5)
  void clearMode() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.int get uid => $_getIZ(5);
  @$pb.TagNumber(6)
  set uid($core.int value) => $_setUnsignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasUid() => $_has(5);
  @$pb.TagNumber(6)
  void clearUid() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.int get gid => $_getIZ(6);
  @$pb.TagNumber(7)
  set gid($core.int value) => $_setUnsignedInt32(6, value);
  @$pb.TagNumber(7)
  $core.bool hasGid() => $_has(6);
  @$pb.TagNumber(7)
  void clearGid() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.int get windowsAttributes => $_getIZ(7);
  @$pb.TagNumber(8)
  set windowsAttributes($core.int value) => $_setUnsignedInt32(7, value);
  @$pb.TagNumber(8)
  $core.bool hasWindowsAttributes() => $_has(7);
  @$pb.TagNumber(8)
  void clearWindowsAttributes() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.List<$core.int> get symlinkTarget => $_getN(8);
  @$pb.TagNumber(9)
  set symlinkTarget($core.List<$core.int> value) => $_setBytes(8, value);
  @$pb.TagNumber(9)
  $core.bool hasSymlinkTarget() => $_has(8);
  @$pb.TagNumber(9)
  void clearSymlinkTarget() => $_clearField(9);

  @$pb.TagNumber(10)
  $pb.PbList<$core.List<$core.int>> get content => $_getList(9);

  @$pb.TagNumber(11)
  $pb.PbList<$core.List<$core.int>> get subtree => $_getList(10);
}

/// Объект-индекс: копии оглавлений сегментов и сведения о фрагментах.
/// Хранится на координаторе как блоб типа 3, идентификатор блоба = index_id.
class Index extends $pb.GeneratedMessage {
  factory Index({
    $core.int? formatVersion,
    $core.List<$core.int>? indexId,
    $core.Iterable<SegmentRecord>? segments,
    $core.Iterable<$core.List<$core.int>>? supersedes,
  }) {
    final result = Index._();
    if (formatVersion != null) result.formatVersion = formatVersion;
    if (indexId != null) result.indexId = indexId;
    if (segments != null) result.segments.addAll(segments);
    if (supersedes != null) result.supersedes.addAll(supersedes);
    return result;
  }

  Index._();

  factory Index.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Index()..mergeFromBuffer(data, registry);
  factory Index.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Index()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Index',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: Index.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'formatVersion',
        fieldType: $pb.PbFieldType.OU3)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'indexId', $pb.PbFieldType.OY)
    ..pPM<SegmentRecord>(3, _omitFieldNames ? '' : 'segments',
        subBuilder: SegmentRecord.$_createMessage)
    ..p<$core.List<$core.int>>(
        4, _omitFieldNames ? '' : 'supersedes', $pb.PbFieldType.PY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Index clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Index copyWith(void Function(Index) updates) =>
      super.copyWith((message) => updates(message as Index)) as Index;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Index() / Index.new instead')
  static Index create() => Index._();
  static $pb.GeneratedMessage $_createMessage() => Index._();
  @$core.override
  Index createEmptyInstance() => Index._();
  @$core.pragma('dart2js:noInline')
  static Index getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Index>(Index.$_createMessage);
  static Index? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get formatVersion => $_getIZ(0);
  @$pb.TagNumber(1)
  set formatVersion($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasFormatVersion() => $_has(0);
  @$pb.TagNumber(1)
  void clearFormatVersion() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get indexId => $_getN(1);
  @$pb.TagNumber(2)
  set indexId($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasIndexId() => $_has(1);
  @$pb.TagNumber(2)
  void clearIndexId() => $_clearField(2);

  @$pb.TagNumber(3)
  $pb.PbList<SegmentRecord> get segments => $_getList(2);

  @$pb.TagNumber(4)
  $pb.PbList<$core.List<$core.int>> get supersedes => $_getList(3);
}

class SegmentRecord extends $pb.GeneratedMessage {
  factory SegmentRecord({
    $core.List<$core.int>? segmentId,
    $core.int? k,
    $core.int? n,
    $core.int? blobLength,
    $core.int? shardSize,
    $core.Iterable<$core.List<$core.int>>? fragmentIds,
    $core.Iterable<ChunkEntry>? chunks,
  }) {
    final result = SegmentRecord._();
    if (segmentId != null) result.segmentId = segmentId;
    if (k != null) result.k = k;
    if (n != null) result.n = n;
    if (blobLength != null) result.blobLength = blobLength;
    if (shardSize != null) result.shardSize = shardSize;
    if (fragmentIds != null) result.fragmentIds.addAll(fragmentIds);
    if (chunks != null) result.chunks.addAll(chunks);
    return result;
  }

  SegmentRecord._();

  factory SegmentRecord.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SegmentRecord()..mergeFromBuffer(data, registry);
  factory SegmentRecord.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SegmentRecord()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SegmentRecord',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: SegmentRecord.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'segmentId', $pb.PbFieldType.OY)
    ..aI(2, _omitFieldNames ? '' : 'k', fieldType: $pb.PbFieldType.OU3)
    ..aI(3, _omitFieldNames ? '' : 'n', fieldType: $pb.PbFieldType.OU3)
    ..aI(4, _omitFieldNames ? '' : 'blobLength', fieldType: $pb.PbFieldType.OU3)
    ..aI(5, _omitFieldNames ? '' : 'shardSize', fieldType: $pb.PbFieldType.OU3)
    ..p<$core.List<$core.int>>(
        6, _omitFieldNames ? '' : 'fragmentIds', $pb.PbFieldType.PY)
    ..pPM<ChunkEntry>(7, _omitFieldNames ? '' : 'chunks',
        subBuilder: ChunkEntry.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SegmentRecord clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SegmentRecord copyWith(void Function(SegmentRecord) updates) =>
      super.copyWith((message) => updates(message as SegmentRecord))
          as SegmentRecord;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use SegmentRecord() / SegmentRecord.new instead')
  static SegmentRecord create() => SegmentRecord._();
  static $pb.GeneratedMessage $_createMessage() => SegmentRecord._();
  @$core.override
  SegmentRecord createEmptyInstance() => SegmentRecord._();
  @$core.pragma('dart2js:noInline')
  static SegmentRecord getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SegmentRecord>(
          SegmentRecord.$_createMessage);
  static SegmentRecord? _defaultInstance;

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
  $core.int get blobLength => $_getIZ(3);
  @$pb.TagNumber(4)
  set blobLength($core.int value) => $_setUnsignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasBlobLength() => $_has(3);
  @$pb.TagNumber(4)
  void clearBlobLength() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get shardSize => $_getIZ(4);
  @$pb.TagNumber(5)
  set shardSize($core.int value) => $_setUnsignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasShardSize() => $_has(4);
  @$pb.TagNumber(5)
  void clearShardSize() => $_clearField(5);

  @$pb.TagNumber(6)
  $pb.PbList<$core.List<$core.int>> get fragmentIds => $_getList(5);

  @$pb.TagNumber(7)
  $pb.PbList<ChunkEntry> get chunks => $_getList(6);
}

class ChunkEntry extends $pb.GeneratedMessage {
  factory ChunkEntry({
    $core.List<$core.int>? chunkId,
    ChunkType? type,
    $core.int? offset,
    $core.int? length,
  }) {
    final result = ChunkEntry._();
    if (chunkId != null) result.chunkId = chunkId;
    if (type != null) result.type = type;
    if (offset != null) result.offset = offset;
    if (length != null) result.length = length;
    return result;
  }

  ChunkEntry._();

  factory ChunkEntry.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ChunkEntry()..mergeFromBuffer(data, registry);
  factory ChunkEntry.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ChunkEntry()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ChunkEntry',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fs.v1'),
      createEmptyInstance: ChunkEntry.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'chunkId', $pb.PbFieldType.OY)
    ..aE<ChunkType>(2, _omitFieldNames ? '' : 'type',
        enumValues: ChunkType.values)
    ..aI(3, _omitFieldNames ? '' : 'offset', fieldType: $pb.PbFieldType.OU3)
    ..aI(4, _omitFieldNames ? '' : 'length', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ChunkEntry clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ChunkEntry copyWith(void Function(ChunkEntry) updates) =>
      super.copyWith((message) => updates(message as ChunkEntry)) as ChunkEntry;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ChunkEntry() / ChunkEntry.new instead')
  static ChunkEntry create() => ChunkEntry._();
  static $pb.GeneratedMessage $_createMessage() => ChunkEntry._();
  @$core.override
  ChunkEntry createEmptyInstance() => ChunkEntry._();
  @$core.pragma('dart2js:noInline')
  static ChunkEntry getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ChunkEntry>(ChunkEntry.$_createMessage);
  static ChunkEntry? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get chunkId => $_getN(0);
  @$pb.TagNumber(1)
  set chunkId($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasChunkId() => $_has(0);
  @$pb.TagNumber(1)
  void clearChunkId() => $_clearField(1);

  @$pb.TagNumber(2)
  ChunkType get type => $_getN(1);
  @$pb.TagNumber(2)
  set type(ChunkType value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasType() => $_has(1);
  @$pb.TagNumber(2)
  void clearType() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get offset => $_getIZ(2);
  @$pb.TagNumber(3)
  set offset($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasOffset() => $_has(2);
  @$pb.TagNumber(3)
  void clearOffset() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get length => $_getIZ(3);
  @$pb.TagNumber(4)
  set length($core.int value) => $_setUnsignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasLength() => $_has(3);
  @$pb.TagNumber(4)
  void clearLength() => $_clearField(4);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
