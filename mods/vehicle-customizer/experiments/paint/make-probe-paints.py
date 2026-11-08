"""Paint files for the colour probes (RECORD.md, 2026-11-08; dev job "paint"): a copy of the game's car paint surface
with colours of our own added to its palette, and a Hella paint whose body layer uses one of them. Goes into
dev/archive/pc/mod/vehiclecustomizerdev/vc_paintprobe.archive. Run with: python -I make-probe-paints.py"""
import copy
import json
import os
import shutil
import subprocess
import tempfile

WK = r"H:\WolvenKit\Console\WolvenKit.CLI.exe"
CONTENT = r"C:\Program Files (x86)\Steam\steamapps\common\Cyberpunk 2077\archive\pc\content"
ARCHIVES = ["basegame_1_engine", "basegame_3_nightcity", "basegame_4_appearance", "basegame_4_gamedata"]
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "dev", "archive", "pc", "mod", "vehiclecustomizerdev")
DEPOT = r"vehiclecustomizerdev\paint"
SURFACE = DEPOT + r"\vc_car_paint.mltemplate"
COLOURS = {"vc_magenta": (1.0, 0.0, 1.0), "vc_cyan": (0.0, 1.0, 1.0), "vc_lime": (0.25, 1.0, 0.0)}


# catalog/shop-palette.json holds what's seen on screen (sRGB); a surface's palette is linear.
def linear(channel):
    c = channel / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


with open(os.path.join(HERE, "..", "..", "catalog", "shop-palette.json"), encoding="utf-8") as f:
    SHOP = [(name.lower().replace(" ", "_"), tuple(linear(int(hex_[i:i + 2], 16)) for i in (1, 3, 5)))
            for group in json.load(f)["groups"] for name, hex_ in group["colours"]]
assert len(SHOP) == 89 and len({s for s, _ in SHOP}) == 89, len(SHOP)
COLOURS.update({"vc_s_" + slug: rgb for slug, rgb in SHOP})
LUA_COLOURS = os.path.join(HERE, "..", "..", "dev", "bin", "x64", "plugins", "cyber_engine_tweaks", "mods", "VehicleCustomizerDev", "paint-colours.lua")


