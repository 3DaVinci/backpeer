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
from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey, X25519PublicKey
from cryptography.hazmat.primitives.kdf.hkdf import HKDF
from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat

OUT_DIR = os.path.join("test-vectors", "crypto")
WORDLIST = os.path.join("tool", "bip39-english.txt")
WORDLIST_SHA256 = "2f5eed53a4727b4bf8880d8f3f199efc90e58503646d9ff8eff3a2ed3b24dbda"
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


def xchacha_decrypt_ok(key: bytes, nonce: bytes, ciphertext: bytes, aad: bytes) -> bool:
    out = ctypes.create_string_buffer(max(len(ciphertext) - 16, 1))
    out_len = ctypes.c_ulonglong()
    rc = _sodium.crypto_aead_xchacha20poly1305_ietf_decrypt(
        out, ctypes.byref(out_len), None,
        ciphertext, ctypes.c_ulonglong(len(ciphertext)),
        aad, ctypes.c_ulonglong(len(aad)),
        nonce, key,
    )
    return rc == 0


def sodium_x25519(scalar: bytes, point: bytes):
    out = ctypes.create_string_buffer(32)
    rc = _sodium.crypto_scalarmult(out, scalar, point)
    return out.raw if rc == 0 else None


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


# --- BIP39: энтропия → фраза ------------------------------------------------

def load_wordlist() -> list:
    with open(WORDLIST, "rb") as f:
        raw = f.read()
    assert hashlib.sha256(raw).hexdigest() == WORDLIST_SHA256
    words = raw.decode("ascii").split()
    assert len(words) == 2048
    return words


def entropy_to_mnemonic(words: list, entropy: bytes) -> str:
    bits = len(entropy) * 8
    checksum_bits = bits // 32
    value = int.from_bytes(entropy, "big") << checksum_bits
    value |= hashlib.sha256(entropy).digest()[0] >> (8 - checksum_bits)
    count = (bits + checksum_bits) // 11
    return " ".join(words[(value >> (11 * (count - 1 - i))) & 0x7FF] for i in range(count))


