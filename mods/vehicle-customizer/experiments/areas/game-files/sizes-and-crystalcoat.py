"""Corrected size check, an exact CrystalCoat search, and which cars share a base rig."""
import collections
import json
import os
import re
import statistics
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pkg
import rdar

S = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")
present = json.load(open(os.path.join(S, "parts.json"), encoding="utf-8"))["present"]
apps = json.load(open(os.path.join(S, "apps.json"), encoding="utf-8"))
depot = pkg.Depot()
depot.add_names(present)


def read_box(path):
    head, _ = depot.load(path)
    c = rdar.CR2W(head)
    off, n, _ = c.tables[4]
    for i in range(n):
        cls, _f, _par, size, data_off, _t, _c = struct.unpack_from("<HHIIIII", head, off + i * 24)
        if c.names[cls] != "CMesh":
            continue
        p = data_off + 1
        end = data_off + size
        while p + 8 <= end:
            ni = struct.unpack_from("<H", head, p)[0]
            if ni == 0:
                break
            _ti, sz = struct.unpack_from("<HI", head, p + 2)
            if c.names[ni] == "boundingBox":
                box = {}
                q = p + 9
                while q + 8 <= p + 4 + sz:
                    nj = struct.unpack_from("<H", head, q)[0]
                    if nj == 0:
                        break
                    _tj, szj = struct.unpack_from("<HI", head, q + 2)
                    vec = {}
                    r = q + 9
                    while r + 8 <= q + 4 + szj:
                        nk = struct.unpack_from("<H", head, r)[0]
                        if nk == 0:
                            break
                        _tk, szk = struct.unpack_from("<HI", head, r + 2)
                        vec[c.names[nk]] = struct.unpack_from("<f", head, r + 8)[0]
                        r += 4 + szk
                    box[c.names[nj]] = vec
                    q += 4 + szj
                return box
            p += 4 + sz
    return None


def pretty(box):
    lo, hi = box["Min"], box["Max"]
    return [round(lo[a], 2) for a in "XYZ"], [round(hi[a], 2) for a in "XYZ"]


wanted = ["bumper_f_01", "bumper_b_01", "hood_a", "trunk_a", "wheel_01_fl_a", "tire_01_fl_a", "body_01"]
slot_mesh = collections.defaultdict(dict)
for path, app in apps.items():
    name = os.path.basename(path)[:-4]
    counts = collections.defaultdict(collections.Counter)
    for comp in app.values():
        for slot in wanted:
            if slot in comp:
                counts[slot][comp[slot]["mesh"]] += 1
    for slot, c in counts.items():
        slot_mesh[slot][name] = c.most_common(1)[0][0]

print("-- part sizes across cars in metres: width x length x height, min / median / max --")
boxes = {}
for slot in wanted:
    rows = []
    for name, m in slot_mesh[slot].items():
        if m.startswith("#"):
            continue
        try:
            b = read_box(m)
        except Exception:
            b = None
        if b and "Min" in b and "Max" in b and "X" in b["Min"]:
            d = tuple(round(b["Max"][a] - b["Min"][a], 3) for a in "XYZ")
            rows.append((d, name, b))
    boxes[slot] = rows
    if not rows:
        print(slot, "no boxes")
        continue
    axes = list(zip(*[r[0] for r in rows]))
    print(f"{slot:14s} n={len(rows):3d}  W {min(axes[0]):.2f}/{statistics.median(axes[0]):.2f}/{max(axes[0]):.2f}"
          f"  L {min(axes[1]):.2f}/{statistics.median(axes[1]):.2f}/{max(axes[1]):.2f}"
          f"  H {min(axes[2]):.2f}/{statistics.median(axes[2]):.2f}/{max(axes[2]):.2f}")

print("\n-- where parts sit: is a part's box in car space or around its own pivot? --")
for name, m in sorted(slot_mesh["bumper_f_01"].items())[:8]:
    if m.startswith("#"):
        continue
    b = read_box(m)
    if b:
        print(f"  bumper_f {name:34s} {pretty(b)}")
for name, m in sorted(slot_mesh["wheel_01_fl_a"].items())[:6]:
    if m.startswith("#"):
        continue
    b = read_box(m)
    if b:
        print(f"  wheel    {name:34s} {pretty(b)}")

print("\n-- bumper_f pairs from DIFFERENT cars within 3 cm width and 3 cm height --")
rows = [r for r in boxes["bumper_f_01"]]
fam = lambda n: re.sub(r"_(basic|nomad|kurtz|heist|.*limo|barghest|corpbud|nusa|orbitalair|player).*", "", n).rstrip("_")
pairs = []
for i, a in enumerate(rows):
    for b in rows[i + 1:]:
        if fam(a[1]) != fam(b[1]) and abs(a[0][0] - b[0][0]) <= 0.03 and abs(a[0][2] - b[0][2]) <= 0.03:
            pairs.append((a[1], b[1], a[0], b[0]))
print(f"{len(pairs)} near-size pairs out of {len(rows)} bumpers; first few:")
for p in pairs[:8]:
    print("  ", p)

print("\n-- wheel + tire overall diameter by car (tire height) --")
tires = sorted((r[0][2], r[1]) for r in boxes["tire_01_fl_a"])
for d, n in tires[::6]:
    print(f"  {d:.2f} m  {n}")

# Exact CrystalCoat search over real vehicle entity files
print("\n-- .ent files naming vehicleVisualCustomization / vvc_color exactly --")
all_ents = [p for p in present if p.endswith(".ent") and "\\vehicles\\" in p]
hits = []
base_rigs = 0
for p in all_ents:
    a, h = depot.find(p)
    if a is None:
        continue
    e = a.files[h]
    blob = b""
    for i in range(e[2], e[3]):
        if a._seg(i)[2] < 4_000_000:
            blob += a.read_segment(i)
    has = b"vehicleVisualCustomization" in blob, b"vvc_color" in blob
    if has[0] or has[1]:
        hits.append((p, has))
print("entities checked:", len(all_ents), "with component:", sum(1 for _, h in hits if h[0]), "with vvc_color effects:", sum(1 for _, h in hits if h[1]))
real = [p for p, h in hits if "\\base_rig\\" not in p and "\\quest\\" not in p and "\\open_world\\" not in p]
print("excluding rigs and quest copies:", len(real))
names = collections.Counter(re.sub(r"^.*\\", "", p)[:-4] for p in real)
print(sorted(names)[:90])
json.dump({"crystalcoat": [p for p, _ in hits]}, open(os.path.join(S, "cc.json"), "w"), indent=0)

# Structure of one car's entity file: which files does it reference, and from where?
print("\n-- structure of a car's entity file --")
sample = next((p for p in all_ents if p.endswith("v_standard2_archer_hella.ent") or p.endswith("v_standard2_archer_hella__basic.ent")), None)
candidates = [p for p in all_ents if "archer_hella" in p and "\\entities\\" not in p][:8]
print("hella ents:", candidates[:8], "sample:", sample)
target = sample or (candidates[0] if candidates else None)
if target:
    head, bufs = depot.load(target)
    c = pkg.Cooked(head, bufs, depot)
    root = c.exports[0][1]
    print("root keys:", list(root.keys()))
    print("appearances:", [a.get("name") for a in root.get("appearances", [])][:8] if isinstance(root.get("appearances"), list) else root.get("appearances"))
    print("deps:", [depot.name(x) for x in depot.find(target)[0].deps(depot.find(target)[1])][:30])
