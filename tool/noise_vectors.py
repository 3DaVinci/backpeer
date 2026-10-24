#!/usr/bin/env python3
"""Генератор тестовых векторов канала Noise (docs/spec/protocol.md, раздел 3).

Эталонная реализация Noise_XX_25519_ChaChaPoly_BLAKE2b (Noise Protocol
Framework, ревизия 34), независимая от кода на Dart: стандартная
библиотека Python (BLAKE2b, HMAC) и пакет cryptography (X25519,
ChaCha20-Poly1305). Перед генерацией реализация сверяется с официальными
векторами cacophony (test-vectors/protocol/noise-cacophony.json).

Запуск из корня репозитория:

    python3 -I tool/noise_vectors.py
    python3 -I tool/noise_vectors.py --cacophony /путь/к/cacophony.txt

Второй вариант заново импортирует векторы cacophony для нашего набора
примитивов (https://github.com/haskell-cryptography/cacophony,
vectors/cacophony.txt, общественное достояние). Записывает
test-vectors/protocol/noise-frames.json. Входы фиксированы, поэтому
повторный запуск даёт те же файлы.
"""

import hashlib
import hmac
import json
import os
import struct
import sys

from cryptography.exceptions import InvalidTag
from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey, X25519PublicKey
from cryptography.hazmat.primitives.ciphers.aead import ChaCha20Poly1305
from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat

OUT_DIR = os.path.join("test-vectors", "protocol")
GENERATOR = "tool/noise_vectors.py (Python hashlib, hmac, cryptography)"
PROTOCOL_NAME = b"Noise_XX_25519_ChaChaPoly_BLAKE2b"
PROLOGUE = b"fs/v1/noise"

HASHLEN = 64
MAX_NONCE = 2**64 - 1
MAX_TRANSPORT = 65535                 # длина сообщения Noise в транспортном кадре
MAX_PLAINTEXT = MAX_TRANSPORT - 16    # открытый текст одного транспортного кадра
MAX_APP_MESSAGE = 1 << 20             # PeerMessage в кадре приложения
REKEY_INTERVAL = 65536                # сообщений в одном направлении между Rekey


# --- Noise ------------------------------------------------------------------

def public_key(secret: bytes) -> bytes:
    return X25519PrivateKey.from_private_bytes(secret).public_key().public_bytes(
        Encoding.Raw, PublicFormat.Raw)


def dh(secret: bytes, public: bytes) -> bytes:
    return X25519PrivateKey.from_private_bytes(secret).exchange(
        X25519PublicKey.from_public_bytes(public))


def hash_(data: bytes) -> bytes:
    return hashlib.blake2b(data).digest()


def hkdf(ck: bytes, ikm: bytes, outputs: int):
    temp = hmac.new(ck, ikm, hashlib.blake2b).digest()
    out1 = hmac.new(temp, b"\x01", hashlib.blake2b).digest()
    out2 = hmac.new(temp, out1 + b"\x02", hashlib.blake2b).digest()
    return (out1, out2) if outputs == 2 else (out1, out2,
            hmac.new(temp, out2 + b"\x03", hashlib.blake2b).digest())


class CipherState:
    def __init__(self, key=None):
        self.k = key
        self.n = 0

    @staticmethod
    def nonce(n: int) -> bytes:
        return b"\x00" * 4 + struct.pack("<Q", n)

    def encrypt(self, ad: bytes, plaintext: bytes) -> bytes:
        if self.k is None:
            return plaintext
        assert self.n < MAX_NONCE
        out = ChaCha20Poly1305(self.k).encrypt(self.nonce(self.n), plaintext, ad)
        self.n += 1
        return out

    def decrypt(self, ad: bytes, ciphertext: bytes) -> bytes:
        if self.k is None:
            return ciphertext
        assert self.n < MAX_NONCE
        out = ChaCha20Poly1305(self.k).decrypt(self.nonce(self.n), ciphertext, ad)
        self.n += 1
        return out

    def rekey(self) -> None:
        self.k = ChaCha20Poly1305(self.k).encrypt(self.nonce(MAX_NONCE), bytes(32), b"")[:32]


