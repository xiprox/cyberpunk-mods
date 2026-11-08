"""Where garage-like things stand in the world: car lifts, tires, tools, picked-apart cars, mechanics
at work, big shutters. Reads data/sectors.json (from sectors.py), then each matching sector's
placements (the 144-byte node data records: position, rotation, scale, bounds, node index), groups
props within a few metres into sites, and notes what else is near each site: named locations,
quest-only sectors, people (AI spots, spawners). Writes data/garages.json and prints the best sites.

Node data layout (game 2.x, found by reading records): position xyz at 0, rotation quaternion at 16,
scale at 32, a streaming pivot at 44, bounds min at 56 and max at 68, node id at 80, node index
(u16) at 112, streaming distance at 120. The node index counts the sector's world*Node exports in
file order."""
import collections
import json
import math
import os
import re
import struct
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pkg

HERE = os.path.dirname(os.path.abspath(__file__))
SECTORS = os.path.join(HERE, "data", "sectors.json")
OUT = os.path.join(HERE, "data", "garages.json")
DIR = "base\\worlds\\03_night_city\\_compiled\\default\\"

KINDS = [
    ("lift", re.compile(r"activated_trap_car_lift")),
    ("mechanic", re.compile(r"workspots\\(garage\\|common\\car\\male__lie_creeper|common\\ground\\generic__lie_ground_car__repair"
                            r"|common\\car\\generic__stand_ground_lean_front_car_engine|common\\ground\\generic__kneel_ground_lean_front_screwdriver"
                            r"|main_characters\\panam\\panam__stand_car_lean_front__work)")),
    ("tires", re.compile(r"deco_tire_|tire_wheel_merged|decoration\\entities\\meshes\\tire_|pile_tires|tire_flat")),
    # not dest_workshop_tool*.effect: that breaking effect is shared by cable coils and much else
    ("tools", re.compile(r"decoration\\tools\\workshop\\.*\.mesh$|\\toolbox_[a-g]\.mesh$|medium_toolbox\.ent$|toolbox_small")),
    ("carparts", re.compile(r"picked_apart|deco_service_point|__deco_destroy_|burned_down")),
    ("shutter", re.compile(r"mall_shutter_w(600|650|900)|industrial_sliding_gate|metal_sliding_gate|shutter_window_w(550|600|900)")),
    # the far-away stand-in of a building whose name says garage or workshop
    ("building", re.compile(r"_external\\proxy\\\d+\\[^\\]*(garage|workshop)[^\\]*\.mesh$")),
]
LOC = re.compile(r"^(?:base|ep1)\\worlds\\03_night_city\\sectors\\(.+?)\\(loc_[^\\]+)")


def kind_of(path):
    for k, rx in KINDS:
        if rx.search(path):
            return k
    return None


D = json.load(open(SECTORS, encoding="utf-8"))
paths = D["paths"]
path_kind = {i: kind_of(p) for i, p in enumerate(paths)}
loc_of = {}
for i, p in enumerate(paths):
    m = LOC.match(p)
    if m:
        loc_of[i] = f"{m.group(1)}\\{m.group(2)}"
wanted = [s for s in D["sectors"] if any(path_kind.get(i) or i in loc_of for i in s.get("uses", []))]
print(f"{len(wanted)} sectors to read", flush=True)

depot = pkg.Depot()


def refs_in(obj, exports, depth=0):
    out = []
    for v in obj.values():
        if isinstance(v, tuple) and v[0] == "ref" and v[1]:
            out.append(v[1].lower())
        elif isinstance(v, tuple) and v[0] == "export" and depth == 0 and 0 < v[1] <= len(exports):
            out += refs_in(exports[v[1] - 1][1], exports, 1)  # CR2W handles count from 1
    return out


