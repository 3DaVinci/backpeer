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

import 'package:protobuf/protobuf.dart' as $pb;

class PeerRole extends $pb.ProtobufEnum {
  static const PeerRole PEER_ROLE_UNSPECIFIED =
      PeerRole._(0, _omitEnumNames ? '' : 'PEER_ROLE_UNSPECIFIED');
  static const PeerRole PEER_ROLE_CLIENT =
      PeerRole._(1, _omitEnumNames ? '' : 'PEER_ROLE_CLIENT');
  static const PeerRole PEER_ROLE_NODE =
      PeerRole._(2, _omitEnumNames ? '' : 'PEER_ROLE_NODE');

  static const $core.List<PeerRole> values = <PeerRole>[
    PEER_ROLE_UNSPECIFIED,
    PEER_ROLE_CLIENT,
    PEER_ROLE_NODE,
  ];

  static final $core.List<PeerRole?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 2);
  static PeerRole? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const PeerRole._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
