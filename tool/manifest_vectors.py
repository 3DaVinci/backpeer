#!/usr/bin/env python3
"""Генератор тестовых векторов для docs/spec/manifest.md.

Байты кодирует protoc (`protoc --encode`, эталонная реализация Protobuf на
C++), независимо от кода на Dart. Нужен protoc в PATH или в PROTOC.

Запуск из корня репозитория:

    python3 -I tool/manifest_vectors.py
"""

import json
import os
import subprocess

PROTOC = os.environ.get("PROTOC", "protoc")
OUT_DIR = os.path.join("test-vectors", "manifest")
GENERATOR = "tool/manifest_vectors.py (protoc --encode)"


def encode(message_type: str, text: str) -> bytes:
    result = subprocess.run(
        [PROTOC, "-I", "packages/protocol/proto", f"--encode={message_type}",
         "fs/v1/manifest.proto"],
        input=text.encode(), capture_output=True, check=True)
    return result.stdout


def b(hex_string: str) -> str:
    """Байтовое поле в текстовом формате Protobuf."""
    return '"' + "".join(f"\\x{hex_string[i:i + 2]}" for i in range(0, len(hex_string), 2)) + '"'


ID = lambda x: f"{x:02x}" * 32  # noqa: E731

CASES = [
    ("tree-empty", "fs.v1.Tree", ""),
    ("tree-file-dir-symlink", "fs.v1.Tree", f"""
nodes {{ name: "a.txt" type: NODE_TYPE_FILE size: 1000 mtime_ns: 1700000000123456789
         mode: 420 uid: 1000 gid: 1000 content: {b(ID(1))} content: {b(ID(2))} }}
nodes {{ name: "dir" type: NODE_TYPE_DIRECTORY mtime_ns: -5 mode: 493 subtree: {b(ID(3))} }}
nodes {{ name: "link" type: NODE_TYPE_SYMLINK symlink_target: "a.txt" }}
"""),
    ("snapshot", "fs.v1.Snapshot", f"""
format_version: 1 snapshot_id: {b(ID(0x11))} sequence: 7 parent_snapshot_id: {b(ID(0x10))}
created_at_unix_ms: 1792000000000 hostname: "laptop" device_id: {b(ID(0x22))}
paths: "/home/user/docs" paths: "C:\\\\Users\\\\user" root_tree: {b(ID(0x33))} tags: "daily"
stats {{ files: 10 directories: 2 bytes: 123456 new_chunks: 3 new_bytes: 4000 }}
"""),
    ("index", "fs.v1.Index", f"""
format_version: 1 index_id: {b(ID(0x44))}
segments {{ segment_id: {b(ID(0x55))} k: 4 n: 6 blob_length: 65616 shard_size: 16448
  fragment_ids: {b(ID(0x60))} fragment_ids: {b(ID(0x61))} fragment_ids: {b(ID(0x62))}
  fragment_ids: {b(ID(0x63))} fragment_ids: {b(ID(0x64))} fragment_ids: {b(ID(0x65))}
  chunks {{ chunk_id: {b(ID(0x70))} type: CHUNK_TYPE_CONTENT offset: 0 length: 1000 }}
  chunks {{ chunk_id: {b(ID(0x71))} type: CHUNK_TYPE_TREE offset: 1000 length: 200 }} }}
"""),
]


def main() -> None:
    cases = []
    for name, message_type, text in CASES:
        cases.append({
            "name": name,
            "input": {"messageType": message_type, "textFormat": text.strip()},
            "expected": {"bytes": encode(message_type, text).hex()},
        })
    os.makedirs(OUT_DIR, exist_ok=True)
    doc = {
        "spec": "manifest/encoding", "specVersion": 1, "generator": GENERATOR,
        "description": "Каноническая сериализация Protobuf объектов манифеста (manifest.md, раздел 5): "
                       "сообщение в текстовом формате Protobuf → ожидаемые байты.",
        "cases": cases,
    }
    with open(os.path.join(OUT_DIR, "encoding.json"), "w", encoding="utf-8") as f:
        json.dump(doc, f, ensure_ascii=False, indent=2)
        f.write("\n")


if __name__ == "__main__":
    main()
