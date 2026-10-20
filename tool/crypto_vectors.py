#!/usr/bin/env python3
"""Генератор тестовых векторов для docs/spec/crypto.md.

Эталонная реализация спецификации, независимая от кода на Dart:
стандартная библиотека Python (BLAKE2b, PBKDF2), пакет cryptography (HKDF,
Ed25519) и libsodium через ctypes (XChaCha20-Poly1305, Argon2id).

Запуск из корня репозитория:

    python3 -I tool/crypto_vectors.py

Записывает файлы в test-vectors/crypto/. Входы фиксированы, поэтому
повторный запуск даёт те же файлы.
"""

import ctypes
import ctypes.util
import hashlib
import json
import os
import struct
import unicodedata

from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives.kdf.hkdf import HKDF
from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat

OUT_DIR = os.path.join("test-vectors", "crypto")
GENERATOR = "tool/crypto_vectors.py (Python hashlib, cryptography, libsodium)"

# --- libsodium -----------------------------------------------------------

_sodium = ctypes.CDLL(ctypes.util.find_library("sodium") or "libsodium.so.23")
assert _sodium.sodium_init() >= 0
CRYPTO_PWHASH_ALG_ARGON2ID13 = 2


def xchacha_encrypt(key: bytes, nonce: bytes, plaintext: bytes, aad: bytes) -> bytes:
    out = ctypes.create_string_buffer(len(plaintext) + 16)
    out_len = ctypes.c_ulonglong()
    rc = _sodium.crypto_aead_xchacha20poly1305_ietf_encrypt(
        out, ctypes.byref(out_len),
        plaintext, ctypes.c_ulonglong(len(plaintext)),
        aad, ctypes.c_ulonglong(len(aad)),
        None, nonce, key,
    )
    assert rc == 0
    return out.raw[: out_len.value]


def argon2id(password: bytes, salt: bytes, m_kib: int, t: int, length: int = 32) -> bytes:
    out = ctypes.create_string_buffer(length)
    rc = _sodium.crypto_pwhash(
        out, ctypes.c_ulonglong(length),
        password, ctypes.c_ulonglong(len(password)),
        salt,
        ctypes.c_ulonglong(t), ctypes.c_size_t(m_kib * 1024),
        ctypes.c_int(CRYPTO_PWHASH_ALG_ARGON2ID13),
    )
    assert rc == 0
    return out.raw


def sodium_ed25519_public(seed: bytes) -> bytes:
    pk = ctypes.create_string_buffer(32)
    sk = ctypes.create_string_buffer(64)
    assert _sodium.crypto_sign_seed_keypair(pk, sk, seed) == 0
    return pk.raw


# --- примитивы спецификации ------------------------------------------------

def hkdf(ikm: bytes, salt: bytes, info: bytes, length: int = 32) -> bytes:
    return HKDF(algorithm=hashes.SHA256(), length=length, salt=salt, info=info).derive(ikm)


def blake2b_keyed(key: bytes, data: bytes) -> bytes:
    return hashlib.blake2b(data, digest_size=32, key=key).digest()


def bip39_seed(mnemonic: str, passphrase: str = "") -> bytes:
    password = unicodedata.normalize("NFKD", mnemonic).encode()
    salt = ("mnemonic" + unicodedata.normalize("NFKD", passphrase)).encode()
    return hashlib.pbkdf2_hmac("sha512", password, salt, 2048, 64)


def ed25519_public(seed: bytes) -> bytes:
    public = Ed25519PrivateKey.from_private_bytes(seed).public_key().public_bytes(
        Encoding.Raw, PublicFormat.Raw)
    assert public == sodium_ed25519_public(seed)  # две независимые реализации
    return public


def derive_all(seed: bytes, segment_id: bytes) -> dict:
    mk = hkdf(seed, b"fs/v1/master-salt", b"fs/v1/master")
    keys = {
        "masterKey": mk,
        "manifestKey": hkdf(mk, b"", b"fs/v1/manifest"),
        "dataKey": hkdf(mk, b"", b"fs/v1/data"),
        "chunkIdKey": hkdf(mk, b"", b"fs/v1/chunk-id"),
        "gearKey": hkdf(mk, b"", b"fs/v1/chunk-gear"),
        "accountSignSeed": hkdf(mk, b"", b"fs/v1/account-sign"),
    }
    keys["segmentKey"] = hkdf(keys["dataKey"], b"", b"fs/v1/segment" + segment_id)
    keys["accountPublicKey"] = ed25519_public(keys["accountSignSeed"])
    return keys


BLOB_TYPES = {"segment": 1, "snapshot": 2, "index": 3, "keyBundle": 4}


