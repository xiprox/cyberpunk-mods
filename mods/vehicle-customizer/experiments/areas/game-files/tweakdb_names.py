"""Record and flat names from CET's tweakdbstr.kark (Oodle compressed), saved to data/tweakdb-names.txt."""
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rdar

SRC = os.path.join(rdar.GAME, r"bin\x64\plugins\cyber_engine_tweaks\tweakdb\tweakdbstr.kark")
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data", "tweakdb-names.txt")

blob = open(SRC, "rb").read()
assert blob[:4] == b"KARK"
size = struct.unpack_from("<I", blob, 4)[0]
raw = rdar.kraken(blob[8:], size)
print("decompressed", len(raw), "bytes; first bytes", raw[:32].hex(" "))

# Layout as CET reads it: magic, version, then three counts (records, flats, queries), then
# length-prefixed strings in that order. Print what we see so a wrong guess shows.
magic, version, n_records, n_flats, n_queries = struct.unpack_from("<IIIII", raw, 0)
print(f"magic 0x{magic:08x} version {version} records {n_records} flats {n_flats} queries {n_queries}")
p = 20
names = []
kinds = [("record", n_records), ("flat", n_flats), ("query", n_queries)]
with open(OUT, "w", encoding="utf-8") as out:
    for kind, count in kinds:
        for _ in range(count):
            # RED's string length: first byte holds a sign bit (set: one byte a character), a
            # continuation bit and 6 bits of length; further bytes add 7 bits each.
            b = raw[p]
            p += 1
            narrow = bool(b & 0x80)
            length = b & 0x3F
            more = b & 0x40
            shift = 6
            while more:
                b = raw[p]
                p += 1
                length |= (b & 0x7F) << shift
                more = b & 0x80
                shift += 7
            if narrow:
                text = raw[p:p + length].decode("utf-8", "replace")
                p += length
            else:
                text = raw[p:p + 2 * length].decode("utf-16-le", "replace")
                p += 2 * length
            out.write(f"{kind}\t{text}\n")
            if kind == "record" and len(names) < 5:
                names.append(text)
print("first record names:", names, "ended at", p, "of", len(raw))
