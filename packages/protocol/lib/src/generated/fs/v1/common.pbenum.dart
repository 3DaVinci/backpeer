// This is a generated file - do not edit.
//
// Generated from fs/v1/common.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

class ErrorCode extends $pb.ProtobufEnum {
  static const ErrorCode ERROR_CODE_UNSPECIFIED =
      ErrorCode._(0, _omitEnumNames ? '' : 'ERROR_CODE_UNSPECIFIED');
  static const ErrorCode ERROR_CODE_VERSION_UNSUPPORTED =
      ErrorCode._(1, _omitEnumNames ? '' : 'ERROR_CODE_VERSION_UNSUPPORTED');
  static const ErrorCode ERROR_CODE_BAD_REQUEST =
      ErrorCode._(2, _omitEnumNames ? '' : 'ERROR_CODE_BAD_REQUEST');
  static const ErrorCode ERROR_CODE_UNAUTHENTICATED =
      ErrorCode._(3, _omitEnumNames ? '' : 'ERROR_CODE_UNAUTHENTICATED');
  static const ErrorCode ERROR_CODE_PERMISSION_DENIED =
      ErrorCode._(4, _omitEnumNames ? '' : 'ERROR_CODE_PERMISSION_DENIED');
  static const ErrorCode ERROR_CODE_NOT_FOUND =
      ErrorCode._(5, _omitEnumNames ? '' : 'ERROR_CODE_NOT_FOUND');
  static const ErrorCode ERROR_CODE_ALREADY_EXISTS =
      ErrorCode._(6, _omitEnumNames ? '' : 'ERROR_CODE_ALREADY_EXISTS');
  static const ErrorCode ERROR_CODE_QUOTA_EXCEEDED =
      ErrorCode._(7, _omitEnumNames ? '' : 'ERROR_CODE_QUOTA_EXCEEDED');
  static const ErrorCode ERROR_CODE_INTEGRITY_FAILED =
      ErrorCode._(8, _omitEnumNames ? '' : 'ERROR_CODE_INTEGRITY_FAILED');
  static const ErrorCode ERROR_CODE_TICKET_EXPIRED =
      ErrorCode._(9, _omitEnumNames ? '' : 'ERROR_CODE_TICKET_EXPIRED');
  static const ErrorCode ERROR_CODE_RATE_LIMITED =
      ErrorCode._(10, _omitEnumNames ? '' : 'ERROR_CODE_RATE_LIMITED');
  static const ErrorCode ERROR_CODE_UNAVAILABLE =
      ErrorCode._(11, _omitEnumNames ? '' : 'ERROR_CODE_UNAVAILABLE');
  static const ErrorCode ERROR_CODE_INTERNAL =
      ErrorCode._(12, _omitEnumNames ? '' : 'ERROR_CODE_INTERNAL');

  static const $core.List<ErrorCode> values = <ErrorCode>[
    ERROR_CODE_UNSPECIFIED,
    ERROR_CODE_VERSION_UNSUPPORTED,
    ERROR_CODE_BAD_REQUEST,
    ERROR_CODE_UNAUTHENTICATED,
    ERROR_CODE_PERMISSION_DENIED,
    ERROR_CODE_NOT_FOUND,
    ERROR_CODE_ALREADY_EXISTS,
    ERROR_CODE_QUOTA_EXCEEDED,
    ERROR_CODE_INTEGRITY_FAILED,
    ERROR_CODE_TICKET_EXPIRED,
    ERROR_CODE_RATE_LIMITED,
    ERROR_CODE_UNAVAILABLE,
    ERROR_CODE_INTERNAL,
  ];

  static final $core.List<ErrorCode?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 12);
  static ErrorCode? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const ErrorCode._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
