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

import 'package:protobuf/protobuf.dart' as $pb;

class RelayRole extends $pb.ProtobufEnum {
  static const RelayRole RELAY_ROLE_UNSPECIFIED =
      RelayRole._(0, _omitEnumNames ? '' : 'RELAY_ROLE_UNSPECIFIED');
  static const RelayRole RELAY_ROLE_LISTEN =
      RelayRole._(1, _omitEnumNames ? '' : 'RELAY_ROLE_LISTEN');
  static const RelayRole RELAY_ROLE_CONNECT =
      RelayRole._(2, _omitEnumNames ? '' : 'RELAY_ROLE_CONNECT');

  static const $core.List<RelayRole> values = <RelayRole>[
    RELAY_ROLE_UNSPECIFIED,
    RELAY_ROLE_LISTEN,
    RELAY_ROLE_CONNECT,
  ];

  static final $core.List<RelayRole?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 2);
  static RelayRole? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const RelayRole._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
