"""How many paints (mesh appearances) each car's body mesh has. A mesh's unnamed first appearance is "default"."""
import collections
import json
import os
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


rows = []
for path, app in apps.items():
    counts = collections.Counter(comp["body_01"]["mesh"] for comp in app.values() if "body_01" in comp)
    if not counts:
        continue
    mesh = counts.most_common(1)[0][0]
    if mesh.startswith("#"):
        continue
    names = paints(mesh)
    if names:
        rows.append((len(names), os.path.basename(path)[:-4], names[:6]))
rows.sort(reverse=True)
values = [r[0] for r in rows]
print(f"cars={len(values)} named paints: median={statistics.median(values)} max={max(values)} (each also has a default)")
for row in rows[:8]:
    print(" ", row)
