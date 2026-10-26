// This is a generated file - do not edit.
//
// Generated from fs/v1/coordinator.proto.

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

@$core.Deprecated('Use objectKindDescriptor instead')
const ObjectKind$json = {
  '1': 'ObjectKind',
  '2': [
    {'1': 'OBJECT_KIND_UNSPECIFIED', '2': 0},
    {'1': 'OBJECT_KIND_SNAPSHOT', '2': 1},
    {'1': 'OBJECT_KIND_INDEX', '2': 2},
  ],
};

/// Descriptor for `ObjectKind`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List objectKindDescriptor = $convert.base64Decode(
    'CgpPYmplY3RLaW5kEhsKF09CSkVDVF9LSU5EX1VOU1BFQ0lGSUVEEAASGAoUT0JKRUNUX0tJTk'
    'RfU05BUFNIT1QQARIVChFPQkpFQ1RfS0lORF9JTkRFWBAC');

@$core.Deprecated('Use reachabilityStatusDescriptor instead')
const ReachabilityStatus$json = {
  '1': 'ReachabilityStatus',
  '2': [
    {'1': 'REACHABILITY_STATUS_UNSPECIFIED', '2': 0},
    {'1': 'REACHABILITY_STATUS_REACHABLE', '2': 1},
    {'1': 'REACHABILITY_STATUS_REFUSED', '2': 2},
    {'1': 'REACHABILITY_STATUS_TIMEOUT', '2': 3},
    {'1': 'REACHABILITY_STATUS_WRONG_PEER', '2': 4},
    {'1': 'REACHABILITY_STATUS_NOT_CHECKED', '2': 5},
  ],
};

/// Descriptor for `ReachabilityStatus`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List reachabilityStatusDescriptor = $convert.base64Decode(
    'ChJSZWFjaGFiaWxpdHlTdGF0dXMSIwofUkVBQ0hBQklMSVRZX1NUQVRVU19VTlNQRUNJRklFRB'
    'AAEiEKHVJFQUNIQUJJTElUWV9TVEFUVVNfUkVBQ0hBQkxFEAESHwobUkVBQ0hBQklMSVRZX1NU'
    'QVRVU19SRUZVU0VEEAISHwobUkVBQ0hBQklMSVRZX1NUQVRVU19USU1FT1VUEAMSIgoeUkVBQ0'
    'hBQklMSVRZX1NUQVRVU19XUk9OR19QRUVSEAQSIwofUkVBQ0hBQklMSVRZX1NUQVRVU19OT1Rf'
    'Q0hFQ0tFRBAF');

@$core.Deprecated('Use registerAccountRequestDescriptor instead')
const RegisterAccountRequest$json = {
  '1': 'RegisterAccountRequest',
  '2': [
    {
      '1': 'device_certificate',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.fs.v1.Signed',
      '10': 'deviceCertificate'
    },
    {'1': 'key_bundle', '3': 2, '4': 1, '5': 12, '10': 'keyBundle'},
    {'1': 'auth_verifier', '3': 3, '4': 1, '5': 12, '10': 'authVerifier'},
    {'1': 'login', '3': 4, '4': 1, '5': 9, '10': 'login'},
  ],
};

/// Descriptor for `RegisterAccountRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List registerAccountRequestDescriptor = $convert.base64Decode(
    'ChZSZWdpc3RlckFjY291bnRSZXF1ZXN0EjwKEmRldmljZV9jZXJ0aWZpY2F0ZRgBIAEoCzINLm'
    'ZzLnYxLlNpZ25lZFIRZGV2aWNlQ2VydGlmaWNhdGUSHQoKa2V5X2J1bmRsZRgCIAEoDFIJa2V5'
    'QnVuZGxlEiMKDWF1dGhfdmVyaWZpZXIYAyABKAxSDGF1dGhWZXJpZmllchIUCgVsb2dpbhgEIA'
    'EoCVIFbG9naW4=');

@$core.Deprecated('Use registerAccountResponseDescriptor instead')
const RegisterAccountResponse$json = {
  '1': 'RegisterAccountResponse',
};

/// Descriptor for `RegisterAccountResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List registerAccountResponseDescriptor =
    $convert.base64Decode('ChdSZWdpc3RlckFjY291bnRSZXNwb25zZQ==');

@$core.Deprecated('Use addDeviceRequestDescriptor instead')
const AddDeviceRequest$json = {
  '1': 'AddDeviceRequest',
  '2': [
    {
      '1': 'device_certificate',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.fs.v1.Signed',
      '10': 'deviceCertificate'
    },
  ],
};

/// Descriptor for `AddDeviceRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List addDeviceRequestDescriptor = $convert.base64Decode(
    'ChBBZGREZXZpY2VSZXF1ZXN0EjwKEmRldmljZV9jZXJ0aWZpY2F0ZRgBIAEoCzINLmZzLnYxLl'
    'NpZ25lZFIRZGV2aWNlQ2VydGlmaWNhdGU=');

@$core.Deprecated('Use addDeviceResponseDescriptor instead')
const AddDeviceResponse$json = {
  '1': 'AddDeviceResponse',
};

/// Descriptor for `AddDeviceResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List addDeviceResponseDescriptor =
    $convert.base64Decode('ChFBZGREZXZpY2VSZXNwb25zZQ==');

@$core.Deprecated('Use listDevicesRequestDescriptor instead')
const ListDevicesRequest$json = {
  '1': 'ListDevicesRequest',
};

