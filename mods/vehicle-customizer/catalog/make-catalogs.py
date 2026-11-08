"""Generates the customizer's catalogs for every car and bike from the game's own files (RECORD.md, 2026-11-06).

Input: the vehicle records the game itself dumped (dev/runs/*/vehicle-records.jsonl, from the autotest job
"dump": each record's entity file, look, localized name, kind and whether the garage lists it), and the game's
archives, read with the probes' readers (experiments/areas/game-files, needing its data/parts.json).

A catalog is per entity file (.ent), since that is what a copy of a record can wear; its options come from the
whole model family, every look file of the same car. For each it writes:
- styles: the entity file's looks grouped by the parts and decorations they carry; a style's other looks are
  its factory paints; wrecked looks are kept apart;
- slots: found in the data, not listed by hand: a mount point (corners folded into a set: four wheels, four
  doors) and a kind of part (bumper, rims, tires, body, fairing...), with every option the family uses there;
  an option has meshes, shadows, a default paint, the paints its mesh offers, origin tags and, when it is
  another car's part, that car's name;
- kits: decorative parts that always appear together in the same looks, as add-ons;
- looks: for each look, which part fills each slot, so the engine can find it as the car is built.
Part numbers are the game's own mesh names, tidied (user, 2026-11-06).

Outputs:
- catalog/out/<catalog>.json and .txt for each catalog, and catalog/out/index.txt over all of them;
- mod/r6/tweaks/vehiclecustomizer/catalog/<catalog>.yaml, TweakDB flats under VehicleCustomizer.<catalog>;
- mod/r6/tweaks/vehiclecustomizer/catalogs.yaml, the list of catalogs and which records use which.

Usage: python -I make-catalogs.py [records.jsonl] [catalog ...]   (newest dump and every catalog by default)
"""
import collections
import datetime
import glob
import json
import os
import re
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
PROBES = os.path.join(ROOT, "experiments", "areas", "game-files")
sys.path.insert(0, PROBES)
import pkg  # noqa: E402
import rdar  # noqa: E402

OUT = os.path.join(HERE, "out")
TWEAKS = os.path.join(ROOT, "mod", "r6", "tweaks", "vehiclecustomizer")
FIXED = 131072.0
POOL = 5  # copies per catalog

# Kinds of part a slot can be, by the first of these words in the mesh name after __ext01_ or __int01_.
KINDS = ["bumper", "hood", "trunk", "fender", "spoiler", "wing", "roof", "fairing", "tank", "exhaust", "mirror",
         "seat", "seats", "interior", "door", "window", "wheel", "tire", "body"]
# Parts that are decoration or damage rather than a part of the car's shape.
NOT_A_PART = re.compile(r"sticker|decal|stripe|shadow|bullethole|damage|dirt|livery")
WRECK = re.compile(r"burnt|destroy|damaged|after_accident|wreck|flipped")
# A mesh's appearances that aren't paints: quest effects and damage states (the second sweep, 2026-11-06, turned
# Behemoths neon green with q305_hologram as a whole-car paint and a part's default paint).
NOT_A_PAINT = re.compile(r"holo|burnt|damaged|crashed|destroy|wreck|after_accident|ghost|glitch|scanner|xray")
# Looks that are quest effects, not something to sell: the q305 holograms (one spelled "hologrom").
NOT_A_STYLE = re.compile(r"holo|ghost|glitch|scanner|xray")
DAMAGE = re.compile(r"bullethole|damage|burnt|dirt_decal")
DECOR = re.compile(r"sticker|stripe|decal|antenna|light_device|vehicle_lights|sensor|radar|livery|player|police|kurtz|nomad")
FAMILIES = ["6th_street", "combatcab", "kurtz", "scavengers", "scavenger", "police", "nomad", "player", "deathrace",
            "valentinos", "maelstrom", "tyger", "animals", "sixth", "wraiths", "aldecaldos", "voodoo", "moxes",
            "mox", "barghest", "militech", "arasaka", "trauma", "netwatch", "ncpd", "max_tac", "taxi", "delamain",
            "sticker", "antenna"]
AREAS = [("hood", "hood"), ("door", "doors"), ("trunk", "trunk"), ("bumper", "bumper"), ("interior", "interior"),
         ("glove_box", "interior"), ("fairing", "fairing"), ("tank", "tank"), ("body", "body"), ("Base", "body")]
CORNER_MOUNT = re.compile(r"^(wheel|brake|door|window)_(front|back)_(left|right)(?:_([a-z]))?$")
AXLE_MOUNT = re.compile(r"^(wheel)_(front|back)$")
CORNERS = {"fl", "fr", "bl", "br", "f", "b"}
SLOT_LABELS = {("bumper", "bumper_front"): "Front bumper", ("bumper", "bumper_back"): "Rear bumper",
               ("wheel", "wheel"): "Rims", ("tire", "wheel"): "Tires", ("door", "door"): "Doors",
               ("window", "window"): "Side windows", ("window", "Base"): "Windshield", ("body", "Base"): "Body",
               ("interior", "Base"): "Interior", ("hood", None): "Hood", ("trunk", None): "Trunk",
               ("fairing", None): "Fairing", ("tank", None): "Tank", ("exhaust", None): "Exhaust",
               ("mirror", None): "Mirrors", ("spoiler", None): "Spoiler", ("seat", None): "Seats",
               ("seats", None): "Seats", ("roof", None): "Roof", ("fender", None): "Fenders", ("wing", None): "Wings"}


def fixed(v):
    return round(v["Bits"] / FIXED, 4) if isinstance(v, dict) and "Bits" in v else 0.0


def transform(t):
    if not isinstance(t, dict):
        return [0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 1.0]
    pos = t.get("Position", {}) or {}
    ori = t.get("Orientation", {}) or {}
    return [fixed(pos.get(a)) for a in ("x", "y", "z")], \
        [float(ori.get(a, 0.0 if a != "r" else 1.0) or 0.0) for a in ("i", "j", "k", "r")]


def short_id(text):
    return f"{rdar.fnv1a64(text) & 0xFFFFFFFF:08x}"


def base_name(mesh):
    return os.path.basename(mesh)[:-5] if mesh.endswith(".mesh") else os.path.basename(mesh)


def folder_of(path):
    """The vehicle folder a mesh lives in, such as v_standard2_archer_hella."""
    m = re.search(r"\\(v_[a-z0-9]+_[a-z0-9_]+?|av_[a-z0-9_]+?)\\entities\\", path)
    return m.group(1) if m else ""


def tail_tokens(mesh):
    """The words after __ext01_ or __int01_ in a mesh name, or all of them when it has neither."""
    name = base_name(mesh)
    m = re.search(r"__(?:ext|int)\d+_(.*)$", name)
    return (m.group(1) if m else name).split("_")


def kind_of(mesh):
    for word in tail_tokens(mesh):
        if word in KINDS:
            return "seat" if word == "seats" else word
    return None


def mesh_code(mesh, corners=True):
    """A part number from the game's own mesh name, written as the game writes it: the car's name and ext01
    dropped, the variant (police, junk) kept: v_standard2_archer_hella__ext01_junk_bumper_f_01.mesh becomes
    junk_bumper_f_01. Corner letters stay on a single part and are dropped for a set of four."""
    name = base_name(mesh)
    folder = folder_of(mesh)
    rest = name[len(folder):] if folder and name.startswith(folder) else name
    variant, _, part = rest.partition("__")
    if not part:
        variant, part = "", variant
    if variant.startswith(("v_", "av_")):
        variant = ""
    words = [w for w in variant.strip("_").split("_") + part.split("_")
             if w and (corners or w not in CORNERS) and not re.fullmatch(r"(ext|int)\d+", w)]
    return "_".join(words).lower()


def part_code(meshes):
    return " + ".join(dict.fromkeys(mesh_code(m, corners=len(meshes) == 1) for m in meshes))


def mount_group(mount):
    """A mount point's slot group and corner: wheel_front_left -> (wheel, fl); door_back_right_a -> (door, br);
    wheel_back on a bike -> (wheel, b); bumper_front -> (bumper_front, all)."""
    m = CORNER_MOUNT.match(mount)
    if m:
        group = m.group(1) + (f"_{m.group(4)}" if m.group(4) and m.group(4) != "a" else "")
        return group, m.group(2)[0] + m.group(3)[0]
    m = AXLE_MOUNT.match(mount)
    if m:
        return m.group(1), m.group(2)[0]
    return mount, "all"


CORNER_WORDS = {"fl": ("fl", "front_left", "lf"), "fr": ("fr", "front_right", "rf"),
                "bl": ("bl", "back_left", "rear_left", "lb", "rl"), "br": ("br", "back_right", "rear_right", "rb", "rr"),
                "f": ("f", "front"), "b": ("b", "back", "rear")}


