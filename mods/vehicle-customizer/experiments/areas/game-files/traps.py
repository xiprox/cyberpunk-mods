"""Small traps for part swaps: parts hanging off other parts, paints that differ per mesh, and mount points
holding more than one part."""
import collections
import json
import os

S = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")
apps = json.load(open(os.path.join(S, "apps.json"), encoding="utf-8"))
hella = next(v for k, v in apps.items() if k.endswith("base\\vehicles\\appearances\\standard\\archer_hella__basic.app"))

print("-- Hella, V's look: parts that hang off another part (bound to it rather than to a mount point) --")
look = hella["player_01"]
names = set(look)
for slot, c in sorted(look.items()):
    if c["slot"] in names and "shadow" not in slot:
        print(f"  {slot:40s} hangs off {c['slot']}")

print("\n-- Hella, 6th Street look: stickers and what they hang off --")
for slot, c in sorted(hella["6th_street_01"].items()):
    if "sticker" in slot:
        print(f"  {slot:40s} hangs off {c['slot']}")

print("\n-- across all cars: parts that hang off a swappable part --")
swappable = ("bumper_f_01", "bumper_b_01", "hood_a", "trunk_a", "door_fl_a", "door_fr_a", "door_bl_a", "door_br_a")
hangers = collections.Counter()
for app in apps.values():
    for comp in app.values():
        for slot, c in comp.items():
            if c["slot"] in swappable and "shadow" not in slot:
                hangers[c["slot"]] += 1
print(" ", dict(hangers))

print("\n-- mount points holding more than one visible part in one look (Hella, V's look) --")
by_mount = collections.defaultdict(list)
for slot, c in look.items():
    if "shadow" not in slot and slot != "None":
        by_mount[c["slot"]].append(slot)
for mount, slots in sorted(by_mount.items()):
    if len(slots) > 1 and mount not in ("Base", "None"):
        print(f"  {mount:24s} {sorted(slots)}")
