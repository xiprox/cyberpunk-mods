"""The shop's palette for the paint tool's menu (UX.md, "The paint tool and the tool rack"): groups, names, paint names and colours
from catalog/shop-palette.json, as TweakDB flats in mod/r6/tweaks/vehiclecustomizer/shop-palette.yaml. Colours are the
sRGB of the palette, for the menu's chips; the paints themselves come from make-paints.py. Run with: python -I make-palette-data.py"""
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "..")


def slug(text):
    return text.lower().replace(" ", "_")


with open(os.path.join(ROOT, "catalog", "shop-palette.json"), encoding="utf-8") as f:
    groups = json.load(f)["groups"]

lines = ["# Written by experiments/paint/make-palette-data.py; don't edit by hand.",
         "VehicleCustomizer.shop.groups: [ " + ", ".join(f'n"{slug(g["name"])}"' for g in groups) + " ]"]
for group in groups:
    key = "VehicleCustomizer.shop.group." + slug(group["name"])
    names = [name for name, _hex in group["colours"]]
    colours = [tuple(int(hex_[i:i + 2], 16) / 255.0 for i in (1, 3, 5)) for _name, hex_ in group["colours"]]
    lines.append(f'{key}.label: "{group["name"]}"')
    lines.append(f"{key}.paints: [ " + ", ".join(f'n"vcs_{slug(n)}"' for n in names) + " ]")
    lines.append(f"{key}.names: [ " + ", ".join(f'"{n}"' for n in names) + " ]")
    lines.append(f"{key}.colours: [ " + ", ".join("{ x: %.4f, y: %.4f, z: %.4f }" % c for c in colours) + " ]")
with open(os.path.join(ROOT, "mod", "r6", "tweaks", "vehiclecustomizer", "shop-palette.yaml"), "w", encoding="utf-8") as f:
    f.write("\n".join(lines) + "\n")
print(len(groups), "groups,", sum(len(g["colours"]) for g in groups), "colours")
