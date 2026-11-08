"""TweakDB ids (crc32 + length), checked against tweakdb.bin; plus the Hella's real options from apps.json."""
import json
import os
import struct
import sys
import zlib

S = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")
GAME = r"C:\Program Files (x86)\Steam\steamapps\common\Cyberpunk 2077"
db = open(os.path.join(GAME, r"r6\cache\tweakdb.bin"), "rb").read()
db2 = open(os.path.join(GAME, r"r6\cache\tweakdb_ep1.bin"), "rb").read()


def tid(name):
    return zlib.crc32(name.encode()) | (len(name) << 32)


names = ["Vehicle.v_sportbike2_arch_player_02", "Vehicle.v_sportbike2_arch_player_02_kuro",
         "Vehicle.v_sportbike2_arch_player_02_shiro",
         "Vehicle.v_standard2_archer_hella_player", "Vehicle.v_standard2_archer_hella",
         "Vehicle.v_standard2_thorton_galena_player", "Vehicle.v_standard25_villefort_columbus_player",
         "Vehicle.v_sport2_porsche_911turbo_player", "Vehicle.vehicle_list.list"]
for n in names:
    i = tid(n)
    pat = struct.pack("<Q", i)[:5]
    print(f"{n:50s} 0x{i:010x}  tweakdb:{db.count(pat)}  ep1:{db2.count(pat)}")

apps = json.load(open(os.path.join(S, "apps.json"), encoding="utf-8"))
key = next(k for k in apps if k.endswith("base\\vehicles\\appearances\\standard\\archer_hella__basic.app"))
app = apps[key]
print("\nappearances:", sorted(app)[:50])
player = app.get("player_01", {})
print("\nplayer_01 parts:", len(player))
for slot in sorted(player):
    c = player[slot]
    print(f"  {slot:42s} {c['cls'][:24]:24s} paint={c['app']:14s} bind={c['slot']:18s} {os.path.basename(c['mesh'])}")
print("\nslots whose mesh varies in this .app:")
opts = {}
for name, comp in app.items():
    for slot, c in comp.items():
        opts.setdefault(slot, {}).setdefault(c["mesh"], []).append(name)
for slot, meshes in sorted(opts.items()):
    if len(meshes) > 1 and slot != "None":
        print(" ", slot)
        for m, who in meshes.items():
            print(f"     {m}   <- {who[:4]}{'...' if len(who) > 4 else ''} ({len(who)})")
print("\npaints used on hood_a across appearances:", sorted({c['hood_a']['app'] for c in app.values() if 'hood_a' in c}))