# Официальные векторы BIP39 для английского словаря
# (github.com/trezor/python-mnemonic, vectors.json, MIT): энтропия, фраза,
# seed с passphrase "TREZOR".
TREZOR_ENGLISH = [
    ('00000000000000000000000000000000', 'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about', 'c55257c360c07c72029aebc1b53c05ed0362ada38ead3e3e9efa3708e53495531f09a6987599d18264c1e1c92f2cf141630c7a3c4ab7c81b2f001698e7463b04') ,
    ('7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f', 'legal winner thank year wave sausage worth useful legal winner thank yellow', '2e8905819b8723fe2c1d161860e5ee1830318dbf49a83bd451cfb8440c28bd6fa457fe1296106559a3c80937a1c1069be3a3a5bd381ee6260e8d9739fce1f607') ,
    ('80808080808080808080808080808080', 'letter advice cage absurd amount doctor acoustic avoid letter advice cage above', 'd71de856f81a8acc65e6fc851a38d4d7ec216fd0796d0a6827a3ad6ed5511a30fa280f12eb2e47ed2ac03b5c462a0358d18d69fe4f985ec81778c1b370b652a8') ,
    ('ffffffffffffffffffffffffffffffff', 'zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo wrong', 'ac27495480225222079d7be181583751e86f571027b0497b5b5d11218e0a8a13332572917f0f8e5a589620c6f15b11c61dee327651a14c34e18231052e48c069') ,
    ('000000000000000000000000000000000000000000000000', 'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon agent', '035895f2f481b1b0f01fcf8c289c794660b289981a78f8106447707fdd9666ca06da5a9a565181599b79f53b844d8a71dd9f439c52a3d7b3e8a79c906ac845fa') ,
    ('7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f', 'legal winner thank year wave sausage worth useful legal winner thank year wave sausage worth useful legal will', 'f2b94508732bcbacbcc020faefecfc89feafa6649a5491b8c952cede496c214a0c7b3c392d168748f2d4a612bada0753b52a1c7ac53c1e93abd5c6320b9e95dd') ,
    ('808080808080808080808080808080808080808080808080', 'letter advice cage absurd amount doctor acoustic avoid letter advice cage absurd amount doctor acoustic avoid letter always', '107d7c02a5aa6f38c58083ff74f04c607c2d2c0ecc55501dadd72d025b751bc27fe913ffb796f841c49b1d33b610cf0e91d3aa239027f5e99fe4ce9e5088cd65') ,
    ('ffffffffffffffffffffffffffffffffffffffffffffffff', 'zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo when', '0cd6e5d827bb62eb8fc1e262254223817fd068a74b5b449cc2f667c3f1f985a76379b43348d952e2265b4cd129090758b3e3c2c49103b5051aac2eaeb890a528') ,
    ('0000000000000000000000000000000000000000000000000000000000000000', 'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon art', 'bda85446c68413707090a52022edd26a1c9462295029f2e60cd7c4f2bbd3097170af7a4d73245cafa9c3cca8d561a7c3de6f5d4a10be8ed2a5e608d68f92fcc8') ,
    ('7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f', 'legal winner thank year wave sausage worth useful legal winner thank year wave sausage worth useful legal winner thank year wave sausage worth title', 'bc09fca1804f7e69da93c2f2028eb238c227f2e9dda30cd63699232578480a4021b146ad717fbb7e451ce9eb835f43620bf5c514db0f8add49f5d121449d3e87') ,
    ('8080808080808080808080808080808080808080808080808080808080808080', 'letter advice cage absurd amount doctor acoustic avoid letter advice cage absurd amount doctor acoustic avoid letter advice cage absurd amount doctor acoustic bless', 'c0c519bd0e91a2ed54357d9d1ebef6f5af218a153624cf4f2da911a0ed8f7a09e2ef61af0aca007096df430022f7a2b6fb91661a9589097069720d015e4e982f') ,
    ('ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff', 'zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo vote', 'dd48c104698c30cfe2b6142103248622fb7bb0ff692eebb00089b32d22484e1613912f0a5b694407be899ffd31ed3992c456cdf60f5d4564b8ba3f05a69890ad') ,
    ('9e885d952ad362caeb4efe34a8e91bd2', 'ozone drill grab fiber curtain grace pudding thank cruise elder eight picnic', '274ddc525802f7c828d8ef7ddbcdc5304e87ac3535913611fbbfa986d0c9e5476c91689f9c8a54fd55bd38606aa6a8595ad213d4c9c9f9aca3fb217069a41028') ,
    ('6610b25967cdcca9d59875f5cb50b0ea75433311869e930b', 'gravity machine north sort system female filter attitude volume fold club stay feature office ecology stable narrow fog', '628c3827a8823298ee685db84f55caa34b5cc195a778e52d45f59bcf75aba68e4d7590e101dc414bc1bbd5737666fbbef35d1f1903953b66624f910feef245ac') ,
    ('68a79eaca2324873eacc50cb9c6eca8cc68ea5d936f98787c60c7ebc74e6ce7c', 'hamster diagram private dutch cause delay private meat slide toddler razor book happy fancy gospel tennis maple dilemma loan word shrug inflict delay length', '64c87cde7e12ecf6704ab95bb1408bef047c22db4cc7491c4271d170a1b213d20b385bc1588d9c7b38f1b39d415665b8a9030c9ec653d75e65f847d8fc1fc440') ,
    ('c0ba5a8e914111210f2bd131f3d5e08d', 'scheme spot photo card baby mountain device kick cradle pact join borrow', 'ea725895aaae8d4c1cf682c1bfd2d358d52ed9f0f0591131b559e2724bb234fca05aa9c02c57407e04ee9dc3b454aa63fbff483a8b11de949624b9f1831a9612') ,
    ('6d9be1ee6ebd27a258115aad99b7317b9c8d28b6d76431c3', 'horn tenant knee talent sponsor spell gate clip pulse soap slush warm silver nephew swap uncle crack brave', 'fd579828af3da1d32544ce4db5c73d53fc8acc4ddb1e3b251a31179cdb71e853c56d2fcb11aed39898ce6c34b10b5382772db8796e52837b54468aeb312cfc3d') ,
    ('9f6a2878b2520799a44ef18bc7df394e7061a224d2c33cd015b157d746869863', 'panda eyebrow bullet gorilla call smoke muffin taste mesh discover soft ostrich alcohol speed nation flash devote level hobby quick inner drive ghost inside', '72be8e052fc4919d2adf28d5306b5474b0069df35b02303de8c1729c9538dbb6fc2d731d5f832193cd9fb6aeecbc469594a70e3dd50811b5067f3b88b28c3e8d') ,
    ('23db8160a31d3e0dca3688ed941adbf3', 'cat swing flag economy stadium alone churn speed unique patch report train', 'deb5f45449e615feff5640f2e49f933ff51895de3b4381832b3139941c57b59205a42480c52175b6efcffaa58a2503887c1e8b363a707256bdd2b587b46541f5') ,
    ('8197a4a47f0425faeaa69deebc05ca29c0a5b5cc76ceacc0', 'light rule cinnamon wrap drastic word pride squirrel upgrade then income fatal apart sustain crack supply proud access', '4cbdff1ca2db800fd61cae72a57475fdc6bab03e441fd63f96dabd1f183ef5b782925f00105f318309a7e9c3ea6967c7801e46c8a58082674c860a37b93eda02') ,
    ('066dca1a2bb7e8a1db2832148ce9933eea0f3ac9548d793112d9a95c9407efad', 'all hour make first leader extend hole alien behind guard gospel lava path output census museum junior mass reopen famous sing advance salt reform', '26e975ec644423f4a4c4f4215ef09b4bd7ef924e85d1d17c4cf3f136c2863cf6df0a475045652c57eb5fb41513ca2a2d67722b77e954b4b3fc11f7590449191d') ,
    ('f30f8c1da665478f49b001d94c5fc452', 'vessel ladder alter error federal sibling chat ability sun glass valve picture', '2aaa9242daafcee6aa9d7269f17d4efe271e1b9a529178d7dc139cd18747090bf9d60295d0ce74309a78852a9caadf0af48aae1c6253839624076224374bc63f') ,
    ('c10ec20dc3cd9f652c7fac2f1230f7a3c828389a14392f05', 'scissors invite lock maple supreme raw rapid void congress muscle digital elegant little brisk hair mango congress clump', '7b4a10be9d98e6cba265566db7f136718e1398c71cb581e1b2f464cac1ceedf4f3e274dc270003c670ad8d02c4558b2f8e39edea2775c9e232c7cb798b069e88') ,
    ('f585c11aec520db57dd353c69554b21a89b20fb0650966fa0a9d6f74fd989d8f', 'void come effort suffer camp survey warrior heavy shoot primary clutch crush open amazing screen patrol group space point ten exist slush involve unfold', '01f5bced59dec48e362f2c45b5de68b9fd6c92c6634f44d6d40aab69056506f0e35524a518034ddc1192e1dacd32c1ed3eaa3c3b131c88ed8e7e54c49a5d0998') ,
]


