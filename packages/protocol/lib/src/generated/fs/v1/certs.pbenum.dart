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

import 'package:protobuf/protobuf.dart' as $pb;

class TicketOperation extends $pb.ProtobufEnum {
  static const TicketOperation TICKET_OPERATION_UNSPECIFIED = TicketOperation._(
      0, _omitEnumNames ? '' : 'TICKET_OPERATION_UNSPECIFIED');
  static const TicketOperation TICKET_OPERATION_PUT =
      TicketOperation._(1, _omitEnumNames ? '' : 'TICKET_OPERATION_PUT');
  static const TicketOperation TICKET_OPERATION_GET =
      TicketOperation._(2, _omitEnumNames ? '' : 'TICKET_OPERATION_GET');
  static const TicketOperation TICKET_OPERATION_DELETE =
      TicketOperation._(3, _omitEnumNames ? '' : 'TICKET_OPERATION_DELETE');

  static const $core.List<TicketOperation> values = <TicketOperation>[
    TICKET_OPERATION_UNSPECIFIED,
    TICKET_OPERATION_PUT,
    TICKET_OPERATION_GET,
    TICKET_OPERATION_DELETE,
  ];

  static final $core.List<TicketOperation?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 3);
  static TicketOperation? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const TicketOperation._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
