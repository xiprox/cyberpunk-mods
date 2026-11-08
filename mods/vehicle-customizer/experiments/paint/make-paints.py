"""Step 4 of the shop paints (RECORD.md, 2026-11-08): the shop's 89 colours on every painted part of every model, added to the
game's meshes through ArchiveXL's dynamic materials, as the probe proved (make-probe-paints.py, job "paintscale").

From cache/plan.json (plan-paints.py): for each mesh the look to build on; for each of that look's paint files, which layers are
the body's colour. For each paint file and colour, a copy with those layers in our car paint and that colour. For each mesh, a
patch with a template material per body material (near and far alike) naming the paint by {material}, and 89 appearances named
vcs_<colour>.

Writes mod/archive/pc/mod/vehiclecustomizer/vehiclecustomizer_paint.archive and .xl, and
mod/r6/tweaks/vehiclecustomizer/shop-paints.yaml (the colour list, and which catalog options can wear them).
Run after extract.py, map-paints.py and plan-paints.py: python -I make-paints.py"""
import concurrent.futures
import copy
import glob
import hashlib
import json
import os
import shutil
import subprocess

WK = r"H:\WolvenKit\Console\WolvenKit.CLI.exe"
CONTENT = r"C:\Program Files (x86)\Steam\steamapps\common\Cyberpunk 2077\archive\pc\content"
ARCHIVES = ["basegame_1_engine", "basegame_3_nightcity", "basegame_4_appearance", "basegame_4_gamedata"]
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "..")
CACHE = os.path.join(HERE, "cache")
JS = os.path.join(CACHE, "json")
OUT = os.path.join(ROOT, "mod", "archive", "pc", "mod", "vehiclecustomizer")
TWEAKS = os.path.join(ROOT, "mod", "r6", "tweaks", "vehiclecustomizer")
DEPOT = r"vehiclecustomizer\paint"
SURFACE = DEPOT + r"\vc_car_paint.mltemplate"
CANON = r"base\vehicles\standard\v_standard2_archer_hella\entities\meshes\textures\suburban_01.mlsetup"
WORKERS = 3


