"""Step 0 of the shop paints (RECORD.md, 2026-11-08): the painted parts of each catalog's looks that aren't catalog slots, since a
catalog only has a slot where a model has alternatives: the Legatus, the MT28 and the BMF bodies, the Bandit's shell. Read from
the looks' .app files with the catalog generator's reader; a mechanical part or decoration is left out by name, and
plan-paints.py still has to find a painted body colour on what's left. Writes cache/extra-parts.json.
Run with: python -I list-parts.py"""
import collections
import glob
import importlib.util
import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "..")
OUT = os.path.join(HERE, "cache", "extra-parts.json")

spec = importlib.util.spec_from_file_location("make_catalogs", os.path.join(ROOT, "catalog", "make-catalogs.py"))
catalogs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(catalogs)
reader = catalogs.Reader()

NOT_BODY = re.compile(r"window|glass|windscreen|tire|wheel|rim_|interior|int0|int_|seat|steer|pedal|shadow|proxy|sticker|decal|"
                      r"light|lamp|wiper|plate|cutout|engine|exhaust|fuel|brake|axle|suspens|cable|hose|antenna|sensor|barcode|"
                      r"emissive|stripe|logo|chain|belt|muffler|radiator|gear|cargo|container|barrel|bag_|bags_|addon|attachment|"
                      r"chassis|detail|device|graffiti|burnt|junk|solar|brush|crystaldome|arm_|_arm|step_|monitor|kickstand|_rod|"
                      r"stitch")
MESH_CLASSES = re.compile(r"Mesh")

found = {}
everything = set()
for path in sorted(glob.glob(os.path.join(ROOT, "catalog", "out", "*.json"))):
    with open(path, encoding="utf-8") as f:
        cat = json.load(f)
    slotted = {m.lower() for s in cat["slots"] for o in s["options"] for m in o["meshes"].values() if m}
    extra = set()
    for info in cat["looks"].values():
        look = reader.app_looks(info["app"]).get(info["app_look"])
        if not look:
            continue
        for name, part in look["parts"].items():
            mesh = str(part["mesh"]).lower()
            base = os.path.basename(mesh)
            if not MESH_CLASSES.search(part["cls"]) or mesh in slotted or "\\vehicles\\" not in mesh or not mesh.endswith(".mesh"):
                continue
            # "__ext" leaves out the look-named stand-ins drawn for a far-away car, and props hung on a car.
            if "__ext" not in base or NOT_BODY.search(name.lower()) or NOT_BODY.search(base):
                continue
            extra.add(mesh)
    found[cat["id"]] = sorted(extra)
    everything |= extra

print(len(everything), "meshes outside the slots, across", sum(1 for v in found.values() if v), "catalogs")
for cid in ("archer_bandit_01", "chevalier_legatus_basic_01", "mt28_coach_basic_01", "thorton_mackinaw_bmf_01", "z71_aras__basic_01",
            "rayfield_caliburn__basic_01", "porsche_911turbo__basic_01", "archer_quartz__basic_01"):
    print(cid, len(found.get(cid, [])), [os.path.basename(m)[:-5] for m in found.get(cid, [])][:14])
words = collections.Counter(w for m in everything for w in re.findall(r"[a-z]{3,}", os.path.basename(m)[:-5].split("__")[-1]))
print("words:", words.most_common(40))
with open(OUT, "w", encoding="utf-8") as f:
    json.dump({"catalogs": found, "meshes": sorted(everything)}, f, indent=1)
