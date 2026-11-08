"""Builds the test's twin looks: for every look in a car's .ent, two entries of our own, <look>__vc_a and
<look>__vc_b, pointing at the same look in the same .app. Switching a car between them makes the game build it
again where it stands, which a "change" to the look it already has doesn't (RECORD.md), and a build carrying
one of these names is always ours.

The output is a patch .ent for ArchiveXL, limited in the .xl to the `appearances` field, so the rest of the
file (a copy of the target's) is ignored.

Input: WolvenKit JSON of the target .ent (WolvenKit.CLI convert serialize).
Usage: python -I make-twin-looks.py <car.ent.json> <out.ent.json>
"""
import copy
import json
import sys

TWINS = ("__vc_a", "__vc_b")


def main(ent_path, out_path):
    doc = json.load(open(ent_path, encoding="utf-8"))
    root = doc["Data"]["RootChunk"]
    twins = []
    for look in root["appearances"]:
        name = look["name"]["$value"]
        if "__vc_" in name:
            sys.exit(f"the car already has a twin look: {name}")
        for suffix in TWINS:
            twin = copy.deepcopy(look)
            twin["name"]["$value"] = name + suffix
            twins.append(twin)
    out = copy.deepcopy(doc)
    out["Data"]["RootChunk"]["appearances"] = twins
    out["Header"]["ArchiveFileName"] = ""
    json.dump(out, open(out_path, "w", encoding="utf-8"), indent=1)
    print(f"{len(root['appearances'])} looks, {len(twins)} twin entries; first: {twins[0]['name']['$value']} -> "
          f"{twins[0]['appearanceName']['$value']} in {twins[0]['appearanceResource']['DepotPath']['$value']}")


if __name__ == "__main__":
    main(*sys.argv[1:3])
