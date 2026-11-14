"""Writes src/audio/car_meshes.inc, the box of every car window, windscreen and door mesh in the game, so Voice can tell
where a car's openings are and how big (RECORD.md, 2026-11-13), and src/audio/car_open_tops.inc, the appearances with no
roof. The game gives a part's pivot and its mesh's hash; the mesh's own box, in the part's space, is only in the game
files.

  python -I tools/car_openings.py

Reads the game's archives with the repo's shared readers (tools/rdar.py and tools/pkg.py at the repo's root), and finds the vehicle appearance files by name in Codeware's list of known paths. Rerun it after a game patch."""
import os
import re
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
READERS = os.path.normpath(os.path.join(HERE, "..", "..", "..", "tools"))
sys.path.insert(0, READERS)
import pkg  # noqa: E402
import rdar  # noqa: E402

OUT = os.path.normpath(os.path.join(HERE, "..", "src", "audio", "car_meshes.inc"))
OUT_TOPS = os.path.normpath(os.path.join(HERE, "..", "src", "audio", "car_open_tops.inc"))
KNOWN = os.path.join(rdar.GAME, "red4ext", "plugins", "Codeware", "Data", "KnownHashes.txt")

# Glass is named in each car's TweakDB record (window_f, window_fl_a, trunk_a_window_01, ...); taking every part with
# "window" or "glass" in its name covers those, and a few extras cost nothing. A door's gap is its main panel.
GLASS = re.compile(r"window|glass")
DOOR = re.compile(r"^door_(fl|fr|bl|br)_a$")
SKIP = re.compile(r"shadow|sticker|decal")


def read_box(depot, mesh):
    """CMesh.boundingBox (min, max) in the mesh's own space, or None."""
    loaded = depot.load(mesh)
    if loaded is None:
        return None
    head, _ = loaded
    c = rdar.CR2W(head)
    off, n, _ = c.tables[4]
    for i in range(n):
        cls, _f, _par, size, data_off, _t, _c = struct.unpack_from("<HHIIIII", head, off + i * 24)
        if c.names[cls] != "CMesh":
            continue
        p, end = data_off + 1, data_off + size
        while p + 8 <= end:
            ni = struct.unpack_from("<H", head, p)[0]
            if ni == 0:
                break
            _ti, sz = struct.unpack_from("<HI", head, p + 2)
            if c.names[ni] == "boundingBox":
                box, q = {}, p + 9
                while q + 8 <= p + 4 + sz:
                    nj = struct.unpack_from("<H", head, q)[0]
                    if nj == 0:
                        break
                    _tj, szj = struct.unpack_from("<HI", head, q + 2)
                    vec, r = {}, q + 9
                    while r + 8 <= q + 4 + szj:
                        nk = struct.unpack_from("<H", head, r)[0]
                        if nk == 0:
                            break
                        _tk, szk = struct.unpack_from("<HI", head, r + 2)
                        vec[c.names[nk]] = struct.unpack_from("<f", head, r + 8)[0]
                        r += 4 + szk
                    box[c.names[nj]] = vec
                    q += 4 + szj
                if "Min" in box and "Max" in box:
                    return ([box["Min"].get(k, 0.0) for k in "XYZ"], [box["Max"].get(k, 0.0) for k in "XYZ"])
                return None
            p += 4 + sz
    return None


def vehicle_apps(depot):
    """The vehicle appearance files, after teaching the depot the vehicle meshes' names so parts come back named."""
    apps, meshes = set(), []
    with open(KNOWN, encoding="utf-8", errors="replace") as f:
        for line in f:
            p = line.strip().lower()
            if "\\vehicles\\" in p:
                if p.endswith(".app"):
                    apps.add(p)
                elif p.endswith(".mesh"):
                    meshes.append(p)
    depot.add_names(meshes)
    return sorted(p for p in apps if depot.find(p)[0] is not None)


def mesh_hash(mesh):
    """The hash the game gives for a mesh path; the depot writes one it has no name for as #<hex>."""
    return int(mesh[1:], 16) if mesh.startswith("#") else rdar.fnv1a64(mesh)


def parts_of(depot, app):
    """(look, part name, mesh path) of every mesh part in every appearance of one .app."""
    head, bufs = depot.load(app)
    cooked = pkg.Cooked(head, bufs, depot)
    for cls, definition in cooked.exports:
        if cls != "appearanceAppearanceDefinition":
            continue
        data = definition.get("compiledData")
        buffer = cooked.buffer(data[1]) if data else None
        if not buffer:
            continue
        look = str(definition.get("name"))
        for _cls, obj in pkg.Package(buffer, depot).objects(only={"name", "mesh"}):
            mesh = obj.get("mesh")
            if isinstance(mesh, tuple) and mesh[0] == "ref" and mesh[1]:
                yield look, str(obj.get("name")), mesh[1]


ROOF = re.compile(r"^roof(_[a-z])?(_\d+)?$")


def open_tops(app, looks):
    """The looks of one .app that have no roof, as the entity names its appearances: <.app name>_<look>. The game marks
    none, so: a look named cabrio or targa, or one that lacks the roof part its siblings have (the Alvarado "Vato").
    Burnt wrecks are left out."""
    stem = os.path.splitext(os.path.basename(app))[0]
    roofed = {look for look, parts in looks.items() if any(ROOF.match(p) for p in parts)}
    found = []
    for look, parts in looks.items():
        if "burnt" in look:
            continue
        if re.search(r"cabrio|targa", look) or (roofed and look not in roofed):
            found.append("%s_%s" % (stem, look))
    return found


def main():
    depot = pkg.Depot()
    apps = vehicle_apps(depot)
    meshes, failed, tops = {}, [], []
    for app in apps:
        looks = {}
        try:
            for look, name, mesh in parts_of(depot, app):
                low = name.lower()
                looks.setdefault(look, set()).add(low)
                if (GLASS.search(low) or DOOR.match(low)) and not SKIP.search(low):
                    meshes.setdefault(mesh_hash(mesh), mesh)
        except Exception as ex:  # one unreadable file shouldn't stop the rest
            failed.append("%s (%s)" % (app, ex))
        tops += open_tops(app, looks)
    rows, missing = [], 0
    for h in sorted(meshes):
        box = read_box(depot, h)
        if box is None:
            missing += 1
            continue
        lo, hi = box
        rows.append("    {0x%016xull, {%.3ff, %.3ff, %.3ff}, {%.3ff, %.3ff, %.3ff}}, // %s"
                    % (h, lo[0], lo[1], lo[2], hi[0], hi[1], hi[2], os.path.basename(meshes[h])))
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("// Written by tools/car_openings.py from the game's files: each car window, windscreen and door mesh's own box\n")
        f.write("// (mesh hash, min, max), sorted by the mesh path's hash as the game gives it. Don't edit by hand.\n")
        f.write("\n".join(rows) + "\n")
    with open(OUT_TOPS, "w", encoding="utf-8", newline="\n") as f:
        f.write("// Written by tools/car_openings.py from the game's files: appearances with no roof, as the entity names them.\n")
        f.write("// Don't edit by hand.\n")
        f.write("\n".join('    "%s",' % t for t in sorted(tops)) + "\n")
    print("%d vehicle appearance files, %d meshes with boxes, %d without, %d files unread"
          % (len(apps), len(rows), missing, len(failed)))
    print("open tops:", ", ".join(sorted(tops)))
    for line in failed[:5]:
        print("  unread:", line)


main()
