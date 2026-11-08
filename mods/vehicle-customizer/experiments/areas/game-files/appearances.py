"""Across every vehicle .app: which part slots exist, what varies between appearances, what is shared between cars."""
import collections
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pkg

S = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")
present = json.load(open(os.path.join(S, "parts.json"), encoding="utf-8"))["present"]
depot = pkg.Depot()
depot.add_names(present)

apps = [p for p in present if p.endswith(".app") and ("\\vehicles\\appearances\\" in p or "\\vehicles\\" in p)]
result = {}
failures = []
total_defs = 0
for path in apps:
    try:
        head, bufs = depot.load(path)
        c = pkg.Cooked(head, bufs, depot)
    except Exception as ex:
        failures.append((path, "cr2w", str(ex)))
        continue
    defs = [o for cls, o in c.exports if cls == "appearanceAppearanceDefinition"]
    app = {}
    for d in defs:
        name = d.get("name")
        total_defs += 1
        comp = {}
        try:
            cd = d.get("compiledData")
            b = c.buffer(cd[1]) if cd else None
            if not b:
                continue
            p = pkg.Package(b, depot)
            objs = p.objects(only={"name", "mesh", "meshAppearance", "parentTransform", "slotName", "bindName"})
        except Exception as ex:
            failures.append((path, name, str(ex)))
            continue
        for cls, obj in objs:
            m = obj.get("mesh")
            if isinstance(m, tuple) and m[0] == "ref":
                binding = None
                pt = obj.get("parentTransform")
                if isinstance(pt, tuple) and 0 <= pt[1] < len(objs):
                    binding = objs[pt[1]][1].get("slotName") or objs[pt[1]][1].get("bindName")
                comp[str(obj.get("name"))] = {"cls": cls, "mesh": m[1], "app": str(obj.get("meshAppearance", "default")),
                                              "slot": str(binding)}
        app[str(name)] = comp
    result[path] = app

json.dump(result, open(os.path.join(S, "apps.json"), "w", encoding="utf-8"))
print("apps parsed", len(result), "appearances", total_defs, "failures", len(failures), failures[:5])

# Per .app: slots, and how many distinct meshes / mesh appearances a slot takes
print("\n-- per .app: appearances, slots, slots whose MESH varies, slots whose only PAINT varies --")
rows = []
for path, app in result.items():
    slots = collections.defaultdict(lambda: (set(), set()))
    for name, comp in app.items():
        for cname, c in comp.items():
            slots[cname][0].add(c["mesh"])
            slots[cname][1].add(c["app"])
    mesh_var = {k: len(v[0]) for k, v in slots.items() if len(v[0]) > 1}
    paint_var = {k: len(v[1]) for k, v in slots.items() if len(v[1]) > 1 and len(v[0]) == 1}
    rows.append((len(app), os.path.basename(path), len(slots), mesh_var, paint_var, len(result[path])))
rows.sort(key=lambda r: -r[0])
for n, name, slots, mv, pv, _ in rows[:30]:
    print(f"{n:4d} appearances {name:44s} slots={slots:3d} mesh-varies={len(mv):3d} paint-only={len(pv):3d}  e.g. {dict(list(mv.items())[:5])}")

# A worked example: which slots differ between two appearances of one car
sample = next(p for p in result if "archer_hella__basic" in p)
a, b = "default", "suburban_1"
ca, cb = result[sample].get(a, {}), result[sample].get(b, {})
print(f"\n-- {os.path.basename(sample)}: '{a}' {len(ca)} comps vs '{b}' {len(cb)} comps --")
for k in sorted(set(ca) | set(cb)):
    va, vb = ca.get(k), cb.get(k)
    if va != vb:
        print(f"  {k:34s} {va and (os.path.basename(va['mesh']), va['app'])}  ->  {vb and (os.path.basename(vb['mesh']), vb['app'])}")

# Cross-model sharing
mesh_models = collections.defaultdict(set)
for path, app in result.items():
    model = os.path.basename(path).replace(".app", "")
    model = re.sub(r"__.*|_basic.*|_kurtz.*", "", model)
    for comp in app.values():
        for c in comp.values():
            mesh_models[c["mesh"]].add(model)
shared = {m: s for m, s in mesh_models.items() if len(s) > 1}
print("\ndistinct meshes used by apps:", len(mesh_models), "used by more than one model family:", len(shared))
bytype = collections.Counter()
for m in shared:
    bits = m.split("\\")
    bytype["\\".join(bits[2:4])] += 1
print("shared by folder:", bytype.most_common(12))
for m, s in sorted(shared.items(), key=lambda kv: -len(kv[1]))[:25]:
    print(f"  {len(s):3d} models  {m}")

# Slot names common to all cars
slot_counter = collections.Counter()
for path, app in result.items():
    names = set()
    for comp in app.values():
        names |= set(comp)
    for n in names:
        slot_counter[n] += 1
print("\n-- commonest slot names, by number of .app files --")
print(slot_counter.most_common(60))
