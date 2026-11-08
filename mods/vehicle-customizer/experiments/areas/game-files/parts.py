"""Group vehicle meshes by model and part, and report how modular the data really is."""
import collections
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rdar

KNOWN = os.path.join(rdar.GAME, r"red4ext\plugins\Codeware\Data\KnownHashes.txt")
ROOT = os.path.join(rdar.GAME, "archive", "pc")
ARCHIVES = [("content", "basegame_4_appearance.archive"), ("content", "basegame_4_gamedata.archive"),
            ("content", "basegame_1_engine.archive"), ("content", "basegame_3_nightcity.archive"),
            ("ep1", "ep1_1_nightcity.archive"), ("ep1", "ep1_2_gamedata.archive")]

paths = set()
with open(KNOWN, encoding="utf-8", errors="replace") as f:
    for line in f:
        p = line.strip().lower()
        if "vehicle" in p and "\\" in p:
            paths.add(p)
DATA = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")
cat = json.load(open(os.path.join(DATA, "catalogue.json"), encoding="utf-8"))
paths |= set(cat["paths"])

hashes = set()
for sub, n in ARCHIVES:
    hashes |= set(rdar.Archive(os.path.join(ROOT, sub, n)).files)
present = sorted(p for p in paths if rdar.fnv1a64(p) in hashes)
print("vehicle-ish paths known:", len(paths), "present in archives:", len(present))

ext = collections.Counter(os.path.splitext(p)[1] for p in present)
print("by extension:", ext.most_common(16))

top = collections.Counter("\\".join(p.split("\\")[:3]) for p in present)
print("top dirs:", top.most_common(25))

# v_standard2_archer_hella__ext01_bumper_f_01.mesh
pat = re.compile(r"\\(v_[a-z0-9]+_[a-z0-9_]+?)__(ext|int)(\d\d)_([a-z_]+?)_?(\d\d)?(?:_[a-z0-9_]*)?\.mesh$")
models = collections.defaultdict(lambda: collections.defaultdict(set))
kits = collections.defaultdict(set)
for p in present:
    m = pat.search(p)
    if not m:
        continue
    model, side, kit, part, num = m.groups()
    models[model][f"{side}:{part}"].add((kit, num, p))
    kits[model].add(f"{side}{kit}")

print("models with part-named meshes:", len(models))
rows = []
for model, parts in sorted(models.items()):
    variants = {k: len(v) for k, v in parts.items()}
    rows.append((sum(variants.values()), model, variants, sorted(kits[model])))
rows.sort(reverse=True)
print("\n-- most parts per model --")
for total, model, variants, k in rows[:25]:
    swappable = {k2: v for k2, v in variants.items() if v > 1}
    print(f"{total:4d} {model:45s} kits={','.join(k)}  multi={dict(list(swappable.items())[:8])}")

part_names = collections.Counter()
multi = collections.Counter()
for _, model, variants, _k in rows:
    for k2, v in variants.items():
        part_names[k2] += 1
        if v > 1:
            multi[k2] += 1
print("\n-- part slot: models having it, models having >1 variant --")
for k2, n in part_names.most_common(40):
    print(f"{k2:34s} {n:4d}  {multi[k2]:4d}")

json.dump({"present": present,
           "models": {m: {k2: sorted(map(list, v), key=str) for k2, v in parts.items()} for m, parts in models.items()}},
          open(os.path.join(DATA, "parts.json"), "w", encoding="utf-8"), indent=0)
