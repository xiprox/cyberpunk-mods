"""Step 2c of the shop paints (RECORD.md, 2026-11-08): every model folder's meshes as glb in cache/glb, so plan-paints.py can
measure what a paint layer covers on the real triangles and not on the whole texture sheet. Only reads the game. Run with:
python -I extract-geometry.py"""
import glob
import json
import os
import subprocess

WK = r"H:\WolvenKit\Console\WolvenKit.CLI.exe"
GAME = r"C:\Program Files (x86)\Steam\steamapps\common\Cyberpunk 2077"
ARCHIVES = [os.path.join(GAME, "archive", "pc", "content", a + ".archive") for a in
            ("basegame_1_engine", "basegame_3_nightcity", "basegame_4_appearance", "basegame_4_gamedata")]
ARCHIVES += [os.path.join(GAME, "archive", "pc", "ep1", a + ".archive") for a in ("ep1_1_nightcity", "ep1_2_gamedata")]
HERE = os.path.dirname(os.path.abspath(__file__))
CATALOGS = os.path.join(HERE, "..", "..", "catalog", "out")
OUT = os.path.join(HERE, "cache", "glb")

folders = set()
for path in glob.glob(os.path.join(CATALOGS, "*.json")):
    with open(path, encoding="utf-8") as f:
        cat = json.load(f)
    for slot in cat["slots"]:
        for option in slot["options"]:
            for mesh in option["meshes"].values():
                parts = mesh.lower().split("\\")
                if len(parts) > 4:
                    folders.add(parts[3])
extra = os.path.join(HERE, "cache", "extra-parts.json")
if os.path.exists(extra):
    with open(extra, encoding="utf-8") as f:
        folders.update(m.split("\\")[3] for m in json.load(f)["meshes"] if len(m.split("\\")) > 4)
os.makedirs(OUT, exist_ok=True)
pattern = r"vehicles\\[^\\]+\\(" + "|".join(sorted(folders)) + r")\\.*\.mesh$"
print(len(folders), "model folders", flush=True)
subprocess.run([WK, "uncook", *ARCHIVES, "-o", OUT, "-r", pattern, "--mesh-export-type", "MeshOnly", "-gp", GAME, "-v", "Minimal"],
               check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
count = sum(1 for _d, _s, files in os.walk(OUT) for n in files if n.endswith(".glb"))
print(count, "glb files")
