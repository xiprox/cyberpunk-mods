"""Probe 2 of the tool idea (UX.md, 2026-11-07): each part's box, for naming the part under the crosshair.

  python -I part-bounds.py <catalog id> <out.lua>

Reads every mesh a catalog names (its slots' options and shadows, its wheel sets) and writes a Lua table, keyed by
the mesh path's hash as the game gives it (FNV-1a 64, decimal), of each mesh's own bounding box (CMesh.boundingBox,
in the mesh's local space). In the game a part's box goes through its component's GetLocalToWorld."""
import json
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "areas", "game-files"))
import pkg  # noqa: E402
import rdar  # noqa: E402

CATALOGS = os.path.join(HERE, "..", "..", "catalog", "out")


def read_box(depot, path):
    """CMesh.boundingBox as {"Min": {X, Y, Z, W}, "Max": {...}} (as in sizes-and-crystalcoat.py)."""
    loaded = depot.load(path)
    if loaded is None:
        return None
    head, _ = loaded
    c = rdar.CR2W(head)
    off, n, _ = c.tables[4]
    for i in range(n):
        cls, _f, _par, size, data_off, _t, _c = struct.unpack_from("<HHIIIII", head, off + i * 24)
        if c.names[cls] != "CMesh":
            continue
        p = data_off + 1
        end = data_off + size
        while p + 8 <= end:
            ni = struct.unpack_from("<H", head, p)[0]
            if ni == 0:
                break
            _ti, sz = struct.unpack_from("<HI", head, p + 2)
            if c.names[ni] == "boundingBox":
                box = {}
                q = p + 9
                while q + 8 <= p + 4 + sz:
                    nj = struct.unpack_from("<H", head, q)[0]
                    if nj == 0:
                        break
                    _tj, szj = struct.unpack_from("<HI", head, q + 2)
                    vec = {}
                    r = q + 9
                    while r + 8 <= q + 4 + szj:
                        nk = struct.unpack_from("<H", head, r)[0]
                        if nk == 0:
                            break
                        _tk, szk = struct.unpack_from("<HI", head, r + 2)
                        vec[c.names[nk]] = struct.unpack_from("<f", head, r + 8)[0]
                        r += 4 + szk
                    box[c.names[nj]] = vec
                    q += 4 + szj
                return box
            p += 4 + sz
    return None


def meshes_in(value, out):
    if isinstance(value, str):
        if value.lower().endswith(".mesh"):
            out.add(value)
    elif isinstance(value, dict):
        for v in value.values():
            meshes_in(v, out)
    elif isinstance(value, list):
        for v in value:
            meshes_in(v, out)


def main():
    cat, out_path = sys.argv[1], sys.argv[2]
    catalog = json.load(open(os.path.join(CATALOGS, cat + ".json"), encoding="utf-8"))
    paths = set()
    meshes_in(catalog.get("slots"), paths)
    meshes_in(catalog.get("wheel_sets"), paths)
    depot = pkg.Depot()
    lines, missing = [], []
    for path in sorted(paths):
        box = read_box(depot, path)
        if not box or "Min" not in box or "Max" not in box:
            missing.append(path)
            continue
        mn, mx = box["Min"], box["Max"]
        lines.append('    ["%d"] = { path = %s, min = { %.4f, %.4f, %.4f }, max = { %.4f, %.4f, %.4f } },'
                     % (rdar.fnv1a64(path), json.dumps(path), mn.get("X", 0), mn.get("Y", 0), mn.get("Z", 0),
                        mx.get("X", 0), mx.get("Y", 0), mx.get("Z", 0)))
    with open(out_path, "w", encoding="utf-8", newline="\n") as f:
        f.write("-- Written by experiments/tool/part-bounds.py from catalog/out/%s.json; each mesh's own box.\n" % cat)
        f.write("return {\n" + "\n".join(lines) + "\n}\n")
    print("%d meshes with boxes, %d without: %s" % (len(lines), len(missing), ", ".join(missing[:5])))


main()