def bip39_mnemonic_cases() -> list:
    words = load_wordlist()
    cases = []
    for entropy, mnemonic, seed in TREZOR_ENGLISH:
        assert entropy_to_mnemonic(words, bytes.fromhex(entropy)) == mnemonic
        assert bip39_seed(mnemonic, "TREZOR").hex() == seed
        count = len(mnemonic.split())
        cases.append({
            "name": f"trezor-{count}-{entropy[:8]}",
            "input": {"entropy": bytes.fromhex(entropy)},
            "expected": {"mnemonic": mnemonic, "seedTrezor": bytes.fromhex(seed)},
        })

    # Разбор введённой пользователем фразы (только 24 слова, crypto.md, 3.1).
    valid = entropy_to_mnemonic(words, bytes(range(32)))
    abandon = ["abandon"] * 24
    parse = [
        ("parse-valid", valid, {"entropy": bytes(range(32))}),
        ("parse-case-and-spaces", "  " + valid.upper().replace(" ", " \t ", 3) + "\n",
         {"entropy": bytes(range(32))}),
        ("parse-bad-checksum", " ".join(abandon), {"error": "integrity"}),
        ("parse-unknown-word", " ".join(abandon[:23] + ["abandonx"]), {"error": "format"}),
        ("parse-23-words", " ".join(valid.split()[:23]), {"error": "format"}),
        ("parse-12-words", TREZOR_ENGLISH[0][1], {"error": "format"}),
        ("parse-empty", "", {"error": "format"}),
    ]
    for name, text, expected in parse:
        cases.append({"name": name, "input": {"phrase": text}, "expected": expected})
    return cases


# --- NFKC для паролей -----------------------------------------------------

