"""Step 3 of the shop paints (RECORD.md, 2026-11-08): for each model folder, the paint the shop's colours are built on and which
of its layers are the body's colour, by measuring what each layer shows on the real geometry: each layer's mask, composited
from the top down, sampled at the triangles of the parts that use it and weighted by their area. Measuring the whole texture
sheet instead counts space the visible body doesn't use (the Bandit got its dark layer 0 where its doors are layer 1, gold).

A material is body if its mask is an exterior one by name; on a mesh with none, any mask not named for something else (the
Kusanagi's "..._masksset"). A far material is body if it names the same paint file as a near one (the Zeya's "yellow_masksset_lod").

Reads cache/map.json, cache/masks and cache/glb; writes cache/plan.json. Run with: python -I plan-paints.py"""
import collections
import glob
import json
import os
import re
import struct

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(HERE, "cache")
CATALOGS = os.path.join(HERE, "..", "..", "catalog", "out")
N = 64
NOT_A_PAINT = re.compile(r"holo|burnt|damaged|crashed|destroy|wreck|after_accident|ghost|glitch|scanner|xray")
# Interiors, seats, rubber and glass take no body colour.
SKIP = {"interior", "seat", "seats", "tire", "wheel", "window"}
# Surfaces laid over the paint, never the paint itself.
OVERLAY = re.compile(r"dust|dirt|grime|rust|mud|soot|velvet|plaster|tape|burn|water|oil|felt|carpet")
# Bare materials: a body colour only if nothing else on the part can be.
RAW = re.compile(r"iron|steel|alumin|carbon|rubber|leather|chrome|metal_generic|nylon|strap|fabric|cloth|canvas|webbing|checker")
NOT_BODY = re.compile(r"int0|int_|interior|tire|wheel|rim|engine|glass|window|seat|stripe|sticker|decal|burnt")

with open(os.path.join(CACHE, "map.json"), encoding="utf-8") as f:
    MAP = json.load(f)
MESHES, SETUPS = MAP["meshes"], MAP["setups"]

kinds = collections.defaultdict(set)
for path in glob.glob(os.path.join(CATALOGS, "*.json")):
    with open(path, encoding="utf-8") as f:
        cat = json.load(f)
    for slot in cat["slots"]:
        for option in slot["options"]:
            for mesh in option["meshes"].values():
                kinds[mesh.lower()].add(slot["kind"])
    for kit in cat.get("kits", []):
        for part in kit.get("parts", []):
            if part.get("mesh"):
                kinds[part["mesh"].lower()].add("kit")


# Parts outside the catalog's slots (list-parts.py): painted only if a real body colour shows on them.
EXTRA = set()
if os.path.exists(os.path.join(CACHE, "extra-parts.json")):
    with open(os.path.join(CACHE, "extra-parts.json"), encoding="utf-8") as f:
        EXTRA = set(json.load(f)["meshes"])
for mesh in EXTRA:
    kinds[mesh].add("extra")


def named_ext(mask):
    name = os.path.basename(mask or "")
    return "ext" in name and "int0" not in name and "interior" not in name


def body_chunks(mesh, chunks):
    materials = mesh["materials"]
    named = [c for c in chunks if c in materials and named_ext(materials[c]["mask"])]
    if named:
        return named
    return [c for c in chunks if c in materials and materials[c]["mask"]
            and not NOT_BODY.search(os.path.basename(materials[c]["mask"]))]


mask_cache = {}


def mask_layers(mask):
    if mask not in mask_cache:
        stem = mask[:-len(".mlmask")]
        base = os.path.join(CACHE, "masks", stem + "_layers", os.path.basename(stem))
        layers = {}
        for i in range(20):
            p = f"{base}_{i}.g64"
            if os.path.exists(p):
                with open(p, "rb") as f:
                    layers[i] = f.read()
        mask_cache[mask] = layers or None
    return mask_cache[mask]


def read_glb(rel):
    """The near chunks of a mesh: chunk number -> (positions, uvs, indices); None if there's no export."""
    path = os.path.join(CACHE, "glb", rel[:-len(".mesh")] + ".glb")
    if not os.path.exists(path):
        return None
    with open(path, "rb") as f:
        data = f.read()
    length = struct.unpack_from("<I", data, 12)[0]
    doc = json.loads(data[20:20 + length])
    blob = data[20 + length + 8:]

    def accessor(i):
        a = doc["accessors"][i]
        view = doc["bufferViews"][a["bufferView"]]
        offset = view.get("byteOffset", 0) + a.get("byteOffset", 0)
        size = {"SCALAR": 1, "VEC2": 2, "VEC3": 3}[a["type"]]
        kind = {5123: "H", 5125: "I", 5126: "f"}[a["componentType"]]
        return struct.unpack_from(f"<{a['count'] * size}{kind}", blob, offset)

    out = {}
    for mesh in doc["meshes"]:
        parts = mesh["name"].split("_")
        if parts[-1] != "1":  # submesh_NN_LOD_1 is the near one
            continue
        prim = mesh["primitives"][0]
        out[int(parts[1])] = (accessor(prim["attributes"]["POSITION"]), accessor(prim["attributes"]["TEXCOORD_0"]), accessor(prim["indices"]))
    return out


