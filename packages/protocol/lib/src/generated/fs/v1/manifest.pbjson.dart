// This is a generated file - do not edit.
//
// Generated from fs/v1/manifest.proto.

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

@$core.Deprecated('Use nodeTypeDescriptor instead')
const NodeType$json = {
  '1': 'NodeType',
  '2': [
    {'1': 'NODE_TYPE_UNSPECIFIED', '2': 0},
    {'1': 'NODE_TYPE_FILE', '2': 1},
    {'1': 'NODE_TYPE_DIRECTORY', '2': 2},
    {'1': 'NODE_TYPE_SYMLINK', '2': 3},
  ],
};

/// Descriptor for `NodeType`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List nodeTypeDescriptor = $convert.base64Decode(
    'CghOb2RlVHlwZRIZChVOT0RFX1RZUEVfVU5TUEVDSUZJRUQQABISCg5OT0RFX1RZUEVfRklMRR'
    'ABEhcKE05PREVfVFlQRV9ESVJFQ1RPUlkQAhIVChFOT0RFX1RZUEVfU1lNTElOSxAD');

@$core.Deprecated('Use chunkTypeDescriptor instead')
const ChunkType$json = {
  '1': 'ChunkType',
  '2': [
    {'1': 'CHUNK_TYPE_UNSPECIFIED', '2': 0},
    {'1': 'CHUNK_TYPE_CONTENT', '2': 1},
    {'1': 'CHUNK_TYPE_TREE', '2': 2},
  ],
};

/// Descriptor for `ChunkType`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List chunkTypeDescriptor = $convert.base64Decode(
    'CglDaHVua1R5cGUSGgoWQ0hVTktfVFlQRV9VTlNQRUNJRklFRBAAEhYKEkNIVU5LX1RZUEVfQ0'
    '9OVEVOVBABEhMKD0NIVU5LX1RZUEVfVFJFRRAC');

@$core.Deprecated('Use snapshotDescriptor instead')
const Snapshot$json = {
  '1': 'Snapshot',
  '2': [
    {'1': 'format_version', '3': 1, '4': 1, '5': 13, '10': 'formatVersion'},
    {'1': 'snapshot_id', '3': 2, '4': 1, '5': 12, '10': 'snapshotId'},
    {'1': 'sequence', '3': 3, '4': 1, '5': 4, '10': 'sequence'},
    {
      '1': 'parent_snapshot_id',
      '3': 4,
      '4': 1,
      '5': 12,
      '10': 'parentSnapshotId'
    },
    {
      '1': 'created_at_unix_ms',
      '3': 5,
      '4': 1,
      '5': 3,
      '10': 'createdAtUnixMs'
    },
    {'1': 'hostname', '3': 6, '4': 1, '5': 9, '10': 'hostname'},
    {'1': 'device_id', '3': 7, '4': 1, '5': 12, '10': 'deviceId'},
    {'1': 'paths', '3': 8, '4': 3, '5': 9, '10': 'paths'},
    {'1': 'root_tree', '3': 9, '4': 3, '5': 12, '10': 'rootTree'},
    {'1': 'tags', '3': 10, '4': 3, '5': 9, '10': 'tags'},
    {
      '1': 'stats',
      '3': 11,
      '4': 1,
      '5': 11,
      '6': '.fs.v1.SnapshotStats',
      '10': 'stats'
    },
  ],
};

/// Descriptor for `Snapshot`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List snapshotDescriptor = $convert.base64Decode(
    'CghTbmFwc2hvdBIlCg5mb3JtYXRfdmVyc2lvbhgBIAEoDVINZm9ybWF0VmVyc2lvbhIfCgtzbm'
    'Fwc2hvdF9pZBgCIAEoDFIKc25hcHNob3RJZBIaCghzZXF1ZW5jZRgDIAEoBFIIc2VxdWVuY2US'
    'LAoScGFyZW50X3NuYXBzaG90X2lkGAQgASgMUhBwYXJlbnRTbmFwc2hvdElkEisKEmNyZWF0ZW'
    'RfYXRfdW5peF9tcxgFIAEoA1IPY3JlYXRlZEF0VW5peE1zEhoKCGhvc3RuYW1lGAYgASgJUgho'
    'b3N0bmFtZRIbCglkZXZpY2VfaWQYByABKAxSCGRldmljZUlkEhQKBXBhdGhzGAggAygJUgVwYX'
    'RocxIbCglyb290X3RyZWUYCSADKAxSCHJvb3RUcmVlEhIKBHRhZ3MYCiADKAlSBHRhZ3MSKgoF'
    'c3RhdHMYCyABKAsyFC5mcy52MS5TbmFwc2hvdFN0YXRzUgVzdGF0cw==');

