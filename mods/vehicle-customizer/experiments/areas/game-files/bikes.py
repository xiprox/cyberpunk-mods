"""Bikes against cars: looks, parts, what varies, the names and classes parts use, and what's shared."""
import collections
import json
import os
import re
import statistics

S = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")
apps = json.load(open(os.path.join(S, "apps.json"), encoding="utf-8"))


def is_bike(app):
    return any("\\sportbike\\" in c["mesh"] for comp in app.values() for c in comp.values())


def visible(slot):
    return slot != "None" and "shadow" not in slot


bikes = {p: a for p, a in apps.items() if is_bike(a)}
print("bike .app files:", len(bikes), "of", len(apps))
for path, app in sorted(bikes.items()):
    meshes = collections.defaultdict(set)
    paints = collections.defaultdict(set)
    classes = collections.Counter()
    for comp in app.values():
        for slot, c in comp.items():
            if visible(slot):
                meshes[slot].add(c["mesh"])
                paints[slot].add(c["app"])
                classes[c["cls"]] += 1
    shape = {s: len(m) for s, m in meshes.items() if len(m) > 1}
    paint_only = sum(1 for s in meshes if len(meshes[s]) == 1 and len(paints[s]) > 1)
    print(f"\n{os.path.basename(path)[:-4]}  looks={len(app)}  parts={len(meshes)}  shape varies={len(shape)}  only paint varies={paint_only}")
    print("  classes:", classes.most_common(3))
    print("  shape:", dict(sorted(shape.items(), key=lambda kv: -kv[1])[:10]))
    print("  part names:", sorted(meshes)[:14])

print("\n-- does a bike use the car part names? --")
car_names = ["body_01", "hood_a", "trunk_a", "bumper_f_01", "bumper_b_01", "door_fl_a", "wheel_01_fl_a", "tire_01_fl_a", "steering_wheel", "fairing_a_01"]
for name in car_names:
    n = sum(1 for a in bikes.values() if any(name in comp for comp in a.values()))
    print(f"  {name:18s} {n}/{len(bikes)}")

print("\n-- the commonest bike part names, by .app --")
names = collections.Counter()
for a in bikes.values():
    seen = set()
    for comp in a.values():
        seen |= {s for s in comp if visible(s)}
    names.update(seen)
print(names.most_common(30))

print("\n-- meshes one bike family shares with another --")
fam = lambda p: "_".join(re.split(r"_+", os.path.basename(p)[:-4])[:2])
users = collections.defaultdict(set)
for p, a in bikes.items():
    for comp in a.values():
        for slot, c in comp.items():
            if visible(slot):
                users[c["mesh"]].add(fam(p))
shared = {m: f for m, f in users.items() if len(f) > 1}
print(f"distinct {len(users)}, shared across bike families {len(shared)}")
for m, f in sorted(shared.items(), key=lambda kv: -len(kv[1]))[:10]:
    print(f"  {sorted(f)}  {m}")
