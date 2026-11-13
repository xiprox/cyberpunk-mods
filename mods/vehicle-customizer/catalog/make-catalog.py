"""Generates the customizer's catalog for one car model from the game's own files (RECORD.md, 2026-11-06).

For the model it writes:
- styles: the looks the copy's entity file offers, grouped by the parts they carry; each style has a base look
  and its other looks as factory paint variants; wrecked looks are flagged;
- slots: a mount point and kind of part (front bumper, rims...), with every option the model uses there in any
  of its looks, each with its meshes, shadows, default paint, the paints its mesh offers and the styles it
  comes from;
- kits: decorative parts that hang off other parts (stickers, stripes, decals, light bars), grouped by the
  family their names share, as add-ons.

Outputs, next to this script: <model>.json (the catalog), <model>.txt (a summary to read) and <model>.yaml
(the same as TweakDB flats for TweakXL, under VehicleCustomizer.<model>).

Usage: python -I make-catalog.py [model]     (only archer_hella so far)
"""
import collections
import datetime
import json
import os
import re
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PROBES = os.path.join(HERE, "..", "experiments", "areas", "game-files")
sys.path.insert(0, os.path.join(HERE, "..", "..", "..", "tools"))
import pkg  # noqa: E402
import rdar  # noqa: E402

FIXED = 131072.0

MODELS = {
    "archer_hella": {
        "label": "Archer Hella",
        "ent": r"base\vehicles\standard\v_standard2_archer_hella__basic_01.ent",
        "prefix": "v_standard2_archer_hella",
        "apps": re.compile(r"\\archer_hella[^\\]*\.app$"),
    },
}

# Mount points (slot names under vehicle_slots) and the slot they belong to. Corner slots are one choice for
# the set, with a mesh per corner.
SLOTS = [
    # id, label, kind pattern (on the mesh name), mounts, corner names
    ("front_bumper", "Front bumper", r"bumper_f", ["bumper_front"], None),
    ("rear_bumper", "Rear bumper", r"bumper_b", ["bumper_back"], None),
    ("hood", "Hood", r"hood", ["hood_a"], None),
    ("trunk", "Trunk", r"trunk", ["trunk_a"], None),
    ("body", "Body", r"body", ["Base"], None),
    ("rims", "Rims", r"wheel", ["wheel_front_left", "wheel_front_right", "wheel_back_left", "wheel_back_right"],
     ["fl", "fr", "bl", "br"]),
    ("tires", "Tires", r"tire", ["wheel_front_left", "wheel_front_right", "wheel_back_left", "wheel_back_right"],
     ["fl", "fr", "bl", "br"]),
    ("doors", "Doors", r"door", ["door_front_left_a", "door_front_right_a", "door_back_left_a", "door_back_right_a"],
     ["fl", "fr", "bl", "br"]),
    ("windows", "Side windows", r"window", ["window_front_left_a", "window_front_right_a", "window_back_left_a",
                                             "window_back_right_a"], ["fl", "fr", "bl", "br"]),
]

WRECK = re.compile(r"burnt|destroy|damaged|after_accident|wreck|flipped")
DAMAGE = re.compile(r"bullethole|damage|burnt|dirt_decal")
# What makes a part decoration rather than clutter (bottles, fuse boxes, the interior light).
DECOR = re.compile(r"sticker|stripe|decal|antenna|light_device|vehicle_lights|sensor|radar|livery|player|police|kurtz|nomad")
# Families decorative parts are named by, by a word in their name or mesh; the first match wins.
FAMILIES = [("6th_street", "6th Street stickers"), ("combatcab", "Combat cab stickers"), ("kurtz", "Kurtz stickers"),
            ("scavengers", "Scavenger stickers"), ("police", "Police kit"), ("nomad", "Nomad gear"),
            ("player", "V's stripes and extras"), ("deathrace", "Deathrace livery"), ("sticker", "Stickers"),
            ("antenna", "Antennas")]
STYLE_NAMES = {"player": "V's own", "6th street": "6th Street", "combatcab": "Combat cab"}
AREAS = [("hood", "hood"), ("door", "doors"), ("trunk", "trunk"), ("bumper", "bumper"), ("interior", "interior"),
         ("glove_box", "interior"), ("body", "body"), ("Base", "body")]


