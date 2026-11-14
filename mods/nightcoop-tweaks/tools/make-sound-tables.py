"""Writes the sound tables the horn, siren and silenced-shot tweaks look events
up in, from the game's own audio metadata, so no event name is typed by hand.

  - tweaks/silencedshots/sounds.lua: a weapon's audio set (Item_Record.AudioName,
    e.g. "wea_set_unity") -> the shots an NPC firing it silenced makes: its
    `npcSilenced` settings, or `npcSettings` where the set has none, through
    their gun choir to each voice's single shot, burst, and automatic loop
  - tweaks/horn/horns.lua: a vehicle's audio resource (Vehicle_Record's
    player_audio_resource, e.g. "v_car_thorton_galena") -> its horn's on and
    off events, and the police horn's where it has one
  - tweaks/siren/sirens.lua: a police car's audio resource -> its siren's on
    and off events (generalData's sirenOnEvent and sirenOffEvent)

It unbundles the base game's and Phantom Liberty's cooked_metadata.audio_metadata
from their audio_1_general.archive with WolvenKit's command line and serializes
them to JSON in a work folder; Phantom Liberty's has its own weapons and
vehicles. Run it again after a game patch.

usage: python -I tools/make-sound-tables.py [--game <game folder>] [--wolvenkit <WolvenKit.CLI.exe>] [--work <folder>]
"""
import argparse
import json
import os
import subprocess
import sys
import tempfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MOD = os.path.join(REPO, "cet", "NightCoopTweaks")
GAME = r"C:\Program Files (x86)\Steam\steamapps\common\Cyberpunk 2077"
WOLVENKIT = r"H:\WolvenKit\Console\WolvenKit.CLI.exe"
# (archive under archive\pc, metadata file inside it); Phantom Liberty's comes second and wins a clash.
SOURCES = [
    (r"content\audio_1_general.archive", r"base\sound\metadata\cooked_metadata.audio_metadata"),
    (r"ep1\audio_1_general.archive", r"ep1\sound\metadata\cooked_metadata.audio_metadata"),
]


def name(value):
    """A CName as WolvenKit writes it ({"$value": ...}); None for the game's "None"."""
    if isinstance(value, dict):
        value = value.get("$value")
    return None if value in (None, "", "None") else value


def objects(node, out):
    if isinstance(node, dict):
        if "$type" in node:
            out.append(node)
        for value in node.values():
            objects(value, out)
    elif isinstance(node, list):
        for value in node:
            objects(value, out)
    return out


def extract(game, wolvenkit, work):
    """The serialized JSON of each source's metadata, base game first."""
    paths = []
    for i, (archive, metadata) in enumerate(SOURCES):
        raw = os.path.join(work, f"raw{i}")
        serialized = os.path.join(work, f"json{i}")
        os.makedirs(serialized, exist_ok=True)
        subprocess.run([wolvenkit, "unbundle", "-p", os.path.join(game, "archive", "pc", archive), "-o", raw,
                        "-r", "cooked_metadata"], check=True, stdout=subprocess.DEVNULL)
        subprocess.run([wolvenkit, "convert", "serialize", os.path.join(raw, metadata), "-o", serialized],
                       check=True, stdout=subprocess.DEVNULL)
        paths.append(os.path.join(serialized, "cooked_metadata.audio_metadata.json"))
    return paths


def weapon_table(by_name, groups):
    table = {}
    for group in groups:
        settings_name = name(group.get("npcSilenced"))
        fallback = settings_name is None
        if fallback:
            settings_name = name(group.get("npcSettings"))
        settings = by_name.get(settings_name)
        choir = by_name.get(name(settings.get("gunChoir"))) if settings else None
        voices = []
        for voice_name in (choir or {}).get("voices", []):
            voice = by_name.get(name(voice_name))
            if not voice:
                continue
            entry = {key: name(voice.get(field)) for key, field in
                     (("single", "fireSound"), ("burst", "burstFireSound"),
                      ("loop", "autoFireSound"), ("loopStop", "autoFireStop"))}
            if entry["loop"] is None:
                entry["loopStop"] = None
            entry = {k: v for k, v in entry.items() if v}
            if entry:
                voices.append(entry)
        if voices:
            table[name(group["name"])] = {"settings": settings_name, "fallback": fallback, "voices": voices}
    return table