class SymmetricState:
    def __init__(self, name: bytes):
        self.h = name.ljust(HASHLEN, b"\x00") if len(name) <= HASHLEN else hash_(name)
        self.ck = self.h
        self.cs = CipherState()

    def mix_hash(self, data: bytes) -> None:
        self.h = hash_(self.h + data)

    def mix_key(self, ikm: bytes) -> None:
        self.ck, temp = hkdf(self.ck, ikm, 2)
        self.cs = CipherState(temp[:32])

    def encrypt_and_hash(self, plaintext: bytes) -> bytes:
        ct = self.cs.encrypt(self.h, plaintext)
        self.mix_hash(ct)
        return ct

    def decrypt_and_hash(self, ciphertext: bytes) -> bytes:
        pt = self.cs.decrypt(self.h, ciphertext)
        self.mix_hash(ciphertext)
        return pt

    def split(self):
        k1, k2 = hkdf(self.ck, b"", 2)
        return CipherState(k1[:32]), CipherState(k2[:32])


class HandshakeXX:
    """XX: -> e; <- e, ee, s, es; -> s, se."""

    def __init__(self, initiator: bool, prologue: bytes, s: bytes, e: bytes):
        self.initiator = initiator
        self.ss = SymmetricState(PROTOCOL_NAME)
        self.ss.mix_hash(prologue)
        self.s, self.e = s, e
        self.rs = self.re = None
        self.step = 0

    def write(self, payload: bytes) -> bytes:
        ss, out = self.ss, b""
        if self.step == 0:
            out += public_key(self.e)
            ss.mix_hash(public_key(self.e))
        elif self.step == 1:
            out += public_key(self.e)
            ss.mix_hash(public_key(self.e))
            ss.mix_key(dh(self.e, self.re))
            out += ss.encrypt_and_hash(public_key(self.s))
            ss.mix_key(dh(self.s, self.re))
        else:
            out += ss.encrypt_and_hash(public_key(self.s))
            ss.mix_key(dh(self.s, self.re))
        out += ss.encrypt_and_hash(payload)
        self.step += 1
        return out

    def read(self, message: bytes) -> bytes:
        ss = self.ss
        if self.step == 0:
            self.re, rest = message[:32], message[32:]
            ss.mix_hash(self.re)
        elif self.step == 1:
            self.re = message[:32]
            ss.mix_hash(self.re)
            ss.mix_key(dh(self.e, self.re))
            self.rs = ss.decrypt_and_hash(message[32:80])
            ss.mix_key(dh(self.e, self.rs))
            rest = message[80:]
        else:
            self.rs = ss.decrypt_and_hash(message[:48])
            ss.mix_key(dh(self.e, self.rs))
            rest = message[48:]
        self.step += 1
        return ss.decrypt_and_hash(rest)

    def ciphers(self):
        """(отправка, приём) после третьего сообщения."""
        c1, c2 = self.ss.split()
        return (c1, c2) if self.initiator else (c2, c1)


def run_handshake(init_s, init_e, resp_s, resp_e, prologue, payloads):
    """Три сообщения рукопожатия; возвращает их байты и обе стороны."""
    i = HandshakeXX(True, prologue, init_s, init_e)
    r = HandshakeXX(False, prologue, resp_s, resp_e)
    messages = []
    for step, payload in enumerate(payloads):
        writer, reader = (i, r) if step % 2 == 0 else (r, i)
        msg = writer.write(payload)
        assert reader.read(msg) == payload
        messages.append(msg)
    assert i.ss.h == r.ss.h
    return messages, i, r


# --- cacophony ---------------------------------------------------------------

