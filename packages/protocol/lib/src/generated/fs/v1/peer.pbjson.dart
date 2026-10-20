// This is a generated file - do not edit.
//
// Generated from fs/v1/peer.proto.

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

@$core.Deprecated('Use peerRoleDescriptor instead')
const PeerRole$json = {
  '1': 'PeerRole',
  '2': [
    {'1': 'PEER_ROLE_UNSPECIFIED', '2': 0},
    {'1': 'PEER_ROLE_CLIENT', '2': 1},
    {'1': 'PEER_ROLE_NODE', '2': 2},
  ],
};

/// Descriptor for `PeerRole`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List peerRoleDescriptor = $convert.base64Decode(
    'CghQZWVyUm9sZRIZChVQRUVSX1JPTEVfVU5TUEVDSUZJRUQQABIUChBQRUVSX1JPTEVfQ0xJRU'
    '5UEAESEgoOUEVFUl9ST0xFX05PREUQAg==');

@$core.Deprecated('Use helloDescriptor instead')
const Hello$json = {
  '1': 'Hello',
  '2': [
    {'1': 'versions', '3': 1, '4': 3, '5': 13, '10': 'versions'},
    {
      '1': 'role',
      '3': 2,
      '4': 1,
      '5': 14,
      '6': '.fs.v1.PeerRole',
      '10': 'role'
    },
    {
      '1': 'certificate',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.fs.v1.Signed',
      '10': 'certificate'
    },
    {'1': 'software', '3': 4, '4': 1, '5': 9, '10': 'software'},
  ],
};

/// Descriptor for `Hello`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List helloDescriptor = $convert.base64Decode(
    'CgVIZWxsbxIaCgh2ZXJzaW9ucxgBIAMoDVIIdmVyc2lvbnMSIwoEcm9sZRgCIAEoDjIPLmZzLn'
    'YxLlBlZXJSb2xlUgRyb2xlEi8KC2NlcnRpZmljYXRlGAMgASgLMg0uZnMudjEuU2lnbmVkUgtj'
    'ZXJ0aWZpY2F0ZRIaCghzb2Z0d2FyZRgEIAEoCVIIc29mdHdhcmU=');

@$core.Deprecated('Use peerMessageDescriptor instead')
const PeerMessage$json = {
  '1': 'PeerMessage',
  '2': [
    {'1': 'request_id', '3': 1, '4': 1, '5': 4, '10': 'requestId'},
    {
      '1': 'error',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.fs.v1.Error',
      '9': 0,
      '10': 'error'
    },
    {
      '1': 'put_fragment',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.fs.v1.PutFragment',
      '9': 0,
      '10': 'putFragment'
    },
    {
      '1': 'fragment_data',
      '3': 4,
      '4': 1,
      '5': 11,
      '6': '.fs.v1.FragmentData',
      '9': 0,
      '10': 'fragmentData'
    },
    {
      '1': 'put_fragment_result',
      '3': 5,
      '4': 1,
      '5': 11,
      '6': '.fs.v1.PutFragmentResult',
      '9': 0,
      '10': 'putFragmentResult'
    },
    {
      '1': 'get_fragment',
      '3': 6,
      '4': 1,
      '5': 11,
      '6': '.fs.v1.GetFragment',
      '9': 0,
      '10': 'getFragment'
    },
    {
      '1': 'get_fragment_result',
      '3': 7,
      '4': 1,
      '5': 11,
      '6': '.fs.v1.GetFragmentResult',
      '9': 0,
      '10': 'getFragmentResult'
    },
    {
      '1': 'has_fragments',
      '3': 8,
      '4': 1,
      '5': 11,
      '6': '.fs.v1.HasFragments',
      '9': 0,
      '10': 'hasFragments'
    },
    {
      '1': 'has_fragments_result',
      '3': 9,
      '4': 1,
      '5': 11,
      '6': '.fs.v1.HasFragmentsResult',
      '9': 0,
      '10': 'hasFragmentsResult'
    },
    {
      '1': 'delete_fragment',
      '3': 10,
      '4': 1,
      '5': 11,
      '6': '.fs.v1.DeleteFragment',
      '9': 0,
      '10': 'deleteFragment'
    },
    {
      '1': 'delete_fragment_result',
      '3': 11,
      '4': 1,
      '5': 11,
      '6': '.fs.v1.DeleteFragmentResult',
      '9': 0,
      '10': 'deleteFragmentResult'
    },
    {
      '1': 'ping',
      '3': 12,
      '4': 1,
      '5': 11,
      '6': '.fs.v1.Ping',
      '9': 0,
      '10': 'ping'
    },
    {
      '1': 'pong',
      '3': 13,
      '4': 1,
      '5': 11,
      '6': '.fs.v1.Pong',
      '9': 0,
      '10': 'pong'
    },
  ],
  '8': [
    {'1': 'body'},
  ],
};

