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

import 'package:protobuf/protobuf.dart' as $pb;

class NodeType extends $pb.ProtobufEnum {
  static const NodeType NODE_TYPE_UNSPECIFIED =
      NodeType._(0, _omitEnumNames ? '' : 'NODE_TYPE_UNSPECIFIED');
  static const NodeType NODE_TYPE_FILE =
      NodeType._(1, _omitEnumNames ? '' : 'NODE_TYPE_FILE');
  static const NodeType NODE_TYPE_DIRECTORY =
      NodeType._(2, _omitEnumNames ? '' : 'NODE_TYPE_DIRECTORY');
  static const NodeType NODE_TYPE_SYMLINK =
      NodeType._(3, _omitEnumNames ? '' : 'NODE_TYPE_SYMLINK');

  static const $core.List<NodeType> values = <NodeType>[
    NODE_TYPE_UNSPECIFIED,
    NODE_TYPE_FILE,
    NODE_TYPE_DIRECTORY,
    NODE_TYPE_SYMLINK,
  ];

  static final $core.List<NodeType?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 3);
  static NodeType? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const NodeType._(super.value, super.name);
}

class ChunkType extends $pb.ProtobufEnum {
  static const ChunkType CHUNK_TYPE_UNSPECIFIED =
      ChunkType._(0, _omitEnumNames ? '' : 'CHUNK_TYPE_UNSPECIFIED');
  static const ChunkType CHUNK_TYPE_CONTENT =
      ChunkType._(1, _omitEnumNames ? '' : 'CHUNK_TYPE_CONTENT');
  static const ChunkType CHUNK_TYPE_TREE =
      ChunkType._(2, _omitEnumNames ? '' : 'CHUNK_TYPE_TREE');

  static const $core.List<ChunkType> values = <ChunkType>[
    CHUNK_TYPE_UNSPECIFIED,
    CHUNK_TYPE_CONTENT,
    CHUNK_TYPE_TREE,
  ];

  static final $core.List<ChunkType?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 2);
  static ChunkType? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const ChunkType._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