def import_cacophony(path: str) -> None:
    with open(path, encoding="utf-8") as f:
        source = json.load(f)
    name = PROTOCOL_NAME.decode()
    cases = []
    for v in source["vectors"]:
        if v.get("protocol_name") != name:
            continue
        cases.append({
            "name": f"cacophony-{len(cases) + 1}",
            "input": {k: v[k] for k in ("init_prologue", "init_static", "init_ephemeral",
                                        "resp_prologue", "resp_static", "resp_ephemeral")},
            "expected": {"handshake_hash": v["handshake_hash"], "messages": v["messages"]},
        })
    assert cases, "в файле нет векторов " + name
    write_json("noise-cacophony.json", {
        "spec": "protocol/noise-cacophony",
        "specVersion": 1,
        "generator": "cacophony (https://github.com/haskell-cryptography/cacophony, "
                     "vectors/cacophony.txt, общественное достояние); импорт — "
                     "tool/noise_vectors.py --cacophony",
        "description": "Официальные векторы Noise для " + name + " (protocol.md, "
                       "раздел 3.1). Ключи — закрытые ключи X25519. messages[0..2] — "
                       "рукопожатие XX (полезная нагрузка и сообщение Noise), дальше — "
                       "транспортные сообщения: чётные индексы отправляет инициатор, "
                       "нечётные — отвечающий. handshake_hash — h после рукопожатия.",
        "cases": cases,
    })


def check_cacophony() -> None:
    path = os.path.join(OUT_DIR, "noise-cacophony.json")
    with open(path, encoding="utf-8") as f:
        cases = json.load(f)["cases"]
    for case in cases:
        inp, exp = case["input"], case["expected"]
        h = bytes.fromhex
        msgs = exp["messages"]
        wire, i, r = run_handshake(h(inp["init_static"]), h(inp["init_ephemeral"]),
                                   h(inp["resp_static"]), h(inp["resp_ephemeral"]),
                                   h(inp["init_prologue"]),
                                   [h(m["payload"]) for m in msgs[:3]])
        assert [m.hex() for m in wire] == [m["ciphertext"] for m in msgs[:3]], case["name"]
        assert i.ss.h.hex() == exp["handshake_hash"], case["name"]
        i_send, i_recv = i.ciphers()
        r_send, r_recv = r.ciphers()
        for index, m in enumerate(msgs[3:], start=3):
            send, recv = (i_send, r_recv) if index % 2 == 0 else (r_send, i_recv)
            ct = send.encrypt(b"", h(m["payload"]))
            assert ct.hex() == m["ciphertext"], (case["name"], index)
            assert recv.decrypt(b"", ct) == h(m["payload"])


# --- кадры (protocol.md, раздел 3.3) -----------------------------------------

def splitmix64_bytes(seed: int, length: int) -> bytes:
    out = bytearray()
    state = seed & 0xFFFFFFFFFFFFFFFF
    while len(out) < length:
        state = (state + 0x9E3779B97F4A7C15) & 0xFFFFFFFFFFFFFFFF
        z = state
        z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & 0xFFFFFFFFFFFFFFFF
        z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & 0xFFFFFFFFFFFFFFFF
        z ^= z >> 31
        out += struct.pack("<Q", z)
    return bytes(out[:length])


class Sender:
    """Отправитель канала: нарезка кадра приложения и смена ключей."""

    def __init__(self, cipher: CipherState, rekey_interval: int):
        self.cipher = cipher
        self.interval = rekey_interval

    def frame(self, plaintext: bytes) -> bytes:
        assert len(plaintext) <= MAX_PLAINTEXT
        ct = self.cipher.encrypt(b"", plaintext)
        if self.cipher.n % self.interval == 0:
            self.cipher.rekey()
        return struct.pack(">H", len(ct)) + ct

    def message(self, body: bytes) -> bytes:
        data = struct.pack(">I", len(body)) + body
        return b"".join(self.frame(data[i:i + MAX_PLAINTEXT])
                        for i in range(0, len(data), MAX_PLAINTEXT))


class Receiver:
    """Получатель: не опирается на границы транспортных кадров."""

    def __init__(self, cipher: CipherState, rekey_interval: int):
        self.cipher = cipher
        self.interval = rekey_interval

    def read(self, wire: bytes):
        stream, pos = b"", 0
        while pos < len(wire):
            if len(wire) - pos < 2:
                return "format"
            (length,) = struct.unpack(">H", wire[pos:pos + 2])
            if length < 16 or len(wire) - pos - 2 < length:
                return "format"
            try:
                stream += self.cipher.decrypt(b"", wire[pos + 2:pos + 2 + length])
            except InvalidTag:
                return "integrity"
            if self.cipher.n % self.interval == 0:
                self.cipher.rekey()
            pos += 2 + length
        messages = []
        while stream:
            if len(stream) < 4:
                return "format"
            (length,) = struct.unpack(">I", stream[:4])
            if length > MAX_APP_MESSAGE:
                return "format"
            if len(stream) < 4 + length:
                return "format"
            messages.append(stream[4:4 + length])
            stream = stream[4 + length:]
        return messages