/// Descriptor for `PeerMessage`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List peerMessageDescriptor = $convert.base64Decode(
    'CgtQZWVyTWVzc2FnZRIdCgpyZXF1ZXN0X2lkGAEgASgEUglyZXF1ZXN0SWQSJAoFZXJyb3IYAi'
    'ABKAsyDC5mcy52MS5FcnJvckgAUgVlcnJvchI3CgxwdXRfZnJhZ21lbnQYAyABKAsyEi5mcy52'
    'MS5QdXRGcmFnbWVudEgAUgtwdXRGcmFnbWVudBI6Cg1mcmFnbWVudF9kYXRhGAQgASgLMhMuZn'
    'MudjEuRnJhZ21lbnREYXRhSABSDGZyYWdtZW50RGF0YRJKChNwdXRfZnJhZ21lbnRfcmVzdWx0'
    'GAUgASgLMhguZnMudjEuUHV0RnJhZ21lbnRSZXN1bHRIAFIRcHV0RnJhZ21lbnRSZXN1bHQSNw'
    'oMZ2V0X2ZyYWdtZW50GAYgASgLMhIuZnMudjEuR2V0RnJhZ21lbnRIAFILZ2V0RnJhZ21lbnQS'
    'SgoTZ2V0X2ZyYWdtZW50X3Jlc3VsdBgHIAEoCzIYLmZzLnYxLkdldEZyYWdtZW50UmVzdWx0SA'
    'BSEWdldEZyYWdtZW50UmVzdWx0EjoKDWhhc19mcmFnbWVudHMYCCABKAsyEy5mcy52MS5IYXNG'
    'cmFnbWVudHNIAFIMaGFzRnJhZ21lbnRzEk0KFGhhc19mcmFnbWVudHNfcmVzdWx0GAkgASgLMh'
    'kuZnMudjEuSGFzRnJhZ21lbnRzUmVzdWx0SABSEmhhc0ZyYWdtZW50c1Jlc3VsdBJACg9kZWxl'
    'dGVfZnJhZ21lbnQYCiABKAsyFS5mcy52MS5EZWxldGVGcmFnbWVudEgAUg5kZWxldGVGcmFnbW'
    'VudBJTChZkZWxldGVfZnJhZ21lbnRfcmVzdWx0GAsgASgLMhsuZnMudjEuRGVsZXRlRnJhZ21l'
    'bnRSZXN1bHRIAFIUZGVsZXRlRnJhZ21lbnRSZXN1bHQSIQoEcGluZxgMIAEoCzILLmZzLnYxLl'
    'BpbmdIAFIEcGluZxIhCgRwb25nGA0gASgLMgsuZnMudjEuUG9uZ0gAUgRwb25nQgYKBGJvZHk=');

@$core.Deprecated('Use putFragmentDescriptor instead')
const PutFragment$json = {
  '1': 'PutFragment',
  '2': [
    {
      '1': 'ticket',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.fs.v1.Signed',
      '10': 'ticket'
    },
  ],
};

/// Descriptor for `PutFragment`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List putFragmentDescriptor = $convert.base64Decode(
    'CgtQdXRGcmFnbWVudBIlCgZ0aWNrZXQYASABKAsyDS5mcy52MS5TaWduZWRSBnRpY2tldA==');

@$core.Deprecated('Use fragmentDataDescriptor instead')
const FragmentData$json = {
  '1': 'FragmentData',
  '2': [
    {'1': 'data', '3': 1, '4': 1, '5': 12, '10': 'data'},
    {'1': 'last', '3': 2, '4': 1, '5': 8, '10': 'last'},
  ],
};

/// Descriptor for `FragmentData`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List fragmentDataDescriptor = $convert.base64Decode(
    'CgxGcmFnbWVudERhdGESEgoEZGF0YRgBIAEoDFIEZGF0YRISCgRsYXN0GAIgASgIUgRsYXN0');

