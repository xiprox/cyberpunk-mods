import json, os
S = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")
apps = json.load(open(os.path.join(S, "apps.json"), encoding="utf-8"))
key = next(k for k in apps if k.endswith("base\\vehicles\\appearances\\standard\\archer_hella__basic.app"))
slots = ["wheel_01_fl_a", "wheel_01_fr_a", "wheel_01_bl_a", "wheel_01_br_a", "tire_01_fl_a", "tire_01_fr_a", "tire_01_bl_a", "tire_01_br_a"]
for name, comp in sorted(apps[key].items()):
    have = sum(1 for s in slots[:4] if s in comp)
    if have:
        print(f"{name:22s} wheel slots={have}  " + "  ".join(f"{s[9:11]}:{os.path.basename(comp[s]['mesh']).replace('.mesh','')[-28:]}" for s in slots if s in comp))
print()
for name in ("deathrace_01", "police_01"):
    c = apps[key][name]
    print(name, {s: c[s]["app"] for s in ("hood_a", "bumper_f_01", "bumper_b_01", "body_01") if s in c}, "bumper_f:", os.path.basename(c["bumper_f_01"]["mesh"]) if "bumper_f_01" in c else None)
