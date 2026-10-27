#!/usr/bin/env python3
"""Генератор тестовых векторов для docs/spec/data-format.md.

Эталонная реализация спецификации на Python, независимая от кода на Dart.
Reed–Solomon реализован здесь же и перед генерацией сверяется с векторами
крейта reed-solomon-erasure (test-vectors/erasure/reed-solomon.json).

Запуск из корня репозитория (после tool/crypto_vectors.py):

    python3 -I tool/format_vectors.py
"""

import hashlib
import importlib.util
import json
import os
import struct

_spec = importlib.util.spec_from_file_location(
    "crypto_vectors", os.path.join("tool", "crypto_vectors.py"))
cv = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(cv)

OUT_DIR = os.path.join("test-vectors", "format")
GENERATOR = "tool/format_vectors.py (Python, независимая реализация)"

MIN, NORMAL, MAX = 512 * 1024, 1024 * 1024, 8 * 1024 * 1024
MASK_S = 0xFFFFFC0000000000
MASK_L = 0xFFFFC00000000000
U64 = 0xFFFFFFFFFFFFFFFF
SEGMENT_MAX = 16 * 1024 * 1024
SEGMENT_ALIGN = 65536
BLOCK = 65536


def H(data: bytes) -> bytes:
    return hashlib.blake2b(data, digest_size=32).digest()


# --- FastCDC -----------------------------------------------------------------

def gear_table(gear_key: bytes) -> list:
    return [struct.unpack("<Q", cv.blake2b_keyed(gear_key, b"fs/v1/gear" + bytes([i]))[:8])[0]
            for i in range(256)]


def cut(data: bytes, start: int, gear: list) -> int:
    length = len(data) - start
    if length <= MIN:
        return length
    n = min(length, MAX)
    normal = min(NORMAL, n)
    fp = 0
    i = MIN
    while i < normal:
        fp = ((fp << 1) + gear[data[start + i]]) & U64
        if fp & MASK_S == 0:
            return i + 1
        i += 1
    while i < n:
        fp = ((fp << 1) + gear[data[start + i]]) & U64
        if fp & MASK_L == 0:
            return i + 1
        i += 1
    return n


def chunk_lengths(data: bytes, gear: list) -> list:
    out, pos = [], 0
    while pos < len(data):
        size = cut(data, pos, gear)
        out.append(size)
        pos += size
    return out


def expected_average() -> float:
    """Ожидаемая длина чанка на случайных данных (аналитически)."""
    p1, p2 = 2.0 ** -22, 2.0 ** -18
    m1, m2 = NORMAL - MIN, MAX - NORMAL
    no_cut_1 = (1 - p1) ** m1
    e1 = (1 - no_cut_1) / p1
    e2 = (1 - (1 - p2) ** m2) / p2
    return MIN + e1 + no_cut_1 * e2


# --- Сегмент -------------------------------------------------------------------

def segment_plaintext(chunks: list) -> bytes:
    """chunks: список (chunk_id, тип, данные)."""
    data_length = sum(len(c[2]) for c in chunks)
    out = bytearray(b"FSSG" + bytes([1, 0, 0, 0]) + struct.pack("<II", len(chunks), data_length))
    for chunk_id, kind, data in chunks:
        out += chunk_id + bytes([kind, 0, 0, 0]) + struct.pack("<I", len(data))
    for _, _, data in chunks:
        out += data
    out += bytes((-len(out)) % SEGMENT_ALIGN)
    assert len(out) <= SEGMENT_MAX
    return bytes(out)


# --- Reed–Solomon (как в reed-solomon-erasure, galois_8) ------------------------

EXP = [0] * 510
LOG = [0] * 256
_x = 1
for _i in range(255):
    EXP[_i] = EXP[_i + 255] = _x
    LOG[_x] = _i
    _x <<= 1
    if _x & 0x100:
        _x ^= 0x11D


def gmul(a: int, b: int) -> int:
    return 0 if a == 0 or b == 0 else EXP[LOG[a] + LOG[b]]