def add_weights(chunk, weights):
    """Each triangle's area shared over four points on it, in the mask's pixels (V as exported; the Bandit door's colour proves it)."""
    pos, uv, ix = chunk
    for t in range(0, len(ix) - 2, 3):
        a, b, c = ix[t], ix[t + 1], ix[t + 2]
        ax, ay, az = pos[a * 3], pos[a * 3 + 1], pos[a * 3 + 2]
        ux, uy, uz = pos[b * 3] - ax, pos[b * 3 + 1] - ay, pos[b * 3 + 2] - az
        vx, vy, vz = pos[c * 3] - ax, pos[c * 3 + 1] - ay, pos[c * 3 + 2] - az
        area = 0.5 * ((uy * vz - uz * vy) ** 2 + (uz * vx - ux * vz) ** 2 + (ux * vy - uy * vx) ** 2) ** 0.5
        u0, v0, u1, v1, u2, v2 = uv[a * 2], uv[a * 2 + 1], uv[b * 2], uv[b * 2 + 1], uv[c * 2], uv[c * 2 + 1]
        for p, q in (((u0 + u1 + u2) / 3, (v0 + v1 + v2) / 3), ((u0 + u1) / 2, (v0 + v1) / 2), ((u1 + u2) / 2, (v1 + v2) / 2), ((u2 + u0) / 2, (v2 + v0) / 2)):
            weights[int(q % 1 * N) % N * N + int(p % 1 * N) % N] += area / 4


by_folder = collections.defaultdict(dict)
for rel, mesh in MESHES.items():
    if not kinds.get(rel) or kinds[rel] <= (SKIP | {"kit"}):
        continue
    apps = {a: c for a, c in mesh["appearances"].items() if not NOT_A_PAINT.search(a) and body_chunks(mesh, c)}
    if apps:
        by_folder[rel.split("\\")[3]][rel] = apps

old = {}
if os.path.exists(os.path.join(CACHE, "plan-before-geometry.json")):
    with open(os.path.join(CACHE, "plan-before-geometry.json"), encoding="utf-8") as f:
        old = json.load(f)
BASES = {f: v["base"] for f, v in old.get("folders", {}).items()}