# Строки, которые встречаются в паролях: полноширинные и лигатуры,
# составные и разложенные буквы, надстрочные цифры, хангыль, японская
# полуширинная катакана, формы арабского письма. Только символы, назначенные
# уже в Unicode 3.2: их NFKC одинакова во всех реализациях (политика
# стабильности нормализации), даже если версии Unicode у них разные.
NFKC_SAMPLES = [
    ("ascii", "correct horse battery staple"),
    ("fullwidth", "\uff30\uff41\uff53\uff53\uff57\uff4f\uff52\uff44\uff11\uff12\uff13"),
    ("ligatures", "\ufb01\ufb02\ufb00 \u0132"),
    ("latin-decomposed", "Cafe\u0301 nai\u0308ve"),
    ("latin-composed", "Caf\u00e9 na\u00efve"),
    ("cyrillic-decomposed", "\u0438\u0306\u043e\u0434 \u0435\u0308\u0436"),
    ("cyrillic-composed", "\u0439\u043e\u0434 \u0451\u0436"),
    ("superscript-fraction", "x\u00b2 \u00bd \u2460 \u2163"),
    ("hangul-jamo", "\u1112\u1161\u11ab\u1100\u1173\u11af"),
    ("hangul-syllables", "\ud55c\uae00"),
    ("halfwidth-katakana", "\uff8a\uff9f\uff7d\uff9c\uff70\uff84\uff9e"),
    ("greek-tonos", "\u0390 \u1fbe \u03d2\u0301"),
    ("arabic-presentation", "\ufefb \ufdfa"),
    ("nbsp-and-ideographic-space", "a\u00a0b\u3000c"),
    ("angstrom-ohm-kelvin", "\u212b \u2126 \u212a"),
    ("combining-order", "a\u0323\u0307 a\u0307\u0323"),
    ("empty", ""),
]


def nfkc_cases() -> list:
    cases = []
    for name, text in NFKC_SAMPLES:
        assert all(unicodedata.ucd_3_2_0.category(ch) != "Cn" for ch in text), name
        normalized = unicodedata.normalize("NFKC", text)
        assert unicodedata.ucd_3_2_0.normalize("NFKC", text) == normalized, name
        cases.append({
            "name": name,
            "input": {"text": text},
            "expected": {"nfkc": normalized, "nfkcUtf8": normalized.encode("utf-8")},
        })
    return cases


# --- примитивы: векторы из RFC ---------------------------------------------
# Значения перенесены из текстов RFC; каждое сверяется с независимой
# реализацией (cryptography, hashlib, libsodium). Если перенос с ошибкой,
# генератор падает.

def h(text: str) -> bytes:
    return bytes.fromhex("".join(text.split()))


