"""Builds the held tools' archive from the game's own Lexington files and blockout.py's meshes (RECORD.md, 2026-11-08).

Reads the templates out of the game with WolvenKit, edits their JSON, imports our geometry, and packs
mod/archive/pc/mod/vehiclecustomizer/vehiclecustomizer_tools.archive with its .archive.xl. Game files stay in work/, out of git.
Installs nothing. Run with: python -I make-tools.py
"""
import copy
import hashlib
import json
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MOD = os.path.dirname(HERE)
WORK = os.path.join(HERE, "work")
GAME = r"C:\Program Files (x86)\Steam\steamapps\common\Cyberpunk 2077"
CONTENT = os.path.join(GAME, "archive", "pc", "content")
CLI = r"H:\WolvenKit\Console\WolvenKit.CLI.exe"
BLENDER = r"C:\Program Files\Blender Foundation\Blender 5.1\blender.exe"
TEMPLATES = os.path.join(WORK, "templates")
JSONS = os.path.join(WORK, "json")
PACK = os.path.join(WORK, "vehiclecustomizer_tools")
OUT = os.path.join(WORK, "out")
GLB = os.path.join(WORK, "glb")
DEPOT = "vehicle_customizer\\tools"
LEX = "base\\weapons\\firearms\\handgun\\militech_lexington"
LEX_NAME = "w_handgun__militech_lexington"
BODY_COMPONENT = LEX_NAME + "__base1_01"
SHADOW_COMPONENT = "Mesh7743"
SCREEN_COMPONENT = "vc_tool_screen"
HOUSING_COMPONENT = "vc_tool_housing"
WIDGET_COMPONENT = "vc_tool_screen_ui"
WIDGET_SIZE = (512.0, 512.0)  # square, as the game draws it; the screen shows its middle band (blockout.py). 1024 blanked the screen, or the backing did (RECORD.md)
TOOLS = {"wrench": ("Items.VC_Tool", "VC_Tool_Wrench"), "paint": ("Items.VC_PaintTool", "VC_Tool_Paint")}
TEXTS = [
    ("vc_tool_wrench_name", "Shop Wrench"),
    ("vc_tool_wrench_desc", "Directs a shop's machines. Aim at a car to change its parts, wheels, style and add-ons."),
    ("vc_tool_paint_name", "Shop Paint Tool"),
    ("vc_tool_paint_desc", "Directs a shop's paint machines. Load a color and apply it to whatever you aim at."),
]

# The screen's material: the Militech HMG's counter (the one seen working in the game, RECORD.md 2026-11-07), with its ghost
# layers and scanlines turned down so small text stays sharp. The game's own device screens (base\materials\screen\screen_ui.mi
# and its neighbours) all set Metalness 0 and keep the smooth default surface, so they behave like glass. Metalness left at 0.9
# turned the screen into a white sheet in the sun, and RoughnessScale 0.85 into a flat grey board (user's screenshots, 2026-11-08).
# Their default RoughnessScale of 0.1 still spread the sun into a soft blob and read as plastic (user, with path tracing on), so
# ours is much smoother, for crisp reflections like hard glass. EmissiveEV is above their indoor 2.5 to 4 because the text has
# to hold up in daylight. To tune by eye in the game.
SCREEN_VALUES = [
    {"$type": "Vector4", "IntensityPerLayer": {"$type": "Vector4", "W": 0, "X": 1, "Y": 0, "Z": 0}},
    {"$type": "Float", "ScanlinesIntensity": 0.1},
    {"$type": "Float", "LayersSeparation": 0.0},
    {"$type": "Float", "Metalness": 0.0},
    {"$type": "Float", "RoughnessScale": 0.05},  # 0.02 was a mirror, a little too sharp (user)
    {"$type": "Float", "EmissiveEV": 6.0},  # with nothing over the menu any more, 9 bloomed (user)
]
# The placeholder body's flat material, on the engine's plain metal.
BODY_VALUES = [
    {"$type": "Vector4", "BaseColorScale": {"$type": "Vector4", "W": 1, "X": 0.09, "Y": 0.09, "Z": 0.10}},
    {"$type": "Float", "MetalnessScale": 0.15},
    {"$type": "Float", "RoughnessScale": 0.65},
]


