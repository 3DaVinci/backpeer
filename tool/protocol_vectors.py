#!/usr/bin/env python3
"""Генератор тестовых векторов для docs/spec/protocol.md.

Эталонная реализация подписи запроса к координатору (заголовок FS-Auth,
раздел 4.2) и входа по паролю (раздел 4.7, crypto.md, раздел 4.4),
независимая от кода на Dart: стандартная библиотека Python (BLAKE2b,
unicodedata), пакет cryptography (Ed25519, HKDF) и libsodium через ctypes
(Argon2id).

Запуск из корня репозитория:

    python3 -I tool/protocol_vectors.py

Записывает файлы в test-vectors/protocol/. Входы фиксированы, поэтому
повторный запуск даёт те же файлы.
"""

import ctypes
import ctypes.util
import hashlib
import json
import os
import re
import struct
import unicodedata

from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives.kdf.hkdf import HKDF
from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat

OUT_DIR = os.path.join("test-vectors", "protocol")
GENERATOR = "tool/protocol_vectors.py (Python hashlib, cryptography, libsodium)"

CONTEXT = b"fs/v1/sign/api-request\x00"
HEADER_RE = re.compile(r"^([0-9a-f]{64})\.(0|[1-9][0-9]{0,14})\.([0-9a-f]{128})$")


_sodium = ctypes.CDLL(ctypes.util.find_library("sodium") or "libsodium.so.23")
assert _sodium.sodium_init() >= 0
LOGIN_CONTEXT = b"fs/v1/sign/login\x00"
LOGIN_RE = re.compile(r"^[a-z0-9][a-z0-9._-]{2,31}$")


def argon2id(password: bytes, salt: bytes, m_kib: int, t: int) -> bytes:
    out = ctypes.create_string_buffer(32)
    rc = _sodium.crypto_pwhash(
        out, ctypes.c_ulonglong(32),
        password, ctypes.c_ulonglong(len(password)),
        salt,
        ctypes.c_ulonglong(t), ctypes.c_size_t(m_kib * 1024),
        ctypes.c_int(2),  # crypto_pwhash_ALG_ARGON2ID13
    )
    assert rc == 0
    return out.raw


def hkdf(ikm: bytes, info: bytes) -> bytes:
    return HKDF(algorithm=hashes.SHA256(), length=32, salt=None, info=info).derive(ikm)


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


def normalize_login(login: str):
    """Имя для входа (protocol.md, раздел 4.7): нижний регистр ASCII, затем
    проверка; None — имя недопустимо."""
    if not login.isascii():
        return None
    lowered = login.lower()
    return lowered if LOGIN_RE.match(lowered) else None


def login_cases() -> list:
    cases = []
    for name, raw in [
        ("login-simple", "alice"),
        ("login-uppercase", "Alice.Smith"),
        ("login-symbols", "a_b-c.9"),
        ("login-min", "abc"),
        ("login-max", "a" * 32),
        ("login-too-short", "ab"),
        ("login-too-long", "a" * 33),
        ("login-leading-dot", ".alice"),
        ("login-space", "ali ce"),
        ("login-cyrillic", "алиса"),
        ("login-at", "alice@example.com"),
        ("login-empty", ""),
        ("login-kelvin", "\u212aelvin"),
    ]:
        cases.append({
            "name": name,
            "input": {"operation": "normalize", "login": raw},
            "expected": {"login": normalize_login(raw)},
        })

    salt = bytes(range(16))
    time_ms = 1792713600000  # 23.10.2026 00:00 UTC
    for name, password, login, m, t in [
        ("proof-fast-params", "correct horse battery staple", "alice", 1024, 1),
        ("proof-nfkc-fast-params", "Ｐａｓｓ ﬁ ½ пароль", "bob.smith", 1024, 1),
    ]:
        pk = argon2id(unicodedata.normalize("NFKC", password).encode("utf-8"), salt, m, t)
        auth = hkdf(pk, b"fs/v1/auth")
        key = Ed25519PrivateKey.from_private_bytes(auth)
        message = LOGIN_CONTEXT + struct.pack(">Q", time_ms) + login.encode("ascii")
        cases.append({
            "name": name,
            "input": {
                "operation": "proof",
                "password": password,
                "salt": salt,
                "memoryKiB": m,
                "iterations": t,
                "login": login,
                "timeMs": time_ms,
            },
            "expected": {
                "auth": auth,
                "verifier": key.public_key().public_bytes(Encoding.Raw, PublicFormat.Raw),
                "message": message,
                "proof": key.sign(message),
            },
        })
    return cases


def main() -> None:
    write(
        "login.json",
        "protocol/login",
        "Вход по паролю (protocol.md, раздел 4.7; crypto.md, раздел 4.4). "
        "operation = normalize: имя для входа в нижнем регистре или null, если "
        "имя недопустимо (3–32 символа a–z, 0–9, '.', '_', '-', первый — буква "
        "или цифра; не-ASCII отклоняется до приведения регистра). "
        "operation = proof: AUTH из пароля (NFKC, Argon2id, HKDF), открытый "
        "ключ входа (Ed25519 из seed = AUTH), подписываемое сообщение "
        "(контекст login с байтом 0x00, u64be времени, имя) и подпись. "
        "Случаи *-fast-params используют малые параметры только для скорости.",
        login_cases(),
    )
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