/// Descriptor for `ListDevicesRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listDevicesRequestDescriptor =
    $convert.base64Decode('ChJMaXN0RGV2aWNlc1JlcXVlc3Q=');

@$core.Deprecated('Use listDevicesResponseDescriptor instead')
const ListDevicesResponse$json = {
  '1': 'ListDevicesResponse',
  '2': [
    {
      '1': 'devices',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.fs.v1.DeviceInfo',
      '10': 'devices'
    },
  ],
};

/// Descriptor for `ListDevicesResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listDevicesResponseDescriptor = $convert.base64Decode(
    'ChNMaXN0RGV2aWNlc1Jlc3BvbnNlEisKB2RldmljZXMYASADKAsyES5mcy52MS5EZXZpY2VJbm'
    'ZvUgdkZXZpY2Vz');

@$core.Deprecated('Use deviceInfoDescriptor instead')
const DeviceInfo$json = {
  '1': 'DeviceInfo',
  '2': [
    {
      '1': 'certificate',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.fs.v1.Signed',
      '10': 'certificate'
    },
    {'1': 'added_at_unix_ms', '3': 2, '4': 1, '5': 3, '10': 'addedAtUnixMs'},
    {
      '1': 'revoked_at_unix_ms',
      '3': 3,
      '4': 1,
      '5': 3,
      '10': 'revokedAtUnixMs'
    },
  ],
};

/// Descriptor for `DeviceInfo`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List deviceInfoDescriptor = $convert.base64Decode(
    'CgpEZXZpY2VJbmZvEi8KC2NlcnRpZmljYXRlGAEgASgLMg0uZnMudjEuU2lnbmVkUgtjZXJ0aW'
    'ZpY2F0ZRInChBhZGRlZF9hdF91bml4X21zGAIgASgDUg1hZGRlZEF0VW5peE1zEisKEnJldm9r'
    'ZWRfYXRfdW5peF9tcxgDIAEoA1IPcmV2b2tlZEF0VW5peE1z');

@$core.Deprecated('Use revokeDeviceRequestDescriptor instead')
const RevokeDeviceRequest$json = {
  '1': 'RevokeDeviceRequest',
  '2': [
    {
      '1': 'revocation',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.fs.v1.Signed',
      '10': 'revocation'
    },
  ],
};

/// Descriptor for `RevokeDeviceRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List revokeDeviceRequestDescriptor = $convert.base64Decode(
    'ChNSZXZva2VEZXZpY2VSZXF1ZXN0Ei0KCnJldm9jYXRpb24YASABKAsyDS5mcy52MS5TaWduZW'
    'RSCnJldm9jYXRpb24=');

@$core.Deprecated('Use revokeDeviceResponseDescriptor instead')
const RevokeDeviceResponse$json = {
  '1': 'RevokeDeviceResponse',
};

/// Descriptor for `RevokeDeviceResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List revokeDeviceResponseDescriptor =
    $convert.base64Decode('ChRSZXZva2VEZXZpY2VSZXNwb25zZQ==');

@$core.Deprecated('Use listRevocationsRequestDescriptor instead')
const ListRevocationsRequest$json = {
  '1': 'ListRevocationsRequest',
  '2': [
    {'1': 'after_sequence', '3': 1, '4': 1, '5': 4, '10': 'afterSequence'},
    {'1': 'limit', '3': 2, '4': 1, '5': 13, '10': 'limit'},
  ],
};

/// Descriptor for `ListRevocationsRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listRevocationsRequestDescriptor =
    $convert.base64Decode(
        'ChZMaXN0UmV2b2NhdGlvbnNSZXF1ZXN0EiUKDmFmdGVyX3NlcXVlbmNlGAEgASgEUg1hZnRlcl'
        'NlcXVlbmNlEhQKBWxpbWl0GAIgASgNUgVsaW1pdA==');

@$core.Deprecated('Use listRevocationsResponseDescriptor instead')
const ListRevocationsResponse$json = {
  '1': 'ListRevocationsResponse',
  '2': [
    {
      '1': 'revocations',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.fs.v1.RevocationEntry',
      '10': 'revocations'
    },
    {'1': 'more', '3': 2, '4': 1, '5': 8, '10': 'more'},
  ],
};

/// Descriptor for `ListRevocationsResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listRevocationsResponseDescriptor =
    $convert.base64Decode(
        'ChdMaXN0UmV2b2NhdGlvbnNSZXNwb25zZRI4CgtyZXZvY2F0aW9ucxgBIAMoCzIWLmZzLnYxLl'
        'Jldm9jYXRpb25FbnRyeVILcmV2b2NhdGlvbnMSEgoEbW9yZRgCIAEoCFIEbW9yZQ==');

@$core.Deprecated('Use revocationEntryDescriptor instead')
const RevocationEntry$json = {
  '1': 'RevocationEntry',
  '2': [
    {'1': 'sequence', '3': 1, '4': 1, '5': 4, '10': 'sequence'},
    {
      '1': 'revocation',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.fs.v1.Signed',
      '10': 'revocation'
    },
  ],
};

/// Descriptor for `RevocationEntry`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List revocationEntryDescriptor = $convert.base64Decode(
    'Cg9SZXZvY2F0aW9uRW50cnkSGgoIc2VxdWVuY2UYASABKARSCHNlcXVlbmNlEi0KCnJldm9jYX'
    'Rpb24YAiABKAsyDS5mcy52MS5TaWduZWRSCnJldm9jYXRpb24=');

