"""Group each car's looks by the set of visible parts they have, which is what decides which swaps a look can take.
Also prints what the Hella's tire parts are on a traffic look, where it has no wheel parts."""
import collections
import json
import os
import re
import statistics

S = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")
apps = json.load(open(os.path.join(S, "apps.json"), encoding="utf-8"))

# Parts that make the shape of a car, without shadows, clutter and the distance model.
SHAPE = re.compile(r"^(body|hood|trunk|bumper|door|wheel|tire|fender|roof|spoiler|wing|exhaust|mirror|window_f$|interior_01$|chas)")


def shape_parts(comp):
    return frozenset(s for s in comp if SHAPE.match(s) and "shadow" not in s)


hella = next(v for k, v in apps.items() if k.endswith("base\\vehicles\\appearances\\standard\\archer_hella__basic.app"))
print("-- Hella suburban_1: every part with wheel, tire, rim or hub in its name or mesh --")
for slot, c in sorted(hella["suburban_1"].items()):
    if re.search(r"wheel|tire|rim|hub", slot + c["mesh"]):
        print(f"  {slot:24s} {c['cls']:26s} {os.path.basename(c['mesh'])}")

rows = []
for path, app in sorted(apps.items()):
    if any(s in path for s in ("decoration", "destroyed", "filpped")):
        continue
    groups = collections.defaultdict(list)
    for look, comp in app.items():
        groups[shape_parts(comp)].append(look)
    rows.append((os.path.basename(path)[:-4], len(app), groups))

counts = [len(g) for _, _, g in rows]
print(f"\n{len(rows)} appearance files; groups of looks with the same shape parts: median {statistics.median(counts)}, max {max(counts)}")
for name, n, groups in rows:
    if "archer_hella__basic" in name or "thorton_colby__basic" in name or "arch_nemesis_basic" in name or "quadra_type66__basic" in name:
        print(f"\n{name}: {n} looks in {len(groups)} groups")
        ordered = sorted(groups.items(), key=lambda kv: -len(kv[1]))
        common = frozenset.intersection(*[k for k, _ in ordered])
        for parts, looks in ordered:
            extra = sorted(parts - common)
            print(f"  {len(looks):2d} looks {looks[:5]}{' ...' if len(looks) > 5 else ''}")
            print(f"     parts beyond the shared {len(common)}: {extra[:14]}{' ...' if len(extra) > 14 else ''}")
