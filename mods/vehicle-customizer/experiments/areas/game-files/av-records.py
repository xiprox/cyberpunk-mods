"""Every AV among TweakDB's vehicle records, grouped by model, with the ones on the garage list marked."""
import collections
import os
import re
import struct
import sys
import zlib

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "..", "..", "tools"))
import rdar

HERE = os.path.dirname(os.path.abspath(__file__))
data = open(os.path.join(rdar.GAME, r"r6\cache\tweakdb_ep1.bin"), "rb").read()


def tid(name):
    return zlib.crc32(name.encode()) | (len(name) << 32)


names = []
with open(os.path.join(HERE, "data", "tweakdb-names.txt"), encoding="utf-8") as f:
    for line in f:
        kind, name = line.rstrip("\n").split("\t", 1)
        if kind == "record":
            names.append(name)
by_id = {tid(n): n for n in names}
off = struct.unpack_from("<8I", data, 0)[5]
types = {}
for i in range(struct.unpack_from("<I", data, off)[0]):
    rid, thash = struct.unpack_from("<QI", data, off + 4 + i * 12)
    types[rid & 0xFFFFFFFFFF] = thash
vt = types[tid("Vehicle.v_standard2_archer_hella")]
avs = sorted(by_id[r] for r, t in types.items() if t == vt and r in by_id and re.search(r"(^Vehicle\.av_|_av_|_av$)", by_id[r]))
print("AV records:", len(avs))
models = collections.defaultdict(list)
for a in avs:
    m = re.match(r"^Vehicle\.av_([a-z]+)_([a-z0-9]+)", a)
    models[f"{m.group(1)}_{m.group(2)}" if m else "(quest or scene) " + a.split(".")[1].split("_av")[0]].append(a)
for model, records in sorted(models.items()):
    print(f"  {model:34s} {len(records):3d}  {records[:4]}")