def wk(*args):
    subprocess.run([WK, *args, "-v", "Minimal"], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def find(root, name):
    for folder, _dirs, files in os.walk(root):
        if name in files:
            return os.path.join(folder, name)
    raise SystemExit(f"{name} not found under {root}")


work = tempfile.mkdtemp(prefix="vc-paint-")
src, js, pack = (os.path.join(work, x) for x in ("src", "json", "vc_paintprobe"))
os.makedirs(js)
MESH_DIR = r"base\vehicles\standard\v_standard2_archer_hella\entities\meshes"
DOORS = {c: f"v_standard2_archer_hella__ext01_door_{c}_01" for c in ("fl", "fr", "bl", "br")}
wk("unbundle", *[os.path.join(CONTENT, a + ".archive") for a in ARCHIVES], "-o", src,
   "-r", r"(car_paint_metallic_01\.mltemplate|v_standard2_archer_hella\\entities\\meshes\\textures\\suburban_01\.mlsetup"
         r"|v_standard2_archer_hella\\entities\\meshes\\v_standard2_archer_hella__ext01_door_(fl|fr|bl|br)_01\.mesh)$")
surface_src, setup_src = find(src, "car_paint_metallic_01.mltemplate"), find(src, "suburban_01.mlsetup")
wk("convert", "serialize", surface_src, "-o", js)
wk("convert", "serialize", setup_src, "-o", js)
for mesh in DOORS.values():
    wk("convert", "serialize", find(src, mesh + ".mesh"), "-o", js)

# Our surface: the game's, with our colours added to its palette.
with open(os.path.join(js, "car_paint_metallic_01.mltemplate.json"), encoding="utf-8") as f:
    surface = json.load(f)
palette = surface["Data"]["RootChunk"]["overrides"]["colorScale"]
for name, rgb in COLOURS.items():
    entry = copy.deepcopy(palette[0])
    entry["n"]["$value"] = name
    entry["v"]["Elements"] = list(rgb)
    palette.append(entry)

# The Suburban paint with its body layer in our surface and magenta.
with open(os.path.join(js, "suburban_01.mlsetup.json"), encoding="utf-8") as f:
    setup = json.load(f)
body = setup["Data"]["RootChunk"]["layers"][0]
assert "car_paint_metallic_01" in body["material"]["DepotPath"]["$value"], body["material"]
body["material"]["DepotPath"]["$value"] = SURFACE
body["colorScale"]["$value"] = "vc_magenta"

# The same in lime and cyan, for colours edited in memory before anything has drawn them.
def tinted(colour):
    doc = copy.deepcopy(setup)
    doc["Data"]["RootChunk"]["layers"][0]["colorScale"]["$value"] = colour
    return doc


# A patch for ArchiveXL: new paints for a door mesh, each the Suburban paint with its body material pointing at one of
# ours. Self-contained: every material its appearances use is in the patch, under a name of ours, since a patch can't
# change the target's materials (wiki, Resource patching). No geometry: a mesh patch only carries appearances.
PAINTS = ("magenta", "lime", "cyan")


def door_patch(mesh):
    with open(os.path.join(js, mesh + ".mesh.json"), encoding="utf-8") as f:
        doc = json.load(f)
    root = doc["Data"]["RootChunk"]
    buffer = root["localMaterialBuffer"]
    index = {e["name"]["$value"]: e["index"] for e in root["materialEntries"]}
    base = next(a for a in root["appearances"] if a["Data"]["name"]["$value"] == "suburban_01")
    used = []
    for c in base["Data"]["chunkMaterials"]:
        if c["$value"] not in used:
            used.append(c["$value"])
    body = "suburban_01_ext"
    assert body in used, used
    entries, materials, appearances = [], [], []

    def add(name, material):
        entry = copy.deepcopy(root["materialEntries"][0])
        entry["name"]["$value"] = name
        entry["index"] = len(entries)
        entries.append(entry)
        materials.append(material)

    for name in used:
        if name != body:
            add("vc_" + name, copy.deepcopy(buffer["materials"][index[name]]))
    for n, paint in enumerate(PAINTS):
        material = copy.deepcopy(buffer["materials"][index[body]])
        for value in material["values"]:
            if "MultilayerSetup" in value:
                value["MultilayerSetup"]["DepotPath"]["$value"] = DEPOT + "\\door_" + paint + ".mlsetup"
        add("vc_ext_" + paint, material)
        appearance = copy.deepcopy(base)
        appearance["HandleId"] = str(n)
        appearance["Data"]["name"]["$value"] = "vc_" + paint
        for c in appearance["Data"]["chunkMaterials"]:
            c["$value"] = "vc_ext_" + paint if c["$value"] == body else "vc_" + c["$value"]
        appearances.append(appearance)
    root["appearances"] = appearances
    root["materialEntries"] = entries
    buffer["materials"] = materials
    root["parameters"] = []
    root["lodLevelInfo"] = []
    root["renderResourceBlob"] = None
    return doc


# The shop's 89 colours (catalog/shop-palette.json) on the same doors, two ways, for job "paintscale". Unlike door_patch,
# both paint the door's far-away chunks too: its lod_ext_suburban_01 material names the same paint file as the near one,
# so a patch that leaves it alone keeps the old colour at a distance.
#   Plain ("vcp_<colour>"): an appearance and two materials for every colour.
#   Dynamic ("vcd_<colour>"): ArchiveXL's dynamic materials. Two template materials (@vc_ext, @vc_far) whose paint path
#   has {material} in it; the first appearance's chunks say "vcd_<colour>@vc_ext", the rest have no chunks and name the
#   first in their tag, so ArchiveXL expands them (wiki; Mesh/Extension.cpp, ResourcePatch/Extension.cpp).
BODY, FAR = "suburban_01_ext", "lod_ext_suburban_01"


def cname(value):
    return {"$type": "CName", "$storage": "string", "$value": value}


def shop_patch(mesh, route):
    with open(os.path.join(js, mesh + ".mesh.json"), encoding="utf-8") as f:
        doc = json.load(f)
    root = doc["Data"]["RootChunk"]
    buffer = root["localMaterialBuffer"]
    index = {e["name"]["$value"]: e["index"] for e in root["materialEntries"]}
    base = next(a for a in root["appearances"] if a["Data"]["name"]["$value"] == "suburban_01")
    used = []
    for c in base["Data"]["chunkMaterials"]:
        if c["$value"] not in used:
            used.append(c["$value"])
    assert BODY in used and FAR in used, used
    prefix = "vcp_" if route == "plain" else "vcd_"
    entries, materials, appearances = [], [], []

    def add(name, material):
        entry = copy.deepcopy(root["materialEntries"][0])
        entry["name"]["$value"] = name
        entry["index"] = len(entries)
        entries.append(entry)
        materials.append(material)

    def painted(name, path, soft):
        material = copy.deepcopy(buffer["materials"][index[name]])
        hits = 0
        for value in material["values"]:
            if "MultilayerSetup" in value:
                value["MultilayerSetup"]["DepotPath"]["$value"] = path
                if soft:
                    value["MultilayerSetup"]["Flags"] = "Soft"
                hits += 1
        assert hits == 1, name
        return material

    def appearance(n, name, chunks, tags):
        a = copy.deepcopy(base)
        a["HandleId"] = str(n)
        a["Data"]["name"]["$value"] = name
        a["Data"]["chunkMaterials"] = chunks
        a["Data"]["tags"] = tags
        return a

    def chunks(body, far):
        out = []
        for c in base["Data"]["chunkMaterials"]:
            one = copy.deepcopy(c)
            one["$value"] = body if c["$value"] == BODY else far if c["$value"] == FAR else prefix + c["$value"]
            out.append(one)
        return out

    for name in used:
        if name not in (BODY, FAR):
            add(prefix + name, copy.deepcopy(buffer["materials"][index[name]]))
    if route == "plain":
        for n, (slug, _rgb) in enumerate(SHOP):
            app = prefix + slug
            path = f"{DEPOT}\\plain\\{app}.mlsetup"
            add(app + "_ext", painted(BODY, path, False))
            add(app + "_far", painted(FAR, path, False))
            appearances.append(appearance(n, app, chunks(app + "_ext", app + "_far"), []))
    else:
        path = f"*{DEPOT}\\dyn\\{{material}}.mlsetup"
        add("@vc_ext", painted(BODY, path, True))
        add("@vc_far", painted(FAR, path, True))
        first = prefix + SHOP[0][0]
        for n, (slug, _rgb) in enumerate(SHOP):
            app = prefix + slug
            if n == 0:
                appearances.append(appearance(n, app, chunks(app + "@vc_ext", app + "@vc_far"), []))
            else:
                appearances.append(appearance(n, app, [], [cname(first)]))
    root["appearances"] = appearances
    root["materialEntries"] = entries
    buffer["materials"] = materials
    root["parameters"] = []
    root["lodLevelInfo"] = []
    root["renderResourceBlob"] = None
    return doc


target = os.path.join(pack, DEPOT)
os.makedirs(target)
ours = os.path.join(work, "ours")
os.makedirs(ours)
files = [(surface, "vc_car_paint.mltemplate"), (setup, "door_magenta.mlsetup"), (tinted("vc_lime"), "door_lime.mlsetup"),
         (tinted("vc_cyan"), "door_cyan.mlsetup")]
files += [(door_patch(mesh), f"door_{c}_patch.mesh") for c, mesh in DOORS.items()]
for route in ("plain", "dyn"):
    files += [(shop_patch(mesh, route), f"door_{c}_{route}.mesh") for c, mesh in DOORS.items()]
for doc, name in files:
    with open(os.path.join(ours, name + ".json"), "w", encoding="utf-8") as f:
        json.dump(doc, f, indent=1)
    wk("convert", "deserialize", os.path.join(ours, name + ".json"), "-o", target)
    assert os.path.exists(os.path.join(target, name)), name

# A paint file per colour and route: separate files, so neither route finds the other's already loaded.
for route, prefix in (("plain", "vcp_"), ("dyn", "vcd_")):
    folder = os.path.join(work, "setups_" + route)
    out = os.path.join(target, route)
    os.makedirs(folder)
    os.makedirs(out)
    for slug, _rgb in SHOP:
        with open(os.path.join(folder, f"{prefix}{slug}.mlsetup.json"), "w", encoding="utf-8") as f:
            json.dump(tinted("vc_s_" + slug), f, indent=1)
    wk("convert", "deserialize", folder, "-o", out)
    made = [n for n in os.listdir(out) if n.endswith(".mlsetup")]
    assert len(made) == len(SHOP), (route, len(made))

# A round trip, to be sure the files say what we wrote.
check = os.path.join(work, "check")
os.makedirs(check)
wk("convert", "serialize", os.path.join(target, "door_magenta.mlsetup"), "-o", check)
wk("convert", "serialize", os.path.join(target, "vc_car_paint.mltemplate"), "-o", check)
with open(os.path.join(check, "door_magenta.mlsetup.json"), encoding="utf-8") as f:
    layer = json.load(f)["Data"]["RootChunk"]["layers"][0]
with open(os.path.join(check, "vc_car_paint.mltemplate.json"), encoding="utf-8") as f:
    colours = json.load(f)["Data"]["RootChunk"]["overrides"]["colorScale"]
print("layer 0:", layer["material"]["DepotPath"]["$value"], layer["colorScale"]["$value"])
print("palette:", len(colours), "colours, ending", [(c["n"]["$value"], c["v"]["Elements"]) for c in colours[-3:]])
wk("convert", "serialize", os.path.join(target, "door_fl_patch.mesh"), "-o", check)
with open(os.path.join(check, "door_fl_patch.mesh.json"), encoding="utf-8") as f:
    patch = json.load(f)["Data"]["RootChunk"]
buffer = patch["localMaterialBuffer"]
print("patch: appearances", [a["Data"]["name"]["$value"] for a in patch["appearances"]], "entries", len(patch["materialEntries"]),
      "materials", len(buffer["materials"]), "headers", len(buffer["rawDataHeaders"]),
      "raw files", len(buffer["rawData"]["Data"]["Files"]) if buffer.get("rawData") else None,
      "file bytes", os.path.getsize(os.path.join(target, "door_fl_patch.mesh")))
material = next(m for m, e in zip(buffer["materials"], patch["materialEntries"]) if e["name"]["$value"] == "vc_ext_cyan")
print("vc_ext_cyan's paint:", [v["MultilayerSetup"]["DepotPath"]["$value"] for v in material["values"] if "MultilayerSetup" in v])
for route in ("plain", "dyn"):
    name = f"door_fl_{route}.mesh"
    wk("convert", "serialize", os.path.join(target, name), "-o", check)
    with open(os.path.join(check, name + ".json"), encoding="utf-8") as f:
        one = json.load(f)["Data"]["RootChunk"]
    apps = one["appearances"]
    first = next(m for m in one["localMaterialBuffer"]["materials"] if any("MultilayerSetup" in v for v in m["values"]))
    ref = next(v["MultilayerSetup"] for v in first["values"] if "MultilayerSetup" in v)
    print(route, "patch:", os.path.getsize(os.path.join(target, name)), "bytes,", len(apps), "appearances,",
          len(one["materialEntries"]), "entries; first paint", ref["DepotPath"]["$value"], ref["Flags"])
    print("  first appearance's chunks:", [c["$value"] for c in apps[0]["Data"]["chunkMaterials"]][:5])
    print("  second appearance:", apps[1]["Data"]["name"]["$value"], len(apps[1]["Data"]["chunkMaterials"]), "chunks, tags",
          [t["$value"] for t in apps[1]["Data"]["tags"]])
    print("  entries:", [e["name"]["$value"] for e in one["materialEntries"]][:8])

os.makedirs(OUT, exist_ok=True)
xl = ["resource:", "  patch:"]
for c, mesh in DOORS.items():
    for kind in ("patch", "plain", "dyn"):
        xl += [f"    {DEPOT}\\door_{c}_{kind}.mesh:", f"      - {MESH_DIR}\\{mesh}.mesh"]
with open(os.path.join(OUT, "vc_paintprobe.archive.xl"), "w", encoding="utf-8") as f:
    f.write("\n".join(xl) + "\n")
with open(LUA_COLOURS, "w", encoding="utf-8") as f:
    f.write("-- Written by experiments/paint/make-probe-paints.py: the shop's colours, as the paints' names end.\nreturn {\n"
            + "".join(f'    "{slug}",\n' for slug, _ in SHOP) + "}\n")
wk("pack", pack, "-o", OUT)
print("packed:", os.path.join(os.path.abspath(OUT), "vc_paintprobe.archive"), os.path.getsize(os.path.join(OUT, "vc_paintprobe.archive")), "bytes")
shutil.rmtree(work, ignore_errors=True)