def blob(type_code: int, object_id: bytes, nonce: bytes, key: bytes, plaintext: bytes) -> bytes:
    header = b"FSEB" + bytes([1, type_code, 0, 0]) + object_id
    assert len(header) == 40
    return header + nonce + xchacha_encrypt(key, nonce, plaintext, header)


# --- детерминированные данные ---------------------------------------------

def splitmix64_bytes(seed: int, length: int) -> bytes:
    """Генератор из docs/spec/test-vectors.md: little-endian байты
    последовательных выходов splitmix64."""
    state = seed & 0xFFFFFFFFFFFFFFFF
    out = bytearray()
    mask = 0xFFFFFFFFFFFFFFFF
    while len(out) < length:
        state = (state + 0x9E3779B97F4A7C15) & mask
        z = state
        z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & mask
        z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & mask
        z ^= z >> 31
        out += struct.pack("<Q", z)
    return bytes(out[:length])


def pattern(seed: int, length: int) -> dict:
    return {"type": "splitmix64-le", "seed": seed, "length": length}


# --- файлы векторов ---------------------------------------------------------

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


def load_trezor_24() -> list:
    # Официальные векторы BIP39 (github.com/trezor/python-mnemonic, MIT),
    # 24-словные фразы; ожидаемый seed — с passphrase "TREZOR".
    return [
        ("0000000000000000000000000000000000000000000000000000000000000000",
         "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon art",
         "bda85446c68413707090a52022edd26a1c9462295029f2e60cd7c4f2bbd3097170af7a4d73245cafa9c3cca8d561a7c3de6f5d4a10be8ed2a5e608d68f92fcc8"),
        ("7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f",
         "legal winner thank year wave sausage worth useful legal winner thank year wave sausage worth useful legal winner thank year wave sausage worth title",
         "bc09fca1804f7e69da93c2f2028eb238c227f2e9dda30cd63699232578480a4021b146ad717fbb7e451ce9eb835f43620bf5c514db0f8add49f5d121449d3e87"),
        ("ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
         "zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo vote",
         "dd48c104698c30cfe2b6142103248622fb7bb0ff692eebb00089b32d22484e1613912f0a5b694407be899ffd31ed3992c456cdf60f5d4564b8ba3f05a69890ad"),
        ("68a79eaca2324873eacc50cb9c6eca8cc68ea5d936f98787c60c7ebc74e6ce7c",
         "hamster diagram private dutch cause delay private meat slide toddler razor book happy fancy gospel tennis maple dilemma loan word shrug inflict delay length",
         "64c87cde7e12ecf6704ab95bb1408bef047c22db4cc7491c4271d170a1b213d20b385bc1588d9c7b38f1b39d415665b8a9030c9ec653d75e65f847d8fc1fc440"),
    ]


