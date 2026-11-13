"""Where a Nomad car's add-on parts are mounted: mesh, shadow, binding and local position and rotation."""
import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "..", "..", "tools"))
import pkg

S = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")
present = json.load(open(os.path.join(S, "parts.json"), encoding="utf-8"))["present"]
depot = pkg.Depot()
depot.add_names(present)

APP = next(p for p in present if p.endswith("archer_quartz_nomad.app"))
head, bufs = depot.load(APP)
c = pkg.Cooked(head, bufs, depot)
defs = [o for cls, o in c.exports if cls == "appearanceAppearanceDefinition"]
print(APP, "looks:", [d.get("name") for d in defs][:10])


def fixed(v):
    if isinstance(v, dict) and "Bits" in v:
        return round(v["Bits"] / 131072.0, 4)
    return v


def transform(t):
    if not isinstance(t, dict):
        return None
    pos = t.get("Position", {})
    ori = t.get("Orientation", {})
    p = tuple(fixed(pos.get(a)) if pos.get(a) is not None else 0.0 for a in ("x", "y", "z"))
    q = tuple(ori.get(a, 0.0 if a != "r" else 1.0) for a in ("i", "j", "k", "r"))
    return p, q


d = defs[0]
p = pkg.Package(c.buffer(d["compiledData"][1]), depot)
objs = p.objects()
print("look", d.get("name"), "objects", len(objs))
for cls, obj in objs:
    mesh = obj.get("mesh")
    if not (isinstance(mesh, tuple) and "v_common__nomad" in str(mesh[1])):
        continue
    binding = obj.get("parentTransform")
    bind = objs[binding[1]][1] if isinstance(binding, tuple) and 0 <= binding[1] < len(objs) else {}
    print(f"\n{obj.get('name')}  ({cls})")
    print(f"  mesh {mesh[1]}")
    print(f"  paint {obj.get('meshAppearance', 'default')}")
    print(f"  bound to {bind.get('bindName')} / {bind.get('slotName')}")
    print(f"  local position, rotation {transform(obj.get('localTransform'))}")
    print(f"  raw localTransform {obj.get('localTransform')}")