def primitives_cases() -> list:
    cases = []

    # XChaCha20-Poly1305: draft-irtf-cfrg-xchacha-03, приложение A.3.1.
    key = h("808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f")
    nonce = h("404142434445464748494a4b4c4d4e4f5051525354555657")
    aad = h("50515253c0c1c2c3c4c5c6c7")
    plaintext = (b"Ladies and Gentlemen of the class of '99: If I could offer you "
                 b"only one tip for the future, sunscreen would be it.")
    ciphertext = h("""
        bd6d179d3e83d43b9576579493c0e939572a1700252bfaccbed2902c21396cbb
        731c7f1b0b4aa6440bf3a82f4eda7e39ae64c6708c54c216cb96b72e1213b452
        2f8c9ba40db5d945b11b69b982c1bb9e3f3fac2bc369488f76b2383565d3fff9
        21f9664c97637da9768812f615c68b13b52e""") + h("c0875924c1c7987947deafd8780acf49")
    assert xchacha_encrypt(key, nonce, plaintext, aad) == ciphertext
    aead_input = {"primitive": "xchacha20poly1305", "key": key, "nonce": nonce, "aad": aad}
    cases.append({"name": "xchacha-draft03-a3-1",
                  "input": {**aead_input, "plaintext": plaintext},
                  "expected": {"ciphertext": ciphertext}})
    tampered = ciphertext[:-1] + bytes([ciphertext[-1] ^ 1])
    assert not xchacha_decrypt_ok(key, nonce, tampered, aad)
    cases.append({"name": "xchacha-draft03-a3-1-bad-tag",
                  "input": {**aead_input, "ciphertext": tampered},
                  "expected": {"error": "integrity"}})
    wrong_aad = aad[:-1] + bytes([aad[-1] ^ 1])
    assert not xchacha_decrypt_ok(key, nonce, ciphertext, wrong_aad)
    cases.append({"name": "xchacha-draft03-a3-1-bad-aad",
                  "input": {**aead_input, "aad": wrong_aad, "ciphertext": ciphertext},
                  "expected": {"error": "integrity"}})

    # BLAKE2b-256. В RFC 7693 только BLAKE2b-512("abc"); для 32-байтного
    # выхода — эталон BLAKE2 из hashlib, сверенный с известными значениями.
    assert hashlib.blake2b(b"abc").digest() == h("""
        ba80a53f981c4d0d6a2797b69f12f6e94c212f14685ac4b74b12bb6fdbffa2d1
        7d87c5392aab792dc252d5de4533cc9518d38aa8dbf1925ab92386edd4009923""")  # RFC 7693, A
    for name, data, key, digest in [
        ("blake2b256-empty", b"", None,
         "0e5751c026e543b2e8ab2eb06099daa1d1e5df47778f7787faab45cdf12fe3a8"),
        ("blake2b256-abc", b"abc", None,
         "bddd813c634239723171ef3fee98579b94964e3bb1cb3e427262c8c068d52319"),
        ("blake2b256-keyed", bytes(range(64)), bytes(range(32)), None),
        ("blake2b256-keyed-empty", b"", bytes(range(32)), None),
    ]:
        actual = hashlib.blake2b(data, digest_size=32, key=key or b"").digest()
        if digest is not None:
            assert actual == h(digest), name
        entry = {"primitive": "blake2b256", "data": data}
        if key is not None:
            entry["key"] = key
        cases.append({"name": name, "input": entry, "expected": {"digest": actual}})

    # HKDF-SHA256: RFC 5869, приложение A.1–A.3.
    for name, ikm, salt, info, okm in [
        ("hkdf-rfc5869-a1", h("0b" * 22), h("000102030405060708090a0b0c"),
         h("f0f1f2f3f4f5f6f7f8f9"),
         "3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865"),
        ("hkdf-rfc5869-a2", bytes(range(0x00, 0x50)), bytes(range(0x60, 0xb0)),
         bytes(range(0xb0, 0x100)),
         "b11e398dc80327a1c8e7f78c596a49344f012eda2d4efad8a050cc4c19afa97c"
         "59045a99cac7827271cb41c65e590e09da3275600c2f09b8367793a9aca3db71"
         "cc30c58179ec3e87c14c01d5c1f3434f1d87"),
        ("hkdf-rfc5869-a3", h("0b" * 22), b"", b"",
         "8da4e775a563c18f715f802a063c5a31b8a11f5c5ee1879ec3454e5f3c738d2d9d201395faa4b61a96c8"),
    ]:
        assert hkdf(ikm, salt, info, len(h(okm))) == h(okm), name
        cases.append({"name": name,
                      "input": {"primitive": "hkdf-sha256", "ikm": ikm, "salt": salt,
                                "info": info, "length": len(h(okm))},
                      "expected": {"okm": h(okm)}})

    # Ed25519: RFC 8032, раздел 7.1, TEST 1–3.
    for name, seed, public, message, signature in [
        ("ed25519-rfc8032-test1",
         "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60",
         "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a", "",
         "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e06522490155"
         "5fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b"),
        ("ed25519-rfc8032-test2",
         "4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb",
         "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c", "72",
         "92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da"
         "085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00"),
        ("ed25519-rfc8032-test3",
         "c5aa8df43f9f837bedb7442f31dcb7b166d38535076f094b85ce3a2e0b4458f7",
         "fc51cd8e6218a1a38da47ed00230f0580816ed13ba3303ac5deb911548908025", "af82",
         "6291d657deec24024827e69c3abe01a30ce548a284743a445e3680d7db5ac3ac"
         "18ff9b538d16f290ae67f760984dc6594a7c15e9716ed28dc027beceea1ec40a"),
    ]:
        private = Ed25519PrivateKey.from_private_bytes(h(seed))
        assert ed25519_public(h(seed)) == h(public), name
        assert private.sign(h(message)) == h(signature), name
        cases.append({"name": name,
                      "input": {"primitive": "ed25519", "seed": h(seed), "message": h(message)},
                      "expected": {"publicKey": h(public), "signature": h(signature)}})

    # X25519: RFC 7748, разделы 5.2 и 6.1.
    for name, scalar, point, out in [
        ("x25519-rfc7748-5.2-1",
         "a546e36bf0527c9d3b16154b82465edd62144c0ac1fc5a18506a2244ba449ac4",
         "e6db6867583030db3594c1a424b15f7c726624ec26b3353b10a903a6d0ab1c4c",
         "c3da55379de9c6908e94ea4df28d084f32eccf03491c71f754b4075577a28552"),
        ("x25519-rfc7748-5.2-2",
         "4b66e9d4d1b4673c5ad22691957d6af5c11b6421e0ea01d42ca4169e7918ba0d",
         "e5210f12786811d3f4b7959d0538ae2c31dbe7106fc03c3efc4cd549c715a493",
         "95cbde9476e8907d7aade45cb4b873f88b595a68799fa152e6f8f7647aac7957"),
    ]:
        assert sodium_x25519(h(scalar), h(point)) == h(out), name
        assert X25519PrivateKey.from_private_bytes(h(scalar)).exchange(
            X25519PublicKey.from_public_bytes(h(point))) == h(out), name
        cases.append({"name": name,
                      "input": {"primitive": "x25519", "secretKey": h(scalar), "publicKey": h(point)},
                      "expected": {"sharedSecret": h(out)}})
    alice = h("77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a")
    alice_public = h("8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a")
    bob = h("5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb")
    bob_public = h("de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f")
    shared = h("4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742")
    for priv, pub in [(alice, alice_public), (bob, bob_public)]:
        assert X25519PrivateKey.from_private_bytes(priv).public_key().public_bytes(
            Encoding.Raw, PublicFormat.Raw) == pub
    assert sodium_x25519(alice, bob_public) == shared == sodium_x25519(bob, alice_public)
    cases.append({"name": "x25519-rfc7748-6.1",
                  "input": {"primitive": "x25519-exchange", "aliceSecretKey": alice,
                            "bobSecretKey": bob},
                  "expected": {"alicePublicKey": alice_public, "bobPublicKey": bob_public,
                               "sharedSecret": shared}})
    # Точка малого порядка (u = 0): общий секрет нулевой, открытый ключ
    # собеседника отклоняется как недопустимые данные.
    assert sodium_x25519(alice, bytes(32)) is None
    cases.append({"name": "x25519-low-order-point",
                  "input": {"primitive": "x25519", "secretKey": alice, "publicKey": bytes(32)},
                  "expected": {"error": "format"}})
    return cases


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
    # Тип 5 (локальная копия фразы, crypto.md, раздел 4.2) — в конце файла,
    # чтобы порядок выпущенных случаев не менялся.
    for pt_name, pt in [("entropy", bytes(range(32)))]:
        phrase_key = bytes(range(0x60, 0x80))
        cases.append({
            "name": f"localPhrase-{pt_name}",
            "input": {"type": 5, "objectId": object_id, "nonce": nonce, "key": phrase_key,
                      "plaintext": pt},
            "expected": {"blob": blob(5, object_id, nonce, phrase_key, pt)},
        })
    # Тип 6 (локальные ключи устройства, crypto.md, раздел 3.4) — тоже в конце.
    device_key = bytes(range(0x60, 0x80))
    device_pt = bytes(range(0x80, 0xC0))
    cases.append({
        "name": "localDeviceKeys-seeds",
        "input": {"type": 6, "objectId": object_id, "nonce": nonce, "key": device_key,
                  "plaintext": device_pt},
        "expected": {"blob": blob(6, object_id, nonce, device_key, device_pt)},
    })
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

    write("bip39-mnemonic.json", "crypto/bip39-mnemonic",
          "BIP39 (crypto.md, раздел 3.1): энтропия → фраза на всех английских векторах Trezor "
          "(12, 18 и 24 слова; seedTrezor — seed с passphrase \"TREZOR\"). Случаи parse-* — "
          "разбор введённой фразы: регистр и пробельные символы не важны, допустимы только "
          "24 слова; неизвестное слово или их число — format, контрольная сумма — integrity. "
          "Словарь — tool/bip39-english.txt.",
          bip39_mnemonic_cases())

    write("nfkc.json", "crypto/nfkc",
          "NFKC пароля (crypto.md, раздел 4): строки из символов, назначенных во всех версиях "
          "Unicode, и их нормальная форма; эталон — unicodedata в Python. Тексты в JSON как есть.",
          nfkc_cases())

    write("primitives.json", "crypto/primitives",
          "Примитивы crypto.md, раздел 2, на векторах из RFC: XChaCha20-Poly1305 "
          "(draft-irtf-cfrg-xchacha-03), HKDF-SHA256 (RFC 5869), Ed25519 (RFC 8032), "
          "X25519 (RFC 7748); BLAKE2b-256 — эталон BLAKE2 (в RFC 7693 только 512-битный вектор). "
          "Поле input.primitive задаёт примитив. Argon2id проверяется векторами key-bundle.json: "
          "вектор RFC 9106 требует p = 4, secret и associated data, которых нет в libsodium "
          "и в crypto.md. PBKDF2-HMAC-SHA512 проверяется векторами bip39-seed.json.",
          primitives_cases())


if __name__ == "__main__":
    main()