@$core.Deprecated('Use snapshotStatsDescriptor instead')
const SnapshotStats$json = {
  '1': 'SnapshotStats',
  '2': [
    {'1': 'files', '3': 1, '4': 1, '5': 4, '10': 'files'},
    {'1': 'directories', '3': 2, '4': 1, '5': 4, '10': 'directories'},
    {'1': 'bytes', '3': 3, '4': 1, '5': 4, '10': 'bytes'},
    {'1': 'new_chunks', '3': 4, '4': 1, '5': 4, '10': 'newChunks'},
    {'1': 'new_bytes', '3': 5, '4': 1, '5': 4, '10': 'newBytes'},
    {'1': 'skipped', '3': 6, '4': 1, '5': 4, '10': 'skipped'},
  ],
};

/// Descriptor for `SnapshotStats`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List snapshotStatsDescriptor = $convert.base64Decode(
    'Cg1TbmFwc2hvdFN0YXRzEhQKBWZpbGVzGAEgASgEUgVmaWxlcxIgCgtkaXJlY3RvcmllcxgCIA'
    'EoBFILZGlyZWN0b3JpZXMSFAoFYnl0ZXMYAyABKARSBWJ5dGVzEh0KCm5ld19jaHVua3MYBCAB'
    'KARSCW5ld0NodW5rcxIbCgluZXdfYnl0ZXMYBSABKARSCG5ld0J5dGVzEhgKB3NraXBwZWQYBi'
    'ABKARSB3NraXBwZWQ=');

@$core.Deprecated('Use treeDescriptor instead')
const Tree$json = {
  '1': 'Tree',
  '2': [
    {'1': 'nodes', '3': 1, '4': 3, '5': 11, '6': '.fs.v1.Node', '10': 'nodes'},
  ],
};

/// Descriptor for `Tree`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List treeDescriptor = $convert
    .base64Decode('CgRUcmVlEiEKBW5vZGVzGAEgAygLMgsuZnMudjEuTm9kZVIFbm9kZXM=');

@$core.Deprecated('Use nodeDescriptor instead')
const Node$json = {
  '1': 'Node',
  '2': [
    {'1': 'name', '3': 1, '4': 1, '5': 12, '10': 'name'},
    {
      '1': 'type',
      '3': 2,
      '4': 1,
      '5': 14,
      '6': '.fs.v1.NodeType',
      '10': 'type'
    },
    {'1': 'size', '3': 3, '4': 1, '5': 4, '10': 'size'},
    {'1': 'mtime_ns', '3': 4, '4': 1, '5': 3, '10': 'mtimeNs'},
    {'1': 'mode', '3': 5, '4': 1, '5': 13, '10': 'mode'},
    {'1': 'uid', '3': 6, '4': 1, '5': 13, '10': 'uid'},
    {'1': 'gid', '3': 7, '4': 1, '5': 13, '10': 'gid'},
    {
      '1': 'windows_attributes',
      '3': 8,
      '4': 1,
      '5': 13,
      '10': 'windowsAttributes'
    },
    {'1': 'symlink_target', '3': 9, '4': 1, '5': 12, '10': 'symlinkTarget'},
    {'1': 'content', '3': 10, '4': 3, '5': 12, '10': 'content'},
    {'1': 'subtree', '3': 11, '4': 3, '5': 12, '10': 'subtree'},
  ],
};

/// Descriptor for `Node`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List nodeDescriptor = $convert.base64Decode(
    'CgROb2RlEhIKBG5hbWUYASABKAxSBG5hbWUSIwoEdHlwZRgCIAEoDjIPLmZzLnYxLk5vZGVUeX'
    'BlUgR0eXBlEhIKBHNpemUYAyABKARSBHNpemUSGQoIbXRpbWVfbnMYBCABKANSB210aW1lTnMS'
    'EgoEbW9kZRgFIAEoDVIEbW9kZRIQCgN1aWQYBiABKA1SA3VpZBIQCgNnaWQYByABKA1SA2dpZB'
    'ItChJ3aW5kb3dzX2F0dHJpYnV0ZXMYCCABKA1SEXdpbmRvd3NBdHRyaWJ1dGVzEiUKDnN5bWxp'
    'bmtfdGFyZ2V0GAkgASgMUg1zeW1saW5rVGFyZ2V0EhgKB2NvbnRlbnQYCiADKAxSB2NvbnRlbn'
    'QSGAoHc3VidHJlZRgLIAMoDFIHc3VidHJlZQ==');

