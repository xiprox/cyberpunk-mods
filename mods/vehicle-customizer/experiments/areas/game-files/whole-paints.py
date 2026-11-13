"""Which paints a whole car can wear: paint names every painted body panel of a look has in common."""
import collections
import json
import os
import re
import statistics
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

PANELS = re.compile(r"^(body_01|hood_a|trunk_a|bumper_f_01|bumper_b_01|door_[fb][lr]_a|fender\w*|roof\w*)$")
cache = {}


def paints(path):
    if path in cache:
        return cache[path]
    names = []
    loaded = depot.load(path) if not path.startswith("#") else None
    if loaded:
        head, _ = loaded
        c = rdar.CR2W(head)
        off, n, _ = c.tables[4]
        for i in range(n):
            cls, _f, _par, size, data_off, _t, _c = struct.unpack_from("<HHIIIII", head, off + i * 24)
            if c.names[cls] != "meshMeshAppearance":
                continue
            p = data_off + 1
            while p + 8 <= data_off + size:
                ni = struct.unpack_from("<H", head, p)[0]
                if ni == 0:
                    break
                _ti, sz = struct.unpack_from("<HI", head, p + 2)
                if c.names[ni] == "name":
                    names.append(c.names[struct.unpack_from("<H", head, p + 8)[0]])
                p += 4 + sz
    cache[path] = set(names) | {"default"}
    return cache[path]


rows = []
for path, app in apps.items():
    if any(s in path for s in ("decoration", "destroyed", "filpped")):
        continue
    looks = list(app.values())
    if not looks:
        continue
    biggest = max(looks, key=len)
    panels = {slot: c["mesh"] for slot, c in biggest.items() if PANELS.match(slot)}
    if len(panels) < 3:
        continue
    sets = [paints(m) for m in panels.values()]
    common = set.intersection(*sets)
    wear = {p for p in common if re.search(r"poor|burnt|destroyed|damaged|after_accident|rust|dirty", p)}
    rows.append((len(common), len(common - wear), os.path.basename(path)[:-4], len(panels), sorted(common - wear)[:12]))

rows.sort(reverse=True)
whole = [r[0] for r in rows]
clean = [r[1] for r in rows]
print(f"cars: {len(rows)}; paints shared by every body panel: median {statistics.median(whole)}, min {min(whole)}, max {max(whole)}")
print(f"of those, not worn or burnt: median {statistics.median(clean)}, min {min(clean)}, max {max(clean)}")
for r in rows[:12]:
    print(f"  {r[2]:36s} panels {r[3]:2d}  shared {r[0]:3d}  clean {r[1]:3d}  {r[4]}")
print("fewest:")
for r in rows[-6:]:
    print(f"  {r[2]:36s} panels {r[3]:2d}  shared {r[0]:3d}  clean {r[1]:3d}  {r[4]}")