def node_data(bufs, n_nodes):
    for b in bufs:
        if not b or len(b) % 144:
            continue
        n = len(b) // 144
        ok = 0
        for r in range(n):
            o = r * 144
            q = struct.unpack_from("<4f", b, o + 16)
            ni = struct.unpack_from("<H", b, o + 112)[0]
            if ni < n_nodes and abs(sum(x * x for x in q) - 1) < 0.05:
                ok += 1
        if ok >= 0.95 * n:
            return b
    return None


points = []  # (kind, x, y, z, label, sector)
bad = collections.Counter()
t0 = time.time()
for si, s in enumerate(wanted):
    if si % 200 == 0:
        print(f"{si}/{len(wanted)} points={len(points)} t={time.time() - t0:.0f}s", flush=True)
    loaded = depot.load(DIR + s["name"] + ".streamingsector")
    if not loaded:
        bad["missing"] += 1
        continue
    head, bufs = loaded
    try:
        c = pkg.Cooked(head, bufs, depot)
    except Exception:
        bad["parse"] += 1
        continue
    nodes = [(cls, obj) for cls, obj in c.exports if cls.startswith("world") and "Node" in cls]
    nd = node_data(bufs, len(nodes))
    if nd is None:
        bad["no node data"] += 1
        continue
    per_node = []
    for cls, obj in nodes:
        rs = refs_in(obj, c.exports)
        kinds = {kind_of(r) for r in rs} - {None}
        locs = {LOC.match(r) for r in rs} - {None}
        label = None
        if locs:
            m = next(iter(locs))
            label = f"{m.group(1)}\\{m.group(2)}"
        people = cls in ("worldAISpotNode", "worldPopulationSpawnerNode") or cls.startswith("worldCompiledCommunityAreaNode")
        per_node.append((kinds, label, people, cls, obj.get("debugName")))
    for r in range(len(nd) // 144):
        o = r * 144
        pos = struct.unpack_from("<3f", nd, o)
        ni = struct.unpack_from("<H", nd, o + 112)[0]
        if ni >= len(per_node):
            continue
        kinds, label, people, cls, dbg = per_node[ni]
        if not (kinds or label or people):
            continue
        if pos == (0.0, 0.0, 0.0):
            lo = struct.unpack_from("<3f", nd, o + 56)
            hi = struct.unpack_from("<3f", nd, o + 68)
            pos = tuple((a + b) / 2 for a, b in zip(lo, hi))
        if not all(math.isfinite(v) and abs(v) < 20000 for v in pos):
            continue
        for k in kinds:
            points.append((k, *pos, dbg, s["name"]))
        if label:
            points.append(("loc", *pos, label, s["name"]))
        if people:
            points.append(("people", *pos, dbg, s["name"]))
print("read", len(wanted), "sectors;", dict(bad), f"t={time.time() - t0:.0f}s", flush=True)

# Sites: props (not locations or people) within 12 m of each other, single linkage.
props = [p for p in points if p[0] not in ("loc", "people")]
cell = collections.defaultdict(list)
for i, p in enumerate(props):
    cell[(int(p[1] // 12), int(p[2] // 12))].append(i)
parent = list(range(len(props)))


def find(i):
    while parent[i] != i:
        parent[i] = parent[parent[i]]
        i = parent[i]
    return i


for i, p in enumerate(props):
    cx, cy = int(p[1] // 12), int(p[2] // 12)
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            for j in cell.get((cx + dx, cy + dy), []):
                if j > i:
                    q = props[j]
                    if (p[1] - q[1]) ** 2 + (p[2] - q[2]) ** 2 < 144 and abs(p[3] - q[3]) < 6:
                        parent[find(i)] = find(j)
groups = collections.defaultdict(list)
for i in range(len(props)):
    groups[find(i)].append(props[i])

secs_by_name = {s["name"]: s for s in D["sectors"]}
others = [p for p in points if p[0] in ("loc", "people")]
sites = []
for g in groups.values():
    kinds = collections.Counter(p[0] for p in g)
    # dedupe repeated placements of one prop at one spot
    spots = collections.Counter((p[0], round(p[1]), round(p[2]), round(p[3])) for p in g)
    kinds = collections.Counter(k for k, *_ in spots)
    x = sum(p[1] for p in g) / len(g)
    y = sum(p[2] for p in g) / len(g)
    z = sum(p[3] for p in g) / len(g)
    score = 6 * min(kinds["lift"], 2) + min(kinds["tires"], 12) + 0.5 * min(kinds["tools"], 16) \
        + 3 * min(kinds["carparts"], 3) + 2 * min(kinds["shutter"], 3) + 4 * min(kinds["mechanic"], 2)
    if len(kinds) < 2 and not kinds["lift"]:
        continue
    near_locs = collections.Counter()
    people = 0
    for k, ox, oy, oz, lab, sn in others:
        d = math.hypot(ox - x, oy - y)
        if k == "loc" and d < 120:
            near_locs[lab] += 1
        elif k == "people" and d < 25 and abs(oz - z) < 8:
            people += 1
    sectors = sorted({p[5] for p in g})
    cats = sorted({secs_by_name[n]["cat"] for n in sectors})
    variants = sorted({v for n in sectors for v in secs_by_name[n].get("variants", [])})
    sites.append({"x": round(x, 1), "y": round(y, 1), "z": round(z, 1), "score": score, "kinds": dict(kinds),
                  "locations": [l for l, _ in near_locs.most_common(4)], "people": people, "categories": cats,
                  "sectors": sectors, "variants": variants[:12],
                  "names": sorted({p[4] for p in g if p[4]})[:12]})
sites.sort(key=lambda s: -s["score"])


def surroundings(x, y, z):
    near_locs = collections.Counter()
    people = 0
    for k, ox, oy, oz, lab, sn in others:
        d = math.hypot(ox - x, oy - y)
        if k == "loc" and d < 150:
            near_locs[lab] += 1
        elif k == "people" and d < 25 and abs(oz - z) < 8:
            people += 1
    best = None
    for s in sites:
        d = math.hypot(s["x"] - x, s["y"] - y)
        if d < 30 and (best is None or s["score"] > best["score"]):
            best = s
    return [l for l, _ in near_locs.most_common(3)], people, best


# Every car lift and every garage or workshop building on its own, with what is around it.
markers = []
seen = set()
for k, x, y, z, name, sn in props:
    if k not in ("lift", "building"):
        continue
    key = (k, round(x / 3), round(y / 3), round(z / 3))
    if key in seen:
        continue
    seen.add(key)
    locs, people, site = surroundings(x, y, z)
    sec = secs_by_name[sn]
    markers.append({"kind": k, "x": round(x, 1), "y": round(y, 1), "z": round(z, 1), "name": name, "sector": sn,
                    "category": sec["cat"], "variants": sec.get("variants", [])[:8], "locations": locs, "people": people,
                    "site": {kk: site[kk] for kk in ("x", "y", "z", "score", "kinds")} if site else None})
json.dump({"sites": sites, "markers": markers, "points": len(points)}, open(OUT, "w", encoding="utf-8"), indent=1)
print(f"{len(markers)} lifts and garage buildings")
for m in sorted(markers, key=lambda m: (m["kind"], m["x"])):
    print(f"{m['kind']:8s} ({m['x']:8.1f},{m['y']:8.1f},{m['z']:6.1f}) {m['category']:8s} people={m['people']:3d} "
          f"{(m['name'] or '')[:40]:40s} locs={m['locations'][:2]} site={m['site']['kinds'] if m['site'] else None}")
print(f"{len(sites)} sites")
for s in sites[:60]:
    print(f"{s['score']:5.1f} ({s['x']:8.1f},{s['y']:8.1f},{s['z']:6.1f}) {s['kinds']} people={s['people']} {s['categories']} "
          f"locs={s['locations'][:2]} variants={s['variants'][:4]}")