def mount_area(part):
    """Where a decorative part sits, from what it hangs off: hood, doors, trunk, interior, body."""
    parent = part["bind"] if part["bind"] != "vehicle_slots" else part["slot"]
    for key, area in AREAS:
        if key in str(parent):
            return area
    return "body"


def fixed(v):
    return round(v["Bits"] / FIXED, 4) if isinstance(v, dict) and "Bits" in v else 0.0


def transform(t):
    if not isinstance(t, dict):
        return [0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 1.0]
    pos = t.get("Position", {}) or {}
    ori = t.get("Orientation", {}) or {}
    p = [fixed(pos.get(a)) for a in ("x", "y", "z")]
    q = [float(ori.get(a, 0.0 if a != "r" else 1.0) or 0.0) for a in ("i", "j", "k", "r")]
    return p, q


def short_id(text):
    return f"{rdar.fnv1a64(text) & 0xFFFFFFFF:08x}"


class Reader:
    def __init__(self):
        present = json.load(open(os.path.join(PROBES, "data", "parts.json"), encoding="utf-8"))["present"]
        self.present = present
        self.depot = pkg.Depot()
        self.depot.add_names(present)
        self.paint_cache = {}

    def ent_looks(self, ent):
        head, bufs = self.depot.load(ent)
        root = pkg.Cooked(head, bufs, self.depot).exports[0][1]
        looks = []
        for a in root.get("appearances", []):
            res = a.get("appearanceResource")
            looks.append((str(a.get("name")), res[1] if isinstance(res, tuple) else str(res), str(a.get("appearanceName"))))
        return looks, str(root.get("defaultAppearance"))

    def app_looks(self, app):
        """Every look of an .app: its parts with class, mesh, paint, binding and offset."""
        loaded = self.depot.load(app)
        if not loaded:
            return {}
        head, bufs = loaded
        c = pkg.Cooked(head, bufs, self.depot)
        out = {}
        for cls, d in c.exports:
            if cls != "appearanceAppearanceDefinition":
                continue
            cd = d.get("compiledData")
            b = c.buffer(cd[1]) if cd else None
            if not b:
                continue
            p = pkg.Package(b, self.depot)
            objs = p.objects(only={"name", "mesh", "meshAppearance", "parentTransform", "slotName", "bindName"})
            parts = {}
            for i, (ocls, obj) in enumerate(objs):
                mesh = obj.get("mesh")
                if not (isinstance(mesh, tuple) and mesh[0] == "ref"):
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

    def paints(self, mesh):
        """The paint (appearance) names a mesh offers, in order."""
        if mesh in self.paint_cache:
            return self.paint_cache[mesh]
        names = []
        loaded = self.depot.load(mesh)
        if loaded:
            head, _ = loaded
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
        self.paint_cache[mesh] = names
        return names


def base_name(mesh):
    return os.path.basename(mesh)[:-5] if mesh.endswith(".mesh") else os.path.basename(mesh)


MAKERS = {"v_sport1_quadra_turbo": "Quadra Turbo-R", "v_sport2_porsche_911turbo": "Porsche 911",
          "v_standard2_villefort_cortes": "Villefort Cortes"}
NOISE = {"ext01", "int01", "ext", "int", "fl", "fr", "bl", "br", "f", "b", "front", "back", "a", "l", "r"}


def model_of(mesh):
    """The vehicle folder a mesh lives in, such as v_standard2_archer_hella."""
    m = re.search(r"\\(v_[a-z0-9]+_[a-z0-9_]+?)\\entities\\", mesh)
    return m.group(1) if m else ""


def car_name(folder):
    if folder in MAKERS:
        return MAKERS[folder]
    return " ".join(w.capitalize() for w in folder.split("_")[2:])


CORNERS = {"fl", "fr", "bl", "br"}


