"""Exact names the in-game test needs for the Arch Nemesis (Nazare and Racer)."""
import collections
import json
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pkg
import rdar

S = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")
present = json.load(open(os.path.join(S, "parts.json"), encoding="utf-8"))["present"]
apps = json.load(open(os.path.join(S, "apps.json"), encoding="utf-8"))
depot = pkg.Depot()
depot.add_names(present)


def paints(path):
    loaded = depot.load(path)
    if not loaded:
        return None
    head, _ = loaded
    c = rdar.CR2W(head)
    off, n, _ = c.tables[4]
    out = []
    for i in range(n):
        cls, _f, _par, size, data_off, _t, _c = struct.unpack_from("<HHIIIII", head, off + i * 24)
        if c.names[cls] != "meshMeshAppearance":
            continue
        p = data_off + 1
        end = data_off + size
        while p + 8 <= end:
            ni = struct.unpack_from("<H", head, p)[0]
            if ni == 0:
                break
            _ti, sz = struct.unpack_from("<HI", head, p + 2)
            if c.names[ni] == "name":
                out.append(c.names[struct.unpack_from("<H", head, p + 8)[0]])
            p += 4 + sz
    return out


key = next(k for k in apps if k.endswith("arch_nemesis_basic.app"))
app = apps[key]
print(key)
print("looks:", sorted(app))

print("\n-- the looks with 'player' in the name --")
for look in sorted(app):
    if "player" in look:
        comp = app[look]
        print(f"  {look}")
        for slot in ("fairing_a_01", "fairing_a_01_shadow", "body_a_01", "body_b_01", "tire_f_01", "tire_b_01", "wheel_f_01", "wheel_b_01"):
            c = comp.get(slot)
            print(f"     {slot:22s} {c and (c['cls'], c['app'], os.path.basename(c['mesh']))}")

print("\n-- every fairing and what uses it --")
for slot in ("fairing_a_01", "fairing_a_01_shadow"):
    options = collections.defaultdict(list)
    for look, comp in app.items():
        if slot in comp:
            options[comp[slot]["mesh"]].append(look)
    print(" ", slot)
    for mesh, looks in options.items():
        print(f"     {mesh}\n        looks ({len(looks)}): {looks[:5]}\n        paints: {paints(mesh)}")

print("\n-- paints on the body --")
meshes = {comp["body_a_01"]["mesh"] for comp in app.values() if "body_a_01" in comp}
for mesh in meshes:
    print(f"  {mesh}\n    {paints(mesh)}")

print("\n-- all parts of the first player look --")
look = next(l for l in sorted(app) if "player" in l)
for slot, c in sorted(app[look].items()):
    print(f"  {slot:34s} {c['cls']:34s} {c['app']:16s} {os.path.basename(c['mesh'])}")

print("\n-- which appearance names the bike's entity lists --")
ents = [p for p in present if p.endswith(".ent") and "arch_nemesis" in p and "\\entities\\" not in p]
for ent in ents[:4]:
    head, bufs = depot.load(ent)
    root = pkg.Cooked(head, bufs, depot).exports[0][1]
    names = [a.get("name") for a in root.get("appearances", [])] if isinstance(root.get("appearances"), list) else []
    print(f"  {ent}  count {len(names)}  player: {[n for n in names if 'player' in str(n)]}")
