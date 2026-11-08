"""Which looks the Hella's entity file offers, since a record can only pick one of those by name."""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pkg

S = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")
present = json.load(open(os.path.join(S, "parts.json"), encoding="utf-8"))["present"]
depot = pkg.Depot()
depot.add_names(present)

for ent in [r"base\vehicles\standard\v_standard2_archer_hella__basic_01.ent"]:
    head, bufs = depot.load(ent)
    root = pkg.Cooked(head, bufs, depot).exports[0][1]
    looks = [a for a in root.get("appearances", [])]
    print(ent, "default:", root.get("defaultAppearance"), "count:", len(looks))
    for a in looks:
        res = a.get("appearanceResource")
        print(f"  {str(a.get('name')):42s} -> {str(a.get('appearanceName')):22s} {res[1] if isinstance(res, tuple) else res}")
    names = [str(a.get("name")) for a in looks]
    for wanted in ("archer_hella__basic_deathrace_01", "archer_hella__basic_player_01", "archer_hella__basic_poor_2_2", "archer_hella__basic_suburban_1_2"):
        print(f"has {wanted}: {wanted in names}")