def message_entry(body: bytes, wire: bytes, sender: str, seed=None) -> dict:
    entry = {"from": sender}
    if seed is None:
        entry["message"] = body
    else:
        entry["message"] = {"type": "splitmix64-le", "seed": seed, "length": len(body)}
    if len(wire) <= 4096:
        entry["wire"] = wire
    else:
        entry["wireLength"] = len(wire)
        entry["wireHash"] = hashlib.blake2b(wire, digest_size=32).digest()
    entry["transportFrames"] = count_frames(wire)
    return entry


def count_frames(wire: bytes) -> int:
    pos = frames = 0
    while pos < len(wire):
        (length,) = struct.unpack(">H", wire[pos:pos + 2])
        pos += 2 + length
        frames += 1
    return frames


KEYS = {
    "initStatic": bytes(range(0x01, 0x21)),
    "initEphemeral": bytes(range(0x21, 0x41)),
    "respStatic": bytes(range(0x41, 0x61)),
    "respEphemeral": bytes(range(0x61, 0x81)),
}


def frames_case(name: str, rekey_interval: int, plan, msg2: bytes, msg3: bytes) -> dict:
    wire, i, r = run_handshake(KEYS["initStatic"], KEYS["initEphemeral"],
                               KEYS["respStatic"], KEYS["respEphemeral"],
                               PROLOGUE, [b"", msg2, msg3])
    i_send, i_recv = i.ciphers()
    r_send, r_recv = r.ciphers()
    sides = {
        "initiator": (Sender(i_send, rekey_interval), Receiver(r_recv, rekey_interval)),
        "responder": (Sender(r_send, rekey_interval), Receiver(i_recv, rekey_interval)),
    }
    messages = []
    for sender_name, body, seed in plan:
        sender, receiver = sides[sender_name]
        frames = sender.message(body)
        assert receiver.read(frames) == [body]
        messages.append(message_entry(body, frames, sender_name, seed))
    return {
        "name": name,
        "input": {**KEYS, "prologue": PROLOGUE, "rekeyInterval": rekey_interval,
                  "handshakePayloads": [b"", msg2, msg3]},
        "expected": {
            "handshake": [struct.pack(">H", len(m)) + m for m in wire],
            "handshakeHash": i.ss.h,
            "initiatorStatic": public_key(KEYS["initStatic"]),
            "responderStatic": public_key(KEYS["respStatic"]),
            "messages": messages,
        },
    }


def error_case(name: str, description: str, wire_after_handshake) -> dict:
    """Получатель-отвечающий читает поток инициатора после рукопожатия."""
    msg2, msg3 = b"hello-2", b"hello-3"
    _, i, r = run_handshake(KEYS["initStatic"], KEYS["initEphemeral"],
                            KEYS["respStatic"], KEYS["respEphemeral"],
                            PROLOGUE, [b"", msg2, msg3])
    i_send, _ = i.ciphers()
    _, r_recv = r.ciphers()
    wire = wire_after_handshake(Sender(i_send, REKEY_INTERVAL))
    result = Receiver(r_recv, REKEY_INTERVAL).read(wire)
    assert isinstance(result, str), name
    return {
        "name": name,
        "description": description,
        "input": {**KEYS, "prologue": PROLOGUE, "rekeyInterval": REKEY_INTERVAL,
                  "handshakePayloads": [b"", msg2, msg3], "initiatorWire": wire},
        "expected": {"error": result},
    }


