"""Distinct car and bike models among TweakDB's vehicle records, and which have no record the garage can own.
A model here is maker and name taken from the record name (archer_hella, arch_nemesis), so variants such as
courier, police or nomad fold into their model."""
import collections
import os
import re
import struct
import sys
import zlib

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "..", "..", "tools"))
import rdar

HERE = os.path.dirname(os.path.abspath(__file__))
DB = os.path.join(rdar.GAME, r"r6\cache\tweakdb_ep1.bin")


def tid(name):
    return zlib.crc32(name.encode()) | (len(name) << 32)


names = []
with open(os.path.join(HERE, "data", "tweakdb-names.txt"), encoding="utf-8") as f:
    for line in f:
        kind, name = line.rstrip("\n").split("\t", 1)
        if kind == "record":
            names.append(name)
by_id = {tid(n): n for n in names}
data = open(DB, "rb").read()
records_off = struct.unpack_from("<8I", data, 0)[5]
count = struct.unpack_from("<I", data, records_off)[0]
types = {}
for i in range(count):
    rid, thash = struct.unpack_from("<QI", data, records_off + 4 + i * 12)
    types[rid & 0xFFFFFFFFFF] = thash
vt = types[tid("Vehicle.v_standard2_archer_hella")]
vehicles = [by_id[r] for r, t in types.items() if t == vt and r in by_id]

# The garage list, found as in vehicle-records.py.
hella = tid("Vehicle.v_standard2_archer_hella_player")
ids = {tid(v) for v in vehicles}
at = data.find(struct.pack("<Q", hella)[:5])
best = []
while at >= 0:
    lo = at
    while (struct.unpack_from("<Q", data, lo - 8)[0] & 0xFFFFFFFFFF) in ids:
        lo -= 8
    hi = at
    while (struct.unpack_from("<Q", data, hi + 8)[0] & 0xFFFFFFFFFF) in ids:
        hi += 8
    run = [by_id[struct.unpack_from("<Q", data, lo + k * 8)[0] & 0xFFFFFFFFFF] for k in range((hi - lo) // 8 + 1)]
    if len(run) > len(best):
        best = run
    at = data.find(struct.pack("<Q", hella)[:5], at + 1)
ownable = set(best)

MODEL = re.compile(r"^Vehicle\.v_(standard\d*|sport\d*|utility\d*|sportbike\d*)_([a-z]+)_([a-z0-9]+)")
SPECIAL = re.compile(r"^Vehicle\.v_([a-z]+)_([a-z0-9]+)")
models = collections.defaultdict(lambda: {"records": [], "ownable": []})
for v in vehicles:
    m = MODEL.match(v)
    if m:
        key = ("bike" if "sportbike" in m.group(1) else "car", f"{m.group(2)}_{m.group(3)}")
    else:
        s = SPECIAL.match(v)
        if not s:
            continue
        key = ("special", f"{s.group(1)}_{s.group(2)}")
    models[key]["records"].append(v)
    if v in ownable:
        models[key]["ownable"].append(v)

for kind in ("car", "bike", "special"):
    group = {k: m for k, m in models.items() if k[0] == kind}
    own = {k for k, m in group.items() if m["ownable"]}
    print(f"\n{kind}: {len(group)} models, {len(own)} with an ownable record, {len(group) - len(own)} without")
    for k, m in sorted(group.items()):
        flag = "owned " if m["ownable"] else "never "
        print(f"  {flag} {k[1]:28s} records {len(m['records']):3d}  e.g. {sorted(m['records'])[:3]}")

print(f"\nownable records not matched to a model: {sorted(ownable - {v for m in models.values() for v in m['records']})}")