def role_of(name, corner):
    """A part's role: its name in lowercase with its corner written as <c>, so door_fl_a and door_br_a are one
    role at two corners; a part on a mount with no corners keeps its whole name (seat_fl_a on Base)."""
    n = name.lower()
    for w in CORNER_WORDS.get(corner, ()):
        new = re.sub(rf"(^|_){w}(_|$)", r"\1<c>\2", n, count=1)
        if new != n:
            return new
    return n


def role_words(role):
    model = re.match(r"^v_[a-z0-9_]*?__(?:ext|int)\d+_", role)
    words = set((role[model.end():] if model else role).split("_"))
    if model:
        fam = family_word(model.group(0))
        if fam:
            words.add(fam)
    return {w for w in words if w and w != "<c>" and not w.isdigit() and len(w) > 1}


def role_likeness(a, b):
    """How alike two roles' names are, by the words they share (0 to 1)."""
    wa, wb = role_words(a), role_words(b)
    return len(wa & wb) / len(wa | wb) if wa | wb else 0.0


def role_suffix(role):
    """A short name for a second slot of the same mount and kind: interior_trunk_01 -> interior_trunk, the police
    body over the stock one (v_standard2_archer_hella_police__ext01_body_01) -> police_body."""
    model = re.match(r"^v_[a-z0-9_]*?__(?:ext|int)\d+_", role)
    rest = role[model.end():] if model else role
    fam = family_word(model.group(0)) if model else None
    words = [w for w in rest.split("_") if w and w != "<c>" and not w.isdigit()]
    if fam and fam not in words:
        words.insert(0, fam)
    return re.sub(r"[^a-z0-9_]", "", "_".join(words))


LABEL_WORDS = {"f": "front", "b": "back", "fl": "front left", "fr": "front right", "bl": "back left",
               "br": "back right", "l": "left", "r": "right"}


def role_label(role, kind, base_label=""):
    """What tells one slot from another of the same mount and kind, for people, leaving out what the slot's name
    already says: interior_trunk_01 -> trunk, the police front bumper under "Front bumper" -> police,
    window_bl_02 -> back left; "main" when nothing does."""
    said = set(base_label.lower().split())
    words = [LABEL_WORDS.get(w, w) for w in role_suffix(role).split("_") if w and w != kind and not w.isdigit()]
    words = [w for w in words if not set(w.split()) <= said]
    return " ".join(words) or "main"


def qmul(a, b):
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return [aw * bx + ax * bw + ay * bz - az * by, aw * by - ax * bz + ay * bw + az * bx,
            aw * bz + ax * by - ay * bx + az * bw, aw * bw - ax * bx - ay * by - az * bz]


def qrot(q, v):
    x, y, z, w = q
    tx, ty, tz = 2 * (y * v[2] - z * v[1]), 2 * (z * v[0] - x * v[2]), 2 * (x * v[1] - y * v[0])
    return [v[0] + w * tx + (y * tz - z * ty), v[1] + w * ty + (z * tx - x * tz), v[2] + w * tz + (x * ty - y * tx)]


def slot_label(kind, group):
    for key in ((kind, group), (kind, re.sub(r"_[a-z]$", "", group)), (kind, None)):
        if key in SLOT_LABELS:
            label = SLOT_LABELS[key]
            extra = re.match(r".*_([b-z])$", group)
            return label + (f" ({extra.group(1)})" if extra and key[1] != group else "")
    return f"{kind.capitalize()} ({group})"


def mount_area(part):
    parent = part["bind"] if part["bind"] != "vehicle_slots" else part["slot"]
    for key, area in AREAS:
        if key in str(parent):
            return area
    return "body"


def family_word(text):
    for word in FAMILIES:
        if word in text:
            return word
    return None


class Reader:
    def __init__(self):
        present = json.load(open(os.path.join(PROBES, "data", "parts.json"), encoding="utf-8"))["present"]
        self.present = present
        self.depot = pkg.Depot()
        self.depot.add_names(present)
        self.by_hash = {rdar.fnv1a64(p): p for p in present}
        self.paint_cache = {}
        self.app_cache = {}
        self.box_cache = {}
        self.bounds_cache = {}

    def ent_looks(self, ent):
        loaded = self.depot.load(ent)
        if not loaded:
            return [], None
        head, bufs = loaded
        root = pkg.Cooked(head, bufs, self.depot).exports[0][1]
        looks = []
        for a in root.get("appearances", []) or []:
            res = a.get("appearanceResource")
            looks.append((str(a.get("name")), res[1] if isinstance(res, tuple) else str(res),
                          str(a.get("appearanceName"))))
        return looks, str(root.get("defaultAppearance"))

    def app_looks(self, app):
        if app in self.app_cache:
            return self.app_cache[app]
        out = {}
        loaded = self.depot.load(app)
        if loaded:
            head, bufs = loaded
            try:
                c = pkg.Cooked(head, bufs, self.depot)
            except Exception:
                c = None
            for cls, d in (c.exports if c else []):
                if cls != "appearanceAppearanceDefinition":
                    continue
                cd = d.get("compiledData")
                b = c.buffer(cd[1]) if cd else None
                if not b:
                    continue
                try:
                    p = pkg.Package(b, self.depot)
                    objs = p.objects(only={"name", "mesh", "meshAppearance", "parentTransform", "slotName", "bindName"})
                except Exception:
                    continue
                parts = {}
                for i, (ocls, obj) in enumerate(objs):
                    mesh = obj.get("mesh")
                    if not (isinstance(mesh, tuple) and mesh[0] == "ref") or str(mesh[1]).startswith("#"):
                        continue
                    bind = slot = None
                    pt = obj.get("parentTransform")
                    if isinstance(pt, tuple) and 0 <= pt[1] < len(objs):
                        bind = objs[pt[1]][1].get("bindName")
                        slot = objs[pt[1]][1].get("slotName")
                    parts[str(obj.get("name"))] = {
                        "cls": ocls, "mesh": mesh[1], "paint": str(obj.get("meshAppearance", "default")),
                        "bind": None if bind in (None, "None") else str(bind),
                        "slot": None if slot in (None, "None") else str(slot), "chunk": i,
                    }
                out[str(d.get("name"))] = {"parts": parts, "package": p}
        self.app_cache[app] = out
        return out

    def offset(self, look, name):
        p = look["package"]
        i = look["parts"][name]["chunk"]
        off = p.chunks[i][1]
        end = p.chunks[i + 1][1] if i + 1 < len(p.chunks) else p.end
        try:
            return transform(p.read_obj(off, end).get("localTransform"))
        except Exception:
            return [0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 1.0]

    def mesh_box(self, mesh):
        """A wheel or tire mesh's size from its bounding box, the axle along X: (radius, width), or None."""
        if mesh in self.box_cache:
            return self.box_cache[mesh]
        size = None
        loaded = self.depot.load(mesh)
        if loaded:
            head, bufs = loaded
            try:
                box = pkg.Cooked(head, bufs, self.depot).exports[0][1].get("boundingBox") or {}
                lo, hi = box.get("Min") or {}, box.get("Max") or {}
                radius = max(hi.get("Y", 0) - lo.get("Y", 0), hi.get("Z", 0) - lo.get("Z", 0)) / 2
                width = hi.get("X", 0) - lo.get("X", 0)
                if radius > 0.05 and width > 0.02:
                    size = (round(radius, 4), round(width, 4))
            except Exception:
                size = None
        self.box_cache[mesh] = size
        return size

    def mesh_bounds(self, mesh):
        """A mesh's own bounding box, ((min x, y, z), (max x, y, z)) in its local space, or None (the tool's part
        under the crosshair, UX.md 2026-11-07: a part's box carried into the world by its component's transform)."""
        if mesh in self.bounds_cache:
            return self.bounds_cache[mesh]
        found = None
        loaded = self.depot.load(mesh)
        if loaded:
            head, bufs = loaded
            try:
                box = pkg.Cooked(head, bufs, self.depot).exports[0][1].get("boundingBox") or {}
                lo, hi = box.get("Min") or {}, box.get("Max") or {}
                mn = tuple(round(lo.get(k, 0.0), 4) for k in "XYZ")
                mx = tuple(round(hi.get(k, 0.0), 4) for k in "XYZ")
                if all(b >= a for a, b in zip(mn, mx)) and any(b > a for a, b in zip(mn, mx)):
                    found = (mn, mx)
            except Exception:
                found = None
        self.bounds_cache[mesh] = found
        return found

    def paints(self, mesh):
        if mesh in self.paint_cache:
            return self.paint_cache[mesh]
        names = []
        loaded = self.depot.load(mesh)
        if loaded:
            head, _ = loaded
            try:
                c = rdar.CR2W(head)
                off, n, _ = c.tables[4]
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
                            names.append(c.names[struct.unpack_from("<H", head, p + 8)[0]])
                        p += 4 + sz
            except Exception:
                pass
        self.paint_cache[mesh] = names
        return names


