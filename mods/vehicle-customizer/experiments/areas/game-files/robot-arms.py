"""What the robot arm entities are made of: components, effects, sounds, animations and looks."""
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pkg
import rdar

depot = pkg.Depot()
known = os.path.join(rdar.GAME, r"red4ext\plugins\Codeware\Data\KnownHashes.txt")
with open(known, encoding="utf-8", errors="replace") as f:
    depot.add_names(line.strip() for line in f if line.strip())

FIELDS = {"name", "mesh", "meshAppearance", "effect", "effectName", "graph", "animations", "rig", "audioName",
          "eventName", "soundName", "appearanceName", "resource", "eventsToPlay"}


def components(buffer):
    p = pkg.Package(buffer, depot)
    out = []
    for cls, obj in p.objects(only=FIELDS):
        bits = {k: (v[1] if isinstance(v, tuple) else v) for k, v in obj.items() if v not in (None, "None", "")}
        out.append((cls, bits))
    return out, p


def show_ent(path):
    loaded = depot.load(path)
    if not loaded:
        print(path, "NOT FOUND")
        return
    head, bufs = loaded
    c = pkg.Cooked(head, bufs, depot)
    root = c.exports[0][1]
    print(f"\n== {path}")
    looks = root.get("appearances", [])
    if isinstance(looks, list):
        for a in looks:
            res = a.get("appearanceResource")
            print(f"   look {a.get('name')} -> {a.get('appearanceName')} in {res[1] if isinstance(res, tuple) else res}")
    print("   imports:", [p for p, _c, _f in c.c.imports][:20])
    cd = root.get("compiledData")
    if cd:
        comps, p = components(c.buffer(cd[1]))
        print("   components:")
        for cls, bits in comps:
            if cls.startswith(("ent", "game", "Animation", "AnimationController", "Device", "Scriptable", "Robotic", "audio", "Audio")) or bits:
                print(f"     {cls:40s} {bits}")
        names = [n for n in p.names if any(k in n.lower() for k in ("spark", "weld", "work", "robot", "arm", "sfx", "dev_", "fx"))]
        print("   telling names:", names[:40])


def show_app(path):
    loaded = depot.load(path)
    if not loaded:
        print(path, "NOT FOUND")
        return
    head, bufs = loaded
    c = pkg.Cooked(head, bufs, depot)
    print(f"\n== {path}")
    for cls, d in c.exports:
        if cls != "appearanceAppearanceDefinition":
            continue
        cd = d.get("compiledData")
        if not cd:
            continue
        comps, p = components(c.buffer(cd[1]))
        print(f"   look {d.get('name')}:")
        for cls2, bits in comps:
            if bits:
                print(f"     {cls2:40s} {bits}")
        names = [n for n in p.names if any(k in n.lower() for k in ("spark", "weld", "work", "sfx", "fx", "effect"))]
        print("     telling names:", names[:30])


for ent in (r"ep1\gameplay\devices\robotic_arms\robotic_arms.ent",
            r"ep1\gameplay\devices\robotic_arms\appearances\robotic_arms.ent",
            r"base\items\interactive\industrial\int_industrial_002__robotic_arm_delamain.ent",
            r"base\gameplay\devices\activated\distraction\appearances\robotic_arm_delamain.ent"):
    show_ent(ent)
show_app(r"ep1\gameplay\devices\robotic_arms\appearances\robotic_arms_appearance.app")