@$core.Deprecated('Use indexDescriptor instead')
const Index$json = {
  '1': 'Index',
  '2': [
    {'1': 'format_version', '3': 1, '4': 1, '5': 13, '10': 'formatVersion'},
    {'1': 'index_id', '3': 2, '4': 1, '5': 12, '10': 'indexId'},
    {
      '1': 'segments',
      '3': 3,
      '4': 3,
      '5': 11,
      '6': '.fs.v1.SegmentRecord',
      '10': 'segments'
    },
    {'1': 'supersedes', '3': 4, '4': 3, '5': 12, '10': 'supersedes'},
  ],
};

/// Descriptor for `Index`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List indexDescriptor = $convert.base64Decode(
    'CgVJbmRleBIlCg5mb3JtYXRfdmVyc2lvbhgBIAEoDVINZm9ybWF0VmVyc2lvbhIZCghpbmRleF'
    '9pZBgCIAEoDFIHaW5kZXhJZBIwCghzZWdtZW50cxgDIAMoCzIULmZzLnYxLlNlZ21lbnRSZWNv'
    'cmRSCHNlZ21lbnRzEh4KCnN1cGVyc2VkZXMYBCADKAxSCnN1cGVyc2VkZXM=');

@$core.Deprecated('Use segmentRecordDescriptor instead')
const SegmentRecord$json = {
  '1': 'SegmentRecord',
  '2': [
    {'1': 'segment_id', '3': 1, '4': 1, '5': 12, '10': 'segmentId'},
    {'1': 'k', '3': 2, '4': 1, '5': 13, '10': 'k'},
    {'1': 'n', '3': 3, '4': 1, '5': 13, '10': 'n'},
    {'1': 'blob_length', '3': 4, '4': 1, '5': 13, '10': 'blobLength'},
    {'1': 'shard_size', '3': 5, '4': 1, '5': 13, '10': 'shardSize'},
    {'1': 'fragment_ids', '3': 6, '4': 3, '5': 12, '10': 'fragmentIds'},
    {
      '1': 'chunks',
      '3': 7,
      '4': 3,
      '5': 11,
      '6': '.fs.v1.ChunkEntry',
      '10': 'chunks'
    },
  ],
};

/// Descriptor for `SegmentRecord`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List segmentRecordDescriptor = $convert.base64Decode(
    'Cg1TZWdtZW50UmVjb3JkEh0KCnNlZ21lbnRfaWQYASABKAxSCXNlZ21lbnRJZBIMCgFrGAIgAS'
    'gNUgFrEgwKAW4YAyABKA1SAW4SHwoLYmxvYl9sZW5ndGgYBCABKA1SCmJsb2JMZW5ndGgSHQoK'
    'c2hhcmRfc2l6ZRgFIAEoDVIJc2hhcmRTaXplEiEKDGZyYWdtZW50X2lkcxgGIAMoDFILZnJhZ2'
    '1lbnRJZHMSKQoGY2h1bmtzGAcgAygLMhEuZnMudjEuQ2h1bmtFbnRyeVIGY2h1bmtz');

@$core.Deprecated('Use chunkEntryDescriptor instead')
const ChunkEntry$json = {
  '1': 'ChunkEntry',
  '2': [
    {'1': 'chunk_id', '3': 1, '4': 1, '5': 12, '10': 'chunkId'},
    {
      '1': 'type',
      '3': 2,
      '4': 1,
      '5': 14,
      '6': '.fs.v1.ChunkType',
      '10': 'type'
    },
    {'1': 'offset', '3': 3, '4': 1, '5': 13, '10': 'offset'},
    {'1': 'length', '3': 4, '4': 1, '5': 13, '10': 'length'},
  ],
};

/// Descriptor for `ChunkEntry`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List chunkEntryDescriptor = $convert.base64Decode(
    'CgpDaHVua0VudHJ5EhkKCGNodW5rX2lkGAEgASgMUgdjaHVua0lkEiQKBHR5cGUYAiABKA4yEC'
    '5mcy52MS5DaHVua1R5cGVSBHR5cGUSFgoGb2Zmc2V0GAMgASgNUgZvZmZzZXQSFgoGbGVuZ3Ro'
    'GAQgASgNUgZsZW5ndGg=');
