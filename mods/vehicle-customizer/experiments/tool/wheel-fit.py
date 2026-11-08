"""Does a rule fit a rim to a tire? Tested on the pairs the game's artists made: if a rule built from the meshes alone
finds each pair's real fit (scale 1, no shift), it can be trusted on pairs nobody made.
usage: seat_wheels.py <numpy site-packages> <wheels.yaml> <glb folder>"""
import sys
sys.path.append(sys.argv[1])
import json, os, re, struct, collections
import numpy as np

yaml_path, glb_root = sys.argv[2:4]
text = open(yaml_path, encoding="utf-8").read()
vals = collections.defaultdict(dict)
for m in re.finditer(r'^VehicleCustomizer\.wheel\.(\w+)\.(rim|tire|rimLabel|tireLabel): (.*)$', text, re.M):
    vals[m.group(1)][m.group(2)] = m.group(3)


def points(path):
    with open(path, "rb") as f:
        data = f.read()
    n = struct.unpack_from("<I", data, 12)[0]
    doc = json.loads(data[20:20 + n])
    p = 20 + n
    blen = struct.unpack_from("<I", data, p)[0]
    bin_ = data[p + 8:p + 8 + blen]
    names = [m.get("name", "") for m in doc["meshes"]]
    keep = [i for i, nm in enumerate(names) if nm.endswith("LOD_1")] or list(range(len(names)))
    out = []
    for i in keep:
        for prim in doc["meshes"][i]["primitives"]:
            acc = doc["accessors"][prim["attributes"]["POSITION"]]
            view = doc["bufferViews"][acc["bufferView"]]
            off = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
            stride = view.get("byteStride", 12)
            raw = np.frombuffer(bin_, dtype=np.uint8, count=acc["count"] * stride, offset=off)
            out.append(np.frombuffer(raw.reshape(-1, stride)[:, :12].tobytes(), dtype="<f4").reshape(-1, 3))
    return np.vstack(out)


def load(mesh):
    rel = mesh.replace('r"', "").replace('"', "").replace("\\\\", "\\")
    path = os.path.join(glb_root, rel[:-5] + ".glb")
    if not os.path.exists(path):
        return None
    v = points(path)
    cy, cz = (v[:, 1].max() + v[:, 1].min()) / 2, (v[:, 2].max() + v[:, 2].min()) / 2
    return v[:, 0], np.hypot(v[:, 1] - cy, v[:, 2] - cz)


def tire_shape(x, r):
    # The tread: vertices near the outer radius. The beads: the hole's edge at each sidewall, the smallest radius in
    # the part of the tire beyond the tread's middle on that side, ignoring the deepest 2% (hidden inner walls).
    R = r.max()
    tread = r > R * 0.97
    lo, hi = x[tread].min(), x[tread].max()
    mid = (lo + hi) / 2
    bead = [float(np.percentile(r[(x < mid)], 5)), float(np.percentile(r[(x >= mid)], 5))]
    return {"R": float(R), "lo": float(lo), "hi": float(hi), "bead": bead, "seat": float(max(bead)), "rmin": float(r.min())}


def rim_shape(x, r):
    # The lip: the outermost vertices of the rim, and how far apart along the axle they sit.
    R = r.max()
    lip = r > R * 0.93
    return {"R": float(R), "lo": float(x[lip].min()), "hi": float(x[lip].max()), "xmin": float(x.min()), "xmax": float(x.max())}


cache = {}
def get(mesh, fn):
    if mesh not in cache:
        got = load(mesh)
        cache[mesh] = fn(*got) if got else None
    return cache[mesh]


rows = []
for sid, s in vals.items():
    r, t = get(s["rim"], rim_shape), get(s["tire"], tire_shape)
    if r and t:
        rows.append((sid, s["rimLabel"], r, t))
print(len(rows), "pairs\n")


def stats(name, xs):
    a = np.array(xs)
    print(f"{name:58s} 5% {np.percentile(a,5):7.2f}  25% {np.percentile(a,25):7.2f}  median {np.median(a):7.2f}  75% {np.percentile(a,75):7.2f}  95% {np.percentile(a,95):7.2f}")


seat = [(r["R"] - t["seat"]) * 100 for _, _, r, t in rows]
stats("rim's lip radius - tire's seat radius, cm", seat)
ratio = [r["R"] / t["seat"] for _, _, r, t in rows]
stats("rim's lip radius / tire's seat radius", ratio)
k = float(np.median(ratio))
# The rule "rim's lip = k x tire's seat" applied to each pair: how far from what the artist made, as a radius, cm.
miss = [abs(k * t["seat"] / r["R"] - 1) * r["R"] * 100 for _, _, r, t in rows]
stats("radial miss of the best single rule, cm", miss)
print(f"   k = {k:.3f}; within 0.5 cm: {np.mean(np.array(miss) < 0.5)*100:.0f}%, within 1 cm: {np.mean(np.array(miss) < 1)*100:.0f}%, within 2 cm: {np.mean(np.array(miss) < 2)*100:.0f}%")
wr = [(r["hi"] - r["lo"]) / (t["hi"] - t["lo"]) for _, _, r, t in rows]
stats("rim's lip span / tire's tread span", wr)
kw = float(np.median(wr))
missw = [abs(kw * (t["hi"] - t["lo"]) - (r["hi"] - r["lo"])) * 100 for _, _, r, t in rows]
stats("width miss of the best single rule, cm", missw)
print(f"   k = {kw:.3f}; within 0.5 cm: {np.mean(np.array(missw) < 0.5)*100:.0f}%, within 1 cm: {np.mean(np.array(missw) < 1)*100:.0f}%, within 2 cm: {np.mean(np.array(missw) < 2)*100:.0f}%")
cen = [((r["hi"] + r["lo"]) - (t["hi"] + t["lo"])) * 50 for _, _, r, t in rows]
stats("lip span's centre - tread's centre along the axle, cm", cen)
med = float(np.median(cen))
missc = np.abs(np.array(cen) - med)
print(f"   median {med:.2f}; within 0.5 cm: {np.mean(missc < 0.5)*100:.0f}%, within 1 cm: {np.mean(missc < 1)*100:.0f}%, within 2 cm: {np.mean(missc < 2)*100:.0f}%")
stats("tread's centre from the mesh's pivot, cm", [(t["hi"] + t["lo"]) * 50 for _, _, r, t in rows])
all3 = np.array(miss) < 1
all3 &= np.array(missw) < 1
all3 &= missc < 1
print(f"\nall three within 1 cm: {np.mean(all3)*100:.0f}% of the game's own pairs")
all3b = (np.array(miss) < 2) & (np.array(missw) < 2) & (missc < 2)
print(f"all three within 2 cm: {np.mean(all3b)*100:.0f}%")
worst = sorted(range(len(rows)), key=lambda i: -miss[i])[:8]
print("\nworst on the radius:")
for i in worst:
    print(f"  {miss[i]:5.1f} cm  {rows[i][1]}  rim R {rows[i][2]['R']*100:.1f}  tire seat {rows[i][3]['seat']*100:.1f}  tire R {rows[i][3]['R']*100:.1f}  beads {rows[i][3]['bead'][0]*100:.1f}/{rows[i][3]['bead'][1]*100:.1f}")
