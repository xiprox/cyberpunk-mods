"""Step 1 of the shop paints (RECORD.md, 2026-11-08): every mesh the catalogs use, and every paint file of the game's
vehicles, out of the game's archives and into WolvenKit's JSON, in experiments/paint/cache/ (out of git). Only reads.
Run with: python -I extract.py"""
import glob
import json
import os
import shutil
import subprocess

WK = r"H:\WolvenKit\Console\WolvenKit.CLI.exe"
GAME = r"C:\Program Files (x86)\Steam\steamapps\common\Cyberpunk 2077\archive\pc"
ARCHIVES = [os.path.join(GAME, "content", a + ".archive") for a in
            ("basegame_1_engine", "basegame_3_nightcity", "basegame_4_appearance", "basegame_4_gamedata")]
ARCHIVES += [os.path.join(GAME, "ep1", a + ".archive") for a in ("ep1_1_nightcity", "ep1_2_gamedata")]
HERE = os.path.dirname(os.path.abspath(__file__))
CATALOGS = os.path.join(HERE, "..", "..", "catalog", "out")
CACHE = os.path.join(HERE, "cache")
RAW, JS = os.path.join(CACHE, "raw"), os.path.join(CACHE, "json")


def wk(*args):
    subprocess.run([WK, *args, "-v", "Minimal"], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def catalog_meshes():
    meshes = set()
    for path in glob.glob(os.path.join(CATALOGS, "*.json")):
        with open(path, encoding="utf-8") as f:
            cat = json.load(f)
        for slot in cat["slots"]:
            for option in slot["options"]:
                meshes.update(option["meshes"].values())
        for kit in cat.get("kits", []):
            meshes.update(p["mesh"] for p in kit.get("parts", []) if p.get("mesh"))
        for wheels in cat.get("wheel_sets", []):
            if wheels.get("rim"):
                meshes.add(wheels["rim"])
    # The parts outside the slots (list-parts.py).
    extra = os.path.join(CACHE, "extra-parts.json")
    if os.path.exists(extra):
        with open(extra, encoding="utf-8") as f:
            meshes.update(json.load(f)["meshes"])
    return sorted(m.lower() for m in meshes if m)


def main():
    meshes = catalog_meshes()
    # Whole model folders, since the command line can't hold 1,800 paths; the unwanted ones are skipped below.
    folders = sorted({m.split("\\")[3] for m in meshes if len(m.split("\\")) > 4})
    pattern = r"vehicles\\[^\\]+\\(" + "|".join(folders) + r")\\.*\.mesh$|vehicles\\.*\.mlsetup$"
    print(len(meshes), "meshes in", len(folders), "folders")
    os.makedirs(RAW, exist_ok=True)
    print("unbundling")
    wk("unbundle", *ARCHIVES, "-o", RAW, "-r", pattern)
    wanted = set(meshes)
    kept, dropped = 0, 0
    found = set()
    for folder, _dirs, files in os.walk(RAW):
        for name in files:
            full = os.path.join(folder, name)
            rel = os.path.relpath(full, RAW).lower()
            if name.endswith(".mesh") and rel not in wanted:
                os.remove(full)
                dropped += 1
            else:
                kept += 1
                found.add(rel)
    missing = [m for m in meshes if m not in found]
    print("kept", kept, "dropped", dropped, "missing", len(missing), missing[:5])
    os.makedirs(JS, exist_ok=True)
    print("serializing what isn't yet")
    # One run per folder: a run per file costs about 4 s each just to start. A run takes subfolders too and flattens them,
    # so each folder's own files go through a staging folder of hard links.
    done = 0
    for folder, _dirs, files in os.walk(RAW):
        rel = os.path.relpath(folder, RAW)
        out = os.path.join(JS, rel)
        missing = [n for n in files if not os.path.exists(os.path.join(out, n + ".json"))]
        if not missing or "decoration" in rel:
            continue
        stage = os.path.join(CACHE, "stage")
        os.makedirs(stage)
        for name in missing:
            os.link(os.path.join(folder, name), os.path.join(stage, name))
        os.makedirs(out, exist_ok=True)
        wk("convert", "serialize", stage, "-o", out)
        shutil.rmtree(stage)
        done += len(missing)
        print(done, flush=True)
    print("done:", done, "files")


main()