def run(args, what):
    r = subprocess.run(args, capture_output=True, text=True, encoding="utf-8", errors="replace")
    if r.returncode != 0 or "Error" in r.stdout:
        lines = [x for x in r.stdout.splitlines() if "Error" in x or "error" in x]
        sys.exit(f"FAILED: {what}\n" + "\n".join(lines[:12]) + "\n" + r.stderr[:800])
    return r.stdout


def wk(*args, what=""):
    return run([CLI, *args, "-v", "Minimal"], what or " ".join(args[:2]))


def unbundle(archive, regex):
    wk("unbundle", os.path.join(CONTENT, archive + ".archive"), "-o", TEMPLATES, "-r", regex, what="unbundle " + regex)


def template(rel):
    path = os.path.join(TEMPLATES, rel)
    if not os.path.exists(path):
        sys.exit("missing template: " + rel)
    return path


def serialize(path):
    name = os.path.basename(path) + ".json"
    out = os.path.join(JSONS, name)
    if not os.path.exists(out):
        wk("convert", "serialize", path, "-o", JSONS, what="serialize " + name)
    return out


def load(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def deserialize_to(doc, rel):
    """Write JSON next to its final place in the depot and turn it into the game's format."""
    target = os.path.join(PACK, rel)
    folder = os.path.dirname(target)
    os.makedirs(folder, exist_ok=True)
    tmp = os.path.join(WORK, "tmp", os.path.basename(rel) + ".json")
    os.makedirs(os.path.dirname(tmp), exist_ok=True)
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(doc, f, indent=1)
    wk("convert", "deserialize", tmp, "-o", folder, what="deserialize " + rel)
    if not os.path.exists(target):
        sys.exit("deserialize wrote nothing at " + target)


def cname(text):
    return {"$type": "CName", "$storage": "string", "$value": text}


def respath(text):
    return {"$type": "ResourcePath", "$storage": "string", "$value": text}


def cruid(text):
    return str(int(hashlib.md5(text.encode()).hexdigest()[:15], 16) << 4)


def expand_handles(root):
    """Cooked files share objects: the first use defines a handle, later ones refer to it, and the components refer into the
    compiled chunks. Taking components out would strand references, so every reference becomes its own copy."""
    defs = {}

    def collect(n):
        if isinstance(n, dict):
            if "HandleId" in n and "Data" in n:
                defs[n["HandleId"]] = n["Data"]
            for v in n.values():
                collect(v)
        elif isinstance(n, list):
            for v in n:
                collect(v)

    collect(root)
    counter = [100]

    def rebuild(n, path):
        if isinstance(n, dict):
            if "HandleRefId" in n:
                ref = n["HandleRefId"]
                if ref in path:
                    raise ValueError("handle cycle " + ref)
                counter[0] += 1
                new_id = str(counter[0])
                return {"HandleId": new_id, "Data": rebuild(copy.deepcopy(defs[ref]), path | {ref})}
            if "HandleId" in n and "Data" in n:
                counter[0] += 1
                new_id = str(counter[0])
                return {"HandleId": new_id, "Data": rebuild(n["Data"], path | {n["HandleId"]})}
            return {k: rebuild(v, path) for k, v in n.items()}
        if isinstance(n, list):
            return [rebuild(v, path) for v in n]
        return n

    return rebuild(root, frozenset())


def comp_name(c):
    return c["name"]["$value"]


def set_mesh(c, path):
    c["mesh"]["DepotPath"] = respath(path)
    c["mesh"]["Flags"] = "Default"


def binding(kind, target):
    return {"HandleId": "0", "Data": dict(kind, bindName=cname(target))}


def rigid_part(shadow, name, tool, mesh):
    """A rigid mesh parented as the Lexington's own shadow mesh is, so it can be moved by script (ToolScreens.reds)."""
    part = copy.deepcopy(shadow)
    part["name"] = cname(name)
    part["id"] = cruid(tool + name)
    set_mesh(part, mesh)
    for key in ("castShadows", "castLocalShadows", "castRayTracedGlobalShadows", "castRayTracedLocalShadows"):
        part[key] = "Never"
    return part


def add_screen(components, tool, widget_template, paths):
    shadow = next(c for c in components if comp_name(c) == SHADOW_COMPONENT)
    screen_mesh, widget_path = paths["screen"], paths["widget"]
    components.append(rigid_part(shadow, HOUSING_COMPONENT, tool, paths["housing"]))
    screen = rigid_part(shadow, SCREEN_COMPONENT, tool, screen_mesh)
    widget = copy.deepcopy(widget_template)
    widget["name"] = cname(WIDGET_COMPONENT)
    widget["id"] = cruid(tool + WIDGET_COMPONENT)
    widget["widgetResource"]["DepotPath"] = respath(widget_path)
    widget["widgetResource"]["Flags"] = "Default"
    for key in ("meshTargetBinding", "parentTransform"):
        widget[key]["Data"]["bindName"] = cname(SCREEN_COMPONENT)
    components.append(screen)
    components.append(widget)


def edit_components(components, tool, kind, widget_template, paths):
    keep = []
    for c in components:
        t = c["$type"]
        name = comp_name(c)
        if t in ("entSkinnedMeshComponent", "entMeshComponent"):
            if kind == "body" and name == BODY_COMPONENT:
                set_mesh(c, paths["body"])
            elif kind == "body" and name == SHADOW_COMPONENT:
                set_mesh(c, paths["shadow"])
            else:
                continue
        keep.append(c)
    components[:] = keep
    if kind == "body":
        add_screen(components, tool, widget_template, paths)


def make_app(source, target_rel, tool, kind, preset, widget_template, paths):
    """One appearance named default, our meshes in it, in both the plain list and the compiled copy the game also carries."""
    doc = load(source)
    root = doc["Data"]["RootChunk"]
    root["appearances"] = [root["appearances"][0]]
    root = expand_handles(root)
    doc["Data"]["RootChunk"] = root
    if preset:
        root["preset"] = cname(preset)
    ap = root["appearances"][0]["Data"]
    compiled = ap["compiledData"]["Data"]
    edit_components(ap["components"], tool, kind, widget_template, paths)
    edit_components(compiled["Chunks"], tool, kind, widget_template, paths)
    compiled["CruidDict"] = {str(i): c["id"] for i, c in enumerate(compiled["Chunks"])}
    deps = [d for d in ap["resolvedDependencies"] if not d["DepotPath"]["$value"].endswith(".mesh")]
    if kind == "body":
        for p in (paths["body"], paths["screen"], paths["housing"], paths["shadow"], paths["widget"]):
            deps.append({"DepotPath": respath(p), "Flags": "Soft"})
    ap["resolvedDependencies"] = deps
    # The added screen is copied from other components, ids included, and WolvenKit's reader needs every id unique.
    doc["Data"]["RootChunk"] = expand_handles(root)
    deserialize_to(doc, target_rel)


def make_mesh(template_path, glb_name, target_rel, material_base, values, material_name):
    """Our geometry in a copy of a game mesh, then its materials cut down to one."""
    target = os.path.join(PACK, target_rel)
    os.makedirs(os.path.dirname(target), exist_ok=True)
    shutil.copyfile(template_path, target)
    glb = os.path.join(GLB, glb_name + ".glb")
    wk("import", glb, "-o", os.path.dirname(target), "-k", what="import " + glb_name)
    tmp_dir = os.path.join(WORK, "tmp")
    os.makedirs(tmp_dir, exist_ok=True)
    wk("convert", "serialize", target, "-o", tmp_dir, what="serialize " + glb_name)
    doc = load(os.path.join(tmp_dir, os.path.basename(target) + ".json"))
    root = doc["Data"]["RootChunk"]
    chunks = len(root["appearances"][0]["Data"]["chunkMaterials"])
    blob = root["renderResourceBlob"]["Data"]["header"]
    real = len(blob["renderChunkInfos"])
    root["appearances"] = [root["appearances"][0]]
    root["appearances"][0]["Data"]["name"] = cname("default")
    if material_base:
        root["appearances"][0]["Data"]["chunkMaterials"] = [cname(material_name)] * real
        root["materialEntries"] = [{"$type": "CMeshMaterialEntry", "index": 0, "isLocalInstance": 1, "name": cname(material_name)}]
        root["preloadLocalMaterialInstances"] = [{"HandleId": "9000", "Data": {
            "$type": "CMaterialInstance", "audioTag": cname("None"),
            "baseMaterial": {"DepotPath": respath(material_base), "Flags": "Default"},
            "cookingPlatform": "PLATFORM_None", "enableMask": 0, "metadata": None, "resourceVersion": 4, "values": values}}]
        root["localMaterialInstances"] = []
        root["externalMaterials"] = []
        root["preloadExternalMaterials"] = []
    print(f"  {glb_name}: template chunks {chunks}, ours {real}, bones {[b['$value'] for b in root['boneNames']]}")
    os.remove(target)
    deserialize_to(doc, target_rel)
    # the JSON round trip keeps the geometry's buffer; put the geometry back to be sure
    wk("import", glb, "-o", os.path.dirname(target), "-k", what="re-import " + glb_name)


def make_widget(source, target_rel):
    doc = load(source)
    root = doc["Data"]["RootChunk"]
    item = root["libraryItems"][0]["package"]["Data"]["File"]["RootChunk"]
    # The file holds the root canvas twice and the game read the one the first version of this left at 512 by 512
    # (the log's "root reports"), so every canvas named Root gets the size.
    roots = []

    def walk(n):
        if isinstance(n, dict):
            if n.get("$type") == "inkCanvasWidget" and (n.get("name") or {}).get("$value") == "Root" and isinstance(n.get("size"), dict):
                roots.append(n)
            for v in n.values():
                walk(v)
        elif isinstance(n, list):
            for v in n:
                walk(v)

    walk(root)
    if not roots:
        sys.exit("no root canvas in the widget")
    for canvas in roots:
        canvas["size"]["X"], canvas["size"]["Y"] = WIDGET_SIZE
    print(f"  widget: {len(roots)} root canvases set to {WIDGET_SIZE}")
    deserialize_to(doc, target_rel)


def make_factory(source, target_rel, rows):
    doc = load(source)
    doc["Data"]["RootChunk"]["compiledData"] = [[name, path, "false"] for name, path in rows]
    deserialize_to(doc, target_rel)


def make_text(source, target_rel, texts):
    """The items' names and descriptions, as the game's own text file; femaleVariant is the one used when maleVariant is empty."""
    doc = load(source)
    data = doc["Data"]["RootChunk"]["root"]["Data"]
    entry = data["entries"][0]
    data["entries"] = [dict(entry, femaleVariant=text, maleVariant="", primaryKey="0", secondaryKey=key) for key, text in texts]
    deserialize_to(doc, target_rel)


def main():
    for folder in (PACK, OUT, GLB, os.path.join(WORK, "tmp")):
        shutil.rmtree(folder, ignore_errors=True)
    for folder in (TEMPLATES, JSONS, PACK, OUT, GLB):
        os.makedirs(folder, exist_ok=True)
    print("templates")
    if not os.path.exists(os.path.join(TEMPLATES, LEX, LEX_NAME + ".app")):
        unbundle("basegame_4_gamedata", r"militech_lexington.(appearances.)?w_handgun__militech_lexington(__base1_01|__mag_std_01|__mag_stdr_01)?\.app$")
        for archive in ("basegame_3_nightcity", "basegame_4_gamedata"):
            unbundle(archive, r"militech_lexington.entities.meshes.w_handgun__militech_lexington__base1_01(_shadow)?\.mesh$")
        unbundle("basegame_4_gamedata", r"militech_hmg.w_special__militech_hmg\.app$|crosshair.militech_hmg\.inkwidget$|factories.items.weapons.weapons_appearances\.csv$")
    text_template = "base\\localization\\en-us\\onscreens\\onscreens_final.json"
    if not os.path.exists(os.path.join(TEMPLATES, text_template)):
        unbundle("lang_en_text", r"base.localization.en-us.onscreens.onscreens_final\.json$")
    print("meshes from blender")
    r = subprocess.run([BLENDER, "-b", "--factory-startup", "-P", os.path.join(HERE, "blockout.py"), "--", GLB], capture_output=True, text=True, encoding="utf-8", errors="replace")
    if r.stdout.count("WROTE") != 8:
        sys.exit("blender failed:\n" + r.stdout[-1500:] + r.stderr[-800:])

    hmg_doc = load(serialize(template("base\\weapons\\firearms\\special\\militech_hmg\\w_special__militech_hmg.app")))
    hmg_root = expand_handles(hmg_doc["Data"]["RootChunk"])
    hmg_components = hmg_root["appearances"][0]["Data"]["components"]
    widget_template = next(c for c in hmg_components if c["$type"] == "WorldWidgetComponent")

    widget_rel = DEPOT + "\\vc_tool_screen.inkwidget"
    make_widget(serialize(template("base\\gameplay\\gui\\widgets\\crosshair\\militech_hmg.inkwidget")), widget_rel)

    apps = LEX + "\\appearances\\"
    root_app = serialize(template(LEX + "\\" + LEX_NAME + ".app"))
    body_app = serialize(template(apps + LEX_NAME + "__base1_01.app"))
    mag_app = serialize(template(apps + LEX_NAME + "__mag_std_01.app"))
    magr_app = serialize(template(apps + LEX_NAME + "__mag_stdr_01.app"))
    mesh_t = template(LEX + "\\entities\\meshes\\" + LEX_NAME + "__base1_01.mesh")
    shadow_t = template(LEX + "\\entities\\meshes\\" + LEX_NAME + "__base1_01_shadow.mesh")

    rows = [("VC_Tool_Mag", DEPOT + "\\vc_tool_mag.app"), ("VC_Tool_MagR", DEPOT + "\\vc_tool_magr.app")]
    for tool, (record, name) in TOOLS.items():
        print("tool", tool)
        folder = f"{DEPOT}\\{tool}"
        paths = {"body": f"{folder}\\vc_{tool}_body.mesh", "screen": f"{folder}\\vc_{tool}_screen.mesh", "housing": f"{folder}\\vc_{tool}_housing.mesh", "shadow": f"{folder}\\vc_{tool}_shadow.mesh", "widget": widget_rel}
        make_mesh(mesh_t, f"vc_{tool}_body", paths["body"], "engine\\materials\\metal_base.remt", BODY_VALUES, "body")
        make_mesh(mesh_t, f"vc_{tool}_housing", paths["housing"], "engine\\materials\\metal_base.remt", BODY_VALUES, "body")
        make_mesh(mesh_t, f"vc_{tool}_screen", paths["screen"], "base\\materials\\metal_base_ui.mt", SCREEN_VALUES, "screen")
        make_mesh(shadow_t, f"vc_{tool}_shadow", paths["shadow"], None, None, "shadow")
        make_app(root_app, f"{folder}\\vc_{tool}.app", tool, "body", record, widget_template, paths)
        make_app(body_app, f"{folder}\\vc_{tool}_body.app", tool, "body", None, widget_template, paths)
        rows += [(name, f"{folder}\\vc_{tool}.app"), (name + "_Body", f"{folder}\\vc_{tool}_body.app")]
    none = {}
    make_app(mag_app, DEPOT + "\\vc_tool_mag.app", "shared", "mag", None, None, none)
    make_app(magr_app, DEPOT + "\\vc_tool_magr.app", "shared", "mag", None, None, none)
    make_factory(serialize(template("base\\gameplay\\factories\\items\\weapons\\weapons_appearances.csv")), DEPOT + "\\vc_tools_factory.csv", rows)
    make_text(serialize(template(text_template)), DEPOT + "\\vc_tools_text.json", TEXTS)

    print("pack")
    wk("pack", PACK, "-o", OUT, what="pack")
    archive = os.path.join(OUT, "vehiclecustomizer_tools.archive")
    if not os.path.exists(archive):
        sys.exit("pack wrote nothing")
    dest = os.path.join(MOD, "mod", "archive", "pc", "mod", "vehiclecustomizer")
    shutil.copyfile(archive, os.path.join(dest, "vehiclecustomizer_tools.archive"))
    with open(os.path.join(dest, "vehiclecustomizer_tools.archive.xl"), "w", encoding="utf-8", newline="\n") as f:
        f.write("# Generated by tool-models/make-tools.py; don't edit by hand.\n# The held tools' appearances, by the names Items.VC_Tool and Items.VC_PaintTool use (tool.yaml).\n")
        f.write("factories:\n  - " + DEPOT + "\\vc_tools_factory.csv\n")
        f.write("localization:\n  onscreens:\n    en-us: " + DEPOT + "\\vc_tools_text.json\n")
    print("done:", os.path.getsize(archive), "bytes")


main()
