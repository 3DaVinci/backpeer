// This is a generated file - do not edit.
//
// Generated from fs/v1/common.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports
// ignore_for_file: unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use errorCodeDescriptor instead')
const ErrorCode$json = {
  '1': 'ErrorCode',
  '2': [
    {'1': 'ERROR_CODE_UNSPECIFIED', '2': 0},
    {'1': 'ERROR_CODE_VERSION_UNSUPPORTED', '2': 1},
    {'1': 'ERROR_CODE_BAD_REQUEST', '2': 2},
    {'1': 'ERROR_CODE_UNAUTHENTICATED', '2': 3},
    {'1': 'ERROR_CODE_PERMISSION_DENIED', '2': 4},
    {'1': 'ERROR_CODE_NOT_FOUND', '2': 5},
    {'1': 'ERROR_CODE_ALREADY_EXISTS', '2': 6},
    {'1': 'ERROR_CODE_QUOTA_EXCEEDED', '2': 7},
    {'1': 'ERROR_CODE_INTEGRITY_FAILED', '2': 8},
    {'1': 'ERROR_CODE_TICKET_EXPIRED', '2': 9},
    {'1': 'ERROR_CODE_RATE_LIMITED', '2': 10},
    {'1': 'ERROR_CODE_UNAVAILABLE', '2': 11},
    {'1': 'ERROR_CODE_INTERNAL', '2': 12},
  ],
};

/// Descriptor for `ErrorCode`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List errorCodeDescriptor = $convert.base64Decode(
    'CglFcnJvckNvZGUSGgoWRVJST1JfQ09ERV9VTlNQRUNJRklFRBAAEiIKHkVSUk9SX0NPREVfVk'
    'VSU0lPTl9VTlNVUFBPUlRFRBABEhoKFkVSUk9SX0NPREVfQkFEX1JFUVVFU1QQAhIeChpFUlJP'
    'Ul9DT0RFX1VOQVVUSEVOVElDQVRFRBADEiAKHEVSUk9SX0NPREVfUEVSTUlTU0lPTl9ERU5JRU'
    'QQBBIYChRFUlJPUl9DT0RFX05PVF9GT1VORBAFEh0KGUVSUk9SX0NPREVfQUxSRUFEWV9FWElT'
    'VFMQBhIdChlFUlJPUl9DT0RFX1FVT1RBX0VYQ0VFREVEEAcSHwobRVJST1JfQ09ERV9JTlRFR1'
    'JJVFlfRkFJTEVEEAgSHQoZRVJST1JfQ09ERV9USUNLRVRfRVhQSVJFRBAJEhsKF0VSUk9SX0NP'
    'REVfUkFURV9MSU1JVEVEEAoSGgoWRVJST1JfQ09ERV9VTkFWQUlMQUJMRRALEhcKE0VSUk9SX0'
    'NPREVfSU5URVJOQUwQDA==');

@$core.Deprecated('Use errorDescriptor instead')
const Error$json = {
  '1': 'Error',
  '2': [
    {
      '1': 'code',
      '3': 1,
      '4': 1,
      '5': 14,
      '6': '.fs.v1.ErrorCode',
      '10': 'code'
    },
    {'1': 'message', '3': 2, '4': 1, '5': 9, '10': 'message'},
    {'1': 'retry_after_ms', '3': 3, '4': 1, '5': 13, '10': 'retryAfterMs'},
  ],
};

/// Descriptor for `Error`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List errorDescriptor = $convert.base64Decode(
    'CgVFcnJvchIkCgRjb2RlGAEgASgOMhAuZnMudjEuRXJyb3JDb2RlUgRjb2RlEhgKB21lc3NhZ2'
    'UYAiABKAlSB21lc3NhZ2USJAoOcmV0cnlfYWZ0ZXJfbXMYAyABKA1SDHJldHJ5QWZ0ZXJNcw==');

@$core.Deprecated('Use signedDescriptor instead')
const Signed$json = {
  '1': 'Signed',
  '2': [
    {'1': 'body', '3': 1, '4': 1, '5': 12, '10': 'body'},
    {'1': 'signer', '3': 2, '4': 1, '5': 12, '10': 'signer'},
    {'1': 'signature', '3': 3, '4': 1, '5': 12, '10': 'signature'},
  ],
};

/// Descriptor for `Signed`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List signedDescriptor = $convert.base64Decode(
    'CgZTaWduZWQSEgoEYm9keRgBIAEoDFIEYm9keRIWCgZzaWduZXIYAiABKAxSBnNpZ25lchIcCg'
    'lzaWduYXR1cmUYAyABKAxSCXNpZ25hdHVyZQ==');
