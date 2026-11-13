"""What V's Hella look tells its visual controller to load (appearanceDependency), compared with what the test swapped in."""
import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "..", "..", "tools"))
import pkg

S = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")
present = json.load(open(os.path.join(S, "parts.json"), encoding="utf-8"))["present"]
depot = pkg.Depot()
depot.add_names(present)

APP = r"base\vehicles\appearances\standard\archer_hella__basic.app"
head, bufs = depot.load(APP)
c = pkg.Cooked(head, bufs, depot)
d = next(o for cls, o in c.exports if cls == "appearanceAppearanceDefinition" and o.get("name") == "player_01")
p = pkg.Package(c.buffer(d["compiledData"][1]), depot)
for cls, obj in p.objects():
    if cls == "entVisualControllerComponent":
        deps = obj.get("appearanceDependency", [])
        print("visual controller:", obj.get("name"), "dependencies:", len(deps) if isinstance(deps, list) else deps)
        if isinstance(deps, list):
            for dep in deps[:200]:
                mesh = dep.get("mesh")
                print("  ", dep.get("componentName"), "|", dep.get("appearance") or dep.get("appearanceName"), "|", mesh[1] if isinstance(mesh, tuple) else mesh)
print("resolvedDependencies of the look:", len(d.get("resolvedDependencies", [])))
for r in d.get("resolvedDependencies", [])[:120]:
    print("  ", r)
