"""The tools' placeholder bodies and their real screens, written as glb for WolvenKit to import (run by make-tools.py).
Blender's stock glTF exporter, no add-on. Blender's axes here are the tool's own: X right, Y forward, Z up, metres, origin
at the Lexington's weapon origin, so V's hands fit the grip as they fit the pistol's (RECORD.md, 2026-11-08).
A placeholder: it proves the plumbing in the game. The final shapes replace make_body(); the screen and its numbers stay.

usage: blender -b --factory-startup -P blockout.py -- <out folder>
"""
import math
import os
import sys

import bpy
import bmesh
from mathutils import Matrix, Vector

# The screen: 16 x 7 cm on the rear end, 4 cm left of the tool's line, its bottom edge level with the slide's underside
# and turned up to V's eye (eye in tool space, from the Lexington's idlepose_shoulder; RECORD.md).
SCREEN_W = 0.16
SCREEN_H = 0.07
SCREEN_CENTRE = Vector((-0.04, -0.076, 0.035))
EYE = Vector((-0.053, -0.374, 0.096))
BONE = "barrel"
BEZEL = 0.006
HOUSING_DEPTH = 0.014


def screen_frame():
    """Right, up and out vectors of the screen's plane: no sideways turn, so the tool stays symmetrical about its own axis."""
    out = EYE - SCREEN_CENTRE
    out.x = 0
    out.normalize()
    right = Vector((1, 0, 0))
    up = out.cross(right)
    if up.z < 0:
        up = -up
    return right, up, out


def box(bm, lo, hi):
    """A box between two corners, added to a bmesh."""
    m = Matrix.Translation((Vector(lo) + Vector(hi)) / 2) @ Matrix.Diagonal((*(Vector(hi) - Vector(lo)), 1))
    bmesh.ops.create_cube(bm, size=1.0, matrix=m)


def sheared_box(bm, top_lo, top_hi, bottom_lo, bottom_hi):
    """A box whose bottom face is moved: the raked pistol grip."""
    a, b = Vector(top_lo), Vector(top_hi)
    c, d = Vector(bottom_lo), Vector(bottom_hi)
    v = [bm.verts.new(p) for p in (
        (a.x, a.y, a.z), (b.x, a.y, a.z), (b.x, b.y, a.z), (a.x, b.y, a.z),
        (c.x, c.y, c.z), (d.x, c.y, c.z), (d.x, d.y, c.z), (c.x, d.y, c.z))]
    for f in ((0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)):
        bm.faces.new([v[i] for i in f])


def housing(bm):
    right, up, out = screen_frame()
    c = SCREEN_CENTRE - out * (HOUSING_DEPTH / 2 + 0.001)
    w = SCREEN_W / 2 + BEZEL
    h = SCREEN_H / 2 + BEZEL
    d = HOUSING_DEPTH / 2
    corners = []
    for sd in (d, -d):
        for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            corners.append(bm.verts.new(c + right * (sx * w) + up * (sy * h) + out * sd))
    for f in ((0, 1, 2, 3), (7, 6, 5, 4), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)):
        bm.faces.new([corners[i] for i in f])


def make_body(tool):
    """Slide, raked grip, the screen's housing and its bridge to the slide, and one thing at the front that tells the tools apart."""
    bm = bmesh.new()
    box(bm, (-0.017, -0.066, 0.002), (0.017, 0.150, 0.046))
    sheared_box(bm, (-0.016, -0.045, 0.006), (0.016, 0.018, 0.006), (-0.015, -0.068, -0.100), (0.015, -0.012, -0.100))
    box(bm, (-0.012, -0.068, 0.010), (0.012, -0.060, 0.040))  # the bridge: stops inside the housing, behind the screen
    if tool == "wrench":
        ring = bmesh.ops.create_cone(bm, cap_ends=True, segments=16, radius1=0.034, radius2=0.034, depth=0.03,
                                     matrix=Matrix.Translation((0, 0.170, 0.026)) @ Matrix.Rotation(math.radians(90), 4, "X"))
        assert ring["verts"]
    else:
        cup = bmesh.ops.create_cone(bm, cap_ends=True, segments=16, radius1=0.022, radius2=0.030, depth=0.055,
                                    matrix=Matrix.Translation((0, 0.120, 0.080)))
        assert cup["verts"]
        nozzle = bmesh.ops.create_cone(bm, cap_ends=True, segments=12, radius1=0.012, radius2=0.006, depth=0.04,
                                       matrix=Matrix.Translation((0, 0.170, 0.026)) @ Matrix.Rotation(math.radians(-90), 4, "X"))
        assert nozzle["verts"]
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    return bm


