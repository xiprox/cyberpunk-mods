"""Which nodes each quest switch (variant) of a world sector holds, and whether it starts on or off.
For seeing what a gig's TogglePrefabVariant nodes show and hide (questgraph.py prints those).

  python -I sector-variants.py <sector-name> [regex on variant name or prefab path]

Sector names are in data/sectors.json (sectors.py), with the names of their variants. The streaming block gives each
variant a range index and its default; the sector's own native data, after its properties, ends with a byte count N,
N u32 starts of ranges into the node data (the first 0, the nodes always there), and 4 more bytes. Big low-detail
sectors (such as exterior_-5_8_0_2) don't read with pkg.py yet."""
import os
import re
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pkg

name = sys.argv[1]
flt = re.compile(sys.argv[2], re.I) if len(sys.argv) > 2 else None
DIR = "base\\worlds\\03_night_city\\_compiled\\default\\"
depot = pkg.Depot()
bh, bb = depot.load(DIR + "blocks\\all.streamingblock")
desc = next(d for d in pkg.Cooked(bh, bb, depot).exports[0][1]["descriptors"]
            if d["data"][1].rsplit("\\", 1)[-1] == name + ".streamingsector")
head, bufs = depot.load(DIR + name + ".streamingsector")
c = pkg.Cooked(head, bufs, depot)
off, _n, _ = c.c.tables[4]
_cls, _f, _p, size, data_off, _t, _crc = struct.unpack_from("<HHIIIII", head, off)
tail = head[data_off:data_off + size]
nd = bufs[0]
records = len(nd) // 144

starts = None
for N in range(1, 200):
    o = len(tail) - 4 - 4 * N - 1
    if o < 0:
        break
    if tail[o] != N:
        continue
    vals = list(struct.unpack_from(f"<{N}I", tail, o + 1))
    if vals[0] == 0 and all(a <= b for a, b in zip(vals, vals[1:])) and vals[-1] < records:
        starts = vals
        break
print("records", records, "range starts", starts)
if starts is None:
    sys.exit("no variant ranges found")
bounds = starts + [records]
nodes = [(cls, obj) for cls, obj in c.exports if cls.startswith("world") and "Node" in cls]


def refs_in(obj, depth=0):
    out = []
    for v in obj.values():
        if isinstance(v, tuple) and v[0] == "ref" and v[1]:
            out.append(v[1].lower())
        elif isinstance(v, tuple) and v[0] == "export" and depth == 0 and 0 < v[1] <= len(c.exports):
            out += refs_in(c.exports[v[1] - 1][1], 1)
    return out


for vv in desc.get("variants", []):
    ri = vv.get("rangeIndex", 0)
    vname = vv.get("name", "")
    if flt and not flt.search(vname + " " + vv.get("nodeRef", "")):
        continue
    print(f"\n-- {vname} (range {ri}, starts {'on' if vv.get('enabledByDefault') else 'off'}) {vv.get('nodeRef')}")
    for r in range(bounds[ri], bounds[ri + 1]):
        o = r * 144
        ni = struct.unpack_from("<H", nd, o + 112)[0]
        pos = struct.unpack_from("<3f", nd, o)
        if pos == (0.0, 0.0, 0.0):
            lo = struct.unpack_from("<3f", nd, o + 56)
            hi = struct.unpack_from("<3f", nd, o + 68)
            pos = tuple((a + b) / 2 for a, b in zip(lo, hi))
        cls, obj = nodes[ni] if ni < len(nodes) else ("?", {})
        print(f"   ({pos[0]:8.1f},{pos[1]:8.1f},{pos[2]:6.1f}) {cls:34s} {obj.get('debugName') or ''} "
              f"{' '.join(x.rsplit(chr(92), 1)[-1] for x in refs_in(obj)[:3])}")