def gdiv(a: int, b: int) -> int:
    return 0 if a == 0 else EXP[(LOG[a] - LOG[b]) % 255]


def gpow(a: int, n: int) -> int:
    if n == 0:
        return 1
    return 0 if a == 0 else EXP[(LOG[a] * n) % 255]


def mat_mul(a, b):
    return [[_dot(row, [b[i][c] for i in range(len(b))]) for c in range(len(b[0]))] for row in a]


def _dot(x, y):
    acc = 0
    for p, q in zip(x, y):
        acc ^= gmul(p, q)
    return acc


def mat_inv(m):
    n = len(m)
    w = [row[:] + [1 if i == j else 0 for j in range(n)] for i, row in enumerate(m)]
    for r in range(n):
        if w[r][r] == 0:
            swap = next(i for i in range(r + 1, n) if w[i][r] != 0)
            w[r], w[swap] = w[swap], w[r]
        pivot = w[r][r]
        w[r] = [gdiv(v, pivot) for v in w[r]]
        for o in range(n):
            if o != r and w[o][r]:
                f = w[o][r]
                w[o] = [v ^ gmul(f, pv) for v, pv in zip(w[o], w[r])]
    return [row[n:] for row in w]


def encoding_matrix(k: int, n: int):
    v = [[gpow(r, c) for c in range(k)] for r in range(n)]
    return mat_mul(v, mat_inv(v[:k]))


def rs_encode(data_shards: list, n: int) -> list:
    k = len(data_shards)
    m = encoding_matrix(k, n)
    size = len(data_shards[0])
    parity = []
    for r in range(k, n):
        out = bytearray(size)
        for c in range(k):
            coef = m[r][c]
            if coef == 0:
                continue
            table = bytes(gmul(coef, b) for b in range(256))
            src = data_shards[c]
            out = bytearray(x ^ y for x, y in zip(out, src.translate(table)))
        parity.append(bytes(out))
    return list(data_shards) + parity


def check_rs_against_crate() -> None:
    with open(os.path.join("test-vectors", "erasure", "reed-solomon.json"), encoding="utf-8") as f:
        vectors = json.load(f)
    for case in vectors["cases"]:
        k, n = case["input"]["dataShards"], case["input"]["totalShards"]
        if n > 64:
            continue  # без больших случаев: чистый Python медленный
        data = [bytes.fromhex(h) for h in case["input"]["data"]]
        shards = rs_encode(data, n)
        assert [s.hex() for s in shards[k:]] == case["expected"]["parity"], case["name"]


# --- Фрагменты и дерево Меркла --------------------------------------------------

def merkle_root(body: bytes) -> bytes:
    leaves = [H(b"\x00" + body[i:i + BLOCK]) for i in range(0, len(body), BLOCK)]

    def mth(nodes):
        if len(nodes) == 1:
            return nodes[0]
        j = 1
        while j * 2 < len(nodes):
            j *= 2
        return H(b"\x01" + mth(nodes[:j]) + mth(nodes[j:]))

    return mth(leaves)


def merkle_leaves(body: bytes) -> list:
    return [H(b"\x00" + body[i:i + BLOCK]) for i in range(0, len(body), BLOCK)]


def mth(nodes: list) -> bytes:
    if len(nodes) == 1:
        return nodes[0]
    j = 1
    while j * 2 < len(nodes):
        j *= 2
    return H(b"\x01" + mth(nodes[:j]) + mth(nodes[j:]))


def audit_path(m: int, nodes: list) -> list:
    """PATH(m, D[n]) из RFC 6962, раздел 2.1.1: от листа к корню."""
    if len(nodes) == 1:
        return []
    j = 1
    while j * 2 < len(nodes):
        j *= 2
    if m < j:
        return audit_path(m, nodes[:j]) + [mth(nodes[j:])]
    return audit_path(m - j, nodes[j:]) + [mth(nodes[:j])]


