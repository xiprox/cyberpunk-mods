"""Step 2 of the shop paints (RECORD.md, 2026-11-08): from extract.py's JSON, what each model's paint looks like. For every
mesh the catalogs use: which materials are multilayer, which paint files its appearances name. For every model folder:
which layer of its paint files is the car's colour, found by what varies between its paints. Writes cache/map.json and prints
a table. Run with: python -I map-paints.py"""
import collections
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
JS = os.path.join(HERE, "cache", "json")


def load(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)["Data"]["RootChunk"]


def value(ref):
    return ref["DepotPath"]["$value"].lower() if ref and ref.get("DepotPath") else ""


def read_setup(rel):
    path = os.path.join(JS, rel + ".json")
    if not os.path.exists(path):
        return None
    out = []
    for layer in load(path)["layers"]:
        out.append({"surface": os.path.basename(value(layer["material"])).replace(".mltemplate", ""),
                    "colour": layer["colorScale"]["$value"], "opacity": layer["opacity"]})
    return out


def is_paint(surface):
    return "paint" in surface


meshes = {}
setups = {}
for folder, _dirs, files in os.walk(JS):
    for name in files:
        if not name.endswith(".mesh.json"):
            continue
        rel = os.path.relpath(os.path.join(folder, name), JS)[:-5].lower()
        root = load(os.path.join(folder, name))
        materials = root.get("localMaterialBuffer", {}).get("materials") or []
        entries = {e["name"]["$value"]: e for e in root.get("materialEntries") or []}
        info = {}
        for name_, entry in entries.items():
            if not entry.get("isLocalInstance") or entry["index"] >= len(materials):
                continue
            material = materials[entry["index"]]
            setup = mask = None
            for v in material.get("values") or []:
                if "MultilayerSetup" in v:
                    setup = value(v["MultilayerSetup"])
                if "MultilayerMask" in v:
                    mask = value(v["MultilayerMask"])
            if setup:
                info[name_] = {"setup": setup, "mask": mask, "base": value(material.get("baseMaterial"))}
                if setup not in setups:
                    setups[setup] = read_setup(setup)
        appearances = {}
        for a in root.get("appearances") or []:
            chunks = [c["$value"] for c in a["Data"]["chunkMaterials"]]
            appearances[a["Data"]["name"]["$value"]] = chunks
        meshes[rel] = {"materials": info, "appearances": appearances}

print(len(meshes), "meshes;", sum(1 for m in meshes.values() if m["materials"]), "with multilayer materials;",
      len(setups), "paint files named;", sum(1 for s in setups.values() if s is None), "not found")

by_folder = collections.defaultdict(set)
for rel, m in meshes.items():
    parts = rel.split("\\")
    for material in m["materials"].values():
        by_folder[parts[3]].add(material["setup"])

rows = []
for folder, used in sorted(by_folder.items()):
    known = [setups[s] for s in used if setups.get(s)]
    if not known:
        continue
    varies = []
    for i in range(20):
        seen = collections.Counter()
        paint = 0
        for layers in known:
            if i < len(layers) and layers[i]["opacity"] > 0:
                seen[(layers[i]["surface"], layers[i]["colour"])] += 1
                paint += is_paint(layers[i]["surface"])
        varies.append((len(seen), paint, i))
    best = max(varies, key=lambda v: (v[1] > 0, v[0], v[1]))
    layer0 = collections.Counter(k[0]["surface"] for k in known if k)
    rows.append({"folder": folder, "setups": len(known), "paint_layer": best[2], "colours": best[0], "paint_setups": best[1],
                 "layer0": layer0.most_common(1)[0][0], "layer0_share": layer0.most_common(1)[0][1] / len(known)})

for r in rows:
    print(f"{r['folder'][:42]:42s} {r['setups']:4d} files  layer {r['paint_layer']:2d}  {r['colours']:3d} looks  {r['paint_setups']:3d} paint  layer0 {r['layer0'][:30]} {r['layer0_share']:.0%}")
print("folders:", len(rows), " layer 0:", sum(1 for r in rows if r["paint_layer"] == 0),
      " no paint surface:", sum(1 for r in rows if r["paint_setups"] == 0))
surfaces = collections.Counter()
for layers in setups.values():
    if layers:
        surfaces[layers[0]["surface"]] += 1
print("layer 0 surfaces overall:", surfaces.most_common(14))

with open(os.path.join(HERE, "cache", "map.json"), "w", encoding="utf-8") as f:
    json.dump({"meshes": meshes, "setups": setups, "folders": rows}, f)