def path_hash(path):
    """A depot path's hash as the game keys files: FNV-1a 64 of the lowercased path."""
    h = 0xcbf29ce484222325
    for b in path.lower().encode():
        h = ((h ^ b) * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF
    return h


KNOWN_PATHS = r"C:\Program Files (x86)\Steam\steamapps\common\Cyberpunk 2077\red4ext\plugins\Codeware\Data\KnownHashes.txt"


def guess_entity_paths(r):
    """Entity file paths a record may use, made from its own name and its look's: the game gave some records'
    files only as a hash (every Arch Nazare, Johnny's Porsche, the Semimaru, the Legatus; 2026-11-06), and the
    Nazare's is v_sportbike2_arch_nemesis_basic_01.ent, one underscore where most have two."""
    name = r["name"].split(".", 1)[-1]
    m = re.match(r"(v_([a-z]+?)\d*_)(.*)$", name)
    if not m:
        return []
    prefix, cls, rest = m.group(1), m.group(2), m.group(3)
    models = {re.sub(r"(_player.*|_\d+)$", "", rest)}
    look = r.get("look") or ""
    lm = re.match(r"(.+?)_+basic", look)
    if lm:
        models.add(lm.group(1))
    out = []
    for root in ("base", "ep1"):
        for model in models:
            for tail in ("__basic_01", "_basic_01", "_01", "__01", "_01__basic_01"):
                out.append("%s\\vehicles\\%s\\%s%s%s.ent" % (root, cls, prefix, model, tail))
    return out


def resolve_templates(records):
    """Fills in the entity file of records the dump gave only as a hash, from Codeware's list of known paths and
    from paths guessed from the record's name; says which stay unknown."""
    wanted = {}
    for r in records:
        if not r.get("template") and r.get("template_hash"):
            h = int(str(r["template_hash"]).rstrip("ULL") or 0)
            if h:
                wanted.setdefault(h, []).append(r)
    if not wanted:
        return
    known = {}
    if os.path.exists(KNOWN_PATHS):
        with open(KNOWN_PATHS, encoding="utf-8", errors="replace") as f:
            for line in f:
                path = line.strip()
                if path.endswith(".ent"):
                    h = path_hash(path)
                    if h in wanted:
                        known[h] = path
    for h, rs in wanted.items():
        if h not in known:
            for r in rs:
                for guess in guess_entity_paths(r):
                    if path_hash(guess) == h:
                        known[h] = guess
                        break
                if h in known:
                    break
    unresolved = []
    for h, rs in wanted.items():
        for r in rs:
            if h in known:
                r["template"] = known[h]
            elif r.get("garage"):
                unresolved.append(r["name"])
    print("entity files found from their hash: %d; garage records still without one: %s"
          % (len(known), ", ".join(sorted(unresolved)) or "none"))


def load_records(path):
    records = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                records.append(json.loads(line))
    resolve_templates(records)
    return records


def newest_dump():
    found = sorted(glob.glob(os.path.join(ROOT, "dev", "runs", "*", "vehicle-records.jsonl")))
    if not found:
        sys.exit("no vehicle-records.jsonl in dev/runs: run tools/run-autotest.ps1 -Job dump first")
    return found[-1]


def family_key(ent):
    """The model family an entity file belongs to: its name before __, without _ep1 or a trailing number, so
    v_standard2_villefort_cortes_01__police_01.ent and v_standard2_archer_hella_ep1__basic_01.ent fall in with
    their basic models."""
    stem = os.path.basename(ent)[:-4].split("__")[0]
    while True:
        new = re.sub(r"(_ep1|_\d+)$", "", stem)
        if new == stem:
            return stem
        stem = new


def catalog_id(ent):
    """A catalog's name: the entity file's name without its vehicle class, and _ep1 for Phantom Liberty's copy
    of a base game file."""
    cid = re.sub(r"^(v|av)_[a-z0-9]+_", "", os.path.basename(ent)[:-4])
    if ent.lower().startswith("ep1\\") and "ep1" not in cid:
        cid += "_ep1"
    return cid


QUEST = re.compile(r"\\(q\d|sq\d|mq\d|sts_|mws_|ma_|ps_|ina_|wst_|airdrop|escape_pod|orbital|vehicle_template|"
                   r"drone|q101|panam|judy|johnny|kerry|rogue|saul|santiago|sobchak|takemura|reginald|reed_|jackie|"
                   r"delamain_cab|e319|spaceport|tram|train|drone|platform|metro|sa_|av_|aerial|scanning)")


def choose_entities(records):
    """The entity files that get a catalog: every one a garage record uses, and every one only plain records of
    a car or bike V can't own use, leaving out quest and character one-offs, AVs and scene copies."""
    kind = lambda r: (r.get("type") or "").split(":")[-1].strip()  # noqa: E731
    chosen = collections.OrderedDict()
    for r in records:
        t = r.get("template")
        if r.get("garage") and t and not re.search(r"_vctest|\.vc_", r["name"]):
            chosen.setdefault(t, {"garage": True, "records": []})["records"].append(r)
    skip = ("cs_savable", "hackable", "dummy", "destroyed", "deco", "broken", "test", "trauma", "prevention")
    for r in records:
        t = r.get("template")
        if not t or t in chosen and chosen[t]["garage"]:
            continue
        if not kind(r).startswith(("Car", "Bike")) or "\\av\\" in t or QUEST.search(t.lower()) or \
                re.search(r"drone|train|scanning|platform", os.path.basename(t).lower()):
            continue
        if any(s in r["name"] for s in skip) or re.search(r"\.(q|sq|mq)\d", r["name"]):
            continue
        chosen.setdefault(t, {"garage": False, "records": []})["records"].append(r)
    return chosen


def build_catalog(r, ent, family_ents, names_by_folder, entry):
    """One catalog: the styles of ent, and slots, options and kits from every look file of its family."""
    ent_looks, default = r.ent_looks(ent)
    if not ent_looks:
        return None
    family = family_key(ent)
    apps = set()
    looks_of = {}  # (app, app look) -> entity look name for looks of this entity file
    for other in family_ents:
        el, _ = r.ent_looks(other)
        for name, app, app_look in el:
            apps.add(app)
            if other == ent:
                looks_of[(app, app_look)] = name
    looks = {}
    for app in sorted(apps):
        for name, data in r.app_looks(app).items():
            looks[(app, name)] = data
    reachable = {ent_name: (app, al) for ent_name, app, al in ent_looks if (app, al) in looks}
    if not reachable:
        return None
    short = lambda n: re.sub(r"^.*?__(basic_)?", "", n) if "__" in n else n  # noqa: E731

    def look_key(app, app_look):
        return looks_of.get((app, app_look)) or f"{os.path.basename(app)[:-4]}:{app_look}"

    # --- slots, found in the data, as roles ---
    # A role is one part of the car: a part by its name, the corner written as <c> so a door's four corners are
    # one role (door_<c>_a). Roles a look has side by side are different slots: the Hella's cabin and its trunk
    # interior, a body and the police body over it, a door and its mirror on one mount (2026-11-06: one slot per
    # mount and kind made a second cabin, which flickered). Roles no look has together are alternatives for one
    # slot, joined by the words their names share: the stock and the junk bumper, wheel_<c>_01 and wheel_<c>_03.
    data_by_key = {look_key(app, al): data for (app, al), data in looks.items()}
    roles = collections.defaultdict(dict)  # (group, kind) -> role -> {"looks": {key: {corner: (name, part)}}, "mounts"}
    for (app, app_look), data in looks.items():
        key = look_key(app, app_look)
        for name, part in data["parts"].items():
            if part["bind"] != "vehicle_slots" or not part["slot"]:
                continue
            text = (name + " " + base_name(part["mesh"])).lower()
            if NOT_A_PART.search(text):
                continue
            kind = kind_of(part["mesh"])
            if not kind:
                continue
            group, corner = mount_group(part["slot"])
            role = roles[(group, kind)].setdefault(role_of(name, corner), {"looks": {}, "mounts": {}})
            role["looks"].setdefault(key, {})[corner] = (name, part)
            role["mounts"][corner] = part["slot"]
    units = []  # (group, kind, slot id, label, {role: info}) per slot
    used_ids = set()
    for (group, kind), by_role in roles.items():
        order = sorted(by_role, key=lambda n: (-len(by_role[n]["looks"]), n))

        def clash(a, b):
            # Different parts of the car only if a look has both at the same corner: the game names one part
            # unevenly from corner to corner (police_wheel_01_fl_0a, police_wheel_01_bl_a).
            la, lb = by_role[a]["looks"], by_role[b]["looks"]
            return any(set(la[k]) & set(lb[k]) for k in set(la) & set(lb))

        clusters = []
        for name in order:
            best, best_score = None, 0.0
            for cl in clusters:
                if any(clash(name, other) for other in cl):
                    continue  # a look has both: different parts of the car
                score = max(role_likeness(name, other) for other in cl)
                if score > best_score:
                    best, best_score = cl, score
            if best is None:
                clusters.append([name])
            else:
                best.append(name)
        clusters.sort(key=lambda cl: -len({k for name in cl for k in by_role[name]["looks"]}))
        for n, cl in enumerate(clusters):
            base = f"{group}.{kind}".lower()
            label = slot_label(kind, group)
            if len(clusters) > 1:
                label += ": " + role_label(cl[0], kind, label)
            if n == 0:
                slot_id = base
            else:
                slot_id = f"{base}.{role_suffix(cl[0]) or f'part_{n + 1}'}"
            while slot_id in used_ids:
                slot_id += "_2"
            used_ids.add(slot_id)
            units.append((group, kind, slot_id, label, {name: by_role[name] for name in cl}))
    slots = []
    choice = {}
    slot_parts = collections.defaultdict(dict)
    for group, kind, slot_id, label, members in units:
        mounts = {}
        for info in members.values():
            mounts.update(info["mounts"])
        corners = sorted(mounts, key=lambda c: ["fl", "fr", "bl", "br", "f", "b", "all"].index(c)
                         if c in ("fl", "fr", "bl", "br", "f", "b", "all") else 9)
        picks = collections.defaultdict(dict)  # look key -> {corner: (name, part)}: one part per corner
        for info in members.values():
            for key, at in info["looks"].items():
                picks[key].update(at)
        # Where the slot's part sits on each mount, from the look that has it most often, for adding it to a
        # look that lacks it.
        place = {}
        for info in sorted(members.values(), key=lambda i: -len(i["looks"])):
            for key, at in info["looks"].items():
                for c, (n, _p) in at.items():
                    if c not in place:
                        place[c] = r.offset(data_by_key[key], n)
        options = {}
        for (app, app_look), data in looks.items():
            key = look_key(app, app_look)
            found = picks.get(key)
            if not found or len(found) < len(corners):
                continue
            meshes = {c: found[c][1]["mesh"] for c in corners}
            ident = short_id(slot_id + "|" + "|".join(f"{c}={m}" for c, m in sorted(meshes.items())))
            option = options.setdefault(ident, {"id": ident, "meshes": meshes, "shadows": {}, "classes": set(),
                                                "paint_use": collections.Counter(), "looks": set()})
            option["looks"].add(key)
            for c in corners:
                n, p = found[c]
                option["classes"].add(p["cls"])
                option["paint_use"][p["paint"]] += 1
                for sname, spart in data["parts"].items():
                    if spart["bind"] == n and ("shadow" in sname or "shadow" in spart["mesh"]):
                        option["shadows"][c] = spart["mesh"]
            choice[(key, slot_id)] = ident
            slot_parts[key][slot_id] = {c: found[c][0] for c in corners}
        out = []
        for o in options.values():
            meshes = [o["meshes"][c] for c in corners]
            folder = folder_of(meshes[0])
            vehicle = None
            if folder and family_key(folder + "__.ent") != family:
                vehicle = names_by_folder.get(family_key(folder + "__.ent")) or folder
            paints = [p for p in r.paints(meshes[0]) if not NOT_A_PAINT.search(p)]
            usual = [p for p, _n in o["paint_use"].most_common() if not NOT_A_PAINT.search(p)]
            default = usual[0] if usual else (paints[0] if paints else "default")
            out.append({"id": o["id"], "code": part_code(meshes), "vehicle": vehicle, "meshes": o["meshes"],
                        "shadows": o["shadows"], "classes": sorted(o["classes"]),
                        "default_paint": default, "paints": paints, "looks": sorted(o["looks"])})
        if not out:
            continue
        # A slot with one option and one paint or none is a fixed part, not a choice.
        if len(out) == 1 and len(out[0]["paints"]) <= 1:
            continue
        out.sort(key=lambda o: (-len(o["looks"]), o["code"]))
        slots.append({"id": slot_id, "label": label, "kind": kind, "group": group, "corners": corners,
                      "mounts": [mounts[c] for c in corners],
                      "positions": [place.get(c, ([0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 1.0]))[0] for c in corners],
                      "rotations": [place.get(c, ([0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 1.0]))[1] for c in corners],
                      "roles": sorted(members), "options": out})
    # A slot left alone of its mount and kind, once fixed parts are dropped, needs no word to tell it apart.
    alone = collections.Counter((s["group"], s["kind"]) for s in slots)
    for s in slots:
        if alone[(s["group"], s["kind"])] == 1:
            s["label"] = slot_label(s["kind"], s["group"])
    slots.sort(key=lambda s: (["bumper_front", "bumper_back", "hood_a", "trunk_a", "base", "wheel", "door"].index(
        s["group"].lower()) if s["group"].lower() in ("bumper_front", "bumper_back", "hood_a", "trunk_a", "base",
                                                     "wheel", "door") else 7, s["id"]))

    # --- kits: decorative parts that always appear together ---
    slot_names = {n for parts in slot_parts.values() for v in parts.values() for n in v.values()}
    decor, decor_looks = {}, collections.defaultdict(set)
    for (app, app_look), data in looks.items():
        key = look_key(app, app_look)
        parts = data["parts"]
        for name, part in parts.items():
            text = (name + " " + part["mesh"]).lower()
            if "shadow" in text or DAMAGE.search(text) or name in slot_names or not DECOR.search(text):
                continue
            on_part = part["bind"] in parts and part["bind"] != name
            on_body = part["bind"] == "vehicle_slots" and part["slot"] in ("Base", "body", "root")
            if not (on_part or on_body):
                continue
            ident = (name, part["mesh"])
            decor_looks[ident].add(key)
            if ident not in decor:
                pos, rot = r.offset(data, name)
                shadow = next((sp["mesh"] for sn, sp in parts.items() if sp["bind"] == name and "shadow" in sn), None)
                decor[ident] = {"name": name, "mesh": part["mesh"], "code": mesh_code(part["mesh"]),
                                "paint": part["paint"], "cls": part["cls"], "bind": part["bind"],
                                "slot": part["slot"], "position": pos, "rotation": rot, "shadow": shadow,
                                "look": key}
    together = collections.defaultdict(list)
    for ident, seen in decor_looks.items():
        together[frozenset(seen)].append(decor[ident])
    kits = []
    for seen, parts in together.items():
        parts.sort(key=lambda p: p["name"])
        fam = family_word(" ".join((p["name"] + " " + p["mesh"]).lower() for p in parts))
        if not fam:
            continue
        where = sorted({mount_area(p) for p in parts})
        code = parts[0]["code"] if len(parts) == 1 else "_".join(["kit", fam] + where)
        kits.append({"id": f"{fam}_{short_id('|'.join(p['name'] for p in parts))[:4]}", "family": fam, "code": code,
                     "where": where, "parts": parts, "looks": sorted(seen)})
    # Every kit part hangs straight off a mount point of the car (2026-11-06, user agreed): the chain of parts it
    # hung off in its look is walked up to the part on a mount point, and their offsets worked into its own, so
    # it needs neither that part nor another kit, only the mount point, and a part on a door still swings with
    # the door. A kit whose part sat on another kit's part notes that kit as what it was made for (the police
    # light bar sits on the police body shell's roof rack), a hint, not a rule. Where the chain breaks (a part
    # that isn't a mesh), the part keeps hanging off what it did:
    # a slot's part, "part:<slot>|<corner>"; that part's shadow, "shadow:<slot>|<corner>"; a part of this or
    # another kit, "kit:<kit>:<index>"; or, for anything else, the part's own name.
    in_kit = {p["name"]: (k["id"], i) for k in kits for i, p in enumerate(k["parts"])}
    coverage = collections.Counter(sid for by in slot_parts.values() for sid in by)

    def to_mount(data, name):
        parts = data["parts"]
        pos, rot = r.offset(data, name)
        part = parts[name]
        hops, seen = [], {name}
        while part["bind"] != "vehicle_slots":
            parent = part["bind"]
            if not parent or parent not in parts or parent in seen:
                return None
            seen.add(parent)
            hops.append(parent)
            ppos, prot = r.offset(data, parent)
            moved = qrot(prot, pos)
            pos = [moved[0] + ppos[0], moved[1] + ppos[1], moved[2] + ppos[2]]
            rot = qmul(prot, rot)
            part = parts[parent]
        if not part["slot"]:
            return None
        return part["slot"], pos, rot, hops

    def slot_part_named(name):
        for k in slot_parts:
            for sid, by in slot_parts[k].items():
                for corner, nm in by.items():
                    if nm == name:
                        return sid, corner, k
        return None

    for kit in kits:
        kit["made_for"] = set()
        for p in kit["parts"]:
            bind = p["bind"]
            mounted = to_mount(data_by_key[p["look"]], p["name"]) if bind != "vehicle_slots" else None
            if mounted:
                p["parent"] = f"vehicle_slots:{mounted[0]}"
                p["position"], p["rotation"] = mounted[1], mounted[2]
                for h in mounted[3]:
                    if h in in_kit and in_kit[h][0] != kit["id"]:
                        kit["made_for"].add("kit:" + in_kit[h][0])
                    elif h not in in_kit:
                        under = slot_part_named(h)
                        # A part only some looks have, such as the police body over the stock one.
                        if under and coverage[under[0]] < len(looks):
                            kit["made_for"].add("slot:" + under[0])
                continue
            found = slot_part_named(bind) if bind != "vehicle_slots" else None
            if bind == "vehicle_slots":
                p["parent"] = f"vehicle_slots:{p['slot']}"
            elif bind in in_kit:
                p["parent"] = "kit:%s:%d" % in_kit[bind]
            elif found:
                p["parent"] = f"part:{found[0]}|{found[1]}"
            else:
                p["parent"] = bind
                owner = data_by_key.get(p["look"], {}).get("parts", {}).get(bind)
                if owner and "shadow" in bind:
                    under = slot_part_named(owner["bind"])
                    if under:
                        p["parent"] = f"shadow:{under[0]}|{under[1]}"
        kit["needs"] = sorted({p["parent"].split(":")[1] for p in kit["parts"]
                               if p["parent"].startswith("kit:") and p["parent"].split(":")[1] != kit["id"]})
        kit["made_for"] = sorted(kit["made_for"])
    counts = collections.Counter()
    for kit in sorted(kits, key=lambda k: (-len(k["looks"]), k["id"])):
        counts[kit["code"]] += 1
        if counts[kit["code"]] > 1:
            kit["code"] += f"_{counts[kit['code']]}"
    kits.sort(key=lambda k: (k["family"], k["code"]))

    # --- styles ---
    stem = lambda n: re.sub(r"(_\d+)+$|_new$", "", short(n))  # noqa: E731
    wrecks = sorted(n for n in reachable if WRECK.search(n))
    groups = collections.defaultdict(list)
    for name in reachable:
        if name in wrecks or NOT_A_STYLE.search(name):
            continue
        sig = tuple(choice.get((name, s["id"])) for s in slots)
        kit_sig = tuple(sorted(k["id"] for k in kits if name in k["looks"]))
        groups[(sig, kit_sig)].append(name)
    styles = []
    for (sig, kit_sig), members in groups.items():
        common = collections.Counter(stem(m) for m in members).most_common(1)[0][0]
        members.sort(key=lambda n: (stem(n) != common, len(short(n)), short(n)))
        base = members[0]
        label = re.sub(r"_0?1$", "", short(base)).replace("_", " ")
        label = {"player": "V's own", "6th street": "6th Street", "combatcab": "Combat cab"}.get(
            label, label[:1].upper() + label[1:])
        styles.append({"id": short(base), "code": short(base), "label": label, "base_look": base,
                       "looks": members, "options": {s["id"]: o for s, o in zip(slots, sig) if o},
                       "kits": list(kit_sig)})
    styles.sort(key=lambda s: (s["label"], s["id"]))
    seen_ids = collections.Counter()
    for s in styles:
        seen_ids[s["id"]] += 1
        if seen_ids[s["id"]] > 1:
            s["id"] += f"_{seen_ids[s['id']]}"
    style_of = {look: s["id"] for s in styles for look in s["looks"]}

    def origin(look):
        if look in style_of:
            return "style:" + style_of[look]
        if look in wrecks:
            return "wreck:" + short(look)
        return "look:" + look.split(":")[-1]

    for slot in slots:
        for o in slot["options"]:
            o["origins"] = sorted({origin(l) for l in o["looks"]})
    for kit in kits:
        kit["origins"] = sorted({origin(l) for l in kit["looks"]})

    # --- wheels: every rim and tire pair this family's looks put on an axle, for the shared wheel list, and the
    # size this car's own tires are, which a wheel from elsewhere is scaled to (2026-11-06, user agreed). Both sides
    # of a car use the same meshes (the mount points mirror them), so the left side is read. Only the main axles
    # (wheel_front_*, wheel_back_*; a bike's wheel_front, wheel_back) for now, not a truck's extra ones.
    wheel_sets = {}
    # This car's own rim and tire pairs per axle, so its tires' size (what a tire from elsewhere is scaled to) and its
    # rims' radius (what a tire's inside is sized to when its rim is the car's own) come from one pair (2026-11-07:
    # rims and tires are chosen apart, user).
    own_pairs = {"f": collections.Counter(), "b": collections.Counter()}
    bike = False
    for (app, al), data in looks.items():
        key = look_key(app, al)
        parts = data["parts"]
        per = collections.defaultdict(dict)
        for name, part in parts.items():
            if part["bind"] != "vehicle_slots" or not part["slot"]:
                continue
            text = (name + " " + part["mesh"]).lower()
            kind = kind_of(part["mesh"])
            if kind not in ("wheel", "tire") or "shadow" in text or WRECK.search(text):
                continue
            group, corner = mount_group(part["slot"])
            if group != "wheel" or corner not in ("fl", "bl", "f", "b"):
                continue
            bike = bike or corner in ("f", "b")
            per[corner[0]][kind] = (name, part)
        for axle, got in per.items():
            if "wheel" not in got or "tire" not in got:
                continue
            (rn, rp), (tn, tp) = got["wheel"], got["tire"]
            shadow_of = lambda n: next((sp["mesh"] for sn, sp in parts.items()  # noqa: E731
                                        if sp["bind"] == n and "shadow" in (sn + sp["mesh"]).lower()), "")
            s = wheel_sets.setdefault((rp["mesh"], tp["mesh"]), {
                "rim": rp["mesh"], "tire": tp["mesh"], "rim_shadow": shadow_of(rn), "tire_shadow": shadow_of(tn),
                "axles": set(), "looks": 0, "rim_paint": collections.Counter(), "look_names": set()})
            s["axles"].add(axle)
            s["looks"] += 1
            s["look_names"].add(key)
            s["rim_paint"][rp["paint"]] += 1
            if key in reachable:
                own_pairs[axle][(rp["mesh"], tp["mesh"])] += 1
    # Where a tire sits along the axle from its mesh's pivot, the middle of its box (2026-11-08: pivots differ by up to
    # 20 cm from car to car, so a wheel from elsewhere has to be moved to where this car's own tire sits).
    def center_of(mesh):
        b = r.mesh_bounds(mesh)
        return round((b[0][0] + b[1][0]) / 2, 4) if b else 0.0

    wheel_ref = {}
    for axle, use in own_pairs.items():
        for (rim_mesh, tire_mesh), _n in use.most_common():
            size = r.mesh_box(tire_mesh)
            rim_size = r.mesh_box(rim_mesh)
            if size:
                wheel_ref[axle] = (size[0], size[1], rim_size[0] if rim_size else 0.0, center_of(tire_mesh))
                break
    folder_label = names_by_folder.get(family) or None
    sets_out = []
    for s in wheel_sets.values():
        tire_size, rim_size = r.mesh_box(s["tire"]), r.mesh_box(s["rim"])
        if not tire_size or not rim_size:
            continue
        rim_paints = [p for p in r.paints(s["rim"]) if not NOT_A_PAINT.search(p)]
        usual = [p for p, _n in s["rim_paint"].most_common() if not NOT_A_PAINT.search(p)]
        fam = family_key(folder_of(s["rim"]) + "__.ent") if folder_of(s["rim"]) else family
        sets_out.append({"id": short_id(s["rim"] + "|" + s["tire"]), "rim": s["rim"], "tire": s["tire"],
                         "rim_shadow": s["rim_shadow"], "tire_shadow": s["tire_shadow"],
                         "code": mesh_code(s["rim"]), "tire_code": mesh_code(s["tire"]),
                         "from": names_by_folder.get(fam) or folder_label or catalog_id(ent),
                         "radius": tire_size[0], "width": tire_size[1], "rim_radius": rim_size[0],
                         "tire_center": center_of(s["tire"]),
                         "axles": sorted(s["axles"]), "looks": s["looks"], "paints": rim_paints,
                         "default_paint": usual[0] if usual else (rim_paints[0] if rim_paints else "default"),
                         "kind": "bike" if bike else "car", "look_names": sorted(s["look_names"])})

    look_table = {name: {"app": app, "app_look": al, "style": style_of.get(name), "wreck": name in wrecks,
                         "parts": slot_parts.get(name, {})} for name, (app, al) in reachable.items()}
    # Every mesh this family's looks, options, kits and wheels use, for the shared table of part boxes (boxes.yaml).
    mesh_paths = {part["mesh"] for data in looks.values() for part in data["parts"].values() if part.get("mesh")}
    for slot in slots:
        for o in slot["options"]:
            mesh_paths.update(m for m in o["meshes"].values() if m)
    for kit in kits:
        mesh_paths.update(x["mesh"] for x in kit["parts"] if x.get("mesh"))
    for s in sets_out:
        mesh_paths.update(m for m in (s["rim"], s["tire"]) if m)
    recs = entry["records"]
    label = collections.Counter(x.get("display") for x in recs if x.get("display")).most_common(1)
    return {"id": catalog_id(ent), "label": label[0][0] if label else catalog_id(ent), "entity": ent,
            "family": family, "garage": entry["garage"], "default_look": default,
            "records": sorted(x["name"] for x in recs), "generated": datetime.date.today().isoformat(),
            "source_apps": sorted(apps), "styles": styles, "wrecks": wrecks, "slots": slots, "kits": kits,
            "looks": look_table, "wheel_kind": "bike" if bike else "car", "wheel_ref": wheel_ref,
            "wheel_sets": sets_out, "mesh_paths": sorted(mesh_paths),
            # Which record wears which look, so a wheel is named after the cars it's seen on (wheels.yaml).
            "record_looks": sorted({(x.get("look") or "", x.get("display") or "") for x in recs})}


def summary(cat):
    short = lambda n: re.sub(r"^.*?__(basic_)?", "", n)  # noqa: E731
    lines = [f"{cat['label']} ({cat['id']}), from {cat['entity']}", f"records: {', '.join(cat['records'])}",
             f"generated {cat['generated']}", ""]
    kit_code = {k["id"]: k["code"] for k in cat["kits"]}
    lines.append(f"STYLES ({len(cat['styles'])}; a style's other looks are its factory paints)")
    for s in cat["styles"]:
        lines.append(f"  {s['code']:24s} {s['label']:16s} {len(s['looks'])} looks")
        if len(s["looks"]) > 1:
            lines.append(f"  {'':41s} paints: {', '.join(short(l) for l in s['looks'][1:])}")
        if s["kits"]:
            lines.append(f"  {'':41s} kits: {', '.join(kit_code[k] for k in s['kits'])}")
    if cat["wrecks"]:
        lines.append(f"WRECKS: {', '.join(short(w) for w in cat['wrecks'])}")
    style_label = {s["id"]: s["label"] for s in cat["styles"]}

    def tags(item):
        out = [f"[car: {item['vehicle']}]"] if item.get("vehicle") else []
        for origin in item["origins"]:
            kind, _, name = origin.partition(":")
            out.append(f"[{kind}: {style_label.get(name, name) if kind == 'style' else name}]")
        return " ".join(out[:5]) + (" ..." if len(out) > 5 else "")

    lines += ["", f"SLOTS ({len(cat['slots'])})"]
    for slot in cat["slots"]:
        lines.append(f"  {slot['label']} [{slot['id']}] ({', '.join(slot['mounts'])}): {len(slot['options'])} options")
        for o in slot["options"]:
            lines.append(f"    {o['code'][:46]:46s} {len(o['paints']):2d} paints  {len(o['looks']):2d} looks  {tags(o)}")
    lines += ["", f"KITS ({len(cat['kits'])})"]
    for kit in cat["kits"]:
        lines.append(f"  {kit['code'][:46]:46s} {len(kit['parts'])} parts  {len(kit['looks']):2d} looks  {tags(kit)}")
        if kit.get("needs"):
            lines.append(f"  {'':46s} needs {', '.join(kit_code[x] for x in kit['needs'])}")
        if kit.get("made_for"):
            slot_label_of = {s["id"]: s["label"] for s in cat["slots"]}
            names = [kit_code.get(x[4:], x) if x.startswith("kit:") else slot_label_of.get(x[5:], x[5:])
                     for x in kit["made_for"]]
            lines.append(f"  {'':46s} made to sit on {', '.join(names)}")
    return "\n".join(lines) + "\n"


def yaml_flats(cat):
    root = f"VehicleCustomizer.{cat['id']}"
    s = lambda v: '"' + str(v).replace("\\", "\\\\").replace('"', '\\"') + '"'  # noqa: E731
    n = lambda v: 'n"' + str(v) + '"'  # noqa: E731
    r_ = lambda v: 'r"' + str(v) + '"'  # noqa: E731

    def arr(values, f):
        return "[ " + ", ".join(f(v) for v in values) + " ]" if values else None

    out = [f"# Generated by catalog/make-catalogs.py on {cat['generated']}; don't edit by hand.",
           f"{root}.label: {s(cat['label'])}",
           f"{root}.entity: {r_(cat['entity'])}",
           f"{root}.apps: {arr(sorted({info['app'] for info in cat['looks'].values()}), r_)}",
           f"{root}.styles: {arr([x['id'] for x in cat['styles']], n)}",
           f"{root}.slots: {arr([x['id'] for x in cat['slots']], n)}",
           f"{root}.kits: {arr([x['id'] for x in cat['kits']], n)}",
           f"{root}.wrecks: {arr(cat['wrecks'], n)}"]
    for st in cat["styles"]:
        p = f"{root}.style.{st['id']}"
        out += [f"{p}.code: {s(st['code'])}", f"{p}.label: {s(st['label'])}", f"{p}.base: {n(st['base_look'])}",
                f"{p}.looks: {arr(st['looks'], n)}", f"{p}.kits: {arr(st['kits'], n)}",
                f"{p}.options: {arr([f'{k}={v}' for k, v in st['options'].items()], n)}"]
    for slot in cat["slots"]:
        p = f"{root}.slot.{slot['id']}"
        out += [f"{p}.label: {s(slot['label'])}", f"{p}.kind: {n(slot['kind'])}",
                f"{p}.corners: {arr(slot['corners'], n)}", f"{p}.options: {arr([o['id'] for o in slot['options']], n)}",
                # Where the slot's part goes on a look that lacks it: its mount point and place there, per corner.
                f"{p}.mounts: {arr(slot['mounts'], n)}",
                f"{p}.positions: {arr(slot['positions'], lambda x: '{ x: %.4f, y: %.4f, z: %.4f }' % tuple(x))}",
                f"{p}.rotations: {arr(slot['rotations'], lambda x: '{ i: %.6f, j: %.6f, k: %.6f, r: %.6f }' % tuple(x))}"]
        for o in slot["options"]:
            q = f"{root}.option.{o['id']}"
            corners = slot["corners"]
            out += [f"{q}.code: {s(o['code'])}",
                    f"{q}.meshes: {arr([o['meshes'].get(c, '') for c in corners], r_)}",
                    f"{q}.defaultPaint: {n(o['default_paint'])}",
                    f"{q}.origins: {arr(o['origins'], n)}"]
            if o["vehicle"]:
                out.append(f"{q}.vehicle: {s(o['vehicle'])}")
            if o["shadows"]:
                out.append(f"{q}.shadows: {arr([o['shadows'].get(c, '') for c in corners], r_)}")
            if o["paints"]:
                out.append(f"{q}.paints: {arr(o['paints'], n)}")
    for kit in cat["kits"]:
        p = f"{root}.kit.{kit['id']}"
        out += [f"{p}.code: {s(kit['code'])}", f"{p}.origins: {arr(kit['origins'], n)}",
                f"{p}.parts: {arr([x['name'] for x in kit['parts']], n)}",
                f"{p}.codes: {arr([x['code'] for x in kit['parts']], s)}",
                f"{p}.meshes: {arr([x['mesh'] for x in kit['parts']], r_)}",
                f"{p}.shadows: {arr([x['shadow'] or '' for x in kit['parts']], r_)}",
                f"{p}.paints: {arr([x['paint'] for x in kit['parts']], n)}",
                f"{p}.parents: {arr([x['parent'] for x in kit['parts']], n)}",
                f"{p}.needs: {arr(kit['needs'], n)}",
                f"{p}.madeFor: {arr(kit['made_for'], n)}",
                f"{p}.positions: {arr(kit['parts'], lambda x: '{ x: %.4f, y: %.4f, z: %.4f }' % tuple(x['position']))}",
                f"{p}.rotations: {arr(kit['parts'], lambda x: '{ i: %.6f, j: %.6f, k: %.6f, r: %.6f }' % tuple(x['rotation']))}"]
    # The size this car's own tires are, front and back (x radius, y width, in metres), which a tire from the shared
    # list is scaled to; z its own rims' radius, which a tire's inside is sized to when the rim is the car's own;
    # and whether it takes car or bike wheels.
    ref = cat.get("wheel_ref") or {}
    front = ref.get("f") or ref.get("b")
    back = ref.get("b") or ref.get("f")
    if front and back:
        fz = front[2] if len(front) > 2 else 0.0
        bz = back[2] if len(back) > 2 else 0.0
        out.append(f"{root}.wheelKind: {n(cat['wheel_kind'])}")
        out.append(f"{root}.wheelFit: [ {{ x: {front[0]:.4f}, y: {front[1]:.4f}, z: {fz:.4f} }}, "
                   f"{{ x: {back[0]:.4f}, y: {back[1]:.4f}, z: {bz:.4f} }} ]")
        # Where its own tires sit along the axle from their pivots: x the front's, y the back's.
        fc = front[3] if len(front) > 3 else 0.0
        bc = back[3] if len(back) > 3 else 0.0
        out.append(f"{root}.wheelCenter: {{ x: {fc:.4f}, y: {bc:.4f}, z: 0.0000 }}")
    # Which part fills each slot in each look: "<slot>|<corner>|<part name>".
    for look, info in cat["looks"].items():
        rows = [f"{slot}|{corner}|{name}" for slot, by in info["parts"].items() for corner, name in by.items()]
        out.append(f"{root}.look.{look}.parts: {arr(rows, n)}")
    return "\n".join(line for line in out if not line.endswith(": None")) + "\n"


def main():
    args = sys.argv[1:]
    dump = args.pop(0) if args and args[0].endswith(".jsonl") else newest_dump()
    wanted = set(args)
    records = load_records(dump)
    chosen = choose_entities(records)
    by_family = collections.defaultdict(list)
    for r in records:
        if r.get("template"):
            by_family[family_key(r["template"])].append(r["template"])
    # A car's name for options that come from it: the commonest name among its garage records, else any.
    names_by_folder = {}
    for fam in by_family:
        pool = [r for r in records if r.get("template") and family_key(r["template"]) == fam and r.get("display")]
        best = [r for r in pool if r.get("garage")] or pool
        if best:
            names_by_folder[fam] = collections.Counter(r["display"] for r in best).most_common(1)[0][0]
    reader = Reader()
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(os.path.join(TWEAKS, "catalog"), exist_ok=True)
    index, made = [], []
    all_meshes = set()
    used = collections.Counter()
    for ent, entry in chosen.items():
        cid = catalog_id(ent)
        used[cid] += 1
        if used[cid] > 1:  # two files with one name, as v_utility4_ and the misspelt v_utilty4_ Behemoth
            cid += f"_{used[cid]}"
        if wanted and cid not in wanted:
            continue
        family_ents = sorted(set(by_family[family_key(ent)]))
        try:
            cat = build_catalog(reader, ent, family_ents, names_by_folder, entry)
            if cat:
                cat["id"] = cid
        except Exception as ex:  # one odd file must not stop the rest
            index.append(f"{cid:60s} FAILED: {ex}")
            continue
        if not cat:
            index.append(f"{cid:60s} no looks found")
            continue
        all_meshes.update(cat.pop("mesh_paths", []))
        made.append(cat)
        with open(os.path.join(OUT, f"{cid}.json"), "w", encoding="utf-8") as f:
            json.dump(cat, f, indent=1)
        with open(os.path.join(OUT, f"{cid}.txt"), "w", encoding="utf-8") as f:
            f.write(summary(cat))
        with open(os.path.join(TWEAKS, "catalog", f"{cid}.yaml"), "w", encoding="utf-8") as f:
            f.write(yaml_flats(cat))
        options = sum(len(s["options"]) for s in cat["slots"])
        index.append(f"{cid:60s} {'garage' if cat['garage'] else 'other ':6s} {len(cat['styles']):3d} styles "
                     f"{len(cat['slots']):3d} slots {options:4d} options {len(cat['kits']):3d} kits  {cat['label']}")
    with open(os.path.join(OUT, "index.txt"), "w", encoding="utf-8") as f:
        f.write(f"Catalogs generated {datetime.date.today().isoformat()} from {dump}\n\n" + "\n".join(index) + "\n")
    # Pools: POOL copies of each catalog's main record, for buying a new car of that kind in the shop (user,
    # 2026-11-05: five each). Each is listed in the garage so the game can call it once it's unlocked.
    today = datetime.date.today().isoformat()
    pool_lines = [f"# Generated by catalog/make-catalogs.py on {today}; don't edit by hand.",
                  "# Pools of copies for buying new cars: Vehicle.vc_<catalog>_<n>, based on each catalog's main record."]
    for c in made:
        base = c["records"][0]
        c["pool"] = [f"Vehicle.vc_{c['id']}_{i}" for i in range(1, POOL + 1)]
        for name in c["pool"]:
            pool_lines += [f"{name}:", f"  $base: {base}"]
    # One tag per item, as TweakXL reads it (a list under one tag was refused: "Expected array:TweakDBID").
    pool_lines += ["Vehicle.vehicle_list.list:"]
    for c in made:
        pool_lines += [f"  - !append-once {name}" for name in c["pool"]]
    with open(os.path.join(TWEAKS, "pools.yaml"), "w", encoding="utf-8") as f:
        f.write("\n".join(pool_lines) + "\n")
    lines = [f"# Generated by catalog/make-catalogs.py on {today}; don't edit by hand.",
             "VehicleCustomizer.catalogs: [ " + ", ".join(f'n"{c["id"]}"' for c in made) + " ]"]
    for c in made:
        lines.append(f"VehicleCustomizer.{c['id']}.records: [ " +
                     ", ".join(f't"{x}"' for x in c["records"] + c["pool"]) + " ]")
        lines.append(f"VehicleCustomizer.{c['id']}.pool: [ " + ", ".join(f't"{x}"' for x in c["pool"]) + " ]")
        # The record the pool copies are made from: what a co-op partner without the mod sees instead.
        lines.append(f"VehicleCustomizer.{c['id']}.base: \"{c['records'][0]}\"")
    with open(os.path.join(TWEAKS, "catalogs.yaml"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    # The shared wheel list: every rim and tire pair any catalog's looks use, measured, for any car (or any bike) to
    # wear, scaled to its own wheels' size (user agreed, 2026-11-06).
    sets = {}
    for c in made:
        for s in c.get("wheel_sets", []):
            have = sets.setdefault(s["id"], dict(s, looks=0, axles=set()))
            have["looks"] += s["looks"]
            have["axles"].update(s["axles"])
    s_ = lambda v: '"' + str(v).replace("\\", "\\\\").replace('"', '\\"') + '"'  # noqa: E731
    wl = [f"# Generated by catalog/make-catalogs.py on {today}; don't edit by hand.",
          "# The shared wheel list: rim and tire pairs from every vehicle, measured (size: x tire radius, y tire width,",
          "# z rim radius, metres), for any car or bike to wear, scaled to its own wheels."]
    for kind in ("car", "bike"):
        ids = [i for i, s in sorted(sets.items(), key=lambda kv: (kv[1]["radius"], kv[1]["code"])) if s["kind"] == kind]
        wl.append(f"VehicleCustomizer.wheels.{kind}: [ " + ", ".join(f'n"{i}"' for i in ids) + " ]")
    # Rims and tires are chosen apart (user, 2026-11-07): a rims list and a tires list per kind, each mesh once (the
    # set used most stands for it), labelled "<the car it's seen on> (<what its name says>)", and each catalog's own
    # rims and tires to show first. A set's id names its rim in the rims list and its tire in the tires list.
    # Whose each rim and tire is. Its own car first: the one whose entity lives in the mesh's folder, by the names of
    # its records whose looks wear it (counted by look: the plain Kusanagi's rims are the Kusanagi CT-3X's, the
    # ASM-R250's the Muramasa's), else that car's name; then the other cars wearing it. Naming them only from the
    # folder misnamed some (the Outlaw's tires came out as a Deleon's: its family is v_sport1_herrera_outlaw_basic,
    # not its folder's name), and naming them only by who wears them did too (the Caliburn's tires as the
    # Aerondight's, which wears them).
    own_wearers = collections.defaultdict(collections.Counter)  # (part, mesh) -> record name -> looks
    own_names = collections.defaultdict(collections.Counter)  # (part, mesh) -> its own car's name -> looks
    wearers = collections.defaultdict(collections.Counter)  # the same for the other cars wearing it
    other_names = collections.defaultdict(collections.Counter)
    axles_of = collections.defaultdict(set)  # (part, mesh) -> the axles it's on
    for c in made:
        by_look = collections.defaultdict(set)
        for look, display in c.get("record_looks", []):
            if look and display:
                by_look[look].add(display)
        family_name = names_by_folder.get(c["family"]) or c["label"]
        for s in c.get("wheel_sets", []):
            for part in ("rim", "tire"):
                key = (part, s[part])
                axles_of[key].update(s["axles"])
                folder = folder_of(s[part])
                home = bool(folder) and os.path.basename(c["entity"]).startswith(folder)
                for look in s.get("look_names", []):
                    for display in by_look.get(look, ()):
                        (own_wearers if home else wearers)[key][display] += 1
                (own_names if home else other_names)[key][family_name] += s["looks"]

    # A folder's car when no catalog of its own wears the mesh (the Outlaw's tire_fl_01, worn only by Deleons):
    # the commonest name of the records whose entity file is named after the folder.
    folder_names = {}

    def folder_name(folder):
        if folder not in folder_names:
            counts = collections.Counter(x["display"] for x in records if x.get("template") and x.get("display")
                                         and os.path.basename(x["template"]).lower().startswith(folder + "_"))
            folder_names[folder] = counts.most_common(1)[0][0] if counts else ""
        return folder_names[folder]

    def from_of(part, mesh, fallback):
        for counts in (own_wearers, own_names):
            if counts[(part, mesh)]:
                return counts[(part, mesh)].most_common(1)[0][0]
        folder = folder_of(mesh)
        if folder and folder_name(folder):
            return folder_name(folder)
        for counts in (wearers, other_names):
            if counts[(part, mesh)]:
                return counts[(part, mesh)].most_common(1)[0][0]
        return fallback

    def tail(code):
        # A mesh named without __ext01_ (v_standard25_thorton_colby_kurtz_tire_kurtz_fr_01) carries its car's
        # name in front: from the word for the part on.
        tokens = str(code).lower().split("_")
        if tokens and tokens[0] in ("v", "av"):
            at = next((n for n, t in enumerate(tokens) if t in ("wheel", "tire", "rim")), 0)
            tokens = tokens[at:]
        return tokens

    def variant(code, name):
        # The words of the mesh's name that tell it apart: not "wheel" or a corner, nor a word of the car's name
        # (Aerondight "Guinevere" (aerondight), ASM-R250 Muramasa (asm r250 01)).
        words = {"wheel", "wheels", "rim", "rims", "tire", "tires", "tyre", "fl", "fr", "bl", "br", "f", "b", "l", "r"}
        flat = re.sub(r"[^a-z0-9]", "", name.lower())
        kept = []
        for t in tail(code):
            # Each word once (Emperor 620 Ragnar (police police 01)).
            if t and t not in words and not (len(t) >= 3 and t in flat) and t not in kept:
                kept.append(t)
        return " ".join(kept)

    def corner_word(code, kind):
        # The axle the mesh's own name says it's for (a bike's back wheel is wheel_r, its rear).
        for t in tail(code):
            if t in ("fl", "fr", "f"):
                return "front"
            if t in ("bl", "br", "b") or (kind == "bike" and t == "r"):
                return "back"
        return ""

    reps = {"rim": {}, "tire": {}}
    for i, s in sorted(sets.items()):
        for part in ("rim", "tire"):
            have = reps[part].get((s["kind"], s[part]))
            if have is None or sets[have]["looks"] < s["looks"]:
                reps[part][(s["kind"], s[part])] = i
    # Each mesh's label. A car's front and back versions of one design read alike once the corner is dropped from
    # the name (Archer Hella (01) twice: the back tire is wider), so where two labels meet, each says its axle: the
    # one it's on, if only one, else the one its name says; any still alike get a number, in the order the game
    # uses them most. Parentheses, not a middle dot: the HUD's font may not have one.
    mesh_label = {}
    for kind in ("car", "bike"):
        for part, code in (("rim", "code"), ("tire", "tire_code")):
            parts = {}
            for (k, mesh), i in reps[part].items():
                if k == kind:
                    name = from_of(part, mesh, sets[i]["from"])
                    parts[mesh] = (name, variant(sets[i][code], name), i)
            alike = collections.Counter((name, v) for name, v, _i in parts.values())
            labels = {}
            for mesh, (name, v, i) in parts.items():
                words = [v] if v else []
                axles = axles_of[(part, mesh)]
                if alike[(name, v)] > 1:
                    axle = ("front" if "f" in axles else "back") if len(axles) == 1 else corner_word(sets[i][code], kind)
                    if axle:
                        words.append(axle)
                labels[mesh] = (name, words, sets[i]["looks"])
            again = collections.defaultdict(list)
            for mesh, (name, words, looks) in labels.items():
                again[(name, tuple(words))].append((-looks, mesh))
            for (name, words), meshes in again.items():
                for n, (_looks, mesh) in enumerate(sorted(meshes)):
                    shown = list(words) + ([str(n + 1)] if len(meshes) > 1 else [])
                    mesh_label[(kind, part, mesh)] = f"{name} ({', '.join(shown)})" if shown else name
    for kind in ("car", "bike"):
        for part, plural in (("rim", "rims"), ("tire", "tires")):
            ids = sorted((i for (k, _m), i in reps[part].items() if k == kind),
                         key=lambda i: mesh_label[(kind, part, sets[i][part])].lower())
            wl.append(f"VehicleCustomizer.{plural}.{kind}: [ " + ", ".join(f'n"{i}"' for i in ids) + " ]")
    for c in made:
        own_rims = sorted({reps["rim"][(s["kind"], s["rim"])] for s in c.get("wheel_sets", []) if (s["kind"], s["rim"]) in reps["rim"]})
        own_tires = sorted({reps["tire"][(s["kind"], s["tire"])] for s in c.get("wheel_sets", []) if (s["kind"], s["tire"]) in reps["tire"]})
        if own_rims:
            wl.append(f"VehicleCustomizer.{c['id']}.ownRims: [ " + ", ".join(f'n"{i}"' for i in own_rims) + " ]")
        if own_tires:
            wl.append(f"VehicleCustomizer.{c['id']}.ownTires: [ " + ", ".join(f'n"{i}"' for i in own_tires) + " ]")
    for i, s in sorted(sets.items()):
        p = f"VehicleCustomizer.wheel.{i}"
        wl += [f"{p}.rimLabel: {s_(mesh_label[(s['kind'], 'rim', s['rim'])])}",
               f"{p}.tireLabel: {s_(mesh_label[(s['kind'], 'tire', s['tire'])])}"]
        wl += [f"{p}.code: {s_(s['code'])}", f"{p}.tireCode: {s_(s['tire_code'])}",
               f"{p}.from: {s_(from_of('rim', s['rim'], s['from']))}",
               f'{p}.rim: r"{s["rim"]}"', f'{p}.tire: r"{s["tire"]}"',
               f'{p}.rimShadow: r"{s["rim_shadow"]}"', f'{p}.tireShadow: r"{s["tire_shadow"]}"',
               f"{p}.size: {{ x: {s['radius']:.4f}, y: {s['width']:.4f}, z: {s['rim_radius']:.4f} }}",
               f"{p}.tireCenter: {s['tire_center']:.4f}",
               f'{p}.defaultPaint: n"{s["default_paint"]}"',
               f"{p}.paints: [ " + ", ".join(f'n"{x}"' for x in s["paints"]) + " ]"]
    with open(os.path.join(TWEAKS, "wheels.yaml"), "w", encoding="utf-8") as f:
        f.write("\n".join(line for line in wl if not line.endswith(".paints: [  ]")) + "\n")
    # The part boxes: every mesh any catalog's car can wear, its own bounding box (min, max) in its local space, keyed
    # by its path's hash as the game gives it (ResourceAsyncRef.GetHash), read as a signed 64-bit number: p<n> or
    # n<-n>. The tool finds the part under the crosshair with these (UX.md, 2026-11-07).
    bl = [f"# Generated by catalog/make-catalogs.py on {today}; don't edit by hand.",
          "# Part boxes: each mesh's own box (min, max, metres, its local space), by its path's hash (signed: p<n>, n<-n>)."]
    boxed = 0
    for mesh in sorted(all_meshes):
        bounds = reader.mesh_bounds(mesh)
        if not bounds:
            continue
        h = rdar.fnv1a64(mesh)
        signed = h - (1 << 64) if h >= (1 << 63) else h
        key = f"n{-signed}" if signed < 0 else f"p{signed}"
        (a, b, c), (d, e, g) = bounds
        bl.append(f"VehicleCustomizer.box.{key}: [ {{ x: {a:.4f}, y: {b:.4f}, z: {c:.4f} }}, "
                  f"{{ x: {d:.4f}, y: {e:.4f}, z: {g:.4f} }} ]")
        boxed += 1
    with open(os.path.join(TWEAKS, "boxes.yaml"), "w", encoding="utf-8") as f:
        f.write("\n".join(bl) + "\n")
    print(f"{boxed} part boxes of {len(all_meshes)} meshes")
    print(f"{len(made)} catalogs from {len(chosen)} entity files; index in {os.path.join(OUT, 'index.txt')}; "
          f"{sum(1 for s in sets.values() if s['kind'] == 'car')} car and "
          f"{sum(1 for s in sets.values() if s['kind'] == 'bike')} bike wheel sets")


if __name__ == "__main__":
    main()
