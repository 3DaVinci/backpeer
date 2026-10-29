// This is a generated file - do not edit.
//
// Generated from fs/v1/certs.proto.

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

@$core.Deprecated('Use ticketOperationDescriptor instead')
const TicketOperation$json = {
  '1': 'TicketOperation',
  '2': [
    {'1': 'TICKET_OPERATION_UNSPECIFIED', '2': 0},
    {'1': 'TICKET_OPERATION_PUT', '2': 1},
    {'1': 'TICKET_OPERATION_GET', '2': 2},
    {'1': 'TICKET_OPERATION_DELETE', '2': 3},
  ],
};

/// Descriptor for `TicketOperation`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List ticketOperationDescriptor = $convert.base64Decode(
    'Cg9UaWNrZXRPcGVyYXRpb24SIAocVElDS0VUX09QRVJBVElPTl9VTlNQRUNJRklFRBAAEhgKFF'
    'RJQ0tFVF9PUEVSQVRJT05fUFVUEAESGAoUVElDS0VUX09QRVJBVElPTl9HRVQQAhIbChdUSUNL'
    'RVRfT1BFUkFUSU9OX0RFTEVURRAD');

@$core.Deprecated('Use deviceCertificateDescriptor instead')
const DeviceCertificate$json = {
  '1': 'DeviceCertificate',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 12, '10': 'accountId'},
    {'1': 'device_sign', '3': 2, '4': 1, '5': 12, '10': 'deviceSign'},
    {'1': 'device_dh', '3': 3, '4': 1, '5': 12, '10': 'deviceDh'},
    {'1': 'issued_at_unix_ms', '3': 4, '4': 1, '5': 3, '10': 'issuedAtUnixMs'},
  ],
};

/// Descriptor for `DeviceCertificate`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List deviceCertificateDescriptor = $convert.base64Decode(
    'ChFEZXZpY2VDZXJ0aWZpY2F0ZRIdCgphY2NvdW50X2lkGAEgASgMUglhY2NvdW50SWQSHwoLZG'
    'V2aWNlX3NpZ24YAiABKAxSCmRldmljZVNpZ24SGwoJZGV2aWNlX2RoGAMgASgMUghkZXZpY2VE'
    'aBIpChFpc3N1ZWRfYXRfdW5peF9tcxgEIAEoA1IOaXNzdWVkQXRVbml4TXM=');

@$core.Deprecated('Use deviceRevocationDescriptor instead')
const DeviceRevocation$json = {
  '1': 'DeviceRevocation',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 12, '10': 'accountId'},
    {'1': 'device_sign', '3': 2, '4': 1, '5': 12, '10': 'deviceSign'},
    {
      '1': 'revoked_at_unix_ms',
      '3': 3,
      '4': 1,
      '5': 3,
      '10': 'revokedAtUnixMs'
    },
  ],
};

/// Descriptor for `DeviceRevocation`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List deviceRevocationDescriptor = $convert.base64Decode(
    'ChBEZXZpY2VSZXZvY2F0aW9uEh0KCmFjY291bnRfaWQYASABKAxSCWFjY291bnRJZBIfCgtkZX'
    'ZpY2Vfc2lnbhgCIAEoDFIKZGV2aWNlU2lnbhIrChJyZXZva2VkX2F0X3VuaXhfbXMYAyABKANS'
    'D3Jldm9rZWRBdFVuaXhNcw==');

@$core.Deprecated('Use nodeCertificateDescriptor instead')
const NodeCertificate$json = {
  '1': 'NodeCertificate',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 12, '10': 'accountId'},
    {'1': 'node_id', '3': 2, '4': 1, '5': 12, '10': 'nodeId'},
    {'1': 'node_dh', '3': 3, '4': 1, '5': 12, '10': 'nodeDh'},
    {'1': 'issued_at_unix_ms', '3': 4, '4': 1, '5': 3, '10': 'issuedAtUnixMs'},
  ],
};

/// Descriptor for `NodeCertificate`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List nodeCertificateDescriptor = $convert.base64Decode(
    'Cg9Ob2RlQ2VydGlmaWNhdGUSHQoKYWNjb3VudF9pZBgBIAEoDFIJYWNjb3VudElkEhcKB25vZG'
    'VfaWQYAiABKAxSBm5vZGVJZBIXCgdub2RlX2RoGAMgASgMUgZub2RlRGgSKQoRaXNzdWVkX2F0'
    'X3VuaXhfbXMYBCABKANSDmlzc3VlZEF0VW5peE1z');

@$core.Deprecated('Use fragmentTicketDescriptor instead')
const FragmentTicket$json = {
  '1': 'FragmentTicket',
  '2': [
    {
      '1': 'operation',
      '3': 1,
      '4': 1,
      '5': 14,
      '6': '.fs.v1.TicketOperation',
      '10': 'operation'
    },
    {'1': 'node_id', '3': 2, '4': 1, '5': 12, '10': 'nodeId'},
    {'1': 'device_sign', '3': 3, '4': 1, '5': 12, '10': 'deviceSign'},
    {'1': 'fragment_id', '3': 4, '4': 1, '5': 12, '10': 'fragmentId'},
    {'1': 'fragment_size', '3': 5, '4': 1, '5': 13, '10': 'fragmentSize'},
    {
      '1': 'expires_at_unix_ms',
      '3': 6,
      '4': 1,
      '5': 3,
      '10': 'expiresAtUnixMs'
    },
    {'1': 'ticket_id', '3': 7, '4': 1, '5': 12, '10': 'ticketId'},
    {'1': 'owner_account', '3': 8, '4': 1, '5': 12, '10': 'ownerAccount'},
  ],
};

/// Descriptor for `FragmentTicket`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List fragmentTicketDescriptor = $convert.base64Decode(
    'Cg5GcmFnbWVudFRpY2tldBI0CglvcGVyYXRpb24YASABKA4yFi5mcy52MS5UaWNrZXRPcGVyYX'
    'Rpb25SCW9wZXJhdGlvbhIXCgdub2RlX2lkGAIgASgMUgZub2RlSWQSHwoLZGV2aWNlX3NpZ24Y'
    'AyABKAxSCmRldmljZVNpZ24SHwoLZnJhZ21lbnRfaWQYBCABKAxSCmZyYWdtZW50SWQSIwoNZn'
    'JhZ21lbnRfc2l6ZRgFIAEoDVIMZnJhZ21lbnRTaXplEisKEmV4cGlyZXNfYXRfdW5peF9tcxgG'
    'IAEoA1IPZXhwaXJlc0F0VW5peE1zEhsKCXRpY2tldF9pZBgHIAEoDFIIdGlja2V0SWQSIwoNb3'
    'duZXJfYWNjb3VudBgIIAEoDFIMb3duZXJBY2NvdW50');
