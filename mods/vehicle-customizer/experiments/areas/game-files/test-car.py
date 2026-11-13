"""Exact names the first in-game test needs, and which way parent bindings are numbered."""
import collections
import json
import os
import struct
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "..", "..", "tools"))
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


print("-- entity files and their appearance names --")
for ent in [r"base\vehicles\standard\v_standard2_archer_hella__basic_01.ent", r"ep1\vehicles\standard\v_standard2_archer_hella_ep1__basic_01.ent"]:
    head, bufs = depot.load(ent)
    c = pkg.Cooked(head, bufs, depot)
    root = c.exports[0][1]
    names = [a.get("name") for a in root.get("appearances", [])] if isinstance(root.get("appearances"), list) else []
    print(ent, "count", len(names), "default", root.get("defaultAppearance"))
    print("   has player_01:", "archer_hella__basic_player_01" in names, " has suburban_1:", "archer_hella__basic_suburban_1" in names)
    print("   sample:", names[:4], [n for n in names if "player" in str(n)])

print("\n-- paints on the parts the test uses --")
base = r"base\vehicles\standard\v_standard2_archer_hella\entities\meshes\v_standard2_archer_hella__"
for m in ["ext01_hood_01", "ext01_bumper_f_01", "ext01_junk_bumper_f_01", "ext01_bumper_b_01", "ext01_junk_bumper_b_01", "ext01_tire_fl_01", "ext01_tire_bl_01", "ext01_wheel_fl_01", "ext01_wheel_bl_01"]:
    print(f"  {m:30s} {paints(base + m + '.mesh')}")

print("\n-- what a suburban_1 Hella uses in the slots the test touches --")
key = next(k for k in apps if k.endswith("base\\vehicles\\appearances\\standard\\archer_hella__basic.app"))
sub = apps[key]["suburban_1"]
for slot in ["hood_a", "bumper_f_01", "bumper_f_shadow", "bumper_b_01", "wheel_01_fl_a", "wheel_01_fr_a", "wheel_01_bl_a", "wheel_01_br_a", "tire_01_fl_a", "tire_01_fr_a", "tire_01_bl_a", "tire_01_br_a",
             "tire_01_fl_a_shadow", "tire_01_fr_a_shadow", "tire_01_bl_a_shadow", "tire_01_br_a_shadow"]:
    c = sub.get(slot)
    print(f"  {slot:24s} {c and (c['cls'], c['app'], c['mesh'])}")

print("\n-- wheels and tires on other cars --")
for needle in ["porsche_911turbo__basic", "quadra_turbo_basic"]:
    k = next(x for x in apps if needle in x)
    counts = collections.defaultdict(collections.Counter)
    for app in apps[k].values():
        for slot in ["wheel_01_fl_a", "wheel_01_fr_a", "wheel_01_bl_a", "wheel_01_br_a", "tire_01_fl_a", "tire_01_fr_a", "tire_01_bl_a", "tire_01_br_a",
                     "tire_01_fl_a_shadow", "tire_01_fr_a_shadow", "tire_01_bl_a_shadow", "tire_01_br_a_shadow"]:
            if slot in app:
                counts[slot][(app[slot]["mesh"], app[slot]["app"])] += 1
    print(k)
    for slot, c in counts.items():
        print(f"  {slot:24s} {c.most_common(2)}")

print("\n-- binding numbering: what class does a parentTransform handle land on? --")
head, bufs = depot.load(key)
c = pkg.Cooked(head, bufs, depot)
d = next(o for cls, o in c.exports if cls == "appearanceAppearanceDefinition" and o.get("name") == "default")
p = pkg.Package(c.buffer(d["compiledData"][1]), depot)
objs = p.objects(only={"name", "mesh", "parentTransform", "slotName", "bindName"})
shown = 0
for cls, o in objs:
    if o.get("name") in ("hood_a", "door_fl_a", "bumper_f_01", "wheel_01_fl_a", "tire_01_fl_a", "body_01"):
        h = o["parentTransform"][1]
        print(f"  {o['name']:16s} handle {h:4d}  as-is -> {objs[h][0]} {objs[h][1]}   minus-1 -> {objs[h-1][0]} {objs[h-1][1]}")