def make_housing():
    """The screen's case and its rod, one rigid part: it and the screen move toward or away from the eye with the field of view
    (ToolScreens.reds). The rod runs inside the body, so it slides in and out and the screen never floats (user's idea, 2026-11-08):
    its front stays inside the body over the whole travel, 9 cm toward the eye to 6 cm away."""
    bm = bmesh.new()
    housing(bm)
    box(bm, (-0.007, -0.070, 0.018), (0.007, 0.080, 0.032))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    return bm


def make_screen():
    """The screen face: one quad, UV 0..1. The game's picture has its top at v = 1 (first look in the game, 2026-11-08)."""
    right, up, out = screen_frame()
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UV0")
    w = SCREEN_W / 2
    h = SCREEN_H / 2
    v = [bm.verts.new(SCREEN_CENTRE + right * (sx * w) + up * (sy * h)) for sx, sy in ((-1, 1), (-1, -1), (1, -1), (1, 1))]
    f = bm.faces.new(v)
    f.normal_update()
    if f.normal.dot(out) < 0:
        f.normal_flip()
    for loop in f.loops:
        p = loop.vert.co - SCREEN_CENTRE
        # The game draws the widget into a square picture (measured on the user's screenshot: the menu filled the width and
        # 36% of the height), so the screen shows the picture's middle band, u and v to the same scale, and nothing is stretched.
        loop[uv].uv = ((p.dot(right) / SCREEN_W + 0.5), (0.5 + p.dot(up) / SCREEN_W))
    bmesh.ops.triangulate(bm, faces=[f])
    return bm


def write(name, bm, out_dir, skinned=True):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    me = bpy.data.meshes.new("submesh_00_LOD_1")
    if not bm.loops.layers.uv:
        bm.loops.layers.uv.new("UV0")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("submesh_00_LOD_1", me)
    scene.collection.objects.link(ob)
    me.materials.append(bpy.data.materials.new("mat0"))
    if skinned:
        arm = bpy.data.armatures.new("Armature")
        arm_ob = bpy.data.objects.new("Armature", arm)
        scene.collection.objects.link(arm_ob)
        bpy.context.view_layer.objects.active = arm_ob
        bpy.ops.object.mode_set(mode="EDIT")
        b = arm.edit_bones.new(BONE)
        b.head = (0, 0, 0)
        b.tail = (0, 0.05, 0)
        # WolvenKit writes the bone's matrix from this rest pose. The rig's barrel is rolled half a turn about the tool's
        # forward axis from a plain bone along +Y; without this the game drew the tool upside down (first look, 2026-11-08).
        b.roll = math.pi
        bpy.ops.object.mode_set(mode="OBJECT")
        vg = ob.vertex_groups.new(name=BONE)
        vg.add(list(range(len(me.vertices))), 1.0, "REPLACE")
        ob.modifiers.new("arm", "ARMATURE").object = arm_ob
        ob.parent = arm_ob
    for o in bpy.data.objects:
        o.select_set(True)
    path = os.path.join(out_dir, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=False, export_skins=skinned,
                              export_morph=False, export_animations=False, export_tangents=True, export_normals=True,
                              export_yup=True, export_materials="NONE", export_texcoords=True, export_all_influences=False,
                              export_lights=False, export_cameras=False)
    print("WROTE", path, os.path.getsize(path))


def main():
    out_dir = sys.argv[sys.argv.index("--") + 1]
    os.makedirs(out_dir, exist_ok=True)
    for tool in ("wrench", "paint"):
        write(f"vc_{tool}_body", make_body(tool), out_dir)
        write(f"vc_{tool}_screen", make_screen(), out_dir, skinned=False)
        write(f"vc_{tool}_housing", make_housing(), out_dir, skinned=False)
        write(f"vc_{tool}_shadow", make_body(tool), out_dir, skinned=False)


main()