def mesh_code(mesh, corners=True):
    """A part number from the game's own mesh name: the car's name and ext01 dropped, the variant (police, junk)
    kept, written as the game writes it (user): v_standard2_archer_hella__ext01_junk_bumper_f_01.mesh becomes
    junk_bumper_f_01. Corner letters stay on a single part (door_bl_sticker_6th_street); a slot's set of four
    drops them, since one number stands for the set (v_standard2_villefort_cortes__ext01_wheel_fl_police_02.mesh:
    wheel_police_02)."""
    name = base_name(mesh)
    folder = model_of(mesh)
    rest = name[len(folder):] if folder and name.startswith(folder) else name
    variant, _, part = rest.partition("__")
    if not part:
        variant, part = "", variant
    if variant.startswith("v_"):  # a shared part named after its own folder, such as v_common_nomad_part
        variant = ""
    words = [w for w in variant.strip("_").split("_") + part.split("_")
             if w and (corners or w not in CORNERS) and not re.fullmatch(r"(ext|int)\d+", w)]
    return "_".join(words).lower()


def part_code(meshes):
    """One part number for an option: the same for every corner of a set, or each distinct one joined."""
    return " + ".join(dict.fromkeys(mesh_code(m, corners=len(meshes) == 1) for m in meshes))


def home_vehicle(meshes, prefix):
    """The car an option's mesh belongs to, when it isn't the model's own; None for the model's own parts."""
    folder = model_of(meshes[0])
    return car_name(folder) if folder and folder != prefix and not folder.startswith("v_common") else None


def family_of(text):
    for key, label in FAMILIES:
        if key in text:
            return key, label
    return "other", "Other parts"