@$core.Deprecated('Use getLoginParamsRequestDescriptor instead')
const GetLoginParamsRequest$json = {
  '1': 'GetLoginParamsRequest',
  '2': [
    {'1': 'login', '3': 1, '4': 1, '5': 9, '10': 'login'},
  ],
};

/// Descriptor for `GetLoginParamsRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getLoginParamsRequestDescriptor =
    $convert.base64Decode(
        'ChVHZXRMb2dpblBhcmFtc1JlcXVlc3QSFAoFbG9naW4YASABKAlSBWxvZ2lu');

@$core.Deprecated('Use getLoginParamsResponseDescriptor instead')
const GetLoginParamsResponse$json = {
  '1': 'GetLoginParamsResponse',
  '2': [
    {'1': 'salt', '3': 1, '4': 1, '5': 12, '10': 'salt'},
    {'1': 'memory_kib', '3': 2, '4': 1, '5': 13, '10': 'memoryKib'},
    {'1': 'iterations', '3': 3, '4': 1, '5': 13, '10': 'iterations'},
    {'1': 'parallelism', '3': 4, '4': 1, '5': 13, '10': 'parallelism'},
  ],
};

/// Descriptor for `GetLoginParamsResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getLoginParamsResponseDescriptor = $convert.base64Decode(
    'ChZHZXRMb2dpblBhcmFtc1Jlc3BvbnNlEhIKBHNhbHQYASABKAxSBHNhbHQSHQoKbWVtb3J5X2'
    'tpYhgCIAEoDVIJbWVtb3J5S2liEh4KCml0ZXJhdGlvbnMYAyABKA1SCml0ZXJhdGlvbnMSIAoL'
    'cGFyYWxsZWxpc20YBCABKA1SC3BhcmFsbGVsaXNt');

@$core.Deprecated('Use getKeyBundleRequestDescriptor instead')
const GetKeyBundleRequest$json = {
  '1': 'GetKeyBundleRequest',
  '2': [
    {'1': 'auth_proof', '3': 2, '4': 1, '5': 12, '10': 'authProof'},
    {'1': 'login', '3': 3, '4': 1, '5': 9, '10': 'login'},
    {'1': 'time_unix_ms', '3': 4, '4': 1, '5': 3, '10': 'timeUnixMs'},
  ],
  '9': [
    {'1': 1, '2': 2},
  ],
};

/// Descriptor for `GetKeyBundleRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getKeyBundleRequestDescriptor = $convert.base64Decode(
    'ChNHZXRLZXlCdW5kbGVSZXF1ZXN0Eh0KCmF1dGhfcHJvb2YYAiABKAxSCWF1dGhQcm9vZhIUCg'
    'Vsb2dpbhgDIAEoCVIFbG9naW4SIAoMdGltZV91bml4X21zGAQgASgDUgp0aW1lVW5peE1zSgQI'
    'ARAC');

@$core.Deprecated('Use getKeyBundleResponseDescriptor instead')
const GetKeyBundleResponse$json = {
  '1': 'GetKeyBundleResponse',
  '2': [
    {'1': 'key_bundle', '3': 1, '4': 1, '5': 12, '10': 'keyBundle'},
  ],
};

/// Descriptor for `GetKeyBundleResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getKeyBundleResponseDescriptor = $convert.base64Decode(
    'ChRHZXRLZXlCdW5kbGVSZXNwb25zZRIdCgprZXlfYnVuZGxlGAEgASgMUglrZXlCdW5kbGU=');

@$core.Deprecated('Use setKeyBundleRequestDescriptor instead')
const SetKeyBundleRequest$json = {
  '1': 'SetKeyBundleRequest',
  '2': [
    {'1': 'key_bundle', '3': 1, '4': 1, '5': 12, '10': 'keyBundle'},
    {'1': 'auth_verifier', '3': 2, '4': 1, '5': 12, '10': 'authVerifier'},
  ],
};

/// Descriptor for `SetKeyBundleRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List setKeyBundleRequestDescriptor = $convert.base64Decode(
    'ChNTZXRLZXlCdW5kbGVSZXF1ZXN0Eh0KCmtleV9idW5kbGUYASABKAxSCWtleUJ1bmRsZRIjCg'
    '1hdXRoX3ZlcmlmaWVyGAIgASgMUgxhdXRoVmVyaWZpZXI=');

@$core.Deprecated('Use setKeyBundleResponseDescriptor instead')
const SetKeyBundleResponse$json = {
  '1': 'SetKeyBundleResponse',
};

/// Descriptor for `SetKeyBundleResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List setKeyBundleResponseDescriptor =
    $convert.base64Decode('ChRTZXRLZXlCdW5kbGVSZXNwb25zZQ==');

@$core.Deprecated('Use putObjectRequestDescriptor instead')
const PutObjectRequest$json = {
  '1': 'PutObjectRequest',
  '2': [
    {
      '1': 'kind',
      '3': 1,
      '4': 1,
      '5': 14,
      '6': '.fs.v1.ObjectKind',
      '10': 'kind'
    },
    {'1': 'object_id', '3': 2, '4': 1, '5': 12, '10': 'objectId'},
    {'1': 'blob', '3': 3, '4': 1, '5': 12, '10': 'blob'},
    {'1': 'sequence', '3': 4, '4': 1, '5': 4, '10': 'sequence'},
  ],
};