def verify_audit_path(root: bytes, n: int, m: int, block: bytes, path: list) -> bool:
    """Проверка по определению: корень, собранный от листа по PATH."""
    if not 0 <= m < n:
        return False
    try:
        expected = audit_path(m, [b"?" * 32] * n)
    except RecursionError:
        return False
    if len(path) != len(expected):
        return False

    def rebuild(m, lo, hi, it):
        if hi - lo == 1:
            return H(b"\x00" + block)
        j = 1
        while j * 2 < hi - lo:
            j *= 2
        if m < j:
            left = rebuild(m, lo, lo + j, it)
            return H(b"\x01" + left + next(it))
        right = rebuild(m - j, lo + j, hi, it)
        return H(b"\x01" + next(it) + right)

    return rebuild(m, 0, n, iter(path)) == root


def shard_size_for(blob_length: int, k: int) -> int:
    per = -(-blob_length // k)
    return -(-per // 64) * 64


def fragments(blob: bytes, segment_id: bytes, k: int, n: int) -> list:
    size = shard_size_for(len(blob), k)
    padded = blob + bytes(k * size - len(blob))
    shards = rs_encode([padded[i * size:(i + 1) * size] for i in range(k)], n)
    out = []
    for index, body in enumerate(shards):
        root = merkle_root(body)
        header = (b"FSFR" + bytes([1, 1, k, n, index, 16, 0, 0])
                  + struct.pack("<II", len(blob), size) + segment_id + root + bytes(12))
        assert len(header) == 96
        out.append((header, body))
    return out


def check_fragment(data: bytes, expected_id) -> str:
    """Эталонная проверка фрагмента (раздел 5): None, 'format' или 'integrity'."""
    if len(data) < 96:
        return "format"
    h = data[:96]
    if h[0:4] != b"FSFR" or h[4] != 1 or h[5] != 1 or h[9] != 16:
        return "format"
    if h[10:12] != bytes(2) or h[84:96] != bytes(12):
        return "format"
    k, n, index = h[6], h[7], h[8]
    if not (1 <= k < n <= 255) or index >= n:
        return "format"
    blob_length, size = struct.unpack("<II", h[12:20])
    if size != shard_size_for(blob_length, k) or len(data) - 96 != size:
        return "format"
    if merkle_root(data[96:]) != h[52:84]:
        return "integrity"
    if expected_id is not None and H(h) != expected_id:
        return "integrity"
    return None


# --- Запись ------------------------------------------------------------------

def write(name: str, spec: str, description: str, cases: list, extra: dict = None) -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    doc = {"spec": spec, "specVersion": 1, "generator": GENERATOR, "description": description}
    if extra:
        doc.update(extra)
    doc["cases"] = cv.hexify(cases)
    with open(os.path.join(OUT_DIR, name), "w", encoding="utf-8") as f:
        json.dump(doc, f, ensure_ascii=False, indent=2)
        f.write("\n")


def main() -> None:
    check_rs_against_crate()
    root_keys = cv.derive_all(cv.bip39_seed(cv.load_trezor_24()[0][1]), bytes(range(32)))
    gear_key = root_keys["gearKey"]
    chunk_key = root_keys["chunkIdKey"]
    gear = gear_table(gear_key)

    write("gear.json", "format/gear", "Таблица gear FastCDC по ключу K_gear (data-format.md, раздел 2).",
          [{"name": "key-hierarchy-abandon", "input": {"gearKey": gear_key},
            "expected": {"gear": [f"{g:016x}" for g in gear]}}])

    # FastCDC
    cases = []
    inputs = [
        ("empty", cv.pattern(10, 0)),
        ("below-min", cv.pattern(11, 100_000)),
        ("exactly-min", cv.pattern(12, MIN)),
        ("min-plus-one", cv.pattern(13, MIN + 1)),
        ("random-24MiB", cv.pattern(14, 24 * 1024 * 1024)),
    ]
    for name, pat in inputs:
        data = cv.splitmix64_bytes(pat["seed"], pat["length"])
        lengths = chunk_lengths(data, gear)
        cases.append({"name": name, "input": {"gearKey": gear_key, "dataPattern": pat},
                      "expected": {"chunkLengths": lengths}})
    zeros = bytes(20 * 1024 * 1024)
    cases.append({"name": "zeros-20MiB",
                  "input": {"gearKey": gear_key, "dataZeros": len(zeros)},
                  "expected": {"chunkLengths": chunk_lengths(zeros, gear)}})
    write("fastcdc.json", "format/fastcdc",
          "Границы чанков FastCDC (data-format.md, раздел 2). dataPattern — генератор splitmix64-le, "
          "dataZeros — столько нулевых байт.", cases,
          {"expectedAverageChunkLength": round(expected_average())})

    # Сегмент
    chunk_specs = [(20, 1000, 1), (21, 70000, 1), (22, 1, 2), (23, 300000, 1)]
    chunks = []
    for seed, length, kind in chunk_specs:
        data = cv.splitmix64_bytes(seed, length)
        chunks.append((cv.blake2b_keyed(chunk_key, data), kind, data))
    plain = segment_plaintext(chunks)
    segment_id = bytes(range(0x80, 0xA0))
    nonce = bytes(range(0x50, 0x68))
    seg_key = cv.hkdf(root_keys["dataKey"], b"", b"fs/v1/segment" + segment_id)
    blob = cv.blob(1, segment_id, nonce, seg_key, plain)
    seg_case = {
        "name": "four-chunks",
        "input": {
            "chunkIdKey": chunk_key,
            "chunks": [{"dataPattern": cv.pattern(s, l), "type": t} for s, l, t in chunk_specs],
            "segmentId": segment_id, "nonce": nonce, "dataKey": root_keys["dataKey"],
        },
        "expected": {
            "chunkIds": [c[0] for c in chunks],
            "header": plain[:16 + 40 * len(chunks)],
            "plaintextLength": len(plain), "plaintextHash": H(plain),
            "blobLength": len(blob), "blobHash": H(blob),
        },
    }
    rejects = []
    small = segment_plaintext([(bytes(32), 1, b"x")])

    def reject(name, patch=None, truncate=None):
        data = small
        change = {}
        if patch is not None:
            offset, replacement = patch
            data = data[:offset] + replacement + data[offset + len(replacement):]
            change["patch"] = {"offset": offset, "bytes": replacement}
        if truncate is not None:
            data = data[:truncate]
            change["truncate"] = truncate
        rejects.append({"name": "reject-" + name, "input": {"base": "minimal", **change},
                        "expected": {"error": "format"}})

    reject("bad-magic", patch=(0, b"FSSX"))
    reject("unknown-version", patch=(4, b"\x02"))
    reject("nonzero-reserved", patch=(5, b"\x01"))
    reject("zero-count", patch=(8, struct.pack("<I", 0)))
    reject("unknown-type", patch=(16 + 32, b"\x03"))
    reject("data-length-mismatch", patch=(12, struct.pack("<I", 2)))
    reject("nonzero-padding", patch=(len(small) - 1, b"\x01"))
    reject("unaligned-length", truncate=len(small) - 1)
    write("segment.json", "format/segment",
          "Открытый текст сегмента и блоб (data-format.md, раздел 3). Большие результаты заданы "
          "длиной и хэшем BLAKE2b-256. Отклоняемые сегменты строятся из минимального "
          "(base = minimal: один чанк типа 1 с chunk_id из 32 нулей и содержимым \"x\") "
          "правкой patch (заменить байты с offset) или обрезкой truncate (оставить столько байт).",
          [seg_case] + rejects, {"minimalSegment": {"length": len(small), "hash": H(small).hex()}})

    # Дерево Меркла
    cases = []
    for name, seed, length in [("one-block-64", 30, 64), ("exactly-one-block", 31, BLOCK),
                               ("two-blocks-short-tail", 32, BLOCK + 1),
                               ("three-blocks", 33, 3 * BLOCK),
                               ("five-blocks", 34, 4 * BLOCK + 128),
                               ("1MiB", 35, 16 * BLOCK)]:
        body = cv.splitmix64_bytes(seed, length)
        cases.append({"name": name, "input": {"bodyPattern": cv.pattern(seed, length)},
                      "expected": {"root": merkle_root(body)}})
    write("merkle.json", "format/merkle", "Корень дерева Меркла тела фрагмента (data-format.md, раздел 5).",
          cases)

    # Путь аудита (protocol.md, раздел 4.13)
    cases = []
    bodies = {}
    for name, seed, length, indexes in [("one-block", 50, 64, [0]),
                                        ("two-blocks-short-tail", 51, BLOCK + 1, [0, 1]),
                                        ("three-blocks", 52, 3 * BLOCK, [0, 1, 2]),
                                        ("five-blocks", 53, 4 * BLOCK + 128, [0, 3, 4]),
                                        ("seven-blocks", 54, 7 * BLOCK - 64, [0, 2, 5, 6]),
                                        ("16MiB", 55, 256 * BLOCK, [0, 77, 128, 255])]:
        body = cv.splitmix64_bytes(seed, length)
        bodies[name] = (seed, length, body)
        leaves = merkle_leaves(body)
        root = mth(leaves)
        for m in indexes:
            block = body[m * BLOCK:(m + 1) * BLOCK]
            path = audit_path(m, leaves)
            assert verify_audit_path(root, len(leaves), m, block, path)
            cases.append({"name": f"{name}-block-{m}",
                          "input": {"bodyPattern": cv.pattern(seed, length), "index": m},
                          "expected": {"leafCount": len(leaves), "blockLength": len(block),
                                       "blockHash": H(block), "path": path, "root": root}})

    def audit_reject(name, base, m, path_edit=None, block_index=None, index=None):
        seed, length, body = bodies[base]
        leaves = merkle_leaves(body)
        root = mth(leaves)
        path = audit_path(m, leaves)
        if path_edit is not None:
            path = path_edit(path)
        b = m if block_index is None else block_index
        block = body[b * BLOCK:(b + 1) * BLOCK]
        claimed = m if index is None else index
        assert not verify_audit_path(root, len(leaves), claimed, block, path), name
        case = {"bodyPattern": cv.pattern(seed, length), "index": claimed, "path": path}
        if block_index is not None:
            case["blockIndex"] = block_index
        cases.append({"name": name, "input": case, "expected": {"error": "integrity"}})

    flip = lambda p: [bytes([p[0][0] ^ 1]) + p[0][1:]] + p[1:]
    audit_reject("reject-flipped-path", "five-blocks", 3, path_edit=flip)
    audit_reject("reject-other-block", "five-blocks", 3, block_index=2)
    audit_reject("reject-wrong-index", "seven-blocks", 2, index=3)
    audit_reject("reject-short-path", "seven-blocks", 5, path_edit=lambda p: p[:-1])
    audit_reject("reject-long-path", "three-blocks", 2, path_edit=lambda p: p + [p[-1]])
    audit_reject("reject-swapped-path", "16MiB", 77, path_edit=lambda p: [p[1], p[0]] + p[2:])
    audit_reject("reject-index-out-of-range", "three-blocks", 2, index=3)
    write("merkle-audit.json", "format/merkle-audit",
          "Путь аудита в дереве Меркла тела (RFC 6962, PATH; protocol.md, раздел 4.13): тело "
          "bodyPattern, блок index (64 КиБ, последний короче), путь от листа к корню. Случаи "
          "reject-*: блок blockIndex (по умолчанию index), заявленный номер index и путь path "
          "не дают корень тела.", cases)

    # Фрагменты: тот же сегмент, k=4, n=6 и k=10, n=16
    cases = []
    for k, n in [(4, 6), (10, 16)]:
        frs = fragments(blob, segment_id, k, n)
        cases.append({
            "name": f"four-chunks-k{k}-n{n}",
            "input": {"segmentCase": "four-chunks", "k": k, "n": n},
            "expected": {
                "shardSize": shard_size_for(len(blob), k),
                "fragments": [{"header": h, "bodyRoot": merkle_root(b), "bodyHash": H(b),
                               "fragmentId": H(h)} for h, b in frs],
            },
        })
    # Проверка фрагмента (раздел 5): минимальный фрагмент и его порча.
    small_blob = cv.splitmix64_bytes(40, 200)
    small_id = bytes(range(0xC0, 0xE0))
    small = fragments(small_blob, small_id, 2, 3)
    minimal = small[0][0] + small[0][1]
    other_id = H(small[1][0])

    def frag_case(name, error, patch=None, truncate=None, expected_id=None):
        data = bytearray(minimal)
        if patch is not None:
            offset, value = patch
            data[offset:offset + len(value)] = value
        if truncate is not None:
            data = data[:truncate]
        case = {"base": "minimal"}
        if patch is not None:
            case["patch"] = {"offset": patch[0], "bytes": patch[1]}
        if truncate is not None:
            case["truncate"] = truncate
        if expected_id is not None:
            case["expectedFragmentId"] = expected_id
        assert check_fragment(bytes(data), expected_id) == error, name
        cases.append({"name": name, "input": case,
                      "expected": {"error": error} if error else {"ok": True}})

    frag_case("verify-minimal", None, expected_id=H(small[0][0]))
    frag_case("reject-bad-magic", "format", patch=(0, b"FSFX"))
    frag_case("reject-unknown-version", "format", patch=(4, b"\x02"))
    frag_case("reject-unknown-scheme", "format", patch=(5, b"\x02"))
    frag_case("reject-k-not-below-n", "format", patch=(6, b"\x03"))
    frag_case("reject-zero-k", "format", patch=(6, b"\x00"))
    frag_case("reject-index-out-of-range", "format", patch=(8, b"\x03"))
    frag_case("reject-block-log2", "format", patch=(9, b"\x0f"))
    frag_case("reject-nonzero-reserved", "format", patch=(10, b"\x01"))
    frag_case("reject-nonzero-reserved-tail", "format", patch=(95, b"\x01"))
    frag_case("reject-shard-size-mismatch", "format", patch=(16, struct.pack("<I", 192)))
    frag_case("reject-blob-length-mismatch", "format", patch=(12, struct.pack("<I", 400)))
    frag_case("reject-truncated-body", "format", truncate=len(minimal) - 1)
    frag_case("reject-truncated-header", "format", truncate=95)
    frag_case("reject-flipped-body", "integrity", patch=(96 + 5, bytes([minimal[101] ^ 1])))
    frag_case("reject-flipped-root", "integrity", patch=(52, bytes([minimal[52] ^ 1])))
    frag_case("reject-foreign-fragment", "integrity", expected_id=other_id)

    write("fragment.json", "format/fragment",
          "Блоб сегмента из segment.json (случай four-chunks) → n фрагментов (data-format.md, "
          "разделы 4–5). Тела заданы хэшем BLAKE2b-256. Случаи verify-* и reject-* — проверка "
          "фрагмента: base = minimal (фрагмент 0 из k = 2, n = 3 блоба 200 байт, поле "
          "minimalFragment), правка patch или обрезка truncate; expectedFragmentId — ожидаемый "
          "идентификатор (по индексу или талону), если задан.", cases,
          extra={"minimalFragment": {"bytes": minimal.hex(), "fragmentId": H(small[0][0]).hex()}})

    print(f"Средняя длина чанка (расчёт): {expected_average():.0f} байт")
    lengths = next(c for c in json.load(open(os.path.join(OUT_DIR, "fastcdc.json")))["cases"]
                   if c["name"] == "random-24MiB")["expected"]["chunkLengths"]
    print(f"random-24MiB: {len(lengths)} чанков, средняя длина {sum(lengths) / len(lengths):.0f}")


if __name__ == "__main__":
    main()