def build(model_id):
    model = MODELS[model_id]
    r = Reader()
    ent_looks, default = r.ent_looks(model["ent"])
    apps = sorted(p for p in r.present if model["apps"].search(p))
    looks = {}  # (app, app look) -> look data
    for app in apps:
        for name, data in r.app_looks(app).items():
            looks[(app, name)] = data
    reachable = {}  # entity look -> (app, app look)
    for ent_name, app, app_look in ent_looks:
        if (app, app_look) in looks:
            reachable[ent_name] = (app, app_look)

    def look_key(app, app_look):
        """A name for any look: the entity's name when the copy can wear it, else its file and name."""
        for ent_name, key in reachable.items():
            if key == (app, app_look):
                return ent_name
        return f"{os.path.basename(app)[:-4]}:{app_look}"

    # --- slots and their options, from every look of the model ---
    slots = []
    choice = {}  # (look key, slot id) -> option id
    slot_parts = collections.defaultdict(dict)  # look key -> slot id -> component name or {corner: name}
    for slot_id, label, kind, mounts, corners in SLOTS:
        options = {}
        for (app, app_look), data in looks.items():
            key = look_key(app, app_look)
            parts = data["parts"]
            found = {}
            for name, part in parts.items():
                if part["bind"] != "vehicle_slots" or part["slot"] not in mounts:
                    continue
                if "shadow" in name or "shadow" in part["mesh"] or not re.search(kind, base_name(part["mesh"])):
                    continue
                if slot_id == "body" and not re.search(r"__ext\d+_body(_[a-z]+)*_\d+$", base_name(part["mesh"])):
                    continue
                if slot_id == "body" and "sticker" in part["mesh"]:
                    continue
                corner = corners[mounts.index(part["slot"])] if corners else "all"
                found.setdefault(corner, (name, part))
            if not found or (corners and len(found) < len(corners)):
                continue
            meshes = {c: p["mesh"] for c, (n, p) in found.items()}
            ident = short_id(slot_id + "|" + "|".join(f"{c}={m}" for c, m in sorted(meshes.items())))
            option = options.setdefault(ident, {
                "id": ident, "meshes": meshes, "classes": sorted({p["cls"] for _, p in found.values()}),
                "shadows": {}, "paint_use": collections.Counter(), "looks": set(),
            })
            option["looks"].add(key)
            for c, (n, p) in found.items():
                option["paint_use"][p["paint"]] += 1
                for sname, spart in parts.items():
                    if spart["bind"] == n and ("shadow" in sname or "shadow" in spart["mesh"]):
                        option["shadows"][c] = spart["mesh"]
            choice[(key, slot_id)] = ident
            slot_parts[key][slot_id] = {c: n for c, (n, _) in found.items()} if corners else next(iter(found.values()))[0]
        out = []
        for option in options.values():
            meshes = list(option["meshes"].values())
            out.append({
                "id": option["id"],
                "code": part_code(meshes),
                "vehicle": home_vehicle(meshes, model["prefix"]),
                "meshes": option["meshes"], "classes": option["classes"], "shadows": option["shadows"],
                "default_paint": option["paint_use"].most_common(1)[0][0],
                "paints": r.paints(meshes[0]),
                "looks": sorted(option["looks"]),
            })
        out.sort(key=lambda o: (-len(o["looks"]), o["code"]))
        slots.append({"id": slot_id, "label": label, "kind": kind, "mounts": mounts, "corners": corners or ["all"],
                      "options": out})

    # --- kits: decorative parts (stickers, stripes, decals, light bars), grouped by the looks they appear in ---
    # Parts that always appear together in the same looks make one kit, named by the family their names share.
    slot_component_names = {n for parts in slot_parts.values() for v in parts.values()
                            for n in (v.values() if isinstance(v, dict) else [v])}
    decor = {}  # (name, mesh) -> part data
    decor_looks = collections.defaultdict(set)
    for (app, app_look), data in looks.items():
        key = look_key(app, app_look)
        parts = data["parts"]
        for name, part in parts.items():
            text = (name + " " + part["mesh"]).lower()
            if "shadow" in text or DAMAGE.search(text) or name in slot_component_names:
                continue
            if not DECOR.search(text):
                continue
            on_part = part["bind"] in parts and part["bind"] != name
            on_body = part["bind"] == "vehicle_slots" and part["slot"] in ("Base", "body")
            if not (on_part or on_body):
                continue
            ident = (name, part["mesh"])
            decor_looks[ident].add(key)
            if ident not in decor:
                pos, rot = r.offset(data, name)
                shadow = next((sp["mesh"] for sn, sp in parts.items() if sp["bind"] == name and "shadow" in sn), None)
                decor[ident] = {"name": name, "mesh": part["mesh"], "paint": part["paint"], "cls": part["cls"],
                                "bind": part["bind"], "slot": part["slot"], "position": pos, "rotation": rot,
                                "shadow": shadow}
    together = collections.defaultdict(list)
    for ident, seen in decor_looks.items():
        together[frozenset(seen)].append(decor[ident])
    kit_list = []
    for seen, parts in together.items():
        parts.sort(key=lambda p: p["name"])
        fam, fam_label = family_of(" ".join((p["name"] + " " + p["mesh"]).lower() for p in parts))
        if fam == "other":  # standard equipment such as the car's own lights, not decoration
            continue
        where = sorted({mount_area(p) for p in parts})
        # A kit's part number: a single part's own, or kit_, its family and where its parts sit.
        code = mesh_code(parts[0]["mesh"]) if len(parts) == 1 else \
            "_".join(["kit", fam] + where)
        kit_list.append({"id": f"{fam}_{short_id('|'.join(p['name'] for p in parts))[:4]}", "family": fam,
                         "code": code, "where": where, "parts": parts, "looks": sorted(seen)})
    seen_codes = collections.Counter()
    for kit in sorted(kit_list, key=lambda k: (-len(k["looks"]), k["id"])):
        seen_codes[kit["code"]] += 1
        if seen_codes[kit["code"]] > 1:
            kit["code"] += f"_{seen_codes[kit['code']]}"
    for kit in kit_list:
        for p in kit["parts"]:
            p["code"] = mesh_code(p["mesh"])
    kit_list.sort(key=lambda k: (k["family"], k["code"]))

    # --- styles: the copy's looks grouped by the options and kits they carry; wrecks kept apart ---
    short = lambda n: re.sub(r"^" + re.escape(model_id) + r"__basic_", "", n)  # noqa: E731
    stem = lambda n: re.sub(r"(_\d+)+$|_new$", "", short(n))  # noqa: E731
    wrecks = sorted(n for n in reachable if WRECK.search(n))
    groups = collections.defaultdict(list)
    for ent_name in reachable:
        if ent_name in wrecks:
            continue
        sig = tuple(choice.get((ent_name, s[0])) for s in SLOTS)
        kit_sig = tuple(sorted(k["id"] for k in kit_list if ent_name in k["looks"]))
        groups[(sig, kit_sig)].append(ent_name)
    styles = []
    for (sig, kit_sig), members in groups.items():
        common = collections.Counter(stem(m) for m in members).most_common(1)[0][0]
        members.sort(key=lambda n: (stem(n) != common, len(short(n)), short(n)))
        base = members[0]
        label = re.sub(r"_0?1$", "", short(base)).replace("_", " ")
        label = STYLE_NAMES.get(label, label[:1].upper() + label[1:])
        styles.append({"id": short(base), "code": short(base), "label": label,
                       "base_look": base, "looks": members,
                       "options": {s[0]: o for s, o in zip(SLOTS, sig) if o}, "kits": list(kit_sig)})
    styles.sort(key=lambda s: (s["label"], s["id"]))
    style_of = {look: s["id"] for s in styles for look in s["looks"]}

    # Where options and kits come from, as origin tags the screen shows with a colour and an icon per kind
    # (user, 2026-11-06): "style:<id>" for a style of the copy, "look:<name>" for a look of the model the copy
    # can't wear (police, deathrace...), "wreck:<name>" for a wrecked look; an option from another car also
    # names that car in "vehicle".
    def origin(look):
        if look in style_of:
            return "style:" + style_of[look]
        if look in wrecks:
            return "wreck:" + short(look)
        return "look:" + look.split(":")[-1]

    for slot in slots:
        for o in slot["options"]:
            o["origins"] = sorted({origin(l) for l in o["looks"]})
    for kit in kit_list:
        kit["origins"] = sorted({origin(l) for l in kit["looks"]})

    look_table = {}
    for ent_name, (app, app_look) in reachable.items():
        look_table[ent_name] = {"app": app, "app_look": app_look, "style": style_of.get(ent_name),
                                "wreck": ent_name in wrecks, "parts": slot_parts.get(ent_name, {})}

    return {
        "model": model_id, "label": model["label"], "entity": model["ent"], "default_look": default,
        "generated": datetime.date.today().isoformat(), "source_apps": apps,
        "styles": styles, "wrecks": wrecks, "slots": slots, "kits": kit_list, "looks": look_table,
    }