/// Descriptor for `PutObjectRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List putObjectRequestDescriptor = $convert.base64Decode(
    'ChBQdXRPYmplY3RSZXF1ZXN0EiUKBGtpbmQYASABKA4yES5mcy52MS5PYmplY3RLaW5kUgRraW'
    '5kEhsKCW9iamVjdF9pZBgCIAEoDFIIb2JqZWN0SWQSEgoEYmxvYhgDIAEoDFIEYmxvYhIaCghz'
    'ZXF1ZW5jZRgEIAEoBFIIc2VxdWVuY2U=');

@$core.Deprecated('Use putObjectResponseDescriptor instead')
const PutObjectResponse$json = {
  '1': 'PutObjectResponse',
};

/// Descriptor for `PutObjectResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List putObjectResponseDescriptor =
    $convert.base64Decode('ChFQdXRPYmplY3RSZXNwb25zZQ==');

@$core.Deprecated('Use listObjectsRequestDescriptor instead')
const ListObjectsRequest$json = {
  '1': 'ListObjectsRequest',
  '2': [
    {
      '1': 'kind',
      '3': 1,
      '4': 1,
      '5': 14,
      '6': '.fs.v1.ObjectKind',
      '10': 'kind'
    },
    {'1': 'after_object_id', '3': 2, '4': 1, '5': 12, '10': 'afterObjectId'},
    {'1': 'limit', '3': 3, '4': 1, '5': 13, '10': 'limit'},
  ],
};

/// Descriptor for `ListObjectsRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listObjectsRequestDescriptor = $convert.base64Decode(
    'ChJMaXN0T2JqZWN0c1JlcXVlc3QSJQoEa2luZBgBIAEoDjIRLmZzLnYxLk9iamVjdEtpbmRSBG'
    'tpbmQSJgoPYWZ0ZXJfb2JqZWN0X2lkGAIgASgMUg1hZnRlck9iamVjdElkEhQKBWxpbWl0GAMg'
    'ASgNUgVsaW1pdA==');

@$core.Deprecated('Use listObjectsResponseDescriptor instead')
const ListObjectsResponse$json = {
  '1': 'ListObjectsResponse',
  '2': [
    {
      '1': 'objects',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.fs.v1.ObjectInfo',
      '10': 'objects'
    },
    {'1': 'more', '3': 2, '4': 1, '5': 8, '10': 'more'},
  ],
};

/// Descriptor for `ListObjectsResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listObjectsResponseDescriptor = $convert.base64Decode(
    'ChNMaXN0T2JqZWN0c1Jlc3BvbnNlEisKB29iamVjdHMYASADKAsyES5mcy52MS5PYmplY3RJbm'
    'ZvUgdvYmplY3RzEhIKBG1vcmUYAiABKAhSBG1vcmU=');

@$core.Deprecated('Use objectInfoDescriptor instead')
const ObjectInfo$json = {
  '1': 'ObjectInfo',
  '2': [
    {'1': 'object_id', '3': 1, '4': 1, '5': 12, '10': 'objectId'},
    {'1': 'size', '3': 2, '4': 1, '5': 13, '10': 'size'},
    {'1': 'stored_at_unix_ms', '3': 3, '4': 1, '5': 3, '10': 'storedAtUnixMs'},
    {'1': 'sequence', '3': 4, '4': 1, '5': 4, '10': 'sequence'},
  ],
};

/// Descriptor for `ObjectInfo`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List objectInfoDescriptor = $convert.base64Decode(
    'CgpPYmplY3RJbmZvEhsKCW9iamVjdF9pZBgBIAEoDFIIb2JqZWN0SWQSEgoEc2l6ZRgCIAEoDV'
    'IEc2l6ZRIpChFzdG9yZWRfYXRfdW5peF9tcxgDIAEoA1IOc3RvcmVkQXRVbml4TXMSGgoIc2Vx'
    'dWVuY2UYBCABKARSCHNlcXVlbmNl');

@$core.Deprecated('Use getObjectRequestDescriptor instead')
const GetObjectRequest$json = {
  '1': 'GetObjectRequest',
  '2': [
    {
      '1': 'kind',
      '3': 1,
      '4': 1,
      '5': 14,
      '6': '.fs.v1.ObjectKind',
      '10': 'kind'
    },
    {'1': 'object_id', '3': 2, '4': 1, '5': 12, '10': 'objectId'},
  ],
};

/// Descriptor for `GetObjectRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getObjectRequestDescriptor = $convert.base64Decode(
    'ChBHZXRPYmplY3RSZXF1ZXN0EiUKBGtpbmQYASABKA4yES5mcy52MS5PYmplY3RLaW5kUgRraW'
    '5kEhsKCW9iamVjdF9pZBgCIAEoDFIIb2JqZWN0SWQ=');

@$core.Deprecated('Use getObjectResponseDescriptor instead')
const GetObjectResponse$json = {
  '1': 'GetObjectResponse',
  '2': [
    {'1': 'blob', '3': 1, '4': 1, '5': 12, '10': 'blob'},
  ],
};

/// Descriptor for `GetObjectResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getObjectResponseDescriptor = $convert
    .base64Decode('ChFHZXRPYmplY3RSZXNwb25zZRISCgRibG9iGAEgASgMUgRibG9i');

@$core.Deprecated('Use deleteObjectRequestDescriptor instead')
const DeleteObjectRequest$json = {
  '1': 'DeleteObjectRequest',
  '2': [
    {
      '1': 'kind',
      '3': 1,
      '4': 1,
      '5': 14,
      '6': '.fs.v1.ObjectKind',
      '10': 'kind'
    },
    {'1': 'object_id', '3': 2, '4': 1, '5': 12, '10': 'objectId'},
  ],
};

