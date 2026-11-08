"""Every vehicle record in TweakDB, which of them the garage can own, and what kinds they are.
Needs data/tweakdb-names.txt from tweakdb_names.py."""
import collections
import os
import re
import struct
import sys
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rdar

HERE = os.path.dirname(os.path.abspath(__file__))
DB = os.path.join(rdar.GAME, r"r6\cache\tweakdb_ep1.bin")


def tid(name):
    return zlib.crc32(name.encode()) | (len(name) << 32)


records = []
with open(os.path.join(HERE, "data", "tweakdb-names.txt"), encoding="utf-8") as f:
    for line in f:
        kind, name = line.rstrip("\n").split("\t", 1)
        if kind == "record":
            records.append(name)
by_id = {tid(n): n for n in records}

data = open(DB, "rb").read()
magic, blob_version, parser_version, checksum, flats_off, records_off, queries_off, tags_off = struct.unpack_from("<8I", data, 0)
print(f"magic 0x{magic:08x} blob {blob_version} parser {parser_version} records at {records_off}")
count = struct.unpack_from("<I", data, records_off)[0]
types = {}
for i in range(count):
    rid, thash = struct.unpack_from("<QI", data, records_off + 4 + i * 12)
    types[rid & 0xFFFFFFFFFF] = thash
named = sum(1 for r in types if r in by_id)
print(f"records in the table: {count}, with a known name: {named}")

vehicle_type = types[tid("Vehicle.v_standard2_archer_hella")]
vehicles = sorted(by_id[r] for r, t in types.items() if t == vehicle_type and r in by_id)
print(f"vehicle records (same record type as Vehicle.v_standard2_archer_hella): {len(vehicles)}")

# The garage's list: the array of record ids holding V's Hella whose members are all vehicles.
hella = tid("Vehicle.v_standard2_archer_hella_player")
vehicle_ids = {tid(v) for v in vehicles}
best = []
pattern = struct.pack("<Q", hella)[:5]
start = 0
while True:
    at = data.find(pattern, start)
    if at < 0:
        break
    start = at + 1
    lo = at
    while lo - 8 >= 0 and (struct.unpack_from("<Q", data, lo - 8)[0] & 0xFFFFFFFFFF) in vehicle_ids:
        lo -= 8
    hi = at
    while hi + 8 <= len(data) and (struct.unpack_from("<Q", data, hi + 8)[0] & 0xFFFFFFFFFF) in vehicle_ids:
        hi += 8
    n = (hi - lo) // 8 + 1
    stated = struct.unpack_from("<I", data, lo - 4)[0]
    members = [by_id[struct.unpack_from("<Q", data, lo + k * 8)[0] & 0xFFFFFFFFFF] for k in range(n)]
    print(f"  an array holding V's Hella: {n} members, count before it says {stated}")
    if len(members) > len(best):
        best = members
ownable = set(best)
print(f"garage list (largest such array): {len(ownable)}")


def kind(name):
    n = name[len("Vehicle."):]
    if n.startswith("av_") or "_av_" in n:
        return "AV"
    if "sportbike" in n:
        return "bike"
    if any(k in n for k in ("monorail", "tram", "train", "metro")):
        return "train"
    if n.startswith(("v_standard", "v_sport", "v_utility")):
        return "car"
    return "other"


QUEST = re.compile(r"^Vehicle\.(q\d|sq\d|mq\d|ma_|mws_|cs_|dlc|test|debug)|(_quest|_scene|_dummy|_test|_debug|_static|_destroyed|_wreck|_crashed|_broken|_cutscene)")
rows = collections.Counter()
plain = collections.defaultdict(list)
for v in vehicles:
    k = kind(v)
    owned = v in ownable
    quest = bool(QUEST.search(v))
    rows[(k, "ownable" if owned else "not ownable", "quest or scene" if quest else "plain")] += 1
    if not owned and not quest:
        plain[k].append(v)
print("\n-- by kind --")
for key, n in sorted(rows.items()):
    print(f"  {key[0]:6s} {key[1]:12s} {key[2]:15s} {n}")

print("\n-- not ownable, not quest or scene, by kind (samples) --")
for k, names in sorted(plain.items()):
    print(f"  {k}: {len(names)}")
    for n in names[:14]:
        print(f"     {n}")

print("\n-- ownable records --")
print(sorted(ownable))
print("\n-- other kind, all --")
print([v for v in vehicles if kind(v) == "other"])