plan = {"folders": {}, "meshes": {}, "setups": {}}
rows = []
no_geometry = 0
for folder, meshes in sorted(by_folder.items()):
    geometry = {rel: read_glb(rel) for rel in meshes}
    no_geometry += sum(1 for g in geometry.values() if g is None)
    weights_by_mask = {}
    seen = set()
    for rel, apps in meshes.items():
        data = geometry[rel]
        if not data:
            continue
        for chunks in apps.values():
            body = set(body_chunks(MESHES[rel], chunks))
            for i, c in enumerate(chunks):
                if c in body and i in data:
                    mask = MESHES[rel]["materials"][c]["mask"]
                    if (rel, i, mask) not in seen:
                        seen.add((rel, i, mask))
                        add_weights(data[i], weights_by_mask.setdefault(mask, [0.0] * (N * N)))

    judged_cache = {}

    def judged(setup, mask):
        """(the layers that are the body's colour, how much they show, how much dirt shows, the surface), or None."""
        if (setup, mask) not in judged_cache:
            result = None
            layers, masks = SETUPS.get(setup), mask_layers(mask)
            if layers and masks:
                weights = weights_by_mask.get(mask)
                if not weights or sum(weights) <= 0:
                    weights = [1.0] * (N * N)
                total = sum(weights)
                left = [1.0] * (N * N)
                shown = [0.0] * len(layers)
                for i in range(len(layers) - 1, -1, -1):
                    opacity = layers[i]["opacity"]
                    if opacity <= 0:
                        continue
                    m = masks.get(i)
                    for p in range(N * N):
                        alpha = opacity if (i == 0 or m is None) else m[p] / 255.0 * opacity
                        take = left[p] * alpha
                        shown[i] += take * weights[p]
                        left[p] -= take
                shown = [s / total for s in shown]
                options = [i for i in range(len(shown)) if not OVERLAY.search(layers[i]["surface"])]
                painted_ones = [i for i in options if not RAW.search(layers[i]["surface"]) and shown[i] > 0.05]
                options = painted_ones or options
                if options:
                    best = max(options, key=lambda i: shown[i])
                    colour = (layers[best]["surface"], layers[best]["colour"])
                    group = [i for i in options if (layers[i]["surface"], layers[i]["colour"]) == colour and shown[i] > 0.005]
                    dirt = sum(shown[i] for i in range(len(shown)) if OVERLAY.search(layers[i]["surface"]))
                    result = (group, sum(shown[i] for i in group), dirt, colour[0], bool(painted_ones))
            judged_cache[(setup, mask)] = result
        return judged_cache[(setup, mask)]

    def near(rel, i, name):
        data = geometry[rel]
        if data:
            return i in data
        return "lod" not in os.path.basename(MESHES[rel]["materials"][name]["mask"] or "")

    def judge_look(rel, chunks):
        pairs = collections.Counter()
        body = set(body_chunks(MESHES[rel], chunks))
        for i, c in enumerate(chunks):
            if c in body and near(rel, i, c):
                m = MESHES[rel]["materials"][c]
                pairs[(m["setup"], m["mask"])] += 1
        if not pairs:
            return None
        (setup, mask), _n = pairs.most_common(1)[0]
        return judged(setup, mask)

    # The base paint is chosen on the slots' parts; the extra parts usually only have a "default" and would drown them out.
    slotted = {rel: apps for rel, apps in meshes.items() if rel not in EXTRA} or meshes
    count = collections.Counter(a for apps in slotted.values() for a in apps)
    top = max(count.values())
    scores = {}
    candidates = {n for n, c in count.items() if c >= 0.6 * top}
    if BASES.get(folder) in count:
        candidates.add(BASES[folder])
    for name in sorted(candidates):
        values = [judge_look(rel, apps[name]) for rel, apps in slotted.items() if name in apps]
        values = [v for v in values if v]
        if values:
            scores[name] = sum(v[1] - v[2] for v in values) / len(values)
    if not scores:
        rows.append((folder, None, 0, len(meshes), None, "no readable paint", 0.0, 0.0))
        continue
    # The base paint stays as the first plan chose it: the hot pink run looked right on most models with those, and this
    # measure scores liveries and worn paints higher. Only the layers are re-measured.
    earlier = BASES.get(folder)
    base = earlier if earlier in scores else max(scores, key=lambda n: (scores[n], n))
    painted = 0
    for rel, apps in meshes.items():
        name = base if base in apps else None
        if name is None:
            options = {a: judge_look(rel, c) for a, c in apps.items()}
            options = {a: v for a, v in options.items() if v}
            if not options:
                continue
            name = max(options, key=lambda a: (options[a][1] - options[a][2], a))
        chunks = apps[name]
        materials = MESHES[rel]["materials"]
        body = {}
        known = {}
        wanted = set(body_chunks(MESHES[rel], chunks))
        for i, c in enumerate(chunks):
            if c in wanted and near(rel, i, c):
                m = materials[c]
                verdict = judged(m["setup"], m["mask"])
                # A part outside the slots has to be really painted: no bare metal, and the colour must show.
                if verdict and rel in EXTRA and (not verdict[4] or verdict[1] < 0.15):
                    verdict = None
                if verdict:
                    key = f"{folder}|{m['setup']}"
                    plan["setups"][key] = {"setup": m["setup"], "mask": m["mask"], "layers": verdict[0], "shown": round(verdict[1], 3)}
                    body[c] = key
                    known[m["setup"]] = key
        # Far versions: an exterior mask by name or not, what counts is the same paint file as a near body material.
        for c in chunks:
            if c not in body and c in materials and materials[c]["setup"] in known:
                body[c] = known[materials[c]["setup"]]
        if body:
            plan["meshes"][rel] = {"appearance": name, "folder": folder, "body": body}
            painted += 1
    verdict = judge_look(next(r for r, a in meshes.items() if base in a), next(a[base] for a in meshes.values() if base in a))
    plan["folders"][folder] = {"base": base, "meshes": painted, "of": len(meshes)}
    rows.append((folder, base, painted, len(meshes), verdict[0] if verdict else None, verdict[3] if verdict else "?",
                 verdict[1] if verdict else 0.0, verdict[2] if verdict else 0.0))

for r in rows:
    print(f"{r[0][:36]:36s} {str(r[1])[:18]:18s} {r[2]:3d}/{r[3]:3d}  {str(r[4])[:12]:12s} {str(r[5])[:28]:28s} colour {r[6]:4.0%}  dirt {r[7]:4.0%}")
weak = [r for r in rows if r[6] < 0.3]
print(f"{len(rows)} folders; {len(plan['meshes'])} meshes get paint, using {len(plan['setups'])} paint files; {no_geometry} meshes without geometry; "
      f"{len(weak)} folders under 30%:", [r[0] for r in weak])
print("files to make:", len(plan["setups"]) * 89)
if old:
    changed = [f for f, v in plan["folders"].items() if old.get("folders", {}).get(f, {}).get("base") != v["base"]]
    print(len(changed), "folders build on a different paint than before:", changed)
    was = {s: v["layers"] for s, v in old.get("setups", {}).items()}
    moved = [k for k, v in plan["setups"].items() if v["setup"] in was and was[v["setup"]] != v["layers"]]
    print(len(moved), "of the paint files now use different layers")
with open(os.path.join(CACHE, "plan.json"), "w", encoding="utf-8") as f:
    json.dump(plan, f, indent=1)
