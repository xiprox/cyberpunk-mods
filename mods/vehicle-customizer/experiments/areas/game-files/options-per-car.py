"""Real choices per car family, true cross-family sharing, how parts attach, and a wider paint-mask search."""
import collections
import json
import os
import re
import statistics
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pkg

S = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")
present = json.load(open(os.path.join(S, "parts.json"), encoding="utf-8"))["present"]
apps = json.load(open(os.path.join(S, "apps.json"), encoding="utf-8"))
depot = pkg.Depot()
depot.add_names(present)

SKIP = ("decoration", "destroyed", "filpped", "flipped")


def family(path):
    n = os.path.basename(path)[:-4]
    n = re.sub(r"^v_(standard\d*|sport\d*|utility\d*|sportbike\d*)_", "", n)
    bits = re.split(r"_+", n)
    return "_".join(bits[:2])


def group(slot):
    if slot == "None" or "shadow" in slot:
        return None
    for key, pat in [("front bumper", r"bumper_f"), ("rear bumper", r"bumper_b"), ("hood", r"^hood"), ("trunk", r"^trunk"),
                     ("wheel", r"^wheel"), ("tire", r"^tire"), ("body", r"^body_01$|__ext01_body_01$"),
                     ("interior", r"^interior_01$"), ("exhaust", r"^exhaust"), ("spoiler", r"spoiler|wing"),
                     ("mirror", r"mirror"), ("door", r"^door_f[lr]_a$")]:
        if re.search(pat, slot):
            return key
    return None


fam_slot = collections.defaultdict(lambda: collections.defaultdict(set))
fam_paint = collections.defaultdict(lambda: collections.defaultdict(set))
mesh_fams = collections.defaultdict(set)
total_app = 0
slots_paint = 0
slots_mesh = 0
slots_all = 0
bind = collections.Counter()
for path, app in apps.items():
    if any(s in path for s in SKIP):
        continue
    fam = family(path)
    per_slot_mesh = collections.defaultdict(set)
    per_slot_paint = collections.defaultdict(set)
    for name, comp in app.items():
        total_app += 1
        for slot, c in comp.items():
            mesh_fams[c["mesh"]].add(fam)
            per_slot_mesh[slot].add(c["mesh"])
            per_slot_paint[slot].add(c["app"])
            if c.get("slot") and c["slot"] != "None":
                bind[c["slot"]] += 1
            g = group(slot)
            if g:
                fam_slot[fam][g].add(c["mesh"])
                fam_paint[fam][g].add(c["app"])
    for slot in per_slot_mesh:
        if slot == "None" or "shadow" in slot:
            continue
        slots_all += 1
        if len(per_slot_mesh[slot]) > 1:
            slots_mesh += 1
        elif len(per_slot_paint[slot]) > 1:
            slots_paint += 1

print(f"appearances (no wrecks/decoration): {total_app}")
print(f"visible slots: {slots_all}; shape changes between appearances: {slots_mesh} ({slots_mesh*100//slots_all}%); only paint changes: {slots_paint} ({slots_paint*100//slots_all}%); never changes: {slots_all-slots_mesh-slots_paint}")

print("\n-- real mesh options per slot, by car family (wheels and tires count 4 corners, so per-corner shown) --")
keys = ["front bumper", "rear bumper", "hood", "trunk", "body", "wheel", "tire", "exhaust", "spoiler", "interior"]
print(f"{'family':28s} " + " ".join(f"{k[:8]:>8s}" for k in keys))
rows = sorted(fam_slot.items(), key=lambda kv: -sum(len(v) for v in kv[1].values()))
for fam, slots in rows[:32]:
    print(f"{fam:28s} " + " ".join(f"{len(slots.get(k, ())):8d}" for k in keys))

print("\n-- medians across", len(fam_slot), "families --")
for k in keys:
    vals = [len(s[k]) for s in fam_slot.values() if k in s]
    if vals:
        print(f"  {k:14s} in {len(vals):3d} families  median {statistics.median(vals):4.1f}  max {max(vals)}")

cross = {m: f for m, f in mesh_fams.items() if len(f) > 1}
print(f"\ndistinct meshes: {len(mesh_fams)}; used by >1 true family: {len(cross)}")
where = collections.Counter()
for m in cross:
    bits = m.split("\\")
    where["common parts" if "common" in m else ("unnamed" if m.startswith("#") else "\\".join(bits[2:4]))] += 1
print(where.most_common(14))
bysize = sorted(cross.items(), key=lambda kv: -len(kv[1]))
print("non-common examples:")
n = 0
for m, f in bysize:
    if "common" in m or m.startswith("#"):
        continue
    print(f"  {len(f):2d} {m}   {sorted(f)[:4]}")
    n += 1
    if n >= 12:
        break
nomad = [m for m in mesh_fams if "v_common__nomad" in m and "shadow" not in m]
print(f"bolt-on nomad kit pieces: {len(nomad)}, used across {len(set().union(*[mesh_fams[m] for m in nomad])) if nomad else 0} families")

print("\n-- what parts attach to --", bind.most_common(20))

print("\n-- wider paint-mask search: all body meshes used by any appearance --")
body_meshes = set()
for path, app in apps.items():
    if any(s in path for s in SKIP):
        continue
    for comp in app.values():
        for slot, c in comp.items():
            if group(slot) == "body" and not c["mesh"].startswith("#"):
                body_meshes.add((family(path), c["mesh"]))
terms = [b"CustomColorMask", b"CoatTintFwd", b"CoatSpecularColor"]
hits = collections.defaultdict(set)
for fam, m in body_meshes:
    a, h = depot.find(m)
    if a is None:
        continue
    e = a.files[h]
    blob = b""
    for i in range(e[2], e[3]):
        if a._seg(i)[2] < 3_000_000:
            blob += a.read_segment(i)
    for t in terms:
        if t in blob:
            hits[t.decode()].add(fam)
print("body meshes checked:", len(body_meshes))
for t, s in hits.items():
    print(f"  {t}: {len(s)} families -> {sorted(s)}")