/// Descriptor for `DeleteObjectRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List deleteObjectRequestDescriptor = $convert.base64Decode(
    'ChNEZWxldGVPYmplY3RSZXF1ZXN0EiUKBGtpbmQYASABKA4yES5mcy52MS5PYmplY3RLaW5kUg'
    'RraW5kEhsKCW9iamVjdF9pZBgCIAEoDFIIb2JqZWN0SWQ=');

@$core.Deprecated('Use deleteObjectResponseDescriptor instead')
const DeleteObjectResponse$json = {
  '1': 'DeleteObjectResponse',
};

/// Descriptor for `DeleteObjectResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List deleteObjectResponseDescriptor =
    $convert.base64Decode('ChREZWxldGVPYmplY3RSZXNwb25zZQ==');

@$core.Deprecated('Use allocateSegmentRequestDescriptor instead')
const AllocateSegmentRequest$json = {
  '1': 'AllocateSegmentRequest',
  '2': [
    {'1': 'segment_id', '3': 1, '4': 1, '5': 12, '10': 'segmentId'},
    {'1': 'k', '3': 2, '4': 1, '5': 13, '10': 'k'},
    {'1': 'n', '3': 3, '4': 1, '5': 13, '10': 'n'},
    {'1': 'fragment_size', '3': 4, '4': 1, '5': 13, '10': 'fragmentSize'},
    {'1': 'fragment_ids', '3': 5, '4': 3, '5': 12, '10': 'fragmentIds'},
    {'1': 'body_roots', '3': 6, '4': 3, '5': 12, '10': 'bodyRoots'},
    {'1': 'repair_threshold', '3': 7, '4': 1, '5': 13, '10': 'repairThreshold'},
  ],
};

/// Descriptor for `AllocateSegmentRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List allocateSegmentRequestDescriptor = $convert.base64Decode(
    'ChZBbGxvY2F0ZVNlZ21lbnRSZXF1ZXN0Eh0KCnNlZ21lbnRfaWQYASABKAxSCXNlZ21lbnRJZB'
    'IMCgFrGAIgASgNUgFrEgwKAW4YAyABKA1SAW4SIwoNZnJhZ21lbnRfc2l6ZRgEIAEoDVIMZnJh'
    'Z21lbnRTaXplEiEKDGZyYWdtZW50X2lkcxgFIAMoDFILZnJhZ21lbnRJZHMSHQoKYm9keV9yb2'
    '90cxgGIAMoDFIJYm9keVJvb3RzEikKEHJlcGFpcl90aHJlc2hvbGQYByABKA1SD3JlcGFpclRo'
    'cmVzaG9sZA==');

@$core.Deprecated('Use allocateSegmentResponseDescriptor instead')
const AllocateSegmentResponse$json = {
  '1': 'AllocateSegmentResponse',
  '2': [
    {
      '1': 'placements',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.fs.v1.Placement',
      '10': 'placements'
    },
  ],
};

/// Descriptor for `AllocateSegmentResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List allocateSegmentResponseDescriptor =
    $convert.base64Decode(
        'ChdBbGxvY2F0ZVNlZ21lbnRSZXNwb25zZRIwCgpwbGFjZW1lbnRzGAEgAygLMhAuZnMudjEuUG'
        'xhY2VtZW50UgpwbGFjZW1lbnRz');

@$core.Deprecated('Use placementDescriptor instead')
const Placement$json = {
  '1': 'Placement',
  '2': [
    {'1': 'index', '3': 1, '4': 1, '5': 13, '10': 'index'},
    {
      '1': 'node',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.fs.v1.NodeAddress',
      '10': 'node'
    },
    {
      '1': 'ticket',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.fs.v1.Signed',
      '10': 'ticket'
    },
  ],
};

/// Descriptor for `Placement`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List placementDescriptor = $convert.base64Decode(
    'CglQbGFjZW1lbnQSFAoFaW5kZXgYASABKA1SBWluZGV4EiYKBG5vZGUYAiABKAsyEi5mcy52MS'
    '5Ob2RlQWRkcmVzc1IEbm9kZRIlCgZ0aWNrZXQYAyABKAsyDS5mcy52MS5TaWduZWRSBnRpY2tl'
    'dA==');

@$core.Deprecated('Use nodeAddressDescriptor instead')
const NodeAddress$json = {
  '1': 'NodeAddress',
  '2': [
    {'1': 'node_id', '3': 1, '4': 1, '5': 12, '10': 'nodeId'},
    {'1': 'endpoints', '3': 2, '4': 3, '5': 9, '10': 'endpoints'},
    {'1': 'needs_relay', '3': 3, '4': 1, '5': 8, '10': 'needsRelay'},
  ],
};

/// Descriptor for `NodeAddress`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List nodeAddressDescriptor = $convert.base64Decode(
    'CgtOb2RlQWRkcmVzcxIXCgdub2RlX2lkGAEgASgMUgZub2RlSWQSHAoJZW5kcG9pbnRzGAIgAy'
    'gJUgllbmRwb2ludHMSHwoLbmVlZHNfcmVsYXkYAyABKAhSCm5lZWRzUmVsYXk=');

@$core.Deprecated('Use commitSegmentRequestDescriptor instead')
const CommitSegmentRequest$json = {
  '1': 'CommitSegmentRequest',
  '2': [
    {'1': 'segment_id', '3': 1, '4': 1, '5': 12, '10': 'segmentId'},
    {'1': 'stored_indexes', '3': 2, '4': 3, '5': 13, '10': 'storedIndexes'},
  ],
};

