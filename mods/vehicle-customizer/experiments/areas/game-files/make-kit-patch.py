"""Builds the test's ArchiveXL patch: the Archer Quartz Nomad's front kit added to every look of the Hella.

Input: WolvenKit JSON of archer_quartz_nomad.app and archer_hella__basic.app (WolvenKit.CLI convert serialize).
Output: JSON of a patch .app whose only look has no name, which ArchiveXL applies to every look of its target
(ArchiveXL 1.28.6, ResourcePatch/Extension.cpp: a definition with an empty name is a multi-target patch).
The kit's parts are copied from the Quartz's look aldecados_01 and renamed vc_axl_*, so they can't clash with
the parts the redscript service adds (vc_nomad_*). The lamps move 0.9 m ahead, where they cleared the Hella's
bumper in the user's test; the sensor box stays where the Quartz has it, on the hood.

Usage: python -I make-kit-patch.py <quartz.app.json> <hella.app.json> <out.app.json>
"""
import copy
import json
import random
import sys

FIXED = 131072  # WorldPosition FixedPoint: 17 fractional bits
LAMPS_AHEAD = 0.9

RENAME = {
    "sensor_medium_02": "vc_axl_sensor",
    "sensor_medium_02_shadow": "vc_axl_sensor_shadow",
    "detector_medium_01": "vc_axl_detector_1",
    "detector_medium_02": "vc_axl_detector_2",
    "detector_medium_03": "vc_axl_detector_3",
    "detector_medium_04": "vc_axl_detector_4",
    "v_common_nomad_part__ext01_detector_medium_01_shadow": "vc_axl_detector_shadow_a",
    "v_common_nomad_part__ext01_detector_medium_01_shadow4203": "vc_axl_detector_shadow_b",
    "v_common_nomad_part__ext01_detector_medium_01_shadow4268": "vc_axl_detector_shadow_c",
    "v_common_nomad_part__ext01_detector_medium_01_shadow6882": "vc_axl_detector_shadow_d",
}
LAMPS = {"detector_medium_01", "detector_medium_02", "detector_medium_03", "detector_medium_04"}


def cname(value):
    return {"$type": "CName", "$storage": "string", "$value": value}


def empty_path():
    return {"DepotPath": {"$type": "ResourcePath", "$storage": "uint64", "$value": "0"}, "Flags": "Soft"}


def walk(value, visit):
    if isinstance(value, dict):
        visit(value)
        for item in value.values():
            walk(item, visit)
    elif isinstance(value, list):
        for item in value:
            walk(item, visit)


def main(quartz_path, hella_path, out_path):
    quartz = json.load(open(quartz_path, encoding="utf-8"))
    hella = json.load(open(hella_path, encoding="utf-8"))

    look = next(entry["Data"] for entry in quartz["Data"]["RootChunk"]["appearances"]
                if entry["Data"]["name"]["$value"] == "aldecados_01")
    chunks = [copy.deepcopy(chunk) for chunk in look["compiledData"]["Data"]["Chunks"]
              if chunk.get("name", {}).get("$value") in RENAME]
    found = sorted(chunk["name"]["$value"] for chunk in chunks)
    if found != sorted(RENAME):
        sys.exit(f"kit parts found: {found}")

    # Renumber every handle, give each part a new id and name, point shadows at the renamed parts.
    next_handle = [1000]
    handle_map = {}
    rng = random.Random(20261105)

    def renumber(node):
        if "HandleId" in node:
            handle_map[node["HandleId"]] = str(next_handle[0])
            node["HandleId"] = str(next_handle[0])
            next_handle[0] += 1

    for chunk in chunks:
        original = chunk["name"]["$value"]
        chunk["name"] = cname(RENAME[original])
        chunk["id"] = str(rng.getrandbits(63))
        binding = chunk["parentTransform"]["Data"]
        bind_name = binding["bindName"]["$value"]
        if bind_name in RENAME:
            binding["bindName"] = cname(RENAME[bind_name])
        if original in LAMPS:
            chunk["localTransform"]["Position"]["y"]["Bits"] += round(LAMPS_AHEAD * FIXED)
        walk(chunk, renumber)

    def check_refs(node):
        if "HandleRefId" in node and node["HandleRefId"] not in handle_map.values():
            sys.exit(f"reference to a handle outside the kit: {node['HandleRefId']}")

    for chunk in chunks:
        walk(chunk, check_refs)

    # The components list repeats the parts, with handles referring to those in the compiled data.
    def as_refs(value):
        if isinstance(value, dict):
            if "HandleId" in value and "Data" in value:
                return {"HandleRefId": value["HandleId"]}
            return {key: as_refs(item) for key, item in value.items()}
        if isinstance(value, list):
            return [as_refs(item) for item in value]
        return value

    definition = copy.deepcopy(look)
    definition["name"] = cname("None")
    definition["compiledData"]["Data"]["Chunks"] = chunks
    definition["compiledData"]["Data"]["CruidDict"] = {str(i): chunk["id"] for i, chunk in enumerate(chunks)}
    definition["components"] = [as_refs(chunk) for chunk in chunks]
    definition["partsValues"] = []
    definition["partsOverrides"] = []
    definition["partsMasks"] = []
    definition["resolvedDependencies"] = []
    definition["looseDependencies"] = []
    definition["visualTags"] = {"$type": "redTagList", "tags": []}
    definition["inheritedVisualTags"] = {"$type": "redTagList", "tags": []}
    definition["proxyMesh"] = empty_path()
    definition["proxyMeshAppearance"] = cname("None")
    definition["cookedDataPathOverride"] = empty_path()
    definition["parametersBuffer"] = {"$type": "entEntityParametersBuffer", "parameterBuffers": []}
    definition["hitRepresentationOverrides"] = []

    out = copy.deepcopy(hella)
    root = out["Data"]["RootChunk"]
    root["appearances"] = [{"HandleId": "1", "Data": definition}]
    root["DismWoundConfig"] = {"$type": "entdismembermentWoundsConfigSet", "Configs": []}
    root["proxyPolyCount"] = 0
    out["Header"]["ArchiveFileName"] = ""

    json.dump(out, open(out_path, "w", encoding="utf-8"), indent=1)
    for chunk in chunks:
        position = chunk["localTransform"]["Position"]
        xyz = [position[axis]["Bits"] / FIXED for axis in ("x", "y", "z")]
        print(f"{chunk['name']['$value']:28} {chunk['$type']:28} bound to "
              f"{chunk['parentTransform']['Data']['bindName']['$value']:22} at {xyz[0]:.3f}, {xyz[1]:.3f}, {xyz[2]:.3f}")


if __name__ == "__main__":
    main(*sys.argv[1:4])