def horn_table(vehicles):
    table = {}
    for vehicle in vehicles:
        general = vehicle.get("generalData") or {}
        entry = {key: name(general.get(field)) for key, field in
                 (("on", "hornOnEvent"), ("off", "hornOffEvent"),
                  ("policeOn", "policeHornOnEvent"), ("policeOff", "policeHornOffEvent"))}
        entry = {k: v for k, v in entry.items() if v}
        if entry.get("on"):
            table[name(vehicle["name"])] = entry
    return table


def siren_table(vehicles):
    table = {}
    for vehicle in vehicles:
        general = vehicle.get("generalData") or {}
        on, off = name(general.get("sirenOnEvent")), name(general.get("sirenOffEvent"))
        if on and off:
            table[name(vehicle["name"])] = {"on": on, "off": off}
        elif on or off:
            print(f"{name(vehicle['name'])}: a siren with only one of its events ({on or off}), left out")
    return table


def lua_string(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def lua_value(value, indent):
    pad = "    " * indent
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, str):
        return lua_string(value)
    if isinstance(value, list):
        inner = "".join(f"{pad}    {lua_value(v, indent + 1)},\n" for v in value)
        return "{\n" + inner + pad + "}"
    if isinstance(value, dict):
        keys = sorted(value)
        if all(isinstance(value[k], str) for k in keys):
            return "{ " + ", ".join(f"{k} = {lua_string(value[k])}" for k in keys) + " }"
        inner = "".join(f"{pad}    {k} = {lua_value(value[k], indent + 1)},\n" for k in keys)
        return "{\n" + inner + pad + "}"
    raise TypeError(type(value))


def write_table(path, comment, table):
    lines = [f"-- {line}".rstrip() for line in comment.strip().splitlines()]
    lines.append("-- Written by tools/make-sound-tables.py from the game's own audio metadata; don't edit by hand.")
    lines.append("")
    lines.append("return {")
    for key in sorted(table):
        lines.append(f"    [{lua_string(key)}] = {lua_value(table[key], 1)},")
    lines.append("}")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    print(f"{os.path.relpath(path, REPO)}: {len(table)} entries")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--game", default=GAME)
    parser.add_argument("--wolvenkit", default=WOLVENKIT)
    parser.add_argument("--work", default=os.path.join(tempfile.gettempdir(), "nightcoop-tweaks-sounds"))
    opts = parser.parse_args()
    if not os.path.exists(opts.wolvenkit):
        sys.exit(f"no WolvenKit command line at {opts.wolvenkit}: pass --wolvenkit")

    # One namespace for both files: a Phantom Liberty set may name base-game settings.
    by_name = {}
    for path in extract(opts.game, opts.wolvenkit, opts.work):
        with open(path, encoding="utf-8") as f:
            for obj in objects(json.load(f), []):
                key = name(obj.get("name"))
                if key:
                    by_name[key] = obj
    found = list(by_name.values())

    weapons = weapon_table(by_name, [o for o in found if o["$type"] == "audioWeaponSettingsGroup"])
    write_table(os.path.join(MOD, "tweaks", "silencedshots", "sounds.lua"), """
The shots an NPC makes firing a weapon silenced, by the weapon's audio set
(Item_Record.AudioName): the set's npcSilenced settings, or npcSettings
(fallback = true) where it has none, through their gun choir to each voice.
single: one shot; burst: one burst; loop and loopStop: an automatic loop.
""", weapons)

    vehicles = [o for o in found if o["$type"] == "audioVehicleMetadata"]
    horns = horn_table(vehicles)
    write_table(os.path.join(MOD, "tweaks", "horn", "horns.lua"), """
A vehicle's horn by its audio resource (Vehicle_Record's player_audio_resource):
on starts it, off stops it (a bike's beep has no off), police* for a police car's.
""", horns)

    sirens = siren_table(vehicles)
    write_table(os.path.join(MOD, "tweaks", "siren", "sirens.lua"), """
A police car's siren by its audio resource (Vehicle_Record's player_audio_resource,
or AudioResourceName): on starts its loop, off stops it.
""", sirens)


if __name__ == "__main__":
    main()
