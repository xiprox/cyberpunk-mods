"""Every world sector the game streams (all.streamingblock): its box, category, quest variants,
and the files its nodes use (entities, meshes, workspots). Writes data/sectors.json, for finding
places by what stands in them, such as garages with car lifts."""
import collections
import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pkg
import rdar

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data", "sectors.json")
BLOCK = r"base\worlds\03_night_city\_compiled\default\blocks\all.streamingblock"

depot = pkg.Depot()
head, bufs = depot.load(BLOCK)
descs = pkg.Cooked(head, bufs, depot).exports[0][1]["descriptors"]

paths = {}  # path -> id
path_list = []
sectors = []
t0 = time.time()
for i, d in enumerate(descs):
    name = d["data"][1]
    cat = d.get("category")
    if i % 2000 == 0:
        print(f"{i}/{len(descs)} paths={len(path_list)} t={time.time() - t0:.0f}s", flush=True)
    if cat == "Navigation":
        continue
    box = d["streamingBox"]
    entry = {
        "name": name.rsplit("\\", 1)[-1].replace(".streamingsector", ""),
        "cat": cat,
        "min": [round(box["Min"][k], 1) for k in "XYZ"],
        "max": [round(box["Max"][k], 1) for k in "XYZ"],
        "variants": sorted({v.get("name") for v in d.get("variants", []) if isinstance(v, dict) and v.get("name")}),
    }
    a, h = depot.find(name)
    if a is None:
        entry["missing"] = True
        sectors.append(entry)
        continue
    try:
        c = rdar.CR2W(a.head(h))
    except Exception as ex:
        entry["error"] = str(ex)
        sectors.append(entry)
        continue
    ids = []
    for p, _cls, _flags in c.imports:
        p = p.lower()
        if p.endswith((".streamingsector_inplace", ".cfoliage", ".smartobjects")):
            continue
        if p not in paths:
            paths[p] = len(path_list)
            path_list.append(p)
        ids.append(paths[p])
    entry["uses"] = ids
    entry["nodes"] = dict(collections.Counter(c.exports))
    sectors.append(entry)

json.dump({"paths": path_list, "sectors": sectors}, open(OUT, "w", encoding="utf-8"), separators=(",", ":"))
print(f"sectors={len(sectors)} paths={len(path_list)} t={time.time() - t0:.0f}s")