def wk(*args):
    subprocess.run([WK, *args, "-v", "Minimal"], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def linear(channel):
    c = channel / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def load(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def save(doc, path):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(doc, f)


def cname(value):
    return {"$type": "CName", "$storage": "string", "$value": value}


def sid(key):
    return hashlib.md5(key.encode()).hexdigest()[:8]


with open(os.path.join(ROOT, "catalog", "shop-palette.json"), encoding="utf-8") as f:
    SHOP = [(name.lower().replace(" ", "_"), tuple(linear(int(hex_[i:i + 2], 16)) for i in (1, 3, 5)))
            for group in json.load(f)["groups"] for name, hex_ in group["colours"]]
assert len(SHOP) == 89 and len({s for s, _ in SHOP}) == 89
PLAN = load(os.path.join(CACHE, "plan.json"))
MAP = load(os.path.join(CACHE, "map.json"))
MESHES = MAP["meshes"]

build = os.path.join(CACHE, "build")
if os.path.isdir(build):
    shutil.rmtree(build)
source, pack, sets, patches = (os.path.join(build, x) for x in ("src", "vehiclecustomizer_paint", "setups", "patches"))
target = os.path.join(pack, DEPOT)
for d in (source, target, sets, patches):
    os.makedirs(d)

# Our surface: the game's car paint, with the shop's colours added to its palette.
print("surface", flush=True)
wk("unbundle", *[os.path.join(CONTENT, a + ".archive") for a in ARCHIVES], "-o", source, "-r", r"car_paint_metallic_01\.mltemplate$")
found = glob.glob(os.path.join(source, "**", "car_paint_metallic_01.mltemplate"), recursive=True)
assert found, "no car paint surface"
wk("convert", "serialize", found[0], "-o", build)
surface = load(os.path.join(build, "car_paint_metallic_01.mltemplate.json"))
palette = surface["Data"]["RootChunk"]["overrides"]["colorScale"]
for slug, rgb in SHOP:
    entry = copy.deepcopy(palette[0])
    entry["n"]["$value"] = "vc_s_" + slug
    entry["v"]["Elements"] = list(rgb)
    palette.append(entry)
os.makedirs(os.path.join(build, "ours"))
save(surface, os.path.join(build, "ours", "vc_car_paint.mltemplate.json"))
wk("convert", "deserialize", os.path.join(build, "ours", "vc_car_paint.mltemplate.json"), "-o", target)

# The layer every colour is written with: the Hella's Suburban body layer, the probe's, in our surface.
canon = load(os.path.join(JS, CANON + ".json"))["Data"]["RootChunk"]["layers"][0]
assert "car_paint_metallic_01" in canon["material"]["DepotPath"]["$value"]
canon = copy.deepcopy(canon)
canon["material"]["DepotPath"]["$value"] = SURFACE


def make_setups(key):
    """89 paint files for one of the game's on one model (a paint file shared between models can have its colour on different
    layers for each): its body-colour layers rewritten, everything else as it was."""
    layers = PLAN["setups"][key]["layers"]
    doc = load(os.path.join(JS, PLAN["setups"][key]["setup"] + ".json"))
    ident = sid(key)
    folder = os.path.join(sets, ident)
    os.makedirs(folder)
    for slug, _rgb in SHOP:
        one = copy.deepcopy(doc)
        for i in layers:
            layer = copy.deepcopy(canon)
            layer["colorScale"]["$value"] = "vc_s_" + slug
            one["Data"]["RootChunk"]["layers"][i] = layer
        save(one, os.path.join(folder, f"vcs_{slug}.mlsetup.json"))
    out = os.path.join(target, "s", ident)
    os.makedirs(out)
    wk("convert", "deserialize", folder, "-o", out)
    made = [n for n in os.listdir(out) if n.endswith(".mlsetup")]
    assert len(made) == 89, (setup, len(made))
    shutil.rmtree(folder)
    return ident


print(len(PLAN["setups"]), "paint files, 89 colours each", flush=True)
with concurrent.futures.ThreadPoolExecutor(WORKERS) as pool:
    for n, _ in enumerate(pool.map(make_setups, sorted(PLAN["setups"]))):
        if (n + 1) % 20 == 0:
            print(n + 1, flush=True)


def patch(rel, look, body):
    """A mesh's patch: no geometry, every material under a name of ours, 89 appearances."""
    doc = load(os.path.join(JS, rel + ".json"))
    root = doc["Data"]["RootChunk"]
    buffer = root["localMaterialBuffer"]
    index = {e["name"]["$value"]: e["index"] for e in root["materialEntries"]}
    base = next(a for a in root["appearances"] if a["Data"]["name"]["$value"] == look)
    template = root["materialEntries"][0]
    entries, materials, entry_of = [], [], {}

    def add(name, material):
        entry = copy.deepcopy(template)
        entry["name"]["$value"] = name
        entry["index"] = len(entries)
        entries.append(entry)
        materials.append(material)

    for chunk in base["Data"]["chunkMaterials"]:
        name = chunk["$value"]
        if name in entry_of:
            continue
        material = copy.deepcopy(buffer["materials"][index[name]])
        if name in body:
            entry_of[name] = f"@vcs{len(entry_of)}"
            hits = 0
            for value in material["values"]:
                if "MultilayerSetup" in value:
                    value["MultilayerSetup"]["DepotPath"]["$value"] = f"*{DEPOT}\\s\\{sid(body[name])}\\{{material}}.mlsetup"
                    value["MultilayerSetup"]["Flags"] = "Soft"
                    hits += 1
            assert hits == 1, (rel, name)
        else:
            entry_of[name] = "vcs_" + name
        add(entry_of[name], material)
    assert any(v.startswith("@") for v in entry_of.values()), rel

    appearances = []
    first = "vcs_" + SHOP[0][0]
    for n, (slug, _rgb) in enumerate(SHOP):
        a = copy.deepcopy(base)
        a["HandleId"] = str(n)
        a["Data"]["name"]["$value"] = "vcs_" + slug
        if n == 0:
            chunks = []
            for c in base["Data"]["chunkMaterials"]:
                one = copy.deepcopy(c)
                e = entry_of[c["$value"]]
                one["$value"] = first + e if e.startswith("@") else e
                chunks.append(one)
            a["Data"]["chunkMaterials"] = chunks
            a["Data"]["tags"] = []
        else:
            a["Data"]["chunkMaterials"] = []
            a["Data"]["tags"] = [cname(first)]
        appearances.append(a)
    root["appearances"] = appearances
    root["materialEntries"] = entries
    buffer["materials"] = materials
    root["parameters"] = []
    root["lodLevelInfo"] = []
    root["renderResourceBlob"] = None
    return doc


print(len(PLAN["meshes"]), "mesh patches", flush=True)
names = {}
xl = ["resource:", "  patch:"]
for rel, v in sorted(PLAN["meshes"].items()):
    stem = os.path.basename(rel)[:-len(".mesh")]
    name = stem if stem not in names else f"{stem}_{sid(rel)}"
    names[name] = rel
    save(patch(rel, v["appearance"], v["body"]), os.path.join(patches, name + ".mesh.json"))
    xl += [f"    {DEPOT}\\m\\{name}.mesh:", f"      - {rel}"]
out_m = os.path.join(target, "m")
os.makedirs(out_m)
wk("convert", "deserialize", patches, "-o", out_m)
made = [n for n in os.listdir(out_m) if n.endswith(".mesh")]
assert len(made) == len(names), (len(made), len(names))

# A round trip of one of each.
check = os.path.join(build, "check")
os.makedirs(check)
one = sorted(names)[0]
wk("convert", "serialize", os.path.join(out_m, one + ".mesh"), "-o", check)
doc = load(os.path.join(check, one + ".mesh.json"))["Data"]["RootChunk"]
print("patch", one, len(doc["appearances"]), "appearances;", [e["name"]["$value"] for e in doc["materialEntries"]][:6])
print(" first chunks", [c["$value"] for c in doc["appearances"][0]["Data"]["chunkMaterials"]][:4],
      " second tags", [t["$value"] for t in doc["appearances"][1]["Data"]["tags"]])
ident = sid(sorted(PLAN["setups"])[0])
wk("convert", "serialize", os.path.join(target, "s", ident, "vcs_alpine.mlsetup"), "-o", check)
layers = load(os.path.join(check, "vcs_alpine.mlsetup.json"))["Data"]["RootChunk"]["layers"]
print("paint", ident, [(i, l["material"]["DepotPath"]["$value"].split("\\")[-1], l["colorScale"]["$value"]) for i, l in enumerate(layers[:3])])

os.makedirs(OUT, exist_ok=True)
with open(os.path.join(OUT, "vehiclecustomizer_paint.archive.xl"), "w", encoding="utf-8") as f:
    f.write("\n".join(xl) + "\n")
print("packing", flush=True)
wk("pack", pack, "-o", OUT)
print("packed", round(os.path.getsize(os.path.join(OUT, "vehiclecustomizer_paint.archive")) / 1048576, 1), "MB")

# TweakDB: the colour list, and the options every one of whose meshes has the paints.
painted = set(PLAN["meshes"])
lines = ["# Written by experiments/paint/make-paints.py; don't edit by hand.",
         "VehicleCustomizer.shopPaints: [ " + ", ".join(f'n"vcs_{s}"' for s, _ in SHOP) + " ]"]
options = 0
for path in sorted(glob.glob(os.path.join(ROOT, "catalog", "out", "*.json"))):
    cat = load(path)
    for slot in cat["slots"]:
        for option in slot["options"]:
            meshes = [m.lower() for m in option["meshes"].values() if m]
            if meshes and all(m in painted for m in meshes):
                lines.append(f"VehicleCustomizer.{cat['id']}.option.{option['id']}.shopPaint: true")
                options += 1
extra_parts = 0
for cid, meshes in load(os.path.join(CACHE, "extra-parts.json"))["catalogs"].items():
    ready = [m for m in meshes if m in painted]
    if ready:
        lines.append(f"VehicleCustomizer.{cid}.shopMeshes: [ " + ", ".join(f'r"{m}"' for m in ready) + " ]")
        extra_parts += len(ready)
print(extra_parts, "parts outside the slots across the catalogs")
with open(os.path.join(TWEAKS, "shop-paints.yaml"), "w", encoding="utf-8") as f:
    f.write("\n".join(lines) + "\n")
print(options, "options can wear the shop's colours")
shutil.rmtree(build, ignore_errors=True)
print("done")