def summary(cat):
    lines = [f"{cat['label']} ({cat['model']}), from {cat['entity']}", f"generated {cat['generated']}", ""]
    short = lambda n: n.replace(cat["model"] + "__basic_", "")  # noqa: E731
    lines.append(f"STYLES ({len(cat['styles'])}; a style's other looks are its factory paints)")
    kit_code = {k["id"]: k["code"] for k in cat["kits"]}
    for s in cat["styles"]:
        lines.append(f"  {s['code']:16s} {s['label']:12s} base {short(s['base_look'])}")
        if len(s["looks"]) > 1:
            lines.append(f"  {'':29s} paints: {', '.join(short(l) for l in s['looks'][1:])}")
        if s["kits"]:
            lines.append(f"  {'':29s} kits: {', '.join(kit_code[k] for k in s['kits'])}")
    lines.append(f"WRECKS (not sold; parts from them still count): {', '.join(short(w) for w in cat['wrecks'])}")
    style_label = {s["id"]: s["label"] for s in cat["styles"]}

    def tags(item):
        """Origin tags as the screen would show them: [car: ...] [style: ...] [look: ...] [wreck: ...]."""
        out = [f"[car: {item['vehicle']}]"] if item.get("vehicle") else []
        for origin in item["origins"]:
            kind, _, name = origin.partition(":")
            out.append(f"[{kind}: {style_label.get(name, name) if kind == 'style' else name}]")
        return " ".join(out[:6]) + (" ..." if len(out) > 6 else "")

    lines.append("")
    lines.append("SLOTS")
    for slot in cat["slots"]:
        lines.append(f"  {slot['label']} ({', '.join(slot['mounts'])}): {len(slot['options'])} options")
        for o in slot["options"]:
            lines.append(f"    {o['code']:44s} {len(o['paints']):2d} paints, default {o['default_paint']:14s} "
                         f"{len(o['looks']):2d} looks  {tags(o)}")
    lines.append("")
    lines.append("KITS (add-ons: decorative parts that always appear together)")
    for kit in cat["kits"]:
        lines.append(f"  {kit['code']:44s} {len(kit['parts'])} parts, {len(kit['looks']):2d} looks  {tags(kit)}")
        if len(kit["parts"]) > 1:
            for p in kit["parts"]:
                lines.append(f"    {p['code']:42s} on {p['bind'] if p['bind'] != 'vehicle_slots' else p['slot']}")
    return "\n".join(lines) + "\n"


