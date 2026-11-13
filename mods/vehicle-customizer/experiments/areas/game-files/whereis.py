"""Where things stand in the world: every placement of a node whose files match a pattern, or every node
within a radius of a point. Uses data/sectors.json (sectors.py) and the node data layout in garages.py.

  python -I whereis.py <regex>              placements of nodes using matching files
  python -I whereis.py <x> <y> <z> <radius> nodes placed near a point
"""
import math
import os
import re
import struct
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "..", "..", "tools"))
import json

import pkg

HERE = os.path.dirname(os.path.abspath(__file__))
D = json.load(open(os.path.join(HERE, "data", "sectors.json"), encoding="utf-8"))
DIR = "base\\worlds\\03_night_city\\_compiled\\default\\"
depot = pkg.Depot()


def refs_in(obj, exports, depth=0):
    out = []
    for v in obj.values():
        if isinstance(v, tuple) and v[0] == "ref" and v[1]:
            out.append(v[1].lower())
        elif isinstance(v, tuple) and v[0] == "export" and depth == 0 and 0 < v[1] <= len(exports):
            out += refs_in(exports[v[1] - 1][1], exports, 1)
    return out


def node_data(bufs, n_nodes):
    for b in bufs:
        if not b or len(b) % 144:
            continue
        n = len(b) // 144
        ok = sum(1 for r in range(n)
                 if struct.unpack_from("<H", b, r * 144 + 112)[0] < n_nodes
                 and abs(sum(x * x for x in struct.unpack_from("<4f", b, r * 144 + 16)) - 1) < 0.05)
        if ok >= 0.95 * n:
            return b
    return None


def placements(sector):
    loaded = depot.load(DIR + sector["name"] + ".streamingsector")
    if not loaded:
        return
    head, bufs = loaded
    try:
        c = pkg.Cooked(head, bufs, depot)
    except Exception:
        return  # a handful of sectors don't read (19 of 4,558 in garages.py); skip them

    nodes = [(cls, obj) for cls, obj in c.exports if cls.startswith("world") and "Node" in cls]
    nd = node_data(bufs, len(nodes))
    if nd is None:
        return
    for r in range(len(nd) // 144):
        o = r * 144
        ni = struct.unpack_from("<H", nd, o + 112)[0]
        if ni >= len(nodes):
            continue
        pos = struct.unpack_from("<3f", nd, o)
        if pos == (0.0, 0.0, 0.0):
            lo = struct.unpack_from("<3f", nd, o + 56)
            hi = struct.unpack_from("<3f", nd, o + 68)
            pos = tuple((a + b) / 2 for a, b in zip(lo, hi))
        cls, obj = nodes[ni]
        yield cls, obj.get("debugName"), refs_in(obj, c.exports), pos


def main():
    args = sys.argv[1:]
    if len(args) == 4:
        x, y, z, radius = map(float, args)
        for s in D["sectors"]:
            lo, hi = s["min"], s["max"]
            # Quest sectors have boundless boxes; reading all 2,400 of them took one run to 74 GB of memory
            # (2026-11-06), so a radius search skips any box wider than 5 km.
            if hi[0] - lo[0] > 5000 or hi[1] - lo[1] > 5000:
                continue
            if not (lo[0] - radius <= x <= hi[0] + radius and lo[1] - radius <= y <= hi[1] + radius):
                continue
            for cls, dbg, refs, pos in placements(s):
                d = math.dist(pos, (x, y, z))
                if d <= radius:
                    print(f"{d:6.1f} m ({pos[0]:8.1f},{pos[1]:8.1f},{pos[2]:6.1f}) {s['cat']:8s} {cls:36s} {dbg or ''} "
                          f"{' '.join(r.rsplit(chr(92), 1)[-1] for r in refs[:2])} variants={s.get('variants', [])[:4]}")
        return
    rx = re.compile(args[0], re.I)
    ids = {i for i, p in enumerate(D["paths"]) if rx.search(p)}
    for s in D["sectors"]:
        if not ids.intersection(s.get("uses", [])):
            continue
        for cls, dbg, refs, pos in placements(s):
            hits = [r for r in refs if rx.search(r)]
            if hits:
                print(f"({pos[0]:8.1f},{pos[1]:8.1f},{pos[2]:6.1f}) {s['cat']:8s} {s['name']:28s} {cls:30s} {dbg or ''} "
                      f"{hits[0].rsplit(chr(92), 1)[-1]} variants={s.get('variants', [])[:4]}")


main()