/// Descriptor for `CommitSegmentRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List commitSegmentRequestDescriptor = $convert.base64Decode(
    'ChRDb21taXRTZWdtZW50UmVxdWVzdBIdCgpzZWdtZW50X2lkGAEgASgMUglzZWdtZW50SWQSJQ'
    'oOc3RvcmVkX2luZGV4ZXMYAiADKA1SDXN0b3JlZEluZGV4ZXM=');

@$core.Deprecated('Use commitSegmentResponseDescriptor instead')
const CommitSegmentResponse$json = {
  '1': 'CommitSegmentResponse',
};

/// Descriptor for `CommitSegmentResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List commitSegmentResponseDescriptor =
    $convert.base64Decode('ChVDb21taXRTZWdtZW50UmVzcG9uc2U=');

@$core.Deprecated('Use locateSegmentRequestDescriptor instead')
const LocateSegmentRequest$json = {
  '1': 'LocateSegmentRequest',
  '2': [
    {'1': 'segment_id', '3': 1, '4': 1, '5': 12, '10': 'segmentId'},
  ],
};

/// Descriptor for `LocateSegmentRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List locateSegmentRequestDescriptor = $convert.base64Decode(
    'ChRMb2NhdGVTZWdtZW50UmVxdWVzdBIdCgpzZWdtZW50X2lkGAEgASgMUglzZWdtZW50SWQ=');

@$core.Deprecated('Use locateSegmentResponseDescriptor instead')
const LocateSegmentResponse$json = {
  '1': 'LocateSegmentResponse',
  '2': [
    {
      '1': 'placements',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.fs.v1.Placement',
      '10': 'placements'
    },
  ],
};

/// Descriptor for `LocateSegmentResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List locateSegmentResponseDescriptor = $convert.base64Decode(
    'ChVMb2NhdGVTZWdtZW50UmVzcG9uc2USMAoKcGxhY2VtZW50cxgBIAMoCzIQLmZzLnYxLlBsYW'
    'NlbWVudFIKcGxhY2VtZW50cw==');

@$core.Deprecated('Use deleteSegmentRequestDescriptor instead')
const DeleteSegmentRequest$json = {
  '1': 'DeleteSegmentRequest',
  '2': [
    {'1': 'segment_id', '3': 1, '4': 1, '5': 12, '10': 'segmentId'},
  ],
};

/// Descriptor for `DeleteSegmentRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List deleteSegmentRequestDescriptor = $convert.base64Decode(
    'ChREZWxldGVTZWdtZW50UmVxdWVzdBIdCgpzZWdtZW50X2lkGAEgASgMUglzZWdtZW50SWQ=');

@$core.Deprecated('Use deleteSegmentResponseDescriptor instead')
const DeleteSegmentResponse$json = {
  '1': 'DeleteSegmentResponse',
  '2': [
    {
      '1': 'placements',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.fs.v1.Placement',
      '10': 'placements'
    },
  ],
};

/// Descriptor for `DeleteSegmentResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List deleteSegmentResponseDescriptor = $convert.base64Decode(
    'ChVEZWxldGVTZWdtZW50UmVzcG9uc2USMAoKcGxhY2VtZW50cxgBIAMoCzIQLmZzLnYxLlBsYW'
    'NlbWVudFIKcGxhY2VtZW50cw==');

@$core.Deprecated('Use registerNodeRequestDescriptor instead')
const RegisterNodeRequest$json = {
  '1': 'RegisterNodeRequest',
  '2': [
    {
      '1': 'node_certificate',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.fs.v1.Signed',
      '10': 'nodeCertificate'
    },
    {'1': 'capacity_bytes', '3': 2, '4': 1, '5': 4, '10': 'capacityBytes'},
    {'1': 'endpoints', '3': 3, '4': 3, '5': 9, '10': 'endpoints'},
    {'1': 'versions', '3': 4, '4': 3, '5': 13, '10': 'versions'},
    {'1': 'software', '3': 5, '4': 1, '5': 9, '10': 'software'},
  ],
};

/// Descriptor for `RegisterNodeRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List registerNodeRequestDescriptor = $convert.base64Decode(
    'ChNSZWdpc3Rlck5vZGVSZXF1ZXN0EjgKEG5vZGVfY2VydGlmaWNhdGUYASABKAsyDS5mcy52MS'
    '5TaWduZWRSD25vZGVDZXJ0aWZpY2F0ZRIlCg5jYXBhY2l0eV9ieXRlcxgCIAEoBFINY2FwYWNp'
    'dHlCeXRlcxIcCgllbmRwb2ludHMYAyADKAlSCWVuZHBvaW50cxIaCgh2ZXJzaW9ucxgEIAMoDV'
    'IIdmVyc2lvbnMSGgoIc29mdHdhcmUYBSABKAlSCHNvZnR3YXJl');

@$core.Deprecated('Use registerNodeResponseDescriptor instead')
const RegisterNodeResponse$json = {
  '1': 'RegisterNodeResponse',
  '2': [
    {'1': 'coordinator_keys', '3': 1, '4': 3, '5': 12, '10': 'coordinatorKeys'},
  ],
};

/// Descriptor for `RegisterNodeResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List registerNodeResponseDescriptor = $convert.base64Decode(
    'ChRSZWdpc3Rlck5vZGVSZXNwb25zZRIpChBjb29yZGluYXRvcl9rZXlzGAEgAygMUg9jb29yZG'
    'luYXRvcktleXM=');