def yaml_flats(cat):
    """The catalog as TweakDB flats for TweakXL, under VehicleCustomizer.<model>."""
    root = f"VehicleCustomizer.{cat['model']}"

    def s(v):
        return '"' + str(v).replace("\\", "\\\\").replace('"', '\\"') + '"'

    def n(v):
        return 'n"' + str(v) + '"'

    def r_(v):
        return 'r"' + str(v) + '"'

    def arr(values, f):
        return "[ " + ", ".join(f(v) for v in values) + " ]" if values else None

    out = [f"# Generated by catalog/make-catalog.py on {cat['generated']}; don't edit by hand.",
           f"{root}.label: {s(cat['label'])}",
           f"{root}.styles: {arr([x['id'] for x in cat['styles']], n)}",
           f"{root}.slots: {arr([x['id'] for x in cat['slots']], n)}",
           f"{root}.kits: {arr([x['id'] for x in cat['kits']], n)}",
           f"{root}.wrecks: {arr(cat['wrecks'], n)}"]
    for st in cat["styles"]:
        p = f"{root}.style.{st['id']}"
        out += [f"{p}.code: {s(st['code'])}", f"{p}.label: {s(st['label'])}", f"{p}.base: {n(st['base_look'])}",
                f"{p}.looks: {arr(st['looks'], n)}"]
        for slot_id, opt in st["options"].items():
            out.append(f"{p}.option.{slot_id}: {n(opt)}")
        if st["kits"]:
            out.append(f"{p}.kits: {arr(st['kits'], n)}")
    for slot in cat["slots"]:
        p = f"{root}.slot.{slot['id']}"
        out += [f"{p}.label: {s(slot['label'])}", f"{p}.mounts: {arr(slot['mounts'], n)}",
                f"{p}.corners: {arr(slot['corners'], n)}", f"{p}.options: {arr([o['id'] for o in slot['options']], n)}"]
        for o in slot["options"]:
            q = f"{p}.option.{o['id']}"
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
                f"{p}.meshes: {arr([x['mesh'] for x in kit['parts']], r_)}",
                f"{p}.paints: {arr([x['paint'] for x in kit['parts']], n)}",
                f"{p}.parents: {arr([x['bind'] if x['bind'] != 'vehicle_slots' else 'vehicle_slots:' + str(x['slot']) for x in kit['parts']], n)}",
                f"{p}.positions: {arr(kit['parts'], lambda x: '{ x: %.4f, y: %.4f, z: %.4f }' % tuple(x['position']))}",
                f"{p}.rotations: {arr(kit['parts'], lambda x: '{ i: %.6f, j: %.6f, k: %.6f, r: %.6f }' % tuple(x['rotation']))}"]
    return "\n".join(line for line in out if not line.endswith(": None")) + "\n"


def main():
    model_id = sys.argv[1] if len(sys.argv) > 1 else "archer_hella"
    cat = build(model_id)
    with open(os.path.join(HERE, f"{model_id}.json"), "w", encoding="utf-8") as f:
        json.dump(cat, f, indent=1)
    with open(os.path.join(HERE, f"{model_id}.txt"), "w", encoding="utf-8") as f:
        f.write(summary(cat))
    with open(os.path.join(HERE, f"{model_id}.yaml"), "w", encoding="utf-8") as f:
        f.write(yaml_flats(cat))
    print(f"{cat['label']}: {len(cat['styles'])} styles, {len(cat['slots'])} slots "
          f"({sum(len(s['options']) for s in cat['slots'])} options), {len(cat['kits'])} kits, {len(cat['looks'])} looks")


if __name__ == "__main__":
    main()
