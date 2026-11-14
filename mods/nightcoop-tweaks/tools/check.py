"""Checks the mod's Lua without the game: it parses every file with LuaJIT (the
Lua CET runs) and reads its bytecode for globals that would only fail in game.

  - a syntax error, as CET would hit it on Reload All Mods
  - a global set: every module works through locals, so it's a missing `local`
    or a misspelt forward declaration
  - a global read that isn't Lua's, CET's, or a game type (from NightCoop's
    rtti-names-*.txt): a misspelt name
  - an Observe or Override of a function the class (or a parent) doesn't have:
    a misspelt name, or a script static, which the game keeps as a global
    ("Class::Function;Args") where CET's hooks can't reach it
  - a "core/..." or "tweaks/..." module path that isn't a file

usage: python -I tools/check.py [--game <game folder>]
Needs `luajit` on the PATH (scoop install luajit). Exits 1 on any problem.
"""
import argparse
import glob
import os
import re
import shutil
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MOD = os.path.join(REPO, "cet", "NightCoopTweaks")
GAME = r"C:\Program Files (x86)\Steam\steamapps\common\Cyberpunk 2077"

LUA = {
    "_G", "_VERSION", "assert", "collectgarbage", "dofile", "error", "getfenv", "getmetatable",
    "ipairs", "load", "loadfile", "loadstring", "module", "next", "pairs", "pcall", "print",
    "rawequal", "rawget", "rawset", "require", "select", "setfenv", "setmetatable", "tonumber",
    "tostring", "type", "unpack", "xpcall",
    "bit", "coroutine", "debug", "io", "jit", "math", "os", "package", "string", "table",
}

# What CET puts in a mod's environment besides the game's types.
CET = {
    "Game", "GetMod", "GetSingleton", "NewObject", "ToVariant", "FromVariant", "EnumInt", "Enum",
    "IsDefined", "NameToString", "CalcSeed", "Dump", "DumpType", "GameDump",
    "CName", "TweakDB", "TweakDBID", "ItemID", "Vector3", "Vector4", "Quaternion", "EulerAngles",
    "registerForEvent", "registerHotkey", "registerInput",
    "Observe", "ObserveBefore", "ObserveAfter", "Override",
    "ImGui", "ImGuiWindowFlags", "ImGuiTreeNodeFlags", "ImGuiCond", "ImGuiCol", "ImGuiStyleVar",
    "ImGuiInputTextFlags", "ImGuiSelectableFlags", "ImGuiTableFlags", "ImGuiTableColumnFlags",
    "ImGuiHoveredFlags", "ImGuiFocusedFlags", "ImGuiComboFlags", "ImGuiKey", "ImGuiMouseButton",
    "spdlog", "json",
}

# NightCoop's own classes that came after its rtti-names dump (written once per game version).
NIGHTCOOP = {"NightCoopSdk"}

BYTECODE = re.compile(r"^-- BYTECODE -- (.+):(\d+-\d+)$")
GLOBAL = re.compile(r'^\d+\s+(GGET|GSET)\s+\d+\s+\d+\s+; "(.*?)("~|"$)')
MODULE_PATH = re.compile(r'"((?:core|tweaks)/[\w/]+)"')
HOOK = re.compile(r'\b(Observe|ObserveBefore|ObserveAfter|Override)\(\s*"([^"]+)"\s*,\s*"([^"]+)"')


class Dump:
    """NightCoop's dump of the game's types: their names, parents and member functions."""

    def __init__(self, path):
        self.names = set()
        self.classes = {}  # native or alias name -> { "parent": name, "functions": set }
        functions = {}
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f:
                cols = line.rstrip("\n").split("\t")
                if cols[0] in ("C", "E"):
                    self.names.update(c for c in cols[1:3] if c)
                if cols[0] == "C" and len(cols) > 3:
                    record = self.classes.get(cols[1]) or {"parent": cols[3], "functions": set()}
                    record["parent"] = record["parent"] or cols[3]
                    for name in cols[1:3]:
                        if name:
                            self.classes[name] = record
                elif cols[0] == "F" and len(cols) > 3:
                    functions.setdefault(cols[1], set()).update(n for n in cols[2:4] if n)
        for name, found in functions.items():
            if name in self.classes:
                self.classes[name]["functions"].update(found)

    def has_member(self, class_name, function):
        seen = set()
        while class_name and class_name not in seen:
            seen.add(class_name)
            record = self.classes.get(class_name)
            if not record:
                return False
            if function in record["functions"]:
                return True
            class_name = record["parent"]
        return False


def load_dump(game):
    dumps = glob.glob(os.path.join(game, "red4ext", "plugins", "NightCoop", "rtti-names-*.txt"))
    return Dump(dumps[0]) if dumps else None


def check_file(luajit, path, rel, dump):
    known = dump.names if dump else None
    problems = []
    run = subprocess.run([luajit, "-bl", path], capture_output=True, text=True)
    if run.returncode != 0:
        return [run.stderr.strip().replace(path, rel)]

    where = rel
    for line in run.stdout.splitlines():
        header = BYTECODE.match(line)
        if header:
            where = f"{rel}:{header.group(2)}"
            continue
        g = GLOBAL.match(line)
        if not g:
            continue
        op, name, cut = g.group(1), g.group(2), g.group(3) == '"~'
        if op == "GSET":
            problems.append(f"{where}: sets the global '{name}' (a missing local?)")
        elif name not in LUA and name not in CET and name not in NIGHTCOOP:
            if known is None:
                continue
            if name in known or (cut and any(k.startswith(name) for k in known)):
                continue
            problems.append(f"{where}: reads '{name}', which isn't Lua's, CET's, or a game type")

    with open(path, encoding="utf-8") as f:
        source = f.read()
    for module in sorted(set(MODULE_PATH.findall(source))):
        if not os.path.exists(os.path.join(MOD, *module.split("/")) + ".lua"):
            problems.append(f"{rel}: '{module}' isn't a file in the mod")
    if dump:
        for hook, class_name, function in HOOK.findall(source):
            if not dump.has_member(class_name, function):
                problems.append(f"{rel}: {hook}('{class_name}', '{function}'): no such member function "
                                f"of {class_name} or its parents (a script static is a global CET can't hook)")
    return problems


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--game", default=GAME)
    opts = parser.parse_args()

    luajit = shutil.which("luajit")
    if not luajit:
        sys.exit("luajit isn't on the PATH: scoop install luajit")
    dump = load_dump(opts.game)
    if dump is None:
        print(f"no rtti-names-*.txt under {opts.game}: game type names and hooks go unchecked")

    files = sorted(glob.glob(os.path.join(MOD, "**", "*.lua"), recursive=True))
    problems = []
    for path in files:
        rel = os.path.relpath(path, REPO).replace("\\", "/")
        problems += check_file(luajit, path, rel, dump)

    for problem in problems:
        print(problem)
    print(f"{len(files)} file(s), {len(problems)} problem(s)")
    sys.exit(1 if problems else 0)


if __name__ == "__main__":
    main()