@$core.Deprecated('Use heartbeatRequestDescriptor instead')
const HeartbeatRequest$json = {
  '1': 'HeartbeatRequest',
  '2': [
    {'1': 'used_bytes', '3': 1, '4': 1, '5': 4, '10': 'usedBytes'},
    {'1': 'capacity_bytes', '3': 2, '4': 1, '5': 4, '10': 'capacityBytes'},
    {'1': 'endpoints', '3': 3, '4': 3, '5': 9, '10': 'endpoints'},
    {
      '1': 'free_bytes',
      '3': 4,
      '4': 1,
      '5': 4,
      '9': 0,
      '10': 'freeBytes',
      '17': true
    },
  ],
  '8': [
    {'1': '_free_bytes'},
  ],
};

/// Descriptor for `HeartbeatRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List heartbeatRequestDescriptor = $convert.base64Decode(
    'ChBIZWFydGJlYXRSZXF1ZXN0Eh0KCnVzZWRfYnl0ZXMYASABKARSCXVzZWRCeXRlcxIlCg5jYX'
    'BhY2l0eV9ieXRlcxgCIAEoBFINY2FwYWNpdHlCeXRlcxIcCgllbmRwb2ludHMYAyADKAlSCWVu'
    'ZHBvaW50cxIiCgpmcmVlX2J5dGVzGAQgASgESABSCWZyZWVCeXRlc4gBAUINCgtfZnJlZV9ieX'
    'Rlcw==');

@$core.Deprecated('Use heartbeatResponseDescriptor instead')
const HeartbeatResponse$json = {
  '1': 'HeartbeatResponse',
  '2': [
    {
      '1': 'next_heartbeat_ms',
      '3': 1,
      '4': 1,
      '5': 13,
      '10': 'nextHeartbeatMs'
    },
  ],
};

/// Descriptor for `HeartbeatResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List heartbeatResponseDescriptor = $convert.base64Decode(
    'ChFIZWFydGJlYXRSZXNwb25zZRIqChFuZXh0X2hlYXJ0YmVhdF9tcxgBIAEoDVIPbmV4dEhlYX'
    'J0YmVhdE1z');

@$core.Deprecated('Use reportDamagedFragmentsRequestDescriptor instead')
const ReportDamagedFragmentsRequest$json = {
  '1': 'ReportDamagedFragmentsRequest',
  '2': [
    {'1': 'fragment_ids', '3': 1, '4': 3, '5': 12, '10': 'fragmentIds'},
  ],
};

/// Descriptor for `ReportDamagedFragmentsRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List reportDamagedFragmentsRequestDescriptor =
    $convert.base64Decode(
        'Ch1SZXBvcnREYW1hZ2VkRnJhZ21lbnRzUmVxdWVzdBIhCgxmcmFnbWVudF9pZHMYASADKAxSC2'
        'ZyYWdtZW50SWRz');

@$core.Deprecated('Use reportDamagedFragmentsResponseDescriptor instead')
const ReportDamagedFragmentsResponse$json = {
  '1': 'ReportDamagedFragmentsResponse',
  '2': [
    {'1': 'known', '3': 1, '4': 1, '5': 13, '10': 'known'},
  ],
};

/// Descriptor for `ReportDamagedFragmentsResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List reportDamagedFragmentsResponseDescriptor =
    $convert.base64Decode(
        'Ch5SZXBvcnREYW1hZ2VkRnJhZ21lbnRzUmVzcG9uc2USFAoFa25vd24YASABKA1SBWtub3du');

@$core.Deprecated('Use checkReachabilityRequestDescriptor instead')
const CheckReachabilityRequest$json = {
  '1': 'CheckReachabilityRequest',
  '2': [
    {'1': 'ports', '3': 1, '4': 3, '5': 13, '10': 'ports'},
  ],
};

/// Descriptor for `CheckReachabilityRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List checkReachabilityRequestDescriptor =
    $convert.base64Decode(
        'ChhDaGVja1JlYWNoYWJpbGl0eVJlcXVlc3QSFAoFcG9ydHMYASADKA1SBXBvcnRz');

@$core.Deprecated('Use checkReachabilityResponseDescriptor instead')
const CheckReachabilityResponse$json = {
  '1': 'CheckReachabilityResponse',
  '2': [
    {'1': 'observed_address', '3': 1, '4': 1, '5': 9, '10': 'observedAddress'},
    {
      '1': 'results',
      '3': 2,
      '4': 3,
      '5': 11,
      '6': '.fs.v1.ReachabilityResult',
      '10': 'results'
    },
  ],
};

/// Descriptor for `CheckReachabilityResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List checkReachabilityResponseDescriptor = $convert.base64Decode(
    'ChlDaGVja1JlYWNoYWJpbGl0eVJlc3BvbnNlEikKEG9ic2VydmVkX2FkZHJlc3MYASABKAlSD2'
    '9ic2VydmVkQWRkcmVzcxIzCgdyZXN1bHRzGAIgAygLMhkuZnMudjEuUmVhY2hhYmlsaXR5UmVz'
    'dWx0UgdyZXN1bHRz');

@$core.Deprecated('Use reachabilityResultDescriptor instead')
const ReachabilityResult$json = {
  '1': 'ReachabilityResult',
  '2': [
    {'1': 'port', '3': 1, '4': 1, '5': 13, '10': 'port'},
    {
      '1': 'status',
      '3': 2,
      '4': 1,
      '5': 14,
      '6': '.fs.v1.ReachabilityStatus',
      '10': 'status'
    },
  ],
};