def main() -> None:
    trezor = load_trezor_24()

    # bip39-seed.json: проверка PBKDF2 на официальных векторах.
    cases = []
    for entropy, mnemonic, expected in trezor:
        seed = bip39_seed(mnemonic, "TREZOR")
        assert seed.hex() == expected, mnemonic
        cases.append({
            "name": mnemonic.split()[0] + "-" + entropy[:8],
            "input": {"entropy": entropy, "mnemonic": mnemonic, "passphrase": "TREZOR"},
            "expected": {"seed": expected},
        })
    write("bip39-seed.json", "crypto/bip39-seed",
          "BIP39: фраза и passphrase → seed (PBKDF2-HMAC-SHA512). Официальные векторы Trezor.",
          cases)

    # key-hierarchy.json: фраза → seed (passphrase "") → MK → ключи.
    segment_id = bytes(range(32))
    cases = []
    for entropy, mnemonic, _ in trezor:
        seed = bip39_seed(mnemonic)
        keys = derive_all(seed, segment_id)
        cases.append({
            "name": mnemonic.split()[0] + "-" + entropy[:8],
            "input": {"entropy": entropy, "mnemonic": mnemonic, "segmentId": segment_id},
            "expected": {"seed": seed, **keys},
        })
    write("key-hierarchy.json", "crypto/key-hierarchy",
          "Фраза восстановления → seed → мастер-ключ → производные ключи (crypto.md, раздел 3).",
          cases)
    root = derive_all(bip39_seed(trezor[0][1]), segment_id)

    # blob.json
    nonce = bytes(range(0x40, 0x58))
    object_id = bytes(range(0xA0, 0xC0))
    cases = []
    plaintexts = {
        "empty": b"",
        "short": b"fs blob",
        "pattern1000": splitmix64_bytes(1, 1000),
    }
    for type_name, code in BLOB_TYPES.items():
        key = {
            "segment": hkdf(root["dataKey"], b"", b"fs/v1/segment" + object_id),
            "snapshot": root["manifestKey"],
            "index": root["manifestKey"],
            "keyBundle": bytes(range(0x60, 0x80)),
        }[type_name]
        for pt_name, pt in plaintexts.items():
            data = blob(code, object_id, nonce, key, pt)
            cases.append({
                "name": f"{type_name}-{pt_name}",
                "input": {
                    "type": code, "objectId": object_id, "nonce": nonce, "key": key,
                    **({"plaintextPattern": pattern(1, 1000)} if pt_name == "pattern1000"
                       else {"plaintext": pt}),
                },
                "expected": {"blob": data},
            })
    # Испорченные блобы: ожидается ошибка без расшифровки или ошибка целостности.
    key = root["manifestKey"]
    good = blob(2, object_id, nonce, key, b"fs blob")

    def corrupt(name, data, error):
        cases.append({
            "name": "reject-" + name,
            "input": {"key": key, "blob": data},
            "expected": {"error": error},
        })

    corrupt("bad-magic", b"FSEX" + good[4:], "format")
    corrupt("unknown-version", good[:4] + b"\x02" + good[5:], "format")
    corrupt("unknown-type", good[:5] + b"\x09" + good[6:], "format")
    corrupt("nonzero-reserved", good[:6] + b"\x00\x01" + good[8:], "format")
    corrupt("too-short", good[:79], "format")
    flipped = bytearray(good)
    flipped[70] ^= 0x01
    corrupt("flipped-ciphertext", bytes(flipped), "integrity")
    flipped = bytearray(good)
    flipped[-1] ^= 0x80
    corrupt("flipped-tag", bytes(flipped), "integrity")
    corrupt("other-type-in-aad", good[:5] + b"\x03" + good[6:], "integrity")
    other_id = bytearray(good)
    other_id[8] ^= 0xFF
    corrupt("other-object-id", bytes(other_id), "integrity")
    write("blob.json", "crypto/blob",
          "Зашифрованный блоб (crypto.md, раздел 5): шифрование с фиксированными ключом и nonce; "
          "разбор испорченных блобов. Поля plaintext и plaintextPattern взаимоисключающие.",
          cases)

    # chunk-id.json
    key = root["chunkIdKey"]
    cases = []
    for name, seed, length in [("empty", 0, 0), ("one-byte", 2, 1), ("4096", 3, 4096),
                               ("1MiB", 4, 1 << 20)]:
        data = splitmix64_bytes(seed, length)
        cases.append({
            "name": name,
            "input": {"chunkIdKey": key, "dataPattern": pattern(seed, length)},
            "expected": {"chunkId": blake2b_keyed(key, data)},
        })
    write("chunk-id.json", "crypto/chunk-id",
          "Идентификатор чанка: ключевой BLAKE2b-256 (crypto.md, раздел 6).", cases)

    # key-bundle.json
    cases = []
    salt = bytes(range(0x10, 0x20))
    bundle_nonce = bytes(range(0x30, 0x48))
    for name, password, m, t in [
        ("ascii-fast-params", "correct horse battery staple", 1024, 1),
        ("nfkc-fast-params", "Ｐａｓｓ ﬁ ½", 1024, 1),
        ("default-params", "correct horse battery staple", 262144, 3),
    ]:
        normalized = unicodedata.normalize("NFKC", password).encode("utf-8")
        pk = argon2id(normalized, salt, m, t)
        kek = hkdf(pk, b"", b"fs/v1/kek")
        auth = hkdf(pk, b"", b"fs/v1/auth")
        public = b"FSKB" + bytes([1, 1, 0, 0]) + struct.pack("<III", m, t, 1) + salt
        inner = blob(4, root["accountPublicKey"], bundle_nonce, kek, root["masterKey"])
        cases.append({
            "name": name,
            "input": {
                "password": password, "salt": salt, "m": m, "t": t, "p": 1,
                "masterKey": root["masterKey"], "accountPublicKey": root["accountPublicKey"],
                "nonce": bundle_nonce,
            },
            "expected": {
                "passwordNfkcUtf8": normalized, "pk": pk, "kek": kek, "auth": auth,
                "keyBundle": public + inner,
            },
        })
    write("key-bundle.json", "crypto/key-bundle",
          "Пароль → PK (Argon2id) → KEK, AUTH; KeyBundle с копией мастер-ключа (crypto.md, раздел 4). "
          "Случаи *-fast-params используют малые параметры только для скорости тестов.",
          cases)


if __name__ == "__main__":
    main()
