#!/usr/bin/env python3
"""Генератор тестовых векторов для docs/spec/protocol.md.

Эталонная реализация подписи запроса к координатору (заголовок FS-Auth,
раздел 4.2), независимая от кода на Dart: стандартная библиотека Python
(BLAKE2b) и пакет cryptography (Ed25519).

Запуск из корня репозитория:

    python3 -I tool/protocol_vectors.py

Записывает файлы в test-vectors/protocol/. Входы фиксированы, поэтому
повторный запуск даёт те же файлы.
"""

import hashlib
import json
import os
import re
import struct

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat

OUT_DIR = os.path.join("test-vectors", "protocol")
GENERATOR = "tool/protocol_vectors.py (Python hashlib, cryptography)"

CONTEXT = b"fs/v1/sign/api-request\x00"
HEADER_RE = re.compile(r"^([0-9a-f]{64})\.(0|[1-9][0-9]{0,14})\.([0-9a-f]{128})$")


def h(data: bytes) -> bytes:
    return hashlib.blake2b(data, digest_size=32).digest()


def public_key(seed: bytes) -> bytes:
    return Ed25519PrivateKey.from_private_bytes(seed).public_key().public_bytes(
        Encoding.Raw, PublicFormat.Raw
    )


def signing_input(path: str, time_ms: int, body: bytes) -> bytes:
    return CONTEXT + path.encode("utf-8") + struct.pack(">Q", time_ms) + h(body)


def sign(seed: bytes, path: str, time_ms: int, body: bytes) -> dict:
    message = signing_input(path, time_ms, body)
    signature = Ed25519PrivateKey.from_private_bytes(seed).sign(message)
    key = public_key(seed)
    return {
        "publicKey": key,
        "bodyHash": h(body),
        "message": message,
        "signature": signature,
        "header": f"{key.hex()}.{time_ms}.{signature.hex()}",
    }


def verify(header: str, path: str, body: bytes) -> dict:
    """Ожидаемый результат проверки: разбор заголовка и подпись (без окна
    времени и списка ключей — это состояние координатора)."""
    m = HEADER_RE.match(header)
    if m is None:
        return {"error": "format"}
    key = bytes.fromhex(m.group(1))
    time_ms = int(m.group(2))
    signature = bytes.fromhex(m.group(3))
    try:
        from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey

        Ed25519PublicKey.from_public_bytes(key).verify(
            signature, signing_input(path, time_ms, body)
        )
        valid = True
    except Exception:  # InvalidSignature или ключ не точка кривой
        valid = False
    return {"publicKey": key, "timeMs": time_ms, "valid": valid}


def hexify(value):
    if isinstance(value, bytes):
        return value.hex()
    if isinstance(value, dict):
        return {k: hexify(v) for k, v in value.items()}
    if isinstance(value, list):
        return [hexify(v) for v in value]
    return value


def write(name: str, spec: str, description: str, cases: list) -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    doc = {
        "spec": spec,
        "specVersion": 1,
        "generator": GENERATOR,
        "description": description,
        "cases": hexify(cases),
    }
    with open(os.path.join(OUT_DIR, name), "w", encoding="utf-8") as f:
        json.dump(doc, f, ensure_ascii=False, indent=2)
        f.write("\n")


def api_request_cases() -> list:
    seed_a = bytes(range(32))
    seed_b = bytes(range(32, 64))
    body = bytes.fromhex("0801120a") + b"0123456789"
    time_ms = 1792627200000  # 22.10.2026 00:00 UTC

    cases = []
    signs = [
        ("sign-put-object", seed_a, "/api/v1/PutObject", time_ms, body),
        ("sign-empty-body", seed_a, "/api/v1/Heartbeat", time_ms + 1, b""),
        ("sign-other-key", seed_b, "/api/v1/RegisterAccount", 1, bytes(range(256))),
        ("sign-max-time", seed_b, "/api/v1/ListObjects", 10**15 - 1, b"\x00"),
    ]
    signed = {}
    for name, seed, path, t, b in signs:
        expected = sign(seed, path, t, b)
        signed[name] = (path, t, b, expected)
        cases.append({
            "name": name,
            "input": {"operation": "sign", "seed": seed, "path": path, "timeMs": t, "body": b},
            "expected": expected,
        })

    path, t, b, good = signed["sign-put-object"]
    header = good["header"]
    key_hex, _, sig_hex = header.split(".")
    other_sig = signed["sign-other-key"][3]["signature"].hex()
    upper = key_hex.upper()
    verifies = [
        ("verify-ok", header, path, b),
        ("verify-wrong-path", header, "/api/v1/GetObject", b),
        ("verify-wrong-body", header, path, b + b"\x00"),
        ("verify-wrong-time", f"{key_hex}.{t + 1}.{sig_hex}", path, b),
        ("verify-foreign-signature", f"{key_hex}.{t}.{other_sig}", path, b),
        ("format-uppercase-hex", f"{upper}.{t}.{sig_hex}", path, b),
        ("format-leading-zero-time", f"{key_hex}.0{t}.{sig_hex}", path, b),
        ("format-time-16-digits", f"{key_hex}.{10**15}.{sig_hex}", path, b),
        ("format-negative-time", f"{key_hex}.-{t}.{sig_hex}", path, b),
        ("format-short-key", f"{key_hex[:-2]}.{t}.{sig_hex}", path, b),
        ("format-short-signature", f"{key_hex}.{t}.{sig_hex[:-2]}", path, b),
        ("format-missing-part", f"{key_hex}.{t}", path, b),
        ("format-extra-part", f"{header}.00", path, b),
        ("format-spaces", f" {header}", path, b),
        ("format-empty", "", path, b),
    ]
    for name, hdr, p, body_ in verifies:
        cases.append({
            "name": name,
            "input": {"operation": "verify", "header": hdr, "path": p, "body": body_},
            "expected": verify(hdr, p, body_),
        })
    return cases


def main() -> None:
    write(
        "api-request.json",
        "protocol/api-request",
        "Подпись запроса к координатору, заголовок FS-Auth (protocol.md, "
        "раздел 4.2). operation = sign: из seed Ed25519, пути, времени (мс) и "
        "тела получаются открытый ключ, H(тело) (BLAKE2b-256), подписываемое "
        "сообщение (контекст api-request с байтом 0x00), подпись и заголовок. "
        "operation = verify: разбор заголовка и проверка подписи над путём и "
        "телом; error = format — заголовок не разбирается, valid = false — "
        "подпись не сходится. Окно времени и известность ключа не проверяются: "
        "это состояние координатора.",
        api_request_cases(),
    )


if __name__ == "__main__":
    main()