/// Descriptor for `ReachabilityResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List reachabilityResultDescriptor = $convert.base64Decode(
    'ChJSZWFjaGFiaWxpdHlSZXN1bHQSEgoEcG9ydBgBIAEoDVIEcG9ydBIxCgZzdGF0dXMYAiABKA'
    '4yGS5mcy52MS5SZWFjaGFiaWxpdHlTdGF0dXNSBnN0YXR1cw==');

@$core.Deprecated('Use nodeChannelMessageDescriptor instead')
const NodeChannelMessage$json = {
  '1': 'NodeChannelMessage',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 4, '10': 'id'},
    {'1': 'reply_to', '3': 2, '4': 1, '5': 4, '10': 'replyTo'},
    {
      '1': 'heartbeat',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.fs.v1.HeartbeatRequest',
      '9': 0,
      '10': 'heartbeat'
    },
    {
      '1': 'done',
      '3': 4,
      '4': 1,
      '5': 11,
      '6': '.fs.v1.CommandDone',
      '9': 0,
      '10': 'done'
    },
    {
      '1': 'error',
      '3': 5,
      '4': 1,
      '5': 11,
      '6': '.fs.v1.Error',
      '9': 0,
      '10': 'error'
    },
  ],
  '8': [
    {'1': 'body'},
  ],
};

/// Descriptor for `NodeChannelMessage`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List nodeChannelMessageDescriptor = $convert.base64Decode(
    'ChJOb2RlQ2hhbm5lbE1lc3NhZ2USDgoCaWQYASABKARSAmlkEhkKCHJlcGx5X3RvGAIgASgEUg'
    'dyZXBseVRvEjcKCWhlYXJ0YmVhdBgDIAEoCzIXLmZzLnYxLkhlYXJ0YmVhdFJlcXVlc3RIAFIJ'
    'aGVhcnRiZWF0EigKBGRvbmUYBCABKAsyEi5mcy52MS5Db21tYW5kRG9uZUgAUgRkb25lEiQKBW'
    'Vycm9yGAUgASgLMgwuZnMudjEuRXJyb3JIAFIFZXJyb3JCBgoEYm9keQ==');

@$core.Deprecated('Use coordinatorChannelMessageDescriptor instead')
const CoordinatorChannelMessage$json = {
  '1': 'CoordinatorChannelMessage',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 4, '10': 'id'},
    {'1': 'reply_to', '3': 2, '4': 1, '5': 4, '10': 'replyTo'},
    {
      '1': 'heartbeat',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.fs.v1.HeartbeatResponse',
      '9': 0,
      '10': 'heartbeat'
    },
    {
      '1': 'error',
      '3': 4,
      '4': 1,
      '5': 11,
      '6': '.fs.v1.Error',
      '9': 0,
      '10': 'error'
    },
    {
      '1': 'ping',
      '3': 5,
      '4': 1,
      '5': 11,
      '6': '.fs.v1.PingCommand',
      '9': 0,
      '10': 'ping'
    },
    {
      '1': 'sync_revocations',
      '3': 6,
      '4': 1,
      '5': 11,
      '6': '.fs.v1.SyncRevocationsCommand',
      '9': 0,
      '10': 'syncRevocations'
    },
  ],
  '8': [
    {'1': 'body'},
  ],
};

/// Descriptor for `CoordinatorChannelMessage`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List coordinatorChannelMessageDescriptor = $convert.base64Decode(
    'ChlDb29yZGluYXRvckNoYW5uZWxNZXNzYWdlEg4KAmlkGAEgASgEUgJpZBIZCghyZXBseV90bx'
    'gCIAEoBFIHcmVwbHlUbxI4CgloZWFydGJlYXQYAyABKAsyGC5mcy52MS5IZWFydGJlYXRSZXNw'
    'b25zZUgAUgloZWFydGJlYXQSJAoFZXJyb3IYBCABKAsyDC5mcy52MS5FcnJvckgAUgVlcnJvch'
    'IoCgRwaW5nGAUgASgLMhIuZnMudjEuUGluZ0NvbW1hbmRIAFIEcGluZxJKChBzeW5jX3Jldm9j'
    'YXRpb25zGAYgASgLMh0uZnMudjEuU3luY1Jldm9jYXRpb25zQ29tbWFuZEgAUg9zeW5jUmV2b2'
    'NhdGlvbnNCBgoEYm9keQ==');

@$core.Deprecated('Use commandDoneDescriptor instead')
const CommandDone$json = {
  '1': 'CommandDone',
};

/// Descriptor for `CommandDone`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List commandDoneDescriptor =
    $convert.base64Decode('CgtDb21tYW5kRG9uZQ==');

@$core.Deprecated('Use pingCommandDescriptor instead')
const PingCommand$json = {
  '1': 'PingCommand',
};

/// Descriptor for `PingCommand`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pingCommandDescriptor =
    $convert.base64Decode('CgtQaW5nQ29tbWFuZA==');

@$core.Deprecated('Use syncRevocationsCommandDescriptor instead')
const SyncRevocationsCommand$json = {
  '1': 'SyncRevocationsCommand',
  '2': [
    {'1': 'sequence', '3': 1, '4': 1, '5': 4, '10': 'sequence'},
  ],
};

/// Descriptor for `SyncRevocationsCommand`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List syncRevocationsCommandDescriptor =
    $convert.base64Decode(
        'ChZTeW5jUmV2b2NhdGlvbnNDb21tYW5kEhoKCHNlcXVlbmNlGAEgASgEUghzZXF1ZW5jZQ==');