@$core.Deprecated('Use putFragmentResultDescriptor instead')
const PutFragmentResult$json = {
  '1': 'PutFragmentResult',
  '2': [
    {'1': 'fragment_id', '3': 1, '4': 1, '5': 12, '10': 'fragmentId'},
  ],
};

/// Descriptor for `PutFragmentResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List putFragmentResultDescriptor = $convert.base64Decode(
    'ChFQdXRGcmFnbWVudFJlc3VsdBIfCgtmcmFnbWVudF9pZBgBIAEoDFIKZnJhZ21lbnRJZA==');

@$core.Deprecated('Use getFragmentDescriptor instead')
const GetFragment$json = {
  '1': 'GetFragment',
  '2': [
    {
      '1': 'ticket',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.fs.v1.Signed',
      '10': 'ticket'
    },
  ],
};

/// Descriptor for `GetFragment`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getFragmentDescriptor = $convert.base64Decode(
    'CgtHZXRGcmFnbWVudBIlCgZ0aWNrZXQYASABKAsyDS5mcy52MS5TaWduZWRSBnRpY2tldA==');

@$core.Deprecated('Use getFragmentResultDescriptor instead')
const GetFragmentResult$json = {
  '1': 'GetFragmentResult',
  '2': [
    {'1': 'fragment_size', '3': 1, '4': 1, '5': 13, '10': 'fragmentSize'},
  ],
};

/// Descriptor for `GetFragmentResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getFragmentResultDescriptor = $convert.base64Decode(
    'ChFHZXRGcmFnbWVudFJlc3VsdBIjCg1mcmFnbWVudF9zaXplGAEgASgNUgxmcmFnbWVudFNpem'
    'U=');

@$core.Deprecated('Use hasFragmentsDescriptor instead')
const HasFragments$json = {
  '1': 'HasFragments',
  '2': [
    {'1': 'fragment_ids', '3': 1, '4': 3, '5': 12, '10': 'fragmentIds'},
  ],
};

/// Descriptor for `HasFragments`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List hasFragmentsDescriptor = $convert.base64Decode(
    'CgxIYXNGcmFnbWVudHMSIQoMZnJhZ21lbnRfaWRzGAEgAygMUgtmcmFnbWVudElkcw==');

@$core.Deprecated('Use hasFragmentsResultDescriptor instead')
const HasFragmentsResult$json = {
  '1': 'HasFragmentsResult',
  '2': [
    {'1': 'present', '3': 1, '4': 3, '5': 8, '10': 'present'},
  ],
};

/// Descriptor for `HasFragmentsResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List hasFragmentsResultDescriptor =
    $convert.base64Decode(
        'ChJIYXNGcmFnbWVudHNSZXN1bHQSGAoHcHJlc2VudBgBIAMoCFIHcHJlc2VudA==');

@$core.Deprecated('Use deleteFragmentDescriptor instead')
const DeleteFragment$json = {
  '1': 'DeleteFragment',
  '2': [
    {
      '1': 'ticket',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.fs.v1.Signed',
      '10': 'ticket'
    },
  ],
};

/// Descriptor for `DeleteFragment`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List deleteFragmentDescriptor = $convert.base64Decode(
    'Cg5EZWxldGVGcmFnbWVudBIlCgZ0aWNrZXQYASABKAsyDS5mcy52MS5TaWduZWRSBnRpY2tldA'
    '==');

@$core.Deprecated('Use deleteFragmentResultDescriptor instead')
const DeleteFragmentResult$json = {
  '1': 'DeleteFragmentResult',
};

/// Descriptor for `DeleteFragmentResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List deleteFragmentResultDescriptor =
    $convert.base64Decode('ChREZWxldGVGcmFnbWVudFJlc3VsdA==');

@$core.Deprecated('Use pingDescriptor instead')
const Ping$json = {
  '1': 'Ping',
  '2': [
    {'1': 'nonce', '3': 1, '4': 1, '5': 4, '10': 'nonce'},
  ],
};

/// Descriptor for `Ping`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pingDescriptor =
    $convert.base64Decode('CgRQaW5nEhQKBW5vbmNlGAEgASgEUgVub25jZQ==');

@$core.Deprecated('Use pongDescriptor instead')
const Pong$json = {
  '1': 'Pong',
  '2': [
    {'1': 'nonce', '3': 1, '4': 1, '5': 4, '10': 'nonce'},
  ],
};

/// Descriptor for `Pong`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pongDescriptor =
    $convert.base64Decode('CgRQb25nEhQKBW5vbmNlGAEgASgEUgVub25jZQ==');
