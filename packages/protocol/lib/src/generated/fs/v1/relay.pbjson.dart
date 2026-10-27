// This is a generated file - do not edit.
//
// Generated from fs/v1/relay.proto.

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

@$core.Deprecated('Use relayRoleDescriptor instead')
const RelayRole$json = {
  '1': 'RelayRole',
  '2': [
    {'1': 'RELAY_ROLE_UNSPECIFIED', '2': 0},
    {'1': 'RELAY_ROLE_LISTEN', '2': 1},
    {'1': 'RELAY_ROLE_CONNECT', '2': 2},
  ],
};

/// Descriptor for `RelayRole`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List relayRoleDescriptor = $convert.base64Decode(
    'CglSZWxheVJvbGUSGgoWUkVMQVlfUk9MRV9VTlNQRUNJRklFRBAAEhUKEVJFTEFZX1JPTEVfTE'
    'lTVEVOEAESFgoSUkVMQVlfUk9MRV9DT05ORUNUEAI=');

@$core.Deprecated('Use relayPassDescriptor instead')
const RelayPass$json = {
  '1': 'RelayPass',
  '2': [
    {
      '1': 'role',
      '3': 1,
      '4': 1,
      '5': 14,
      '6': '.fs.v1.RelayRole',
      '10': 'role'
    },
    {'1': 'holder', '3': 2, '4': 1, '5': 12, '10': 'holder'},
    {'1': 'node_id', '3': 3, '4': 1, '5': 12, '10': 'nodeId'},
    {'1': 'account_id', '3': 4, '4': 1, '5': 12, '10': 'accountId'},
    {'1': 'relay', '3': 5, '4': 1, '5': 9, '10': 'relay'},
    {'1': 'pass_id', '3': 6, '4': 1, '5': 12, '10': 'passId'},
    {
      '1': 'expires_at_unix_ms',
      '3': 7,
      '4': 1,
      '5': 4,
      '10': 'expiresAtUnixMs'
    },
    {'1': 'max_bytes', '3': 8, '4': 1, '5': 4, '10': 'maxBytes'},
  ],
};

/// Descriptor for `RelayPass`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List relayPassDescriptor = $convert.base64Decode(
    'CglSZWxheVBhc3MSJAoEcm9sZRgBIAEoDjIQLmZzLnYxLlJlbGF5Um9sZVIEcm9sZRIWCgZob2'
    'xkZXIYAiABKAxSBmhvbGRlchIXCgdub2RlX2lkGAMgASgMUgZub2RlSWQSHQoKYWNjb3VudF9p'
    'ZBgEIAEoDFIJYWNjb3VudElkEhQKBXJlbGF5GAUgASgJUgVyZWxheRIXCgdwYXNzX2lkGAYgAS'
    'gMUgZwYXNzSWQSKwoSZXhwaXJlc19hdF91bml4X21zGAcgASgEUg9leHBpcmVzQXRVbml4TXMS'
    'GwoJbWF4X2J5dGVzGAggASgEUghtYXhCeXRlcw==');

@$core.Deprecated('Use relayChallengeDescriptor instead')
const RelayChallenge$json = {
  '1': 'RelayChallenge',
  '2': [
    {'1': 'version', '3': 1, '4': 1, '5': 13, '10': 'version'},
    {'1': 'nonce', '3': 2, '4': 1, '5': 12, '10': 'nonce'},
    {'1': 'relay', '3': 3, '4': 1, '5': 9, '10': 'relay'},
  ],
};

/// Descriptor for `RelayChallenge`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List relayChallengeDescriptor = $convert.base64Decode(
    'Cg5SZWxheUNoYWxsZW5nZRIYCgd2ZXJzaW9uGAEgASgNUgd2ZXJzaW9uEhQKBW5vbmNlGAIgAS'
    'gMUgVub25jZRIUCgVyZWxheRgDIAEoCVIFcmVsYXk=');

@$core.Deprecated('Use relayOpenDescriptor instead')
const RelayOpen$json = {
  '1': 'RelayOpen',
  '2': [
    {'1': 'pass', '3': 1, '4': 1, '5': 11, '6': '.fs.v1.Signed', '10': 'pass'},
    {'1': 'proof', '3': 2, '4': 1, '5': 12, '10': 'proof'},
    {'1': 'accept', '3': 3, '4': 1, '5': 12, '10': 'accept'},
  ],
};

/// Descriptor for `RelayOpen`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List relayOpenDescriptor = $convert.base64Decode(
    'CglSZWxheU9wZW4SIQoEcGFzcxgBIAEoCzINLmZzLnYxLlNpZ25lZFIEcGFzcxIUCgVwcm9vZh'
    'gCIAEoDFIFcHJvb2YSFgoGYWNjZXB0GAMgASgMUgZhY2NlcHQ=');

@$core.Deprecated('Use relayOpenedDescriptor instead')
const RelayOpened$json = {
  '1': 'RelayOpened',
  '2': [
    {'1': 'error', '3': 1, '4': 1, '5': 11, '6': '.fs.v1.Error', '10': 'error'},
  ],
};

/// Descriptor for `RelayOpened`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List relayOpenedDescriptor = $convert.base64Decode(
    'CgtSZWxheU9wZW5lZBIiCgVlcnJvchgBIAEoCzIMLmZzLnYxLkVycm9yUgVlcnJvcg==');

@$core.Deprecated('Use relayControlDescriptor instead')
const RelayControl$json = {
  '1': 'RelayControl',
  '2': [
    {
      '1': 'incoming',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.fs.v1.RelayIncoming',
      '9': 0,
      '10': 'incoming'
    },
    {'1': 'ping', '3': 2, '4': 1, '5': 4, '9': 0, '10': 'ping'},
    {'1': 'pong', '3': 3, '4': 1, '5': 4, '9': 0, '10': 'pong'},
  ],
  '8': [
    {'1': 'body'},
  ],
};

/// Descriptor for `RelayControl`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List relayControlDescriptor = $convert.base64Decode(
    'CgxSZWxheUNvbnRyb2wSMgoIaW5jb21pbmcYASABKAsyFC5mcy52MS5SZWxheUluY29taW5nSA'
    'BSCGluY29taW5nEhQKBHBpbmcYAiABKARIAFIEcGluZxIUCgRwb25nGAMgASgESABSBHBvbmdC'
    'BgoEYm9keQ==');

@$core.Deprecated('Use relayIncomingDescriptor instead')
const RelayIncoming$json = {
  '1': 'RelayIncoming',
  '2': [
    {'1': 'session_id', '3': 1, '4': 1, '5': 12, '10': 'sessionId'},
  ],
};

/// Descriptor for `RelayIncoming`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List relayIncomingDescriptor = $convert.base64Decode(
    'Cg1SZWxheUluY29taW5nEh0KCnNlc3Npb25faWQYASABKAxSCXNlc3Npb25JZA==');