def frames_cases() -> list:
    hello2 = splitmix64_bytes(2, 300)
    hello3 = splitmix64_bytes(3, 280)
    big = splitmix64_bytes(10, 200_000)
    largest = splitmix64_bytes(11, MAX_APP_MESSAGE)
    one_frame = splitmix64_bytes(12, MAX_PLAINTEXT - 4)
    two_frames = splitmix64_bytes(13, MAX_PLAINTEXT - 3)
    cases = [
        frames_case("messages", REKEY_INTERVAL, [
            ("initiator", b"", None),
            ("responder", bytes.fromhex("08011a0408011001"), None),
            ("initiator", splitmix64_bytes(1, 100), None),
            ("initiator", one_frame, 12),
            ("responder", two_frames, 13),
            ("initiator", big, 10),
            ("responder", largest, 11),
        ], hello2, hello3),
        frames_case("rekey", 2, [
            ("initiator", bytes([n]) * (n + 1), None) for n in range(5)
        ] + [
            ("responder", bytes([0x80 + n]) * 3, None) for n in range(3)
        ] + [
            ("initiator", splitmix64_bytes(20, 3 * MAX_PLAINTEXT), 20),
        ], hello2, hello3),
    ]

    def too_large(s: Sender) -> bytes:
        return s.frame(struct.pack(">I", MAX_APP_MESSAGE + 1) + b"x" * 100)

    def tampered(s: Sender) -> bytes:
        w = bytearray(s.message(b"payload"))
        w[-1] ^= 1
        return bytes(w)

    def short_frame(s: Sender) -> bytes:
        return struct.pack(">H", 15) + bytes(15)

    def truncated(s: Sender) -> bytes:
        return s.message(b"payload")[:-3]

    def partial_app(s: Sender) -> bytes:
        return s.frame(struct.pack(">I", 10) + b"abc")

    def reordered(s: Sender) -> bytes:
        a, b = s.message(b"first"), s.message(b"second")
        return b + a

    cases += [
        error_case("app-message-too-large",
                   "длина кадра приложения 1 МиБ + 1", too_large),
        error_case("tampered-frame", "испорчен последний байт тега", tampered),
        error_case("transport-frame-shorter-than-tag",
                   "транспортный кадр короче тега (15 байт)", short_frame),
        error_case("truncated-transport-frame",
                   "поток оборван внутри транспортного кадра", truncated),
        error_case("truncated-app-message",
                   "поток оборван внутри кадра приложения", partial_app),
        error_case("reordered-frames",
                   "транспортные кадры переставлены: nonce не тот", reordered),
    ]
    return cases


# --- запись -------------------------------------------------------------------

def hexify(value):
    if isinstance(value, bytes):
        return value.hex()
    if isinstance(value, dict):
        return {k: hexify(v) for k, v in value.items()}
    if isinstance(value, list):
        return [hexify(v) for v in value]
    return value


def write_json(name: str, data: dict) -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    with open(os.path.join(OUT_DIR, name), "w", encoding="utf-8") as f:
        json.dump(hexify(data), f, ensure_ascii=False, indent=2)
        f.write("\n")


def main() -> None:
    if len(sys.argv) == 3 and sys.argv[1] == "--cacophony":
        import_cacophony(sys.argv[2])
    elif len(sys.argv) != 1:
        sys.exit(__doc__)
    check_cacophony()
    write_json("noise-frames.json", {
        "spec": "protocol/noise-frames",
        "specVersion": 1,
        "generator": GENERATOR,
        "description": (
            "Канал Noise (protocol.md, разделы 3.1, 3.3): рукопожатие XX с "
            "фиксированными закрытыми ключами X25519 (статическими и эфемерными) и "
            "прологом fs/v1/noise, затем кадры приложения. handshake — три "
            "транспортных кадра рукопожатия (u16be длина || сообщение Noise), "
            "handshakePayloads — их полезные нагрузки (в протоколе — Hello; здесь "
            "произвольные байты). messages — сообщения приложения по порядку "
            "отправки: from — отправитель, message — тело PeerMessage (байты или "
            "splitmix64-le, docs/spec/test-vectors.md), wire — транспортные кадры "
            "отправителя (u32be длина || тело, нарезанные по 65 519 байт), для "
            "длинных — wireLength и wireHash (BLAKE2b-256), transportFrames — "
            "число транспортных кадров. "
            "rekeyInterval — через сколько сообщений в направлении вызывается Rekey "
            "(в протоколе 65 536; 2 — чтобы смена ключей была видна). Случаи с "
            "initiatorWire — поток инициатора после рукопожатия, который отвечающий "
            "должен отклонить: error format (длины, обрыв) или integrity (тег)."),
        "cases": frames_cases(),
    })


if __name__ == "__main__":
    main()
