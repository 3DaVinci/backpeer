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

import 'package:protobuf/protobuf.dart' as $pb;

class ObjectKind extends $pb.ProtobufEnum {
  static const ObjectKind OBJECT_KIND_UNSPECIFIED =
      ObjectKind._(0, _omitEnumNames ? '' : 'OBJECT_KIND_UNSPECIFIED');
  static const ObjectKind OBJECT_KIND_SNAPSHOT =
      ObjectKind._(1, _omitEnumNames ? '' : 'OBJECT_KIND_SNAPSHOT');
  static const ObjectKind OBJECT_KIND_INDEX =
      ObjectKind._(2, _omitEnumNames ? '' : 'OBJECT_KIND_INDEX');

  static const $core.List<ObjectKind> values = <ObjectKind>[
    OBJECT_KIND_UNSPECIFIED,
    OBJECT_KIND_SNAPSHOT,
    OBJECT_KIND_INDEX,
  ];

  static final $core.List<ObjectKind?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 2);
  static ObjectKind? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const ObjectKind._(super.value, super.name);
}

class ReachabilityStatus extends $pb.ProtobufEnum {
  static const ReachabilityStatus REACHABILITY_STATUS_UNSPECIFIED =
      ReachabilityStatus._(
          0, _omitEnumNames ? '' : 'REACHABILITY_STATUS_UNSPECIFIED');
  static const ReachabilityStatus REACHABILITY_STATUS_REACHABLE =
      ReachabilityStatus._(
          1, _omitEnumNames ? '' : 'REACHABILITY_STATUS_REACHABLE');
  static const ReachabilityStatus REACHABILITY_STATUS_REFUSED =
      ReachabilityStatus._(
          2, _omitEnumNames ? '' : 'REACHABILITY_STATUS_REFUSED');
  static const ReachabilityStatus REACHABILITY_STATUS_TIMEOUT =
      ReachabilityStatus._(
          3, _omitEnumNames ? '' : 'REACHABILITY_STATUS_TIMEOUT');
  static const ReachabilityStatus REACHABILITY_STATUS_WRONG_PEER =
      ReachabilityStatus._(
          4, _omitEnumNames ? '' : 'REACHABILITY_STATUS_WRONG_PEER');
  static const ReachabilityStatus REACHABILITY_STATUS_NOT_CHECKED =
      ReachabilityStatus._(
          5, _omitEnumNames ? '' : 'REACHABILITY_STATUS_NOT_CHECKED');

  static const $core.List<ReachabilityStatus> values = <ReachabilityStatus>[
    REACHABILITY_STATUS_UNSPECIFIED,
    REACHABILITY_STATUS_REACHABLE,
    REACHABILITY_STATUS_REFUSED,
    REACHABILITY_STATUS_TIMEOUT,
    REACHABILITY_STATUS_WRONG_PEER,
    REACHABILITY_STATUS_NOT_CHECKED,
  ];

  static final $core.List<ReachabilityStatus?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 5);
  static ReachabilityStatus? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const ReachabilityStatus._(super.value, super.name);
}

/// Способ, которым клиент или узел соединился с узлом.
class ConnectionMethod extends $pb.ProtobufEnum {
  static const ConnectionMethod CONNECTION_METHOD_UNSPECIFIED =
      ConnectionMethod._(
          0, _omitEnumNames ? '' : 'CONNECTION_METHOD_UNSPECIFIED');
  static const ConnectionMethod CONNECTION_METHOD_DIRECT =
      ConnectionMethod._(1, _omitEnumNames ? '' : 'CONNECTION_METHOD_DIRECT');
  static const ConnectionMethod CONNECTION_METHOD_UDP =
      ConnectionMethod._(2, _omitEnumNames ? '' : 'CONNECTION_METHOD_UDP');
  static const ConnectionMethod CONNECTION_METHOD_RELAY =
      ConnectionMethod._(3, _omitEnumNames ? '' : 'CONNECTION_METHOD_RELAY');

  static const $core.List<ConnectionMethod> values = <ConnectionMethod>[
    CONNECTION_METHOD_UNSPECIFIED,
    CONNECTION_METHOD_DIRECT,
    CONNECTION_METHOD_UDP,
    CONNECTION_METHOD_RELAY,
  ];

  static final $core.List<ConnectionMethod?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 3);
  static ConnectionMethod? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const ConnectionMethod._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
